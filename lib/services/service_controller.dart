// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:trayforge/foundation/logger.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/foundation/output_pipeline.dart';
import 'package:trayforge/foundation/service_host.dart';
import 'package:trayforge/foundation/service_operator.dart';
import 'package:trayforge/foundation/service_status.dart';

/// Owns the lifecycle of one configured **service group**.
///
/// The deep service module: it turns "one SCM operation per toggle" into the
/// same observable behaviour the dashboard already understands —
/// [ProcState] transitions, an operation log, per-service detail — without
/// pretending a service is a launched child process (see ADR 005).
///
/// Responsibilities hidden behind the small interface:
///
/// - aggregate state ([aggregateState]) and the toggle rule
///   (any member up → stop all, else start all);
/// - polling until the OS reaches a terminal state after an operation, with a
///   timeout instead of hanging;
/// - periodic re-query so a change made outside TrayForge (services.msc,
///   `systemctl`) shows up and is logged;
/// - per-service failure reporting (access denied, dependents, disabled, …);
/// - a sticky `crashed` state after a failed operation, so a red card is not
///   silently repainted green by the next poll.
///
/// The SCM is the source of truth: nothing is persisted here, and an
/// application exit never stops services (they are not owned by the app).
class ServiceController {
  ServiceController({
    required this.name,
    required ServiceConfig config,
    required ServiceHost host,
    required ServiceOperator operator,
    required Duration pollInterval,
    this.settleTimeout = const Duration(seconds: 60),
    this.operationPollInterval = const Duration(milliseconds: 500),
    this.operationTimeout = const Duration(minutes: 5),
    Logger? logger,
  }) : _config = config,
       _host = host,
       _operator = operator,
       _pollInterval = pollInterval,
       _logger = logger;

  /// Display name of the group.
  final String name;

  /// How long the post-operation poll may take to reach a terminal state
  /// before the members that are still moving are reported as unsettled.
  final Duration settleTimeout;

  /// How often an in-flight operation re-queries the OS.
  final Duration operationPollInterval;

  /// Upper bound for the whole operation, including a pending UAC prompt.
  final Duration operationTimeout;

  final ServiceHost _host;
  final ServiceOperator _operator;
  final Logger? _logger;

  ServiceConfig _config;
  Duration _pollInterval;

  ProcState _state = ProcState.stopped;
  List<ServiceStatus> _statuses = const [];
  bool _busy = false;
  bool _disposed = false;

  /// Set when an operation failed; keeps [ProcState.crashed] sticky until the
  /// next operation, so a polling tick cannot hide the problem.
  bool _opFailed = false;

  /// Member statuses captured when the operation failed. A later refresh with
  /// different member states means something changed outside TrayForge, which
  /// un-pins the crashed state. `null` marks a query failure, which the next
  /// successful query clears silently.
  ///
  /// The snapshot is compared member by member, not by aggregate: the
  /// aggregate can be `crashed` on both sides of an external change (one
  /// member missing, another started), so it would never un-pin.
  List<ServiceStatus>? _statusesAtFailure;

  /// The operator run whose future has not completed yet.
  ///
  /// `Future.timeout` gives up on a future but cannot cancel it, so this guard
  /// is held until the helper really exits: a late UAC consent may still move
  /// services after the operation was reported as timed out.
  Future<List<ServiceOpResult>>? _inFlight;

  bool _refreshing = false;

  Timer? _pollTimer;
  BufferedOutputPipeline? _pipeline;
  StreamController<ProcState>? _stateController;
  StreamController<List<ServiceStatus>>? _statusesController;

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  /// Operation log lines for this group (system messages, results).
  Stream<String> get output => pipeline.output;

  /// State transitions of the aggregate.
  Stream<ProcState> get state {
    _stateController ??= StreamController<ProcState>.broadcast(sync: true);
    return _stateController!.stream;
  }

  /// Per-service status after every query.
  Stream<List<ServiceStatus>> get statusesStream {
    _statusesController ??= StreamController<List<ServiceStatus>>.broadcast(
      sync: true,
    );
    return _statusesController!.stream;
  }

  ProcState get currentState => _state;

  List<ServiceStatus> get statuses => List.unmodifiable(_statuses);

  bool get busy => _busy;

  ServiceConfig get config => _config;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Queries the initial state and starts polling.
  Future<void> init() async {
    await _refresh(logSummary: true);
    _startPolling();
  }

  /// Toggles the group: any member up → stop all members, else start all.
  Future<void> toggle() async {
    if (_busy || _disposed) return;
    if (_inFlight != null) {
      // A timed-out operation may still be alive; a second helper would race
      // it for the same services.
      _log('$_groupLabel a previous operation is still running');
      return;
    }
    // Set before the first await so a second click cannot slip through while
    // the current statuses are still being queried.
    _busy = true;
    try {
      final current = await _refresh();
      if (current == null || _disposed) {
        return; // Query failed: state is crashed.
      }
      await _run(
        anyServiceUp(current) ? ServiceOpKind.stop : ServiceOpKind.start,
        current,
      );
    } finally {
      _busy = false;
    }
  }

  /// Re-queries the group without starting an operation.
  Future<void> refreshNow() async {
    if (_disposed || _busy) return;
    await _refresh(logChanges: true);
  }

  /// Applies an edited config (services list, dependents) to this controller.
  void updateConfig(ServiceConfig config) {
    if (config == _config) return;
    _config = config;
    _log('$_groupLabel: configuration updated');
    unawaited(refreshNow());
  }

  /// Changes the idle poll interval (from the global setting).
  void updatePollInterval(Duration interval) {
    if (interval == _pollInterval) return;
    _pollInterval = interval;
    if (_pollTimer != null) _startPolling();
  }

  /// Releases timers and streams. Services are **not** stopped: they belong to
  /// the OS, not to TrayForge.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _statusesController?.close();
    _stateController?.close();
    _pipeline?.dispose();
  }

  // ---------------------------------------------------------------------------
  // Operation
  // ---------------------------------------------------------------------------

  Future<void> _run(ServiceOpKind kind, List<ServiceStatus> current) async {
    _opFailed = false;
    _statusesAtFailure = null;
    final starting = kind == ServiceOpKind.start;

    // Only services not already in the requested state need to move.
    final pending = <String>{
      for (final status in current)
        if (starting ? !status.state.isUp : status.state.isUp) status.name,
    };

    _log(
      '${starting ? 'Starting' : 'Stopping'} '
      '${_config.services.length} service(s)...',
    );
    _setState(starting ? ProcState.starting : ProcState.stopping);

    var results = const <ServiceOpResult>[];
    var timedOut = false;
    try {
      final run = _operator.run(
        ServiceGroupOp(
          kind: kind,
          services: _config.services,
          stopDependents: _config.stopDependents,
        ),
      );
      _inFlight = run;
      // `Future.timeout` cannot cancel the helper, so release the in-flight
      // guard only when the future itself completes.
      unawaited(
        run.then<void>(
          (_) => _finishInFlight(run, timedOut: timedOut),
          onError: (Object _, StackTrace _) =>
              _finishInFlight(run, timedOut: timedOut),
        ),
      );
      results = await run.timeout(
        operationTimeout,
        onTimeout: () {
          // The operation phase can block on a UAC prompt; never leave the
          // group busy forever.
          timedOut = true;
          _log(
            '$_groupLabel operation timed out after '
            '${operationTimeout.inSeconds}s (waiting for elevation?)',
          );
          return const <ServiceOpResult>[];
        },
      );
    } on ServiceOpException catch (e) {
      _log('operation failed: $e');
    }

    final failures = results.where((result) => !result.ok).toList();
    for (final failure in failures) {
      _log(
        '${failure.service}: failed — '
        '${failure.message ?? failure.failure!.name}',
      );
    }

    final unsettled = await _awaitSettled(kind, pending);
    if (_disposed) return;

    // The operator rebuilds its results from the OS after an elevation hop, so
    // its `dependentsRunning` kind is missing on that path: asking the host
    // about what is still up is the report that covers every path.
    if (kind == ServiceOpKind.stop) await _reportDependentsOfStillUp();
    if (_disposed) return;

    if (failures.isNotEmpty || unsettled.isNotEmpty) {
      _opFailed = true;
      _statusesAtFailure = List<ServiceStatus>.unmodifiable(_statuses);
      _setState(ProcState.crashed);
      _log(
        '$_groupLabel: ${failures.length + unsettled.length} problem(s) — '
        'see above',
      );
      return;
    }

    final statuses = await _refresh();
    _log(_doneLine(kind, statuses ?? _statuses));
  }

  /// Releases the in-flight guard once the operator run really completed.
  ///
  /// [timedOut] comes from the operation's own timeout callback: when a helper
  /// answers the UAC prompt after the timeout it may still have moved
  /// services, so that is said once, when it finally finishes.
  void _finishInFlight(
    Future<List<ServiceOpResult>> run, {
    required bool timedOut,
  }) {
    if (!identical(_inFlight, run)) return;
    _inFlight = null;
    if (timedOut) _log('$_groupLabel a previous operation finished late');
  }

  /// Names the dependents of every member a stop left up.
  ///
  /// Best effort, one line per member, and nothing when a member has no
  /// dependents.
  Future<void> _reportDependentsOfStillUp() async {
    for (final status in _statuses) {
      if (_disposed) return;
      if (!status.state.isUp) continue;
      final dependents = await _safeDependents(status.name);
      if (_disposed) return;
      if (dependents.isEmpty) continue;
      _log(
        'still running: ${dependents.join(', ')} — enable '
        '"Stop dependent services" to stop them first',
      );
    }
  }

  Future<List<String>> _safeDependents(String name) async {
    try {
      return await _host.dependents(name);
    } catch (_) {
      return const [];
    }
  }

  /// Polls until every service in [pending] reaches its target state.
  ///
  /// Returns the services that did not make it before [settleTimeout].
  Future<Set<String>> _awaitSettled(
    ServiceOpKind kind,
    Set<String> pending,
  ) async {
    final deadline = DateTime.now().add(settleTimeout);
    final names = pending.toList();

    while (pending.isNotEmpty && !_disposed) {
      final statuses = await _refresh();
      if (statuses != null) {
        for (final name in names) {
          if (!pending.contains(name)) continue;
          final status = _statusOf(statuses, name);
          if (status != null && kind.reaches(status)) {
            pending.remove(name);
            _log('$name: ${status.state.label}');
          }
        }
      }
      if (pending.isEmpty || DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(operationPollInterval);
    }

    for (final name in pending) {
      _log(
        '$name: did not reach '
        '${kind == ServiceOpKind.start ? 'Running' : 'Stopped'} within '
        '${settleTimeout.inSeconds}s',
      );
    }
    return pending;
  }

  // ---------------------------------------------------------------------------
  // Querying
  // ---------------------------------------------------------------------------

  Future<List<ServiceStatus>?> _refresh({
    bool logSummary = false,
    bool logChanges = false,
  }) async {
    if (_disposed || _refreshing) return null;
    _refreshing = true;
    List<ServiceStatus> statuses;
    try {
      statuses = await _host.query(_config.services);
    } on ServiceOpException catch (e) {
      _refreshing = false;
      _log('$_groupLabel: $e');
      _opFailed = true;
      _statusesAtFailure = null; // Any successful query clears this.
      _setState(ProcState.crashed);
      return null;
    } catch (e) {
      _refreshing = false;
      _log('$_groupLabel: query failed — $e');
      _opFailed = true;
      _statusesAtFailure = null;
      _setState(ProcState.crashed);
      return null;
    }
    _refreshing = false;
    if (_disposed) return null;

    final previous = _statuses;
    _statuses = statuses;
    _statusesController?.add(statuses);

    final aggregate = aggregateState(statuses);
    if (logSummary) {
      _log(_summaryLine(statuses));
      for (final line in _problemLines(statuses)) {
        _log(line);
      }
    } else if (logChanges) {
      // Member-level changes are news even when the aggregate stays the same,
      // e.g. one of four services flipping while the group is "running".
      for (final status in statuses) {
        final before = _statusOf(previous, status.name);
        if (before == null || before.state == status.state) continue;
        _log(
          '${status.name}: ${before.state.label} → ${status.state.label} '
          '(changed outside TrayForge)${_codeSuffix(status)}',
        );
      }
    }

    // A crash pinned by a failed operation must not mask an external fix. The
    // member snapshot decides, because the aggregate can be `crashed` on both
    // sides of the change; a `null` snapshot was a query failure, so the first
    // successful query clears it without calling it an external change.
    if (_opFailed) {
      final atFailure = _statusesAtFailure;
      if (atFailure == null) {
        _opFailed = false;
      } else if (!_sameStates(atFailure, statuses)) {
        _opFailed = false;
        _log('$_groupLabel: ${aggregate.label} (changed outside TrayForge)');
      }
    }

    if (!_opFailed) _setState(aggregate);
    return statuses;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (_disposed) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) => _tick());
  }

  Future<void> _tick() async {
    if (_busy || _disposed) return;
    await _refresh(logChanges: true);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  BufferedOutputPipeline get pipeline => _pipeline ??= BufferedOutputPipeline();

  String get _groupLabel => '$name:';

  String _summaryLine(List<ServiceStatus> statuses) {
    final up = statuses.where((status) => status.state.isUp).length;
    final missing = [
      for (final status in statuses)
        if (status.state == ServiceState.notInstalled) status.name,
    ];
    final base = '$_groupLabel $up/${statuses.length} running';
    return missing.isEmpty
        ? base
        : '$base (not installed: ${missing.join(', ')})';
  }

  String _doneLine(ServiceOpKind kind, List<ServiceStatus> statuses) {
    final up = statuses.where((status) => status.state.isUp).length;
    if (kind == ServiceOpKind.stop) {
      return up == 0
          ? '$_groupLabel all stopped'
          : '$_groupLabel stopped, $up still running';
    }
    return '$_groupLabel $up/${statuses.length} running';
  }

  /// Lines for members whose state is a problem, including the OS error code.
  Iterable<String> _problemLines(List<ServiceStatus> statuses) sync* {
    for (final status in statuses) {
      if (status.state.isUp ||
          status.state.isStopped ||
          status.state.isPending) {
        continue;
      }
      yield '${status.name}: ${status.state.label}${_codeSuffix(status)}';
    }
  }

  String _codeSuffix(ServiceStatus status) =>
      status.win32ExitCode == 0 ? '' : ' (Win32 error ${status.win32ExitCode})';

  ServiceStatus? _statusOf(List<ServiceStatus> statuses, String name) {
    for (final status in statuses) {
      if (status.name == name) return status;
    }
    return null;
  }

  /// Whether two snapshots describe the same member states.
  ///
  /// Only the states are compared: a changed exit code is not an external
  /// state change. Names are matched, not positions, because a config reload
  /// can change the order.
  bool _sameStates(List<ServiceStatus> a, List<ServiceStatus> b) {
    if (a.length != b.length) return false;
    final before = {for (final status in a) status.name: status.state};
    for (final status in b) {
      if (before[status.name] != status.state) return false;
    }
    return true;
  }

  void _setState(ProcState state) {
    if (_disposed) return;
    _state = state;
    _stateController?.add(state);
  }

  void _log(String message) {
    if (_disposed) return;
    _logger?.log('[$name] $message');
    pipeline.push(message);
  }
}

import 'package:trayforge/foundation/service_host.dart';
import 'package:trayforge/foundation/service_operator.dart';
import 'package:trayforge/foundation/service_status.dart';

/// In-memory [ServiceHost] for tests.
///
/// States live in a mutable map; `start`/`stop` flip them immediately unless
/// [settleOnOp] is false (used to exercise the operation timeout).
class FakeServiceHost implements ServiceHost {
  FakeServiceHost({Map<String, ServiceState>? states, this.settleOnOp = true})
    : states = {...?states};

  final Map<String, ServiceState> states;

  /// When false, start/stop report success but the state never moves.
  final bool settleOnOp;

  final List<List<String>> queryCalls = [];
  final List<List<String>> startCalls = [];
  final List<List<String>> stopCalls = [];
  final List<String> dependentsCalls = [];

  /// When set, every start/stop result carries this failure.
  ServiceFailure? opFailure;

  /// Per-service failures, overriding a blanket [opFailure].
  Map<String, ServiceFailure> failuresByService = {};

  /// When true, a failing start/stop still moves the state to the target.
  ///
  /// Models "the call looked failed but the service did get there" — the
  /// controller must judge by the settled state, not by the result alone.
  bool moveStateEvenWhenFailing = false;

  /// When true, [query] throws (unsupported host / SCM unavailable).
  bool failQueries = false;

  /// Dependents reported for any service.
  List<String> dependentsOf = const [];

  /// Per-service diagnostic codes reported by [query] (Win32 error numbers).
  Map<String, int> win32Codes = {};

  @override
  Future<List<ServiceStatus>> query(List<String> names) async {
    if (failQueries) {
      throw const ServiceOpException('fake query failure');
    }
    queryCalls.add(List<String>.from(names));
    return [
      for (final name in names)
        ServiceStatus(
          name,
          states[name] ?? ServiceState.notInstalled,
          win32ExitCode: win32Codes[name] ?? 0,
        ),
    ];
  }

  @override
  Future<List<ServiceOpResult>> start(List<String> names) async {
    startCalls.add(List<String>.from(names));
    return _settle(names, ServiceState.running);
  }

  @override
  Future<List<ServiceOpResult>> stop(List<String> names) async {
    stopCalls.add(List<String>.from(names));
    return _settle(names, ServiceState.stopped);
  }

  /// Applies a start/stop to [names], returning one result per service.
  List<ServiceOpResult> _settle(List<String> names, ServiceState target) {
    final results = <ServiceOpResult>[];
    for (final name in names) {
      final failure = failuresByService[name] ?? opFailure;
      if (failure != null) {
        // "The call looked failed, but the service reached the target anyway."
        if (moveStateEvenWhenFailing && settleOnOp) states[name] = target;
        results.add(ServiceOpResult.failed(name, failure, 'fake failure'));
        continue;
      }
      if (settleOnOp) states[name] = target;
      results.add(ServiceOpResult.ok(name));
    }
    return results;
  }

  @override
  Future<List<String>> dependents(String name) async {
    dependentsCalls.add(name);
    return dependentsOf;
  }
}

/// [ElevatedServiceRunner] that records calls instead of prompting UAC.
class FakeElevatedServiceRunner implements ElevatedServiceRunner {
  FakeElevatedServiceRunner({this.onRun, this.throwOnRun});

  final List<ServiceGroupOp> calls = [];

  /// Optional side effect (e.g. move states) applied when run.
  final void Function(ServiceGroupOp op)? onRun;

  /// When set, [run] throws it (simulates a declined UAC prompt).
  Exception? throwOnRun;

  @override
  Future<void> run(ServiceGroupOp op) async {
    calls.add(op);
    final error = throwOnRun;
    if (error != null) throw error;
    onRun?.call(op);
  }
}

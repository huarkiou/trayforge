// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:trayforge/foundation/logger.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/foundation/service_host.dart';
import 'package:trayforge/foundation/service_host_platform.dart';
import 'package:trayforge/foundation/service_operator.dart';
import 'package:trayforge/foundation/service_status.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/service_controller.dart';
import 'package:trayforge/services/service_elevation.dart';

/// Coordinates the configured **service groups**.
///
/// The service sibling of `ProcessManager`: materializes one
/// [ServiceController] per configured group, applies config reload diffs,
/// forwards the facade calls the viewmodels use, and owns the group's streams.
///
/// Deliberately knows nothing about processes: services are not children of
/// this app, so nothing here is written to a pid file, killed on exit, or
/// restarted on failure.
class ServiceManager {
  ServiceManager({
    required ConfigStore configStore,
    ServiceHost? host,
    ServiceOperator? operator,
    Duration settleTimeout = const Duration(seconds: 60),
    Duration operationPollInterval = const Duration(milliseconds: 500),
    Duration operationTimeout = const Duration(minutes: 5),
    Logger? logger,
  }) : _configStore = configStore,
       _logger = logger,
       _host = host ?? createServiceHost(),
       _settleTimeout = settleTimeout,
       _operationPollInterval = operationPollInterval,
       _operationTimeout = operationTimeout {
    _operator =
        operator ??
        ServiceOperator(host: _host, elevated: createElevatedServiceRunner());
  }

  final ConfigStore _configStore;
  final ServiceHost _host;
  final Duration _settleTimeout;
  final Duration _operationPollInterval;
  final Duration _operationTimeout;
  final Logger? _logger;

  late final ServiceOperator _operator;

  final Map<String, ServiceController> _controllers = {};
  final Map<String, ServiceConfig> _configs = {};
  Set<String> _configuredNames = {};

  Duration _pollInterval = const Duration(seconds: 5);

  bool _disposed = false;

  final StreamController<void> _onConfigReloadedController =
      StreamController<void>.broadcast(sync: true);

  /// Emits whenever [reloadConfig] completes.
  Stream<void> get onConfigReloaded => _onConfigReloadedController.stream;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Loads the config and materializes the groups.
  Future<void> init() async {
    final config = _configStore.load();
    if (config == null) return;
    await _applyConfig(config);
  }

  /// Hot-swaps the service configuration.
  ///
  /// Removed groups are disposed — their services keep running, because
  /// TrayForge does not own them. Kept groups keep their controller, streams
  /// and log; changed groups are re-queried with the new member list.
  Future<void> reloadConfig(AppConfig config) async {
    await _applyConfig(config);
    _onConfigReloadedController.add(null);
  }

  /// The one place that owns the name/config/poll bookkeeping: drop removed
  /// groups, update kept ones, start new ones.
  Future<void> _applyConfig(AppConfig config) async {
    final interval = _intervalFrom(config.servicePollMs);
    final newConfigs = {
      for (final service in config.services) service.name: service,
    };
    final existed = Set<String>.from(_controllers.keys);

    for (final name in _controllers.keys.toList()) {
      if (newConfigs.containsKey(name)) continue;
      _controllers.remove(name)?.dispose();
    }

    _configuredNames = newConfigs.keys.toSet();
    _configs
      ..clear()
      ..addAll(newConfigs);
    _pollInterval = interval;

    for (final entry in newConfigs.entries) {
      final controller = _controller(entry.key);
      if (controller == null) continue;
      controller.updatePollInterval(interval);
      if (existed.contains(entry.key)) {
        controller.updateConfig(entry.value);
      } else {
        await controller.init();
      }
    }
  }

  /// Releases every controller. Services are left running. Idempotent.\r
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _onConfigReloadedController.close();
  }

  // ---------------------------------------------------------------------------
  // Facade
  // ---------------------------------------------------------------------------

  /// Operation log lines for [name] (inert for unknown names).
  Stream<String> outputStream(String name) =>
      _controllers[name]?.output ?? Stream<String>.empty();

  /// Aggregate state transitions for [name].
  Stream<ProcState> stateStream(String name) =>
      _controllers[name]?.state ?? Stream<ProcState>.empty();

  /// Per-service status updates for [name].
  Stream<List<ServiceStatus>> statusesStream(String name) =>
      _controllers[name]?.statusesStream ?? Stream<List<ServiceStatus>>.empty();

  ProcState getState(String name) =>
      _controllers[name]?.currentState ?? ProcState.stopped;

  List<ServiceStatus> statuses(String name) =>
      _controllers[name]?.statuses ?? const [];

  /// Toggles the group: any member up → stop all, else start all.
  Future<void> toggle(String name) async {
    await _controllers[name]?.toggle();
  }

  /// Applies a new idle poll interval (global setting) to every group.
  void applyPollInterval(int milliseconds) {
    final interval = _intervalFrom(milliseconds);
    _pollInterval = interval;
    for (final controller in _controllers.values) {
      controller.updatePollInterval(interval);
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  ServiceController? _controller(String name) {
    if (!_configuredNames.contains(name)) return null;
    final config = _configs[name];
    if (config == null) return null;
    return _controllers.putIfAbsent(
      name,
      () => ServiceController(
        name: name,
        config: config,
        host: _host,
        operator: _operator,
        pollInterval: _pollInterval,
        settleTimeout: _settleTimeout,
        operationPollInterval: _operationPollInterval,
        operationTimeout: _operationTimeout,
        logger: _logger,
      ),
    );
  }

  Duration _intervalFrom(int milliseconds) =>
      Duration(milliseconds: milliseconds.clamp(1000, 3600000));
}

// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/autostart.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/services/service_manager.dart';

/// ViewModel for the Settings page.
///
/// Holds a mutable copy of [ProcessConfig] items, supports add/edit/delete/
/// copy/reorder operations, validates via [ConfigStore.validate], and
/// persists changes through [ProcessManager.reloadConfig].
class SettingsViewModel extends ChangeNotifier {
  final ConfigStore _configStore;
  final ProcessManager _processManager;
  final ServiceManager? _serviceManager;
  final Autostart _autostart;

  List<ProcessConfig> _processes = [];
  List<ServiceConfig> _services = [];
  int _outputRefreshMs = 500;
  int _outputHistoryLimit = 1000;
  int _servicePollMs = 5000;
  DashboardLayout _dashboardLayout = DashboardLayout.list;
  StreamSubscription<void>? _configSub;

  SettingsViewModel({
    required ConfigStore configStore,
    required ProcessManager processManager,
    ServiceManager? serviceManager,
    required Autostart autostart,
  }) : _configStore = configStore,
       _processManager = processManager,
       _serviceManager = serviceManager,
       _autostart = autostart {
    _reload();
    _configSub = processManager.onConfigReloaded.listen((_) => _reload());
  }

  /// All process configs in list order.
  List<ProcessConfig> get processes => List.unmodifiable(_processes);

  /// All service groups in list order.
  List<ServiceConfig> get services => List.unmodifiable(_services);

  /// Whether a process with [name] is currently running.
  bool isRunning(String name) {
    final state = _processManager.getState(name);
    return state.isActive;
  }

  /// Output batch interval in milliseconds.
  int get outputRefreshMs => _outputRefreshMs;

  /// Maximum lines retained per process output buffer.
  int get outputHistoryLimit => _outputHistoryLimit;

  /// Dashboard layout mode.
  DashboardLayout get dashboardLayout => _dashboardLayout;

  /// How often service groups re-query the OS, in milliseconds.
  int get servicePollMs => _servicePollMs;

  /// Updates [servicePollMs] and persists.
  void setServicePollMs(int value) {
    _servicePollMs = value;
    _saveGlobals();
    _serviceManager?.applyPollInterval(value);
  }

  /// Updates [outputRefreshMs] and persists.
  void setOutputRefreshMs(int value) {
    _outputRefreshMs = value;
    _saveGlobals();
  }

  /// Updates [outputHistoryLimit] and persists.
  void setOutputHistoryLimit(int value) {
    _outputHistoryLimit = value;
    _saveGlobals();
  }

  /// Updates [dashboardLayout] and persists.
  void setDashboardLayout(DashboardLayout value) {
    _dashboardLayout = value;
    _saveGlobals();
  }

  /// Stops a running process by name.
  Future<void> stopProcess(String name) async {
    await _processManager.stop(name);
  }

  /// Adds a new [ProcessConfig] to the end of the list and persists.
  void add(ProcessConfig config) {
    _configStore.validate(config);
    _processes = [..._processes, config];
    _save();
  }

  /// Replaces the config at [index] with [config] and persists.
  void edit(int index, ProcessConfig config) {
    _configStore.validate(config);
    _processes = List<ProcessConfig>.from(_processes);
    _processes[index] = config;
    _save();
  }

  /// Deletes the config at [index] and persists.
  ///
  /// The process is terminated by [ProcessManager.reloadConfig] via
  /// `applyRemoval` regardless of state — running, starting, cooldown,
  /// or mid-stop — so no orphaned OS process or stale pid file survives.
  void delete(int index) {
    _processes = List<ProcessConfig>.from(_processes);
    _processes.removeAt(index);
    _save();
  }

  /// Copies the config at [index], appending "(copy)" to the name.
  ///
  /// Handles name collisions by appending a number.
  void copy(int index) {
    final source = _processes[index];
    final baseName = '${source.name} (copy)';
    final newName = _uniqueName(baseName);

    _processes = List<ProcessConfig>.from(_processes);
    _processes.insert(index + 1, source.copyWith(name: newName));
    _save();
  }

  /// Reorders the config list and persists.
  ///
  /// Uses the pre-adjusted newIndex from [ReorderableListView.onReorderItem],
  /// which already accounts for the removed item at oldIndex.
  void reorderItem(int oldIndex, int newIndex) {
    _processes = List<ProcessConfig>.from(_processes);
    final item = _processes.removeAt(oldIndex);
    _processes.insert(newIndex, item);
    _save();
  }

  /// Whether trayforge is registered for OS-level autostart.
  bool get autostartEnabled => _autostart.isEnabled();

  /// Toggles OS-level autostart registration on or off.
  Future<void> toggleAutostart() async {
    if (_autostart.isEnabled()) {
      await _autostart.disable();
    } else {
      await _autostart.enable();
    }
    notifyListeners();
  }

  /// Validates a [ProcessConfig] using [ConfigStore.validate].
  ///
  /// Returns `null` on success, or an error message string on failure.
  String? validateConfig(ProcessConfig config) {
    try {
      _configStore.validate(config);
      return null;
    } on ArgumentError catch (e) {
      return e.message;
    }
  }

  // ---- Service groups ----

  /// Adds a service group to the end of the list and persists.
  void addService(ServiceConfig config) {
    _configStore.validateService(config);
    _services = [..._services, config];
    _save();
  }

  /// Replaces the service group at [index] and persists.
  void editService(int index, ServiceConfig config) {
    _configStore.validateService(config);
    _services = List<ServiceConfig>.from(_services);
    _services[index] = config;
    _save();
  }

  /// Removes the service group at [index] and persists.
  ///
  /// The services themselves keep running: TrayForge never owned them.
  void deleteService(int index) {
    _services = List<ServiceConfig>.from(_services);
    _services.removeAt(index);
    _save();
  }

  /// Validates a [ServiceConfig], returning `null` or an error message.
  String? validateServiceConfig(ServiceConfig config) {
    try {
      _configStore.validateService(config);
      return null;
    } on ArgumentError catch (e) {
      return e.message;
    }
  }

  /// Reloads from [ConfigStore] when [ProcessManager.onConfigReloaded] fires.
  void _reload() {
    final config = _configStore.load();
    _processes = config?.processes.toList() ?? [];
    _services = config?.services.toList() ?? [];
    _outputRefreshMs = config?.outputRefreshMs ?? 500;
    _outputHistoryLimit = config?.outputHistoryLimit ?? 1000;
    _servicePollMs = config?.servicePollMs ?? 5000;
    _dashboardLayout = config?.dashboardLayout ?? DashboardLayout.list;
    notifyListeners();
  }

  /// Persists only global settings (refresh interval, history limit, service
  /// poll interval, dashboard layout).
  ///
  /// Writes to disk and notifies listeners. Does **not** call
  /// [ProcessManager.reloadConfig] — globals take effect on next process
  /// start and don't require a hot reload.
  ///
  /// Every global and both config lists must be carried here: writing only the
  /// edited value would silently drop processes or services from disk.
  void _saveGlobals() {
    final config = _configStore.load() ?? AppConfig.defaultConfig();
    final newConfig = AppConfig(
      outputRefreshMs: _outputRefreshMs,
      outputHistoryLimit: _outputHistoryLimit,
      servicePollMs: _servicePollMs,
      dashboardLayout: _dashboardLayout,
      processes: List<ProcessConfig>.from(config.processes),
      services: List<ServiceConfig>.from(config.services),
    );
    _configStore.save(newConfig);
    notifyListeners();
  }

  /// Persists the current process/service lists and triggers a hot reload.
  ///
  /// Follows Path A from the spec:
  ///   1. ConfigStore.save() — write disk only
  ///   2. ProcessManager.reloadConfig() / ServiceManager.reloadConfig() —
  ///      stop/start + emit onConfigReloaded
  void _save() {
    final config = _configStore.load() ?? AppConfig.defaultConfig();
    final newConfig = AppConfig(
      outputHistoryLimit: config.outputHistoryLimit,
      outputRefreshMs: config.outputRefreshMs,
      servicePollMs: config.servicePollMs,
      dashboardLayout: config.dashboardLayout,
      processes: _processes,
      services: _services,
    );
    _configStore.save(newConfig);
    _processManager.reloadConfig(newConfig);
    _serviceManager?.reloadConfig(newConfig);
    notifyListeners();
  }

  /// Generates a unique name by appending a counter if needed.
  String _uniqueName(String base) {
    final existing = _processes.map((p) => p.name).toSet();
    if (!existing.contains(base)) return base;

    var counter = 2;
    while (existing.contains('$base ($counter)')) {
      counter++;
    }
    return '$base ($counter)';
  }

  @override
  void dispose() {
    _configSub?.cancel();
    super.dispose();
  }
}

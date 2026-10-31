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
/// Holds a mutable copy of the [AppConfig.units] list, supports add/edit/
/// delete/copy/reorder operations on unit indexes, validates via
/// [ConfigStore.validate], and persists changes through
/// [ProcessManager.reloadConfig] / [ServiceManager.reloadConfig].
///
/// Both kinds live in the same list: the dashboard's card order *is* the
/// config order, so a reorder here is the whole ordering story.
class SettingsViewModel extends ChangeNotifier {
  final ConfigStore _configStore;
  final ProcessManager _processManager;
  final ServiceManager? _serviceManager;
  final Autostart _autostart;

  List<UnitConfig> _units = [];
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

  /// All units in dashboard order.
  List<UnitConfig> get units => List.unmodifiable(_units);

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

  /// Adds [unit] to the end of the unit list and persists.
  void addUnit(UnitConfig unit) {
    _configStore.validate(unit);
    _units = [..._units, unit];
    _save();
  }

  /// Replaces the unit at [unitIndex] with [unit] and persists.
  void editUnit(int unitIndex, UnitConfig unit) {
    _configStore.validate(unit);
    _replaceUnit(unitIndex, unit);
  }

  /// Deletes the unit at [unitIndex] and persists.
  ///
  /// A deleted process is terminated by [ProcessManager.reloadConfig] via
  /// `applyRemoval` regardless of state — running, starting, cooldown, or
  /// mid-stop — so no orphaned OS process or stale pid file survives. A deleted
  /// service group leaves its services running: TrayForge never owned them.
  void deleteUnit(int unitIndex) {
    _units = List<UnitConfig>.from(_units);
    _units.removeAt(unitIndex);
    _save();
  }

  /// Copies the unit at [unitIndex] right after it, appending "(copy)".
  ///
  /// Handles name collisions by appending a number.
  void copyUnit(int unitIndex) {
    final source = _units[unitIndex];
    final newName = _uniqueName('${source.name} (copy)');

    _units = List<UnitConfig>.from(_units)
      ..insert(unitIndex + 1, source.renamed(newName));
    _save();
  }

  /// Reorders the unit list and persists the new order.
  ///
  /// Uses the pre-adjusted newIndex from [ReorderableListView.onReorderItem],
  /// which already accounts for the removed item at oldIndex. Moving a unit
  /// past a unit of the other kind is just a move: the list has no kinds.
  ///
  /// Deliberately does not touch the managers (see [_saveOrder]): a drag must
  /// not restart anything.
  void reorderItem(int oldIndex, int newIndex) {
    _units = List<UnitConfig>.from(_units);
    final unit = _units.removeAt(oldIndex);
    _units.insert(newIndex, unit);
    _saveOrder();
  }

  /// Replaces the unit at [unitIndex] and persists.
  void _replaceUnit(int unitIndex, UnitConfig unit) {
    _units = List<UnitConfig>.from(_units);
    _units[unitIndex] = unit;
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

  /// Re-reads `config.json` from disk and applies it without restarting.
  ///
  /// The in-memory lists are refreshed first, so a later edit cannot write a
  /// stale config back. Both coordinators then hot-swap: processes removed from
  /// the file are stopped (the usual reload semantics), new/serviced groups are
  /// materialized and the pages rebuild through `onConfigReloaded`.
  ///
  /// Returns `false` when the file is missing or unparsable — a corrupted file
  /// is backed up and reported by [ConfigStore].
  Future<bool> reloadFromDisk() async {
    final config = _configStore.load();
    if (config == null) return false;

    _reload();
    await _processManager.reloadConfig(config);
    await _serviceManager?.reloadConfig(config);
    return true;
  }

  /// Validates a [UnitConfig] using [ConfigStore.validate].
  ///
  /// Returns `null` on success, or an error message string on failure.
  String? validateUnit(UnitConfig unit) {
    try {
      _configStore.validate(unit);
      return null;
    } on ArgumentError catch (e) {
      return e.message;
    }
  }

  /// Reloads from [ConfigStore] when [ProcessManager.onConfigReloaded] fires.
  void _reload() {
    final config = _configStore.load();
    _units = config?.units.toList() ?? [];
    _outputRefreshMs = config?.outputRefreshMs ?? 500;
    _outputHistoryLimit = config?.outputHistoryLimit ?? 1000;
    _servicePollMs = config?.servicePollMs ?? 5000;
    _dashboardLayout = config?.dashboardLayout ?? DashboardLayout.list;
    notifyListeners();
  }

  /// Assembles a complete [AppConfig] from the current in-memory state.
  ///
  /// Every write path goes through this. Assembling in one place is what keeps
  /// a global from landing in three separate `AppConfig(...)` literals: a write
  /// that carried only the edited half would silently drop the other half from
  /// disk.
  AppConfig _buildConfig() => AppConfig(
    outputHistoryLimit: _outputHistoryLimit,
    outputRefreshMs: _outputRefreshMs,
    servicePollMs: _servicePollMs,
    dashboardLayout: _dashboardLayout,
    units: List<UnitConfig>.from(_units),
  );

  /// Persists only global settings (refresh interval, history limit, service
  /// poll interval, dashboard layout).
  ///
  /// Writes to disk and notifies listeners. Does **not** call
  /// [ProcessManager.reloadConfig] — globals take effect on next process
  /// start and don't require a hot reload.
  void _saveGlobals() {
    _configStore.save(_buildConfig());
    notifyListeners();
  }

  /// Persists the current unit order without touching the managers.
  ///
  /// A reorder is a list move, not a change the managers need to act on:
  /// [ProcessManager.reloadConfig] starts every `autostart` process that is in
  /// a terminal state, so routing a drag through it would silently start a
  /// process the user had stopped by hand (and re-apply diffs no order change
  /// needs). The order is persisted here; the dashboard applies it immediately
  /// from `units` through `DashboardViewModel.orderedBy`, while the tray and
  /// the next manager reload both read the config and therefore agree.
  void _saveOrder() {
    _configStore.save(_buildConfig());
    notifyListeners();
  }

  /// Persists the current unit list and triggers a hot reload.
  ///
  /// Follows Path A from the spec:
  ///   1. ConfigStore.save() — write disk only
  ///   2. ProcessManager.reloadConfig() / ServiceManager.reloadConfig() —
  ///      stop/start + emit onConfigReloaded
  void _save() {
    final config = _buildConfig();
    _configStore.save(config);
    _processManager.reloadConfig(config);
    _serviceManager?.reloadConfig(config);
    notifyListeners();
  }

  /// Generates a unique name by appending a counter if needed.
  ///
  /// Copies are checked across every unit, not just the unit's own kind: the
  /// keys could tell a process and a group apart, but a copy must never put
  /// two cards with the same label on the dashboard (ADR 006).
  String _uniqueName(String base) {
    final existing = _units.map((u) => u.name).toSet();
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

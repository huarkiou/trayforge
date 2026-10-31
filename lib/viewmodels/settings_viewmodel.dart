// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/l10n/app_localizations.dart';
import 'package:trayforge/l10n/locale_resolution.dart';
import 'package:trayforge/services/autostart.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/services/service_manager.dart';

/// ViewModel for the Settings page.
///
/// Holds a mutable copy of the [AppConfig.units] list, supports add/edit/
/// delete/copy operations on unit indexes and identity-based moves, validates
/// via [ConfigStore.validate], and persists changes: structural edits reload
/// both managers through [ProcessManager.reloadConfig] /
/// [ServiceManager.reloadConfig], while globals and reorders write the file
/// without a reload.
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
  String? _language;

  /// The resolved locale, published for `MaterialApp`.
  final ValueNotifier<Locale?> _locale = ValueNotifier<Locale?>(null);

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

  /// The persisted language tag (`en`, `zh`), or `null` to follow the OS.
  ///
  /// Normalized on read and on write, so the value is always a tag of a shipped
  /// locale or `null` — a hand-edited `zh-CN` reads back as `zh`, an unsupported
  /// `ja` reads back as `null`.
  String? get language => _language;

  /// The locale to hand to `MaterialApp`, or `null` to follow the OS.
  Locale? get locale => _locale.value;

  /// A listenable that fires only when the language changes.
  ///
  /// The settings notifier fires for every setting (the numeric steppers
  /// included), but `main` only needs to rebuild the `MaterialApp` when the
  /// locale moved — rebuilding it on a stepper edit would churn the whole
  /// widget tree.
  ValueListenable<Locale?> get localeListenable => _locale;

  /// The resolved strings for code outside the widget tree (tray, window
  /// title). Inside a widget, use `AppLocalizations.of(context)`.
  AppLocalizations get localizations => localizationsFor(_language);

  /// Updates the UI language and persists it.
  ///
  /// Passing `null` (the "System default" entry) clears the override. The
  /// change takes effect immediately: [localeListenable] rebuilds the
  /// `MaterialApp`, and `main` re-sets the window title and the tray menu.
  void setLanguage(String? tag) {
    _applyLanguage(tag);
    _persistWithoutReload();
  }

  /// Normalizes [tag] to a shipped tag, stores it, and publishes the locale.
  ///
  /// One place for the read path and the write path, so the getter and the
  /// listenable can never disagree.
  void _applyLanguage(String? tag) {
    final locale = parseLanguageTag(tag);
    _language = locale?.toLanguageTag();
    _locale.value = locale;
  }

  /// Updates [servicePollMs] and persists.
  void setServicePollMs(int value) {
    _servicePollMs = value;
    _persistWithoutReload();
    _serviceManager?.applyPollInterval(value);
  }

  /// Updates [outputRefreshMs] and persists.
  void setOutputRefreshMs(int value) {
    _outputRefreshMs = value;
    _persistWithoutReload();
  }

  /// Updates [outputHistoryLimit] and persists.
  void setOutputHistoryLimit(int value) {
    _outputHistoryLimit = value;
    _persistWithoutReload();
  }

  /// Updates [dashboardLayout] and persists.
  void setDashboardLayout(DashboardLayout value) {
    _dashboardLayout = value;
    _persistWithoutReload();
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

  /// Moves the unit identified by [kind] and [name] so it sits directly before
  /// the unit identified by [before], or at the end when [before] is null.
  ///
  /// Identity, not indexes: the dashboard renders this list's order through
  /// [DashboardViewModel.unitsInOrder], and while a deleted or renamed unit is
  /// still in the dashboard view model the rendered list can differ from this
  /// list by a card — a rendered index would move the wrong unit or run past the
  /// end. A unit that is not in the list is a no-op; an unknown [before] appends;
  /// naming the moved unit itself is a no-op.
  void moveUnitBefore(
    UnitKind kind,
    String name, {
    (UnitKind, String)? before,
  }) {
    final moving = _units.indexWhere((unit) => _isUnit(unit, kind, name));
    if (moving < 0) return;

    if (before != null && _isUnit(_units[moving], before.$1, before.$2)) {
      return;
    }

    final unit = _units[moving];
    final rest = List<UnitConfig>.of(_units)..removeAt(moving);
    final target = before == null
        ? -1
        : rest.indexWhere((other) => _isUnit(other, before.$1, before.$2));

    rest.insert(target < 0 ? rest.length : target, unit);
    _units = rest;
    _persistWithoutReload();
  }

  /// Whether [unit] is the unit identified by [kind] and [name].
  ///
  /// The managers key their controllers by kind + name, so this is the identity
  /// a config-level move can safely use; [DashboardUnit.matches] is for
  /// dashboard view-model units, not configs.
  static bool _isUnit(UnitConfig unit, UnitKind kind, String name) =>
      unit.kind == kind && unit.name == name;

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
  /// Returns `null` on success, or the rejection on failure. The edit pages
  /// format it with `describe(AppLocalizations)`, so the message language
  /// follows the UI.
  UnitValidationError? validateUnit(UnitConfig unit) {
    try {
      _configStore.validate(unit);
      return null;
    } on UnitValidationError catch (e) {
      return e;
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
    _applyLanguage(config?.language);
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
    language: _language,
    units: List<UnitConfig>.from(_units),
  );

  /// Persists the current in-memory config without touching the managers.
  ///
  /// Two callers, neither of which has anything to reload: a global setting
  /// (takes effect on the next launch/start) and a reorder (a list move —
  /// [ProcessManager.reloadConfig] runs the autostart path and would start a
  /// process the user stopped by hand). The dashboard applies a new order
  /// immediately through [DashboardViewModel.unitsInOrder]; the tray and the
  /// next reload of either manager read the config.
  void _persistWithoutReload() {
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
    _locale.dispose();
    super.dispose();
  }
}

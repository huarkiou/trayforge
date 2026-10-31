import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:desktop_tray/desktop_tray.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/services/service_manager.dart';

/// Three-colour tray icon state.
enum TrayColor { green, yellow, red }

/// ViewModel for tray icon state, menu, and interactions.
///
/// Listens to [ProcessManager] and (when wired) [ServiceManager] so the tray
/// colour and menu labels follow live state. The menu lists processes and
/// service groups; both route through the same toggle facades the dashboard
/// uses, so start/stop decisions never live here.
class TrayViewModel extends ChangeNotifier {
  final ConfigStore _configStore;
  final ProcessManager _processManager;
  final ServiceManager? serviceManager;

  /// Called when the user requests the Dashboard window.
  final VoidCallback onShowDashboard;

  /// Called when the user requests app exit.
  final Future<void> Function() onExit;

  /// Called when the user asks to reload the config from disk.
  ///
  /// Shared with the Settings page action, so a manual `config.json` edit
  /// hot-swaps **processes and service groups** and refreshes the in-memory
  /// lists. When absent, the tray falls back to reloading processes alone.
  final Future<void> Function()? onReloadConfig;

  TrayColor _color = TrayColor.red;
  final Map<String, ProcState> _states = {};
  final Map<String, ProcState> _serviceStates = {};

  /// Config-reload subscriptions. Kept apart from the per-unit state
  /// subscriptions because [_rebuildSubscriptions] replaces those: cancelling
  /// this list there would stop the tray from ever hearing about config
  /// changes again.
  final List<StreamSubscription<void>> _configSubscriptions = [];

  final List<StreamSubscription<ProcState>> _stateSubscriptions = [];

  TrayViewModel({
    required this._configStore,
    required this._processManager,
    this.serviceManager,
    required this.onShowDashboard,
    required this.onExit,
    this.onReloadConfig,
  }) {
    _rebuildSubscriptions();

    _configSubscriptions.add(
      _processManager.onConfigReloaded.listen((_) => onConfigChanged()),
    );
    final reloadingManager = serviceManager;
    if (reloadingManager != null) {
      _configSubscriptions.add(
        reloadingManager.onConfigReloaded.listen((_) => onConfigChanged()),
      );
    }
  }

  // ---- Public API ----

  /// Current tray colour based on process states.
  ///
  /// Service groups are deliberately excluded: the colour has always meant
  /// "how many managed processes are up", and services are not children of the
  /// app. They show their own state in the menu labels.
  TrayColor get color => _color;

  /// Returns the icon asset path for the current colour.
  ///
  /// Uses .ico on Windows (Win32 LoadImage with IMAGE_ICON does not
  /// support PNG) and .png on Linux (libappindicator / StatusNotifierItem).
  String get iconPath {
    final ext = Platform.isWindows ? 'ico' : 'png';
    switch (_color) {
      case TrayColor.green:
        return 'assets/icons/icon-green.$ext';
      case TrayColor.yellow:
        return 'assets/icons/icon-yellow.$ext';
      case TrayColor.red:
        return 'assets/icons/icon-red.$ext';
    }
  }

  /// Builds the tray context menu from the current process and service lists.
  TrayMenu buildMenu() {
    final config = _configStore.load();
    final processes = config?.processes ?? <ProcessConfig>[];
    final services = config?.services ?? <ServiceConfig>[];

    final items = <TrayMenuItem>[];

    // Dynamic process items — the key routes the click back here via
    // [handleMenuAction]; desktop_tray has no per-item onClick closure.
    for (final proc in processes) {
      final name = proc.name;
      final state = _states[name] ?? ProcState.stopped;
      final isRunning = state.isActive;
      final label = isRunning ? '\u2713 $name' : '   $name';
      items.add(TrayMenuItem(key: 'proc:$name', label: label));
    }

    if (services.isNotEmpty) {
      if (items.isNotEmpty) items.add(TrayMenuItem.separator());
      for (final group in services) {
        final name = group.name;
        final state = _serviceStates[name] ?? ProcState.stopped;
        // A group is "up" when any member is up; starting counts too, so the
        // check appears as soon as the operation begins.
        final isUp = state.isActive;
        final label = isUp ? '\u2713 $name' : '   $name';
        items.add(TrayMenuItem(key: 'svc:$name', label: label));
      }
    }

    if (items.isNotEmpty) {
      items.add(TrayMenuItem.separator());
    }

    // Fixed items
    items.add(TrayMenuItem(key: 'reload', label: 'Reload Settings'));
    items.add(TrayMenuItem(key: 'dashboard', label: 'Dashboard'));
    items.add(TrayMenuItem(key: 'exit', label: 'Exit'));

    return TrayMenu(items: items);
  }

  /// Routes a tray menu click to the action behind its [key].
  ///
  /// Keys are `proc:<name>` (toggle a process), `svc:<name>` (toggle a service
  /// group), and the fixed `reload` / `dashboard` / `exit`.
  void handleMenuAction(String key) {
    if (key.startsWith('proc:')) {
      _toggleProcess(key.substring('proc:'.length));
      return;
    }
    if (key.startsWith('svc:')) {
      _toggleService(key.substring('svc:'.length));
      return;
    }
    switch (key) {
      case 'reload':
        unawaited(_reloadConfig());
      case 'dashboard':
        onShowDashboard();
      case 'exit':
        onExit();
    }
  }

  /// Called when the process or service list changes (config reload).
  void onConfigChanged() {
    _rebuildSubscriptions();
    notifyListeners();
  }

  /// Releases subscriptions.
  @override
  void dispose() {
    for (final sub in [..._configSubscriptions, ..._stateSubscriptions]) {
      sub.cancel();
    }
    _configSubscriptions.clear();
    _stateSubscriptions.clear();
    super.dispose();
  }

  // ---- Private ----

  void _rebuildSubscriptions() {
    for (final sub in _stateSubscriptions) {
      sub.cancel();
    }
    _stateSubscriptions.clear();
    _states.clear();
    _serviceStates.clear();

    final config = _configStore.load();
    final processes = config?.processes ?? <ProcessConfig>[];
    final services = config?.services ?? <ServiceConfig>[];

    for (final proc in processes) {
      final name = proc.name;
      // Seed from ProcessManager synchronously so the colour is correct
      // before the first async stateStream event fires.
      _states[name] = _processManager.getState(name);
      _stateSubscriptions.add(
        _processManager.stateStream(name).listen((state) {
          _states[name] = state;
          _recomputeColor(processes);
          notifyListeners();
        }),
      );
    }

    if (serviceManager != null) {
      final groups = serviceManager!;
      for (final group in services) {
        final name = group.name;
        _serviceStates[name] = groups.getState(name);
        _stateSubscriptions.add(
          groups.stateStream(name).listen((state) {
            _serviceStates[name] = state;
            notifyListeners();
          }),
        );
      }
    }

    _recomputeColor(processes);
  }

  void _recomputeColor(List<ProcessConfig> processes) {
    if (processes.isEmpty) {
      _color = TrayColor.red;
      return;
    }

    var runningCount = 0;
    for (final proc in processes) {
      final state = _states[proc.name] ?? ProcState.stopped;
      if (state == ProcState.running) {
        runningCount++;
      }
    }

    if (runningCount == processes.length) {
      _color = TrayColor.green;
    } else if (runningCount > 0) {
      _color = TrayColor.yellow;
    } else {
      _color = TrayColor.red;
    }
  }

  void _toggleProcess(String name) {
    // The start/stop decision lives in ProcessController.toggle — the
    // tray only routes the click through the facade.
    _processManager.toggle(name);
  }

  void _toggleService(String name) {
    // ServiceController.toggle owns the aggregate rule (any member up → stop
    // all), including the single UAC prompt for the whole group.
    serviceManager?.toggle(name);
  }

  /// Reloads the config from disk and applies it (Path C from spec).
  ///
  /// Delegates to the shared reload path when wired (processes **and** service
  /// groups); the process-only fallback keeps the tray usable in isolation.
  Future<void> _reloadConfig() async {
    final reload = onReloadConfig;
    if (reload != null) {
      await reload();
      return;
    }

    final config = _configStore.load();
    if (config != null) {
      await _processManager.reloadConfig(config);
    }
  }
}

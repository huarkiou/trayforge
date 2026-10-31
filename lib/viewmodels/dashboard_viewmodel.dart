// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/services/service_manager.dart';
import 'package:trayforge/viewmodels/process_viewmodel.dart';
import 'package:trayforge/viewmodels/service_viewmodel.dart';

/// One card in the dashboard flow.
///
/// A unit is either a process or a service group; both are view models with a
/// name and live state, so the dashboard can render them in one ordered list
/// and move them with one drag. The kind-specific parts (output preview,
/// per-service rows) stay in the card widgets.
sealed class DashboardEntry {
  const DashboardEntry();

  /// Display name, as configured.
  String get name;

  /// Stable identity across both kinds, used as the widget key.
  ///
  /// Names are unique within a kind but not across kinds, so the id carries
  /// the kind prefix: `proc:<name>` / `svc:<name>`.
  String get id;
}

/// A process card in the dashboard flow.
final class ProcessEntry extends DashboardEntry {
  final ProcessViewModel viewModel;

  const ProcessEntry(this.viewModel);

  @override
  String get name => viewModel.name;

  @override
  String get id => 'proc:$name';
}

/// A service group card in the dashboard flow.
final class ServiceEntry extends DashboardEntry {
  final ServiceViewModel viewModel;

  const ServiceEntry(this.viewModel);

  @override
  String get name => viewModel.name;

  @override
  String get id => 'svc:$name';
}

/// ViewModel for the Dashboard window.
///
/// Owns one view model per configured [unit][AppConfig.units], in config order,
/// and exposes them as a single ordered [entries] list so processes and service
/// groups share one card flow. Rebuilds whenever either manager reloads the
/// config, reusing existing view models so logs and subscriptions survive an
/// edit. [isEmpty] tells the UI to show the welcome screen.
class DashboardViewModel extends ChangeNotifier {
  final ConfigStore _configStore;
  final ProcessManager _processManager;
  final ServiceManager _serviceManager;

  final List<ProcessViewModel> _processViewModels = [];
  final List<ServiceViewModel> _serviceViewModels = [];
  List<DashboardEntry> _entries = const [];
  bool _configCorrupted;

  /// Config-reload subscriptions, one per manager. Both fire on a save, so the
  /// rebuild path is shared; the list is kept so [dispose] can cancel them.
  final List<StreamSubscription<void>> _configSubs = [];

  /// App title shown in the window title bar and Dashboard header.
  static const String appTitle = 'trayforge';

  DashboardViewModel({
    required ConfigStore configStore,
    required ProcessManager processManager,
    required ServiceManager serviceManager,
    bool configCorrupted = false,
  }) : _configStore = configStore,
       _processManager = processManager,
       _serviceManager = serviceManager,
       _configCorrupted = configCorrupted {
    _rebuild();
    _configSubs.add(processManager.onConfigReloaded.listen((_) => _rebuild()));
    _configSubs.add(serviceManager.onConfigReloaded.listen((_) => _rebuild()));
  }

  /// All cards, in config order: processes and service groups interleaved.
  List<DashboardEntry> get entries => List.unmodifiable(_entries);

  /// The process view models among the cards, in config order.
  List<ProcessViewModel> get processViewModels =>
      List.unmodifiable(_processViewModels);

  /// The service group view models among the cards, in config order.
  List<ServiceViewModel> get serviceViewModels =>
      List.unmodifiable(_serviceViewModels);

  /// Whether there is nothing to show (no processes and no service groups).
  bool get isEmpty => _entries.isEmpty;

  /// Whether a corrupted config was detected at startup.
  bool get configCorrupted => _configCorrupted;

  /// Clears the corrupted flag after the dialog has been shown.
  void clearCorruptedFlag() {
    _configCorrupted = false;
  }

  void _rebuild() {
    final config = _configStore.load();
    final units = config?.units ?? const <UnitConfig>[];
    final outputHistoryLimit = config?.outputHistoryLimit ?? 1000;

    // Reuse by name so an edit keeps the existing view model (and its log).
    final processesByName = <String, ProcessViewModel>{
      for (final vm in _processViewModels) vm.name: vm,
    };
    final servicesByName = <String, ServiceViewModel>{
      for (final vm in _serviceViewModels) vm.name: vm,
    };

    final entries = <DashboardEntry>[];
    final processes = <ProcessViewModel>[];
    final services = <ServiceViewModel>[];

    for (final unit in units) {
      switch (unit) {
        case ProcessConfig():
          final vm =
              processesByName.remove(unit.name) ??
              ProcessViewModel(
                name: unit.name,
                processManager: _processManager,
                outputHistoryLimit: outputHistoryLimit,
              );
          processes.add(vm);
          entries.add(ProcessEntry(vm));
        case ServiceConfig():
          final vm =
              servicesByName.remove(unit.name) ??
              ServiceViewModel(
                name: unit.name,
                serviceManager: _serviceManager,
                outputHistoryLimit: outputHistoryLimit,
              );
          services.add(vm);
          entries.add(ServiceEntry(vm));
      }
    }

    // Dispose the view models of units that no longer exist.
    for (final vm in processesByName.values) {
      vm.dispose();
    }
    for (final vm in servicesByName.values) {
      vm.dispose();
    }

    _processViewModels
      ..clear()
      ..addAll(processes);
    _serviceViewModels
      ..clear()
      ..addAll(services);
    _entries = entries;

    notifyListeners();
  }

  @override
  void dispose() {
    for (final sub in _configSubs) {
      sub.cancel();
    }
    for (final vm in _processViewModels) {
      vm.dispose();
    }
    for (final vm in _serviceViewModels) {
      vm.dispose();
    }
    super.dispose();
  }
}

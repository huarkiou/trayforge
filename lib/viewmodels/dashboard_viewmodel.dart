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
sealed class DashboardUnit {
  const DashboardUnit();

  /// Which kind of card this is.
  UnitKind get kind;

  /// Display name, as configured.
  String get name;

  /// Stable identity across both kinds, used as the widget key.
  ///
  /// Names are unique within a kind but not across kinds, so the id carries
  /// the kind prefix: `proc:<name>` / `svc:<name>`.
  String get id => '${kind.keyPrefix}$name';

  /// Whether this card is the same unit as [config]: same kind and name.
  bool matches(UnitConfig config) => kind == config.kind && name == config.name;
}

/// A process card in the dashboard flow.
final class ProcessUnit extends DashboardUnit {
  final ProcessViewModel viewModel;

  const ProcessUnit(this.viewModel);

  @override
  UnitKind get kind => UnitKind.process;

  @override
  String get name => viewModel.name;
}

/// A service group card in the dashboard flow.
final class ServiceUnit extends DashboardUnit {
  final ServiceViewModel viewModel;

  const ServiceUnit(this.viewModel);

  @override
  UnitKind get kind => UnitKind.service;

  @override
  String get name => viewModel.name;
}

/// ViewModel for the Dashboard window.
///
/// Owns one view model per configured [unit][AppConfig.units], in config order,
/// and exposes them as a single ordered [units] list so processes and service
/// groups share one card flow. Rebuilds whenever either manager reloads the
/// config, reusing existing view models so logs and subscriptions survive an
/// edit. [isEmpty] tells the UI to show the welcome screen.
class DashboardViewModel extends ChangeNotifier {
  final ConfigStore _configStore;
  final ProcessManager _processManager;
  final ServiceManager _serviceManager;

  final List<ProcessViewModel> _processViewModels = [];
  final List<ServiceViewModel> _serviceViewModels = [];
  List<DashboardUnit> _units = const [];
  bool _configCorrupted;

  /// Config-reload subscriptions, one per manager, both needed.
  ///
  /// Either manager can reload on its own (a tray "Reload Settings", a manual
  /// edit applied through one coordinator), and every rebuild re-reads the
  /// config from disk. When a save fires both, the second rebuild is an
  /// idempotent pass: it finds the same names and reuses the same view
  /// models, so no coalescing machinery is warranted. The list is kept so
  /// [dispose] can cancel them.
  final List<StreamSubscription<void>> _configSubs = [];

  /// App title shown in the window title bar and Dashboard header.
  static const String appTitle = 'trayforge';

  /// The window title, marked when TrayForge itself runs elevated.
  ///
  /// The suffix is the at-a-glance signal that this instance holds the
  /// administrator token — and therefore that every process it starts
  /// inherits it and an `elevated` launch skips the UAC prompt.
  static String windowTitle({required bool elevated}) =>
      elevated ? '$appTitle (Administrator)' : appTitle;

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
  List<DashboardUnit> get units => List.unmodifiable(_units);

  /// The dashboard units in [order].
  ///
  /// Units [order] does not mention are **omitted**: the order comes from the
  /// config, so a unit missing from it is one the config no longer has, and its
  /// view model only survives until the managers' reload lands. Order entries
  /// with no view model yet (a just-added unit) are skipped too.
  List<DashboardUnit> unitsInOrder(List<UnitConfig> order) {
    final remaining = List<DashboardUnit>.of(_units);
    final ordered = <DashboardUnit>[];

    for (final config in order) {
      for (var i = 0; i < remaining.length; i++) {
        if (remaining[i].matches(config)) {
          ordered.add(remaining.removeAt(i));
          break;
        }
      }
    }

    return ordered;
  }

  /// Whether there is nothing to show (no processes and no service groups).
  bool get isEmpty => _units.isEmpty;

  /// Whether a corrupted config was detected at startup.
  bool get configCorrupted => _configCorrupted;

  /// Clears the corrupted flag after the dialog has been shown.
  void clearCorruptedFlag() {
    _configCorrupted = false;
  }

  void _rebuild() {
    final config = _configStore.load();
    final configuredUnits = config?.units ?? const <UnitConfig>[];
    final outputHistoryLimit = config?.outputHistoryLimit ?? 1000;

    // Reuse by name so an edit keeps the existing view model (and its log).
    final processesByName = <String, ProcessViewModel>{
      for (final vm in _processViewModels) vm.name: vm,
    };
    final servicesByName = <String, ServiceViewModel>{
      for (final vm in _serviceViewModels) vm.name: vm,
    };

    final dashboardUnits = <DashboardUnit>[];
    final processes = <ProcessViewModel>[];
    final services = <ServiceViewModel>[];

    for (final unit in configuredUnits) {
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
          dashboardUnits.add(ProcessUnit(vm));
        case ServiceConfig():
          final vm =
              servicesByName.remove(unit.name) ??
              ServiceViewModel(
                name: unit.name,
                serviceManager: _serviceManager,
                outputHistoryLimit: outputHistoryLimit,
              );
          services.add(vm);
          dashboardUnits.add(ServiceUnit(vm));
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
    _units = dashboardUnits;

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

// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/service_manager.dart';
import 'package:trayforge/viewmodels/service_viewmodel.dart';

/// ViewModel for the Services page.
///
/// Holds one [ServiceViewModel] per configured group and rebuilds the list when
/// the service config is reloaded, reusing existing view models so their logs
/// and subscriptions survive an edit.
class ServicesViewModel extends ChangeNotifier {
  final ConfigStore _configStore;
  final ServiceManager _serviceManager;

  final List<ServiceViewModel> _serviceViewModels = [];
  bool _disposed = false;
  StreamSubscription<void>? _configSub;

  ServicesViewModel({
    required ConfigStore configStore,
    required ServiceManager serviceManager,
  }) : _configStore = configStore,
       _serviceManager = serviceManager {
    _rebuild();
    _configSub = serviceManager.onConfigReloaded.listen((_) => _rebuild());
  }

  /// All service group view models, in config order.
  List<ServiceViewModel> get serviceViewModels =>
      List.unmodifiable(_serviceViewModels);

  bool get isEmpty => _serviceViewModels.isEmpty;

  void _rebuild() {
    final config = _configStore.load();
    final groups = config?.services ?? const <ServiceConfig>[];
    final outputHistoryLimit = config?.outputHistoryLimit ?? 1000;

    final existingByName = <String, ServiceViewModel>{};
    for (final vm in _serviceViewModels) {
      existingByName[vm.name] = vm;
    }

    final newVms = <ServiceViewModel>[];
    for (final group in groups) {
      final existing = existingByName.remove(group.name);
      newVms.add(
        existing ??
            ServiceViewModel(
              name: group.name,
              serviceManager: _serviceManager,
              outputHistoryLimit: outputHistoryLimit,
            ),
      );
    }

    for (final vm in existingByName.values) {
      vm.dispose();
    }

    _serviceViewModels
      ..clear()
      ..addAll(newVms);
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _configSub?.cancel();
    for (final vm in _serviceViewModels) {
      vm.dispose();
    }
    super.dispose();
  }
}

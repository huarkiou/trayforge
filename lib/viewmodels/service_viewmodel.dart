// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/foundation/service_status.dart';
import 'package:trayforge/services/service_manager.dart';

/// ViewModel for one configured service group.
///
/// Mirrors the aggregate [ProcState], keeps the last per-service statuses and
/// the operation log (bounded by [outputHistoryLimit]), and shows a spinner
/// while a toggle is in flight. The start/stop decision lives in
/// `ServiceController.toggle` — not here.
class ServiceViewModel extends ChangeNotifier {
  final String name;
  final ServiceManager _serviceManager;
  final int _outputHistoryLimit;

  bool _disposed = false;
  ProcState _state = ProcState.stopped;
  List<ServiceStatus> _statuses = const [];
  final List<String> _outputLines = [];
  bool _transitioning = false;

  StreamSubscription<ProcState>? _stateSub;
  StreamSubscription<List<ServiceStatus>>? _statusesSub;
  StreamSubscription<String>? _outputSub;

  ServiceViewModel({
    required this.name,
    required ServiceManager serviceManager,
    required int outputHistoryLimit,
  }) : _serviceManager = serviceManager,
       _outputHistoryLimit = outputHistoryLimit {
    _state = serviceManager.getState(name);
    _statuses = serviceManager.statuses(name);

    _stateSub = serviceManager.stateStream(name).listen(_onState);
    _statusesSub = serviceManager.statusesStream(name).listen(_onStatuses);
    _outputSub = serviceManager.outputStream(name).listen(_onOutput);
  }

  /// Aggregate state of the group.
  ProcState get state => _state;

  /// Last per-service status snapshot.
  List<ServiceStatus> get statuses => List.unmodifiable(_statuses);

  /// Operation log lines, bounded by [_outputHistoryLimit].
  List<String> get outputLines => List.unmodifiable(_outputLines);

  /// Whether a toggle is awaiting completion (spinner state).
  bool get isTransitioning => _transitioning;

  /// How many members are up.
  int get runningCount => _statuses.where((s) => s.state.isUp).length;

  int get totalCount => _statuses.length;

  /// What the toggle would do right now: "any member up → stop all".
  ///
  /// The button offers Stop exactly when the toggle would stop, so this uses
  /// the toggle rule's own input ([anyServiceUp]). Before the first query the
  /// list is empty and the button offers Start, which matches the toggle.
  /// [ProcState.isActive] would be wrong here: a crashed group with a member
  /// still running must offer "Stop".
  bool get isUp => anyServiceUp(_statuses);

  Future<void> toggle() async {
    if (_transitioning) return;
    _transitioning = true;
    notifyListeners();
    try {
      await _serviceManager.toggle(name);
    } finally {
      if (!_disposed) {
        _transitioning = false;
        notifyListeners();
      }
    }
  }

  void clearOutput() {
    _outputLines.clear();
    notifyListeners();
  }

  void _onState(ProcState state) {
    _state = state;
    notifyListeners();
  }

  void _onStatuses(List<ServiceStatus> statuses) {
    _statuses = statuses;
    notifyListeners();
  }

  void _onOutput(String line) {
    _outputLines.add(line);
    while (_outputLines.length > _outputHistoryLimit) {
      _outputLines.removeAt(0);
    }
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    if (_disposed) return;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_disposed) return;
    super.removeListener(listener);
  }

  @override
  void dispose() {
    _disposed = true;
    _stateSub?.cancel();
    _statusesSub?.cancel();
    _outputSub?.cancel();
    super.dispose();
  }
}

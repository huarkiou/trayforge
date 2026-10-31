/// Platform-neutral view of one service's state.
library;

import 'package:trayforge/foundation/models.dart';

/// The state of a single service, as reported by the OS.
enum ServiceState {
  /// No such service (or unit) is installed.
  notInstalled,

  stopped,
  startPending,
  running,
  stopPending,

  /// Paused / paused-pending / continue-pending: treated as "up" for control
  /// decisions, and displayed as paused.
  paused,

  /// The OS reports the service as failed.
  failed,

  /// The state could not be determined.
  unknown,
}

extension ServiceStateX on ServiceState {
  /// Whether the service is up (running or paused, but not transitioning).
  bool get isUp => this == ServiceState.running || this == ServiceState.paused;

  /// Whether the service is between states.
  bool get isPending =>
      this == ServiceState.startPending || this == ServiceState.stopPending;

  bool get isStopped => this == ServiceState.stopped;

  String get label {
    switch (this) {
      case ServiceState.notInstalled:
        return 'Not installed';
      case ServiceState.stopped:
        return 'Stopped';
      case ServiceState.startPending:
        return 'Starting';
      case ServiceState.running:
        return 'Running';
      case ServiceState.stopPending:
        return 'Stopping';
      case ServiceState.paused:
        return 'Paused';
      case ServiceState.failed:
        return 'Failed';
      case ServiceState.unknown:
        return 'Unknown';
    }
  }
}

/// One service's status snapshot.
class ServiceStatus {
  final String name;
  final ServiceState state;

  /// Service-specific exit code (SCM `dwWin32ExitCode`), or 0.
  final int win32ExitCode;

  const ServiceStatus(this.name, this.state, {this.win32ExitCode = 0});

  @override
  String toString() => '$name: ${state.label}';
}

/// Aggregates a group into the [ProcState] the UI already understands.
///
/// A group is "running" when any member is up, "starting"/"stopping" while any
/// member is transitioning, and "crashed" when a member is missing, failed or
/// unreadable — that is a configuration problem the user must see.
ProcState aggregateState(List<ServiceStatus> statuses) {
  if (statuses.isEmpty) return ProcState.stopped;

  if (statuses.any(
    (s) =>
        s.state == ServiceState.notInstalled ||
        s.state == ServiceState.failed ||
        s.state == ServiceState.unknown,
  )) {
    return ProcState.crashed;
  }
  if (statuses.any((s) => s.state == ServiceState.startPending)) {
    return ProcState.starting;
  }
  if (statuses.any((s) => s.state == ServiceState.stopPending)) {
    return ProcState.stopping;
  }
  if (statuses.any((s) => s.state.isUp)) return ProcState.running;
  return ProcState.stopped;
}

/// Whether the group is currently (partly) up — the input to the toggle rule
/// "any running → stop all, else start all".
bool anyServiceUp(List<ServiceStatus> statuses) =>
    statuses.any((s) => s.state.isUp);

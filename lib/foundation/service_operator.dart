// ignore_for_file: prefer_initializing_formals

/// Runs a service group operation, elevating when the OS requires it.
///
/// The interface is small on purpose: callers (the [ServiceController]) ask for
/// "start/stop this group" and get one authoritative [ServiceOpResult] per
/// service. Whether that happened directly or through an elevated helper
/// process is an implementation detail.
library;

import 'package:trayforge/foundation/elevated_process_win32.dart';
import 'package:trayforge/foundation/service_host.dart';
import 'package:trayforge/foundation/service_status.dart';

/// What a group operation does.
enum ServiceOpKind { start, stop }

/// One operation on a whole group.
class ServiceGroupOp {
  final ServiceOpKind kind;
  final List<String> services;
  final bool stopDependents;

  const ServiceGroupOp({
    required this.kind,
    required this.services,
    this.stopDependents = false,
  });
}

/// Performs a group operation inside a single elevated process.
///
/// Windows: one UAC prompt for the whole group, not one per service.
abstract class ElevatedServiceRunner {
  /// Runs [op] elevated and returns when the helper has exited.
  ///
  /// Throws [ElevationException] when the operation could not be started
  /// (the user declined UAC, access denied, unsupported platform).
  Future<void> run(ServiceGroupOp op);
}

/// Applies a group operation, retrying through elevation when needed.
class ServiceOperator {
  ServiceOperator({required ServiceHost host, ElevatedServiceRunner? elevated})
    : _host = host,
      _elevated = elevated;

  final ServiceHost _host;
  final ElevatedServiceRunner? _elevated;

  /// Runs [op] and returns one result per examined service.
  ///
  /// After an elevation hop the SCM is re-queried: the helper's exit code is
  /// never trusted as the outcome.
  Future<List<ServiceOpResult>> run(ServiceGroupOp op) async {
    final results = await performServiceOp(_host, op);

    final needsElevation = results.any(
      (r) => r.failure == ServiceFailure.accessDenied,
    );
    final elevated = _elevated;
    if (!needsElevation || elevated == null) return results;

    try {
      await elevated.run(op);
    } on ElevationException catch (e) {
      // Only the services that actually needed elevation were cancelled; the
      // direct attempt's other results are still the truth.
      final cancelled = {
        for (final result in results)
          if (result.failure == ServiceFailure.accessDenied) result.service,
      };
      return [
        for (final result in results)
          cancelled.contains(result.service)
              ? ServiceOpResult.failed(
                  result.service,
                  ServiceFailure.cancelled,
                  e.message,
                )
              : result,
      ];
    }

    final statuses = await _host.query(op.services);
    return [
      for (final status in statuses)
        op.kind.isHeadingTo(status)
            ? ServiceOpResult.ok(status.name)
            : ServiceOpResult.failed(
                status.name,
                ServiceFailure.unknown,
                'still ${status.state.label.toLowerCase()} after the '
                'elevated operation',
              ),
    ];
  }
}

/// What an operation is aiming for, in one place so the operator, the helper
/// and the controller cannot disagree.
extension ServiceOpKindX on ServiceOpKind {
  /// Whether [status] already reached the state this operation wants.
  bool reaches(ServiceStatus status) =>
      this == ServiceOpKind.start ? status.state.isUp : status.state.isStopped;

  /// Whether [status] is the target **or already moving toward it**.
  ///
  /// Used for the check immediately after an operation: the OS answers
  /// `STOP_PENDING`/`START_PENDING` for a service that is on its way, and
  /// calling that a failure would report a problem for work that is about to
  /// finish (the controller settles afterwards anyway).
  bool isHeadingTo(ServiceStatus status) {
    if (reaches(status)) return true;
    return this == ServiceOpKind.start
        ? status.state == ServiceState.startPending
        : status.state == ServiceState.stopPending;
  }
}

/// Applies [op] without elevating. Reused by the elevated helper process, so
/// the direct and elevated paths cannot drift apart.
Future<List<ServiceOpResult>> performServiceOp(
  ServiceHost host,
  ServiceGroupOp op,
) async {
  if (op.kind == ServiceOpKind.start) return host.start(op.services);
  if (!op.stopDependents) return host.stop(op.services);

  // Stop the dependents *first*, as the group config promises: the SCM (and
  // systemd) refuse to stop a service while something still depends on it.
  // Querying is best effort — a host that cannot enumerate dependents must not
  // fail the whole operation.
  final members = op.services.toSet();
  final dependentsToStop = <String>{};
  for (final name in members) {
    try {
      for (final dependent in await host.dependents(name)) {
        if (!members.contains(dependent)) dependentsToStop.add(dependent);
      }
    } catch (_) {
      // Best effort: fall through to the member stop below.
    }
  }

  final dependentResults = dependentsToStop.isEmpty
      ? const <ServiceOpResult>[]
      : await host.stop(dependentsToStop.toList());
  final memberResults = await host.stop(op.services);

  return [...dependentResults, ...memberResults];
}

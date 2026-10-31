/// The service-control seam: query state, start and stop services.
///
/// Two adapters satisfy it — the Windows SCM (`service_host_win32.dart`) and
/// systemd (`service_host_linux.dart`) — and tests use a fake. Nothing above
/// this seam knows how services are controlled.
library;

import 'package:trayforge/foundation/service_status.dart';

/// Why a control operation failed.
enum ServiceFailure {
  unknown,
  accessDenied,

  /// Other services depend on the target and are still running.
  dependentsRunning,
  notInstalled,
  notStarted,
  disabled,
  timeout,

  /// The user declined the UAC prompt.
  cancelled,
}

/// The outcome of one control operation for one service.
class ServiceOpResult {
  final String service;
  final ServiceFailure? failure;
  final String? message;

  const ServiceOpResult.ok(this.service) : failure = null, message = null;

  const ServiceOpResult.failed(this.service, this.failure, [this.message]);

  bool get ok => failure == null;

  @override
  String toString() => ok
      ? '$service: ok'
      : '$service: ${failure!.name}${message == null ? '' : ' ($message)'}';
}

/// Thrown when a [ServiceHost] cannot perform a query at all (unsupported
/// platform, SCM unavailable).
class ServiceOpException implements Exception {
  final String message;
  final ServiceFailure failure;

  const ServiceOpException(
    this.message, {
    this.failure = ServiceFailure.unknown,
  });

  @override
  String toString() => message;
}

/// Control surface for services, one call per operation on a group.
abstract class ServiceHost {
  /// Current state of [names], in the same order.
  ///
  /// Unknown services come back as [ServiceState.notInstalled] rather than
  /// throwing: a stale config entry is a display problem, not a crash.
  Future<List<ServiceStatus>> query(List<String> names);

  /// Starts [names], returning one result per service.
  ///
  /// Never throws for a per-service failure (access denied, disabled, …);
  /// those are results. Throws only when the host itself is unusable.
  Future<List<ServiceOpResult>> start(List<String> names);

  /// Stops [names], returning one result per service.
  Future<List<ServiceOpResult>> stop(List<String> names);

  /// Names of services that directly depend on [name].
  Future<List<String>> dependents(String name);
}

/// Host for platforms without native service management.
class UnsupportedServiceHost implements ServiceHost {
  const UnsupportedServiceHost();

  ServiceOpException get _unsupported => const ServiceOpException(
    'Service management is not supported on this platform',
  );

  @override
  Future<List<ServiceStatus>> query(List<String> names) async =>
      throw _unsupported;

  @override
  Future<List<ServiceOpResult>> start(List<String> names) async =>
      throw _unsupported;

  @override
  Future<List<ServiceOpResult>> stop(List<String> names) async =>
      throw _unsupported;

  @override
  Future<List<String>> dependents(String name) async => const [];
}

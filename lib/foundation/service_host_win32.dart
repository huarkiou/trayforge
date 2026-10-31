/// Windows SCM adapter for [ServiceHost].
///
/// Thin and mechanical, like `process_cwd_win32.dart`: every call maps onto one
/// Win32 function on `advapi32`, and per-service failures come back as
/// [ServiceOpResult] values rather than exceptions.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:trayforge/foundation/service_host.dart';
import 'package:trayforge/foundation/service_status.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const int _scManagerConnect = 0x0001;

const int _serviceQueryStatus = 0x0004;
const int _serviceEnumerateDependents = 0x0008;
const int _serviceStart = 0x0010;
const int _serviceStop = 0x0020;

const int _scStatusProcessInfo = 0;
const int _serviceControlStop = 1;
const int _serviceActive = 1;

const int _errorMoreData = 234;

const int _errorAccessDenied = 5;
const int _errorDependentServicesRunning = 1051;
const int _errorServiceRequestTimeout = 1053;
const int _errorServiceAlreadyRunning = 1056;
const int _errorServiceDisabled = 1058;
const int _errorServiceDoesNotExist = 1060;
const int _errorServiceNotActive = 1062;
const int _errorServiceMarkedForDelete = 1072;

// SCM service states.
const int _stateStopped = 1;
const int _stateStartPending = 2;
const int _stateStopPending = 3;
const int _stateRunning = 4;
const int _stateContinuePending = 5;
const int _statePausePending = 6;
const int _statePaused = 7;

// ---------------------------------------------------------------------------
// Structs
// ---------------------------------------------------------------------------

/// `SERVICE_STATUS_PROCESS` (9 DWORDs).
final class _ServiceStatusProcess extends Struct {
  @Uint32()
  external int dwServiceType;

  @Uint32()
  external int dwCurrentState;

  @Uint32()
  external int dwControlsAccepted;

  @Uint32()
  external int dwWin32ExitCode;

  @Uint32()
  external int dwServiceSpecificExitCode;

  @Uint32()
  external int dwCheckPoint;

  @Uint32()
  external int dwWaitHint;

  @Uint32()
  external int dwProcessId;

  @Uint32()
  external int dwServiceFlags;
}

/// `SERVICE_STATUS` (7 DWORDs) — the out parameter of `ControlService`.
final class _ServiceControlStatus extends Struct {
  @Uint32()
  external int dwServiceType;

  @Uint32()
  external int dwCurrentState;

  @Uint32()
  external int dwControlsAccepted;

  @Uint32()
  external int dwWin32ExitCode;

  @Uint32()
  external int dwServiceSpecificExitCode;

  @Uint32()
  external int dwCheckPoint;

  @Uint32()
  external int dwWaitHint;
}

/// One element of the `ENUM_SERVICE_STATUSW` array.
final class _EnumServiceStatusW extends Struct {
  external Pointer<Utf16> lpServiceName;

  external Pointer<Utf16> lpDisplayName;

  external _ServiceControlStatus serviceStatus;
}

// ---------------------------------------------------------------------------
// Bindings
// ---------------------------------------------------------------------------

final DynamicLibrary _advapi32 = DynamicLibrary.open('advapi32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

typedef _OpenSCManagerC =
    IntPtr Function(Pointer<Utf16>, Pointer<Utf16>, Uint32);
typedef _OpenSCManagerDart = int Function(Pointer<Utf16>, Pointer<Utf16>, int);

typedef _OpenServiceC = IntPtr Function(IntPtr, Pointer<Utf16>, Uint32);
typedef _OpenServiceDart = int Function(int, Pointer<Utf16>, int);

typedef _CloseServiceHandleC = Int32 Function(IntPtr);
typedef _CloseServiceHandleDart = int Function(int);

typedef _QueryServiceStatusExC =
    Int32 Function(IntPtr, Int32, Pointer<Uint8>, Uint32, Pointer<Uint32>);
typedef _QueryServiceStatusExDart =
    int Function(int, int, Pointer<Uint8>, int, Pointer<Uint32>);

typedef _StartServiceC =
    Int32 Function(IntPtr, Uint32, Pointer<Pointer<Utf16>>);
typedef _StartServiceDart = int Function(int, int, Pointer<Pointer<Utf16>>);

typedef _ControlServiceC =
    Int32 Function(IntPtr, Uint32, Pointer<_ServiceControlStatus>);
typedef _ControlServiceDart =
    int Function(int, int, Pointer<_ServiceControlStatus>);

typedef _EnumDependentServicesC =
    Int32 Function(
      IntPtr,
      Uint32,
      Pointer<Uint8>,
      Uint32,
      Pointer<Uint32>,
      Pointer<Uint32>,
    );
typedef _EnumDependentServicesDart =
    int Function(
      int,
      int,
      Pointer<Uint8>,
      int,
      Pointer<Uint32>,
      Pointer<Uint32>,
    );

typedef _GetLastErrorC = Uint32 Function();
typedef _GetLastErrorDart = int Function();

// Bindings are resolved once. Resolving (and first-calling) a function pointer
// clears the thread's last error, so a per-call `lookupFunction` would make
// every `GetLastError()` read 0 — which would turn every "access denied" into
// "unknown" and silently skip the elevation path.
final int Function(Pointer<Utf16>, Pointer<Utf16>, int) _openSCManager =
    _advapi32.lookupFunction<_OpenSCManagerC, _OpenSCManagerDart>(
      'OpenSCManagerW',
    );

final int Function(int, Pointer<Utf16>, int) _openService = _advapi32
    .lookupFunction<_OpenServiceC, _OpenServiceDart>('OpenServiceW');

final int Function(int) _closeServiceHandle = _advapi32
    .lookupFunction<_CloseServiceHandleC, _CloseServiceHandleDart>(
      'CloseServiceHandle',
    );

final int Function(int, int, Pointer<Uint8>, int, Pointer<Uint32>)
_queryServiceStatusEx = _advapi32
    .lookupFunction<_QueryServiceStatusExC, _QueryServiceStatusExDart>(
      'QueryServiceStatusEx',
    );

final int Function(int, int, Pointer<Pointer<Utf16>>) _startService = _advapi32
    .lookupFunction<_StartServiceC, _StartServiceDart>('StartServiceW');

final int Function(int, int, Pointer<_ServiceControlStatus>) _controlService =
    _advapi32.lookupFunction<_ControlServiceC, _ControlServiceDart>(
      'ControlService',
    );

final int Function(
  int,
  int,
  Pointer<Uint8>,
  int,
  Pointer<Uint32>,
  Pointer<Uint32>,
)
_enumDependentServices = _advapi32
    .lookupFunction<_EnumDependentServicesC, _EnumDependentServicesDart>(
      'EnumDependentServicesW',
    );

final int Function() _getLastErrorRaw = _kernel32
    .lookupFunction<_GetLastErrorC, _GetLastErrorDart>('GetLastError');

bool _lastErrorWarmed = false;

/// Warms the `GetLastError` binding so the first failure can be read.
///
/// Resolving a function pointer — and calling it for the first time — clears
/// the calling thread's last error, so both steps happen twice here, before
/// the binding is relied on. A future call site must warm *before* the call
/// that can fail: the [_getLastError] getter warms implicitly, which would eat
/// an error that is already pending. Once per process is enough; afterwards
/// the reads are accurate.
void _warmUpLastError() {
  if (_lastErrorWarmed) return;
  _lastErrorWarmed = true;
  _getLastErrorRaw();
  _getLastErrorRaw();
}

int _getLastError() {
  _warmUpLastError();
  return _getLastErrorRaw();
}

// ---------------------------------------------------------------------------
// Win32ServiceHost
// ---------------------------------------------------------------------------

/// Talks to the Windows Service Control Manager.
class Win32ServiceHost implements ServiceHost {
  const Win32ServiceHost();

  @override
  Future<List<ServiceStatus>> query(List<String> names) async {
    final scm = _openScm();
    try {
      return [for (final name in names) _queryOne(scm, name)];
    } finally {
      _closeServiceHandle(scm);
    }
  }

  @override
  Future<List<ServiceOpResult>> start(List<String> names) async {
    final scm = _openScm();
    try {
      return [for (final name in names) _startOne(scm, name)];
    } finally {
      _closeServiceHandle(scm);
    }
  }

  @override
  Future<List<ServiceOpResult>> stop(List<String> names) async {
    final scm = _openScm();
    try {
      return [for (final name in names) _stopOne(scm, name)];
    } finally {
      _closeServiceHandle(scm);
    }
  }

  @override
  Future<List<String>> dependents(String name) async {
    final scm = _openScm();
    final namePtr = name.toNativeUtf16();
    int handle = 0;
    try {
      handle = _openService(
        scm,
        namePtr,
        _serviceEnumerateDependents | _serviceQueryStatus,
      );
      if (handle == 0) return const [];
      return _enumerateDependents(handle);
    } finally {
      if (handle != 0) _closeServiceHandle(handle);
      calloc.free(namePtr);
      _closeServiceHandle(scm);
    }
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  int _openScm() {
    // Warm the error binding before the first call that can fail.
    _warmUpLastError();
    final scm = _openSCManager(nullptr, nullptr, _scManagerConnect);
    if (scm == 0) {
      throw ServiceOpException(
        'Cannot open the service control manager '
        '(Win32 error ${_getLastError()})',
      );
    }
    return scm;
  }

  ServiceStatus _queryOne(int scm, String name) {
    final namePtr = name.toNativeUtf16();
    final handle = _openService(scm, namePtr, _serviceQueryStatus);
    final openError = handle == 0 ? _getLastError() : 0;
    calloc.free(namePtr);

    if (handle == 0) {
      // Only "does not exist" is a display state; anything else (an ACL
      // problem, a marked-for-delete service) is a real query failure and must
      // not masquerade as "not installed".
      return ServiceStatus(
        name,
        openError == _errorServiceDoesNotExist
            ? ServiceState.notInstalled
            : ServiceState.unknown,
        win32ExitCode: openError,
      );
    }

    try {
      final buffer = calloc<_ServiceStatusProcess>();
      final needed = calloc<Uint32>();
      try {
        final ok = _queryServiceStatusEx(
          handle,
          _scStatusProcessInfo,
          buffer.cast<Uint8>(),
          sizeOf<_ServiceStatusProcess>(),
          needed,
        );
        if (ok == 0) {
          return ServiceStatus(
            name,
            ServiceState.unknown,
            win32ExitCode: _getLastError(),
          );
        }
        return ServiceStatus(
          name,
          _mapState(buffer.ref.dwCurrentState),
          win32ExitCode: buffer.ref.dwWin32ExitCode,
        );
      } finally {
        calloc.free(buffer);
        calloc.free(needed);
      }
    } finally {
      _closeServiceHandle(handle);
    }
  }

  ServiceOpResult _startOne(int scm, String name) => _control(
    scm,
    name,
    access: _serviceStart | _serviceQueryStatus,
    // Already running: the requested state is reached.
    toleratedError: _errorServiceAlreadyRunning,
    invoke: (handle) => _startService(handle, 0, nullptr) != 0,
  );

  ServiceOpResult _stopOne(int scm, String name) {
    final status = calloc<_ServiceControlStatus>();
    try {
      return _control(
        scm,
        name,
        access: _serviceStop | _serviceQueryStatus,
        // Already stopped: the requested state is reached.
        toleratedError: _errorServiceNotActive,
        invoke: (handle) =>
            _controlService(handle, _serviceControlStop, status) != 0,
      );
    } finally {
      calloc.free(status);
    }
  }

  /// Opens [name], runs [invoke], and maps the outcome — the shared shape of
  /// start and stop.
  ServiceOpResult _control(
    int scm,
    String name, {
    required int access,
    required int toleratedError,
    required bool Function(int handle) invoke,
  }) {
    final namePtr = name.toNativeUtf16();
    final handle = _openService(scm, namePtr, access);
    final openError = handle == 0 ? _getLastError() : 0;
    calloc.free(namePtr);

    if (handle == 0) return _failure(name, openError);

    try {
      if (invoke(handle)) return ServiceOpResult.ok(name);
      final code = _getLastError();
      if (code == toleratedError) return ServiceOpResult.ok(name);
      return _failure(name, code);
    } finally {
      _closeServiceHandle(handle);
    }
  }

  List<String> _enumerateDependents(int handle) {
    final needed = calloc<Uint32>();
    final count = calloc<Uint32>();
    try {
      final probe = _enumDependentServices(
        handle,
        _serviceActive,
        nullptr,
        0,
        needed,
        count,
      );
      if (probe != 0) return const []; // Nothing depends on it.
      if (_getLastError() != _errorMoreData) return const [];
      if (needed.value == 0 || count.value == 0) return const [];

      final buffer = calloc<Uint8>(needed.value);
      try {
        final ok = _enumDependentServices(
          handle,
          _serviceActive,
          buffer,
          needed.value,
          needed,
          count,
        );
        if (ok == 0) return const [];

        final elementSize = sizeOf<_EnumServiceStatusW>();
        return [
          for (var i = 0; i < count.value; i++)
            (buffer + i * elementSize)
                .cast<_EnumServiceStatusW>()
                .ref
                .lpServiceName
                .toDartString(),
        ];
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(needed);
      calloc.free(count);
    }
  }
}

ServiceState _mapState(int scmState) {
  switch (scmState) {
    case _stateStopped:
      return ServiceState.stopped;
    case _stateStartPending:
      return ServiceState.startPending;
    case _stateStopPending:
      return ServiceState.stopPending;
    case _stateRunning:
      return ServiceState.running;
    case _stateContinuePending:
    case _statePausePending:
    case _statePaused:
      return ServiceState.paused;
    default:
      return ServiceState.unknown;
  }
}

/// Win32 error → (failure kind, human message). One table so the two can never
/// drift apart.
const Map<int, (ServiceFailure, String)> _errorTable = {
  _errorAccessDenied: (
    ServiceFailure.accessDenied,
    'access denied (administrator rights required)',
  ),
  _errorDependentServicesRunning: (
    ServiceFailure.dependentsRunning,
    'other services depend on this one and are still running',
  ),
  _errorServiceRequestTimeout: (
    ServiceFailure.timeout,
    'the service did not respond in time',
  ),
  _errorServiceAlreadyRunning: (
    ServiceFailure.unknown,
    'the service is already running',
  ),
  _errorServiceDisabled: (ServiceFailure.disabled, 'the service is disabled'),
  _errorServiceDoesNotExist: (
    ServiceFailure.notInstalled,
    'the service does not exist',
  ),
  _errorServiceNotActive: (
    ServiceFailure.notStarted,
    'the service is not started',
  ),
  _errorServiceMarkedForDelete: (
    ServiceFailure.unknown,
    'the service is marked for deletion',
  ),
};

ServiceOpResult _failure(String name, int code) {
  final entry = _errorTable[code];
  final failure = entry?.$1 ?? ServiceFailure.unknown;
  final message = entry?.$2 ?? 'the service control manager reported an error';
  return ServiceOpResult.failed(name, failure, '$message (Win32 error $code)');
}

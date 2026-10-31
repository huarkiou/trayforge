/// Windows: launch a child process elevated through the UAC broker.
///
/// [launchElevated] calls `ShellExecuteExW` with the `runas` verb. Windows
/// shows the UAC consent prompt and, on consent, starts the child with the
/// administrator token.
///
/// Two consequences of going through the broker matter for trayforge:
///
/// 1. **No output pipes on the broker path.** The broker creates the child
///    with a fresh console instead of inheriting the parent's
///    stdout/stderr handles, so an elevated child's output cannot reach
///    trayforge's log view while it goes through the broker.
/// 2. **The handle is still useful.** `SEE_MASK_NOCLOSEPROCESS` hands back the
///    process handle, which is enough to read the exit code
///    ([GetExitCodeProcess]) and to terminate the process
///    ([TerminateProcess]) without running anything elevated ourselves.
///
/// `ShellExecuteExW` cannot take an environment block or a job object, so the
/// child does not see the environment trayforge builds for normal launches.
///
/// This is the launch path for an **unprivileged** TrayForge. When TrayForge
/// itself runs elevated, `RealProcessRunner` starts the child with a plain
/// `CreateProcess` instead: the child inherits the administrator token, so no
/// broker is involved and the pipes and environment keep working.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Thrown when an elevated launch cannot be started.
///
/// Covers the cases the user can act on: UAC declined, access denied, missing
/// executable, or a platform without UAC support.
class ElevationException implements Exception {
  final String message;

  const ElevationException(this.message);

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Win32 constants
// ---------------------------------------------------------------------------

/// Hand back `hProcess` in [ShellExecuteInfoW] so exit/termination work.
const int _seeMaskNoCloseProcess = 0x00000040;

const int _swShowNormal = 1;

/// `STILL_ACTIVE` as returned by `GetExitCodeProcess` for a live process.
const int _stillActive = 259;

const int _errorSuccess = 0;
const int _errorFileNotFound = 2;
const int _errorAccessDenied = 5;
const int _errorCancelled = 1223;

/// Consecutive `GetExitCodeProcess` failures tolerated before giving up.
const int _maxPollFailures = 5;

// ---------------------------------------------------------------------------
// SHELLEXECUTEINFOW
// ---------------------------------------------------------------------------

/// `SHELLEXECUTEINFOW` — layout matches the C struct on both 32- and 64-bit.
///
/// The `hIcon`/`hMonitor` union is represented by one pointer-sized field.
final class ShellExecuteInfoW extends Struct {
  @Uint32()
  external int cbSize;

  @Uint32()
  external int fMask;

  @IntPtr()
  external int hwnd;

  external Pointer<Utf16> lpVerb;

  external Pointer<Utf16> lpFile;

  external Pointer<Utf16> lpParameters;

  external Pointer<Utf16> lpDirectory;

  @Int32()
  external int nShow;

  @IntPtr()
  external int hInstApp;

  external Pointer<Void> lpIDList;

  external Pointer<Utf16> lpClass;

  @IntPtr()
  external int hkeyClass;

  @Uint32()
  external int dwHotKey;

  @IntPtr()
  external int hIcon;

  @IntPtr()
  external int hProcess;
}

// ---------------------------------------------------------------------------
// Win32 bindings
// ---------------------------------------------------------------------------

final DynamicLibrary _shell32 = DynamicLibrary.open('shell32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

typedef _ShellExecuteExWC = Int32 Function(Pointer<ShellExecuteInfoW>);
typedef _ShellExecuteExWDart = int Function(Pointer<ShellExecuteInfoW>);

typedef _GetLastErrorC = Uint32 Function();
typedef _GetLastErrorDart = int Function();

typedef _GetProcessIdC = Uint32 Function(IntPtr);
typedef _GetProcessIdDart = int Function(int);

typedef _GetExitCodeProcessC = Int32 Function(IntPtr, Pointer<Uint32>);
typedef _GetExitCodeProcessDart = int Function(int, Pointer<Uint32>);

typedef _TerminateProcessC = Int32 Function(IntPtr, Uint32);
typedef _TerminateProcessDart = int Function(int, int);

typedef _CloseHandleC = Int32 Function(IntPtr);
typedef _CloseHandleDart = int Function(int);

// Bindings are resolved once. Resolving (and first-calling) a function pointer
// clears the thread's last error, so a per-call `lookupFunction` would make
// every `GetLastError()` read 0 — a declined UAC prompt would then be reported
// as "the shell returned no error code" instead of "cancelled".
final int Function(Pointer<ShellExecuteInfoW>) _shellExecuteExW = _shell32
    .lookupFunction<_ShellExecuteExWC, _ShellExecuteExWDart>('ShellExecuteExW');

final int Function() _getLastErrorRaw = _kernel32
    .lookupFunction<_GetLastErrorC, _GetLastErrorDart>('GetLastError');

final int Function(int) _getProcessId = _kernel32
    .lookupFunction<_GetProcessIdC, _GetProcessIdDart>('GetProcessId');

final int Function(int, Pointer<Uint32>) _getExitCodeProcess = _kernel32
    .lookupFunction<_GetExitCodeProcessC, _GetExitCodeProcessDart>(
      'GetExitCodeProcess',
    );

final int Function(int, int) _terminateProcess = _kernel32
    .lookupFunction<_TerminateProcessC, _TerminateProcessDart>(
      'TerminateProcess',
    );

final int Function(int) _closeHandle = _kernel32
    .lookupFunction<_CloseHandleC, _CloseHandleDart>('CloseHandle');

bool _lastErrorWarmed = false;

/// Warms the `GetLastError` binding before the first call that can fail.
///
/// Resolving a function pointer — and calling it for the first time — clears
/// the calling thread's last error, so both steps happen twice here, before
/// the binding is relied on. A future call site must warm *before* the call
/// that can fail: the [_getLastError] getter warms implicitly, which would eat
/// an error that is already pending.
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
// ElevatedProcess
// ---------------------------------------------------------------------------

/// A process started through the UAC broker, addressed by its Win32 handle.
///
/// Only liveness/exit and termination are observable — there are no pipes.
class ElevatedProcess {
  /// Win32 process handle returned by `ShellExecuteExW`.
  final int handle;

  final int pid;

  final Completer<int> _exitCode = Completer<int>();

  /// Polls the exit code. ShellExecuteEx offers no completion callback, so a
  /// short poll is the only way to surface the exit to the controller.
  Timer? _poll;

  int _pollFailures = 0;

  bool _handleClosed = false;

  ElevatedProcess._(this.handle, this.pid) {
    _poll = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _refreshExitCode(),
    );
  }

  /// Completes with the process exit code once the process has exited.
  Future<int> get exitCode => _exitCode.future;

  bool get hasExited => _exitCode.isCompleted;

  /// Terminates the process using the handle from the UAC broker.
  ///
  /// Returns `false` when the handle does not grant `PROCESS_TERMINATE`, in
  /// which case the caller may fall back to an external kill.
  bool terminate() {
    if (hasExited) return true;
    final ok = _terminateProcess(handle, 1) != 0;
    return ok;
  }

  void _refreshExitCode() {
    if (hasExited) return;

    final code = calloc<Uint32>();
    try {
      final ok = _getExitCodeProcess(handle, code);
      if (ok == 0) {
        // A transient failure is possible while the process is still being
        // created; give up only after repeated failures.
        if (++_pollFailures >= _maxPollFailures) _finish(-1);
        return;
      }
      _pollFailures = 0;
      if (code.value != _stillActive) _finish(code.value);
    } finally {
      calloc.free(code);
    }
  }

  void _finish(int code) {
    if (hasExited) return;
    _poll?.cancel();
    _poll = null;
    _closeHandleOnce();
    _exitCode.complete(code);
  }

  void _closeHandleOnce() {
    if (_handleClosed) return;
    _handleClosed = true;
    _closeHandle(handle);
  }
}

// ---------------------------------------------------------------------------
// launchElevated
// ---------------------------------------------------------------------------

/// Starts [executable] with the arguments [arguments], elevated.
///
/// Shows the UAC consent prompt. Throws [ElevationException] when the child
/// cannot be started — including when the user declines the prompt.
///
/// [workingDirectory] must exist; the broker rejects a missing directory.
ElevatedProcess launchElevated(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  // A path that names a file (not a bare name resolved through PATH) must
  // exist: the broker reports a missing file as a generic error, which would
  // otherwise read as "cancelled". A relative path is resolved against
  // [workingDirectory] first, because the broker resolves it against
  // TrayForge's own current directory, not the directory it is handed.
  //
  // This check runs before any `toNativeUtf16()` allocation so a throw cannot
  // leak native memory.
  if (executable.contains(r'\') || executable.contains('/')) {
    final resolved = _resolveAgainst(executable, workingDirectory);
    final type = FileSystemEntity.typeSync(resolved);
    if (type == FileSystemEntityType.directory) {
      throw ElevationException(
        'UAC elevation failed: $resolved is a directory',
      );
    }
    if (type == FileSystemEntityType.notFound) {
      throw ElevationException(
        'UAC elevation failed: executable not found ($resolved)',
      );
    }
  }

  final verb = 'runas'.toNativeUtf16();
  final file = executable.toNativeUtf16();
  final parameters = arguments
      .map(quoteWindowsArgument)
      .join(' ')
      .toNativeUtf16();
  final directory = (workingDirectory == null || workingDirectory.isEmpty)
      ? nullptr
      : workingDirectory.toNativeUtf16();

  // Warm the error binding before the call that can fail.
  _warmUpLastError();

  final info = calloc<ShellExecuteInfoW>();
  try {
    info.ref
      ..cbSize = sizeOf<ShellExecuteInfoW>()
      ..fMask = _seeMaskNoCloseProcess
      ..hwnd = 0
      ..lpVerb = verb
      ..lpFile = file
      ..lpParameters = parameters
      ..lpDirectory = directory
      ..nShow = _swShowNormal;

    final ok = _shellExecuteExW(info);
    if (ok == 0) {
      throw ElevationException(_describeLaunchFailure(_getLastError()));
    }

    final handle = info.ref.hProcess;
    if (handle == 0) {
      throw const ElevationException(
        'UAC elevation started no process (the shell did not return a handle)',
      );
    }

    final pid = _getProcessId(handle);
    if (pid == 0) {
      _closeHandle(handle);
      throw const ElevationException(
        'UAC elevation started but the process id is unavailable',
      );
    }

    return ElevatedProcess._(handle, pid);
  } finally {
    if (directory != nullptr) calloc.free(directory);
    calloc.free(verb);
    calloc.free(file);
    calloc.free(parameters);
    calloc.free(info);
  }
}

/// Resolves a relative [executable] against [workingDirectory].
///
/// Only called for paths that already contain a separator, so bare names keep
/// being resolved by ShellExecute through `PATH`. An absolute path and an
/// empty [workingDirectory] are returned unchanged.
String _resolveAgainst(String executable, String? workingDirectory) {
  final directory = workingDirectory;
  if (directory == null || directory.isEmpty) return executable;
  if (File(executable).isAbsolute) return executable;
  final separator = directory.endsWith(r'\') || directory.endsWith('/')
      ? ''
      : r'\';
  return '$directory$separator$executable';
}

String _describeLaunchFailure(int error) {
  switch (error) {
    case _errorCancelled:
      return 'UAC elevation was cancelled';
    case _errorAccessDenied:
      return 'UAC elevation was denied (access is denied)';
    case _errorFileNotFound:
      return 'UAC elevation failed: executable not found';
    case _errorSuccess:
      return 'UAC elevation failed: the shell returned no error code';
    default:
      return 'UAC elevation failed (Win32 error $error)';
  }
}

// ---------------------------------------------------------------------------
// Command line quoting
// ---------------------------------------------------------------------------

/// Quotes one argument for a Windows command line (`CreateProcess` rules).
///
/// ShellExecuteEx takes a single parameter string, so each argument is quoted
/// exactly the way `Process.start` would quote it for `CreateProcessW`.
String quoteWindowsArgument(String argument) {
  if (argument.isEmpty) return '""';

  final needsQuotes =
      argument.contains(' ') ||
      argument.contains('\t') ||
      argument.contains('"') ||
      argument.contains('\n') ||
      argument.contains('\v');
  if (!needsQuotes) return argument;

  final buffer = StringBuffer('"');
  var backslashes = 0;
  for (final code in argument.codeUnits) {
    if (code == 0x5C) {
      backslashes++;
      continue;
    }
    if (code == 0x22) {
      // Escape the backslashes and the quote itself.
      buffer.write('\\' * (backslashes * 2 + 1));
      buffer.write('"');
      backslashes = 0;
      continue;
    }
    if (backslashes > 0) {
      buffer.write('\\' * backslashes);
      backslashes = 0;
    }
    buffer.writeCharCode(code);
  }
  // Backslashes before the closing quote are doubled.
  buffer.write('\\' * (backslashes * 2));
  buffer.write('"');
  return buffer.toString();
}

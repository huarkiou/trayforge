/// Windows: whether TrayForge itself runs with an elevated token.
///
/// A process elevated once can start an elevated child with a plain
/// `CreateProcess`: the child inherits the administrator token, so there is no
/// UAC consent prompt, no AppInfo broker, and the parent's stdio pipes and
/// environment block still apply. That is the other launch path for
/// `ProcessConfig.elevated` (the UAC broker is only needed while TrayForge
/// itself is unprivileged).
///
/// The check is `TokenElevation`, not group membership: an administrator
/// running under UAC's standard filtered token is a member of the
/// Administrators group but is **not** elevated, and a child that requires
/// administrator rights from that token fails with `ERROR_ELEVATION_REQUIRED`
/// (740). `IsUserAnAdmin` therefore cannot answer the question the launch path
/// asks.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// `TOKEN_QUERY`, the access [OpenProcessToken] needs to read elevation.
const int _tokenQuery = 0x0008;

/// `TokenElevation` in the `TOKEN_INFORMATION_CLASS` enum.
const int _tokenElevation = 20;

typedef _GetCurrentProcessC = IntPtr Function();
typedef _GetCurrentProcessDart = int Function();

typedef _OpenProcessTokenC =
    Int32 Function(IntPtr process, Uint32 access, Pointer<IntPtr> token);
typedef _OpenProcessTokenDart =
    int Function(int process, int access, Pointer<IntPtr> token);

typedef _GetTokenInformationC =
    Int32 Function(
      IntPtr token,
      Int32 informationClass,
      Pointer<Void> information,
      Uint32 informationLength,
      Pointer<Uint32> returnLength,
    );
typedef _GetTokenInformationDart =
    int Function(
      int token,
      int informationClass,
      Pointer<Void> information,
      int informationLength,
      Pointer<Uint32> returnLength,
    );

typedef _CloseHandleC = Int32 Function(IntPtr handle);
typedef _CloseHandleDart = int Function(int handle);

// Resolved lazily: on Linux these files are imported (the runner is shared)
// but the probe returns before touching them.
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
final DynamicLibrary _advapi32 = DynamicLibrary.open('advapi32.dll');

final int Function() _getCurrentProcess = _kernel32
    .lookupFunction<_GetCurrentProcessC, _GetCurrentProcessDart>(
      'GetCurrentProcess',
    );

final int Function(int, int, Pointer<IntPtr>) _openProcessToken = _advapi32
    .lookupFunction<_OpenProcessTokenC, _OpenProcessTokenDart>(
      'OpenProcessToken',
    );

final int Function(int, int, Pointer<Void>, int, Pointer<Uint32>)
_getTokenInformation = _advapi32
    .lookupFunction<_GetTokenInformationC, _GetTokenInformationDart>(
      'GetTokenInformation',
    );

final int Function(int) _closeHandle = _kernel32
    .lookupFunction<_CloseHandleC, _CloseHandleDart>('CloseHandle');

/// Returns whether the current process holds an elevated administrator token.
///
/// `false` on every non-Windows platform, and on Windows when the token cannot
/// be queried (a failed query leaves the caller on the UAC-broker path, which
/// is the safe answer: it still elevates, it just prompts).
bool isCurrentProcessElevated() {
  if (!Platform.isWindows) return false;

  final token = calloc<IntPtr>();
  final elevation = calloc<Uint32>();
  final returnLength = calloc<Uint32>();
  try {
    final process = _getCurrentProcess();
    if (_openProcessToken(process, _tokenQuery, token) == 0) return false;

    final opened = token.value;
    try {
      final ok = _getTokenInformation(
        opened,
        _tokenElevation,
        elevation.cast<Void>(),
        sizeOf<Uint32>(),
        returnLength,
      );
      return ok != 0 && elevation.value != 0;
    } finally {
      _closeHandle(opened);
    }
  } finally {
    calloc.free(token);
    calloc.free(elevation);
    calloc.free(returnLength);
  }
}

import 'dart:async';
import 'dart:io';

import 'package:trayforge/foundation/elevated_process_win32.dart';
import 'package:trayforge/foundation/process_cwd.dart' as process_cwd;
import 'package:trayforge/foundation/process_elevation_win32.dart';

/// How a launched child can be reached.
///
/// The launch route decides what the returned [IProcessHandle] supports:
/// output streams, the built environment, and which kill mechanism works.
enum LaunchKind {
  /// Created directly with TrayForge's own token (a plain `CreateProcess`):
  /// real stdio pipes, the built environment applies, and the OS-level tree
  /// kill can reach it. Ordinary launches and an elevated launch inherited
  /// from an already-elevated TrayForge both take this route.
  direct,

  /// Created through the UAC broker (`runas`): a fresh console instead of
  /// pipes, the environment block is ignored, and only the broker's process
  /// handle can terminate it.
  uacBroker,
}

/// Abstract handle to a running process.
///
/// Exposes the minimal surface the [ProcessController] and [ProcessManager]
/// need: pid, stdout/stderr byte streams, exit code future, [launchKind], and
/// a kill method. Mock implementations use this interface in tests.
abstract class IProcessHandle {
  int get pid;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;

  /// How the child was launched, and therefore what this handle supports.
  LaunchKind get launchKind;

  /// Kills the process.
  ///
  /// Returns `true` if the signal was delivered.
  bool kill({ProcessSignal signal});
}

/// Abstract factory that launches processes and checks OS state.
///
/// The real implementation delegates to [Process.start].
abstract class IProcessRunner {
  Future<IProcessHandle> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell,
  });

  /// Starts [executable] elevated.
  ///
  /// On Windows this is one of two paths:
  ///
  /// - TrayForge is **not** elevated: the child goes through the UAC broker
  ///   (one consent prompt per launch). The broker ignores [environment] and
  ///   the returned handle has [LaunchKind.uacBroker]: no output streams, so
  ///   only the exit code and termination are observable.
  /// - TrayForge **is** elevated: the child is created with the inherited
  ///   administrator token (plain `CreateProcess`), so no prompt appears and
  ///   stdout/stderr and [environment] work like a normal launch
  ///   ([LaunchKind.direct]).
  ///
  /// Throws [ElevationException] when the elevated start itself cannot be
  /// performed (the user declined the prompt, access denied, unsupported
  /// platform, …). In the inherited-token case the launch is an ordinary
  /// [start], so its failures surface as that path's errors (for example a
  /// [ProcessException] from `Process.start`).
  Future<IProcessHandle> startElevated(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });

  /// Returns `true` if a process with [executableName] is already
  /// running at the OS level.
  Future<bool> isProcessRunning(String executableName);

  /// Returns `true` if a process with the given [pid] is running.
  Future<bool> isPidAlive(int pid);

  /// Returns the start time of the process with [pid].
  ///
  /// Returns `null` if the process is not running or the start time
  /// cannot be determined.
  Future<DateTime?> getProcessStartTime(int pid);

  /// Kills the process tree rooted at [pid].
  ///
  /// Uses the same platform dispatch as [ProcessManager.stop]:
  /// `taskkill /t /f /pid <pid>` on Windows,
  /// `pkill -P <pid>` + `SIGKILL` on Linux.
  ///
  /// Returns `true` if the kill succeeded.
  Future<bool> killPid(int pid);

  /// Returns the set of PIDs whose current working directory matches [cwd].
  ///
  /// Used by [cleanupCwd] to kill residual processes from the same working
  /// directory before starting a new instance.
  Future<Set<int>> findPidsByCwd(String cwd);
}

// ---------------------------------------------------------------------------
// Real implementations
// ---------------------------------------------------------------------------

/// Wraps a dart:io [Process] so it satisfies [IProcessHandle].
class RealProcessHandle implements IProcessHandle {
  final Process _process;

  RealProcessHandle(this._process);

  @override
  int get pid => _process.pid;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  LaunchKind get launchKind => LaunchKind.direct;

  @override
  bool kill({ProcessSignal signal = ProcessSignal.sigkill}) {
    return _process.kill(signal);
  }
}

/// Wraps a process started through the UAC broker so it satisfies
/// [IProcessHandle].
///
/// Output streams are always empty: the broker gives an elevated child its own
/// console, so there is nothing to read here. [kill] terminates the process
/// through the broker's handle instead of `taskkill`, which a non-elevated
/// trayforge cannot use on an elevated pid.
class ElevatedProcessHandle implements IProcessHandle {
  final ElevatedProcess _process;

  ElevatedProcessHandle(this._process);

  @override
  int get pid => _process.pid;

  @override
  Stream<List<int>> get stdout => Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => Stream<List<int>>.empty();

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  LaunchKind get launchKind => LaunchKind.uacBroker;

  @override
  bool kill({ProcessSignal signal = ProcessSignal.sigkill}) =>
      _process.terminate();
}

/// Launches real OS processes via [Process.start].
class RealProcessRunner implements IProcessRunner {
  /// Creates a runner whose elevated path follows TrayForge's own token.
  ///
  /// [elevationProbe] is injectable so tests can drive both launch paths
  /// without an actually elevated process.
  RealProcessRunner({bool Function()? elevationProbe})
    : _elevationProbe = elevationProbe ?? isCurrentProcessElevated;

  final bool Function() _elevationProbe;

  /// Whether this TrayForge process holds an elevated token, asked per
  /// elevated launch.
  ///
  /// A failed probe never fails the launch: the broker path still elevates,
  /// it just asks for consent. The answer is deliberately not cached — the
  /// probe is two cheap Win32 calls, and caching a failed query would
  /// permanently demote an elevated TrayForge to the prompting path.
  bool _currentProcessElevated() {
    try {
      return _elevationProbe();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isProcessRunning(String executableName) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('tasklist', [
          '/FI',
          'IMAGENAME eq $executableName',
          '/NH',
        ]);
        return result.stdout.toString().contains(executableName);
      } else {
        final result = await Process.run('pgrep', ['-x', executableName]);
        return result.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isPidAlive(int pid) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('tasklist', [
          '/FI',
          'PID eq $pid',
          '/NH',
        ]);
        return result.stdout.toString().contains(pid.toString());
      } else {
        final result = await Process.run('kill', ['-0', pid.toString()]);
        return result.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DateTime?> getProcessStartTime(int pid) async {
    try {
      if (Platform.isWindows) {
        // wmic returns: CreationDate=20250101083015.123456+480
        final result = await Process.run('wmic', [
          'process',
          'where',
          'ProcessId=$pid',
          'get',
          'CreationDate',
          '/format:csv',
        ]);
        final output = result.stdout.toString();
        final match = RegExp(r'(\d{14})\.\d+').firstMatch(output);
        if (match != null) {
          final ts = match.group(1)!;
          return DateTime(
            int.parse(ts.substring(0, 4)),
            int.parse(ts.substring(4, 6)),
            int.parse(ts.substring(6, 8)),
            int.parse(ts.substring(8, 10)),
            int.parse(ts.substring(10, 12)),
            int.parse(ts.substring(12, 14)),
          );
        }
      } else {
        // /proc/<pid>/stat: field 22 is starttime in clock ticks since boot.
        // Simpler: `ps -o lstart= -p <pid>` returns "Mon Jan  1 08:30:15 2025".
        final result = await Process.run('ps', [
          '-o',
          'lstart=',
          '-p',
          pid.toString(),
        ]);
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty) {
          return DateTime.tryParse(output);
        }
      }
    } catch (_) {
      // Fall through to null.
    }
    return null;
  }

  @override
  Future<bool> killPid(int pid) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('taskkill', [
          '/t',
          '/f',
          '/pid',
          pid.toString(),
        ]);
        return result.exitCode == 0;
      } else {
        await Process.run('pkill', ['-P', pid.toString()]);
        Process.killPid(pid, ProcessSignal.sigkill);
        return true;
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Set<int>> findPidsByCwd(String cwd) async {
    // Import is conditional on dart:ffi availability; on platforms
    // without it the call is a no-op.
    return process_cwd.findPidsByCwd(cwd);
  }

  @override
  Future<IProcessHandle> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
    );
    return RealProcessHandle(process);
  }

  @override
  Future<IProcessHandle> startElevated(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (!Platform.isWindows) {
      throw const ElevationException(
        'Elevated launch is only supported on Windows',
      );
    }
    // An elevated TrayForge already holds the administrator token, so a plain
    // CreateProcess child inherits it: no UAC prompt, no broker, and the
    // stdout/stderr pipes and the built environment survive. The broker is
    // what costs those things, so it is only used when it is needed.
    if (_currentProcessElevated()) {
      return start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    }
    final process = launchElevated(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    return ElevatedProcessHandle(process);
  }
}

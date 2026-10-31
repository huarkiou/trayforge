/// Elevation plumbing for service control (Windows UAC, Linux polkit).
///
/// Windows re-launches TrayForge's own executable in a hidden helper mode.
/// Because the executable is a GUI-subsystem app, no console window flashes; the
/// helper performs the whole group operation and exits with a status code. The
/// caller always re-queries the SCM for the real result, so the exit code is
/// only diagnostic.
///
/// Linux needs no helper: `pkexec` is invoked by [LinuxServiceHost] itself.
library;

import 'dart:io';

import 'package:trayforge/foundation/elevated_process_win32.dart';
import 'package:trayforge/foundation/service_host.dart';
import 'package:trayforge/foundation/service_host_platform.dart';
import 'package:trayforge/foundation/service_operator.dart';

/// First CLI argument that puts the app into service-helper mode.
const String serviceOpFlag = '--service-op';

/// Helper flag: stop dependent services before stopping members.
const String stopDependentsFlag = '--stop-dependents';

/// Exit code returned by the helper when every operation succeeded.
const int serviceOpSuccess = 0;

/// Exit code returned by the helper when at least one operation failed.
const int serviceOpFailure = 1;

/// Exit code returned by the helper for unusable arguments.
const int serviceOpBadUsage = 3;

/// Chooses the elevated runner for this platform, or `null` when the platform
/// handles elevation inside its [ServiceHost].
ElevatedServiceRunner? createElevatedServiceRunner() {
  if (Platform.isWindows) return const WindowsElevatedServiceRunner();
  return null;
}

/// Runs a group operation in a separate elevated TrayForge process (one UAC
/// prompt per call).
class WindowsElevatedServiceRunner implements ElevatedServiceRunner {
  const WindowsElevatedServiceRunner();

  @override
  Future<void> run(ServiceGroupOp op) async {
    final process = launchElevated(
      Platform.resolvedExecutable,
      helperArguments(op),
    );
    // Wait for the helper so the caller can verify the outcome. A non-zero
    // code is not an error here: verification decides, and it has the real
    // per-service state.
    await process.exitCode;
  }
}

/// Command-line arguments that reproduce [op] in the helper process.
List<String> helperArguments(ServiceGroupOp op) => [
  serviceOpFlag,
  op.kind.name,
  if (op.stopDependents) stopDependentsFlag,
  ...op.services,
];

/// Whether [args] ask for service-helper mode.
bool isServiceOpInvocation(List<String> args) =>
    args.isNotEmpty && args.first == serviceOpFlag;

/// Runs the helper side of an elevated invocation and returns the exit code.
///
/// Must not touch Flutter: it runs before the app is initialized.
Future<int> runServiceOpHelper(List<String> args) async {
  final parsed = parseHelperArguments(args);
  if (parsed == null) return serviceOpBadUsage;

  final results = await performServiceOp(createServiceHost(), parsed);
  return results.every((result) => result.ok)
      ? serviceOpSuccess
      : serviceOpFailure;
}

/// Parses `--service-op <start|stop> [--stop-dependents] <name>...`.
ServiceGroupOp? parseHelperArguments(List<String> args) {
  if (args.isEmpty) return null;

  final kind = switch (args.first) {
    'start' => ServiceOpKind.start,
    'stop' => ServiceOpKind.stop,
    _ => null,
  };
  if (kind == null) return null;

  var stopDependents = false;
  final names = <String>[];
  for (final arg in args.skip(1)) {
    if (arg == stopDependentsFlag) {
      stopDependents = true;
    } else if (!arg.startsWith('--') && arg.isNotEmpty) {
      names.add(arg);
    }
  }
  if (names.isEmpty) return null;

  return ServiceGroupOp(
    kind: kind,
    services: names,
    stopDependents: stopDependents,
  );
}

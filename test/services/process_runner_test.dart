import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/elevated_process_win32.dart';
import 'package:trayforge/services/process_runner.dart';

import '../helpers/test_mocks.dart';

/// A [RealProcessRunner] whose plain `start` is intercepted, so the elevated
/// delegation can be observed without launching anything.
class _RecordingRunner extends RealProcessRunner {
  _RecordingRunner(bool Function() elevationProbe)
    : super(elevationProbe: elevationProbe);

  int startCalls = 0;
  String? executable;
  List<String>? arguments;
  String? workingDirectory;
  Map<String, String>? environment;
  final MockProcessHandle handle = MockProcessHandle();

  @override
  Future<IProcessHandle> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    startCalls++;
    this.executable = executable;
    this.arguments = arguments;
    this.workingDirectory = workingDirectory;
    this.environment = environment;
    return handle;
  }
}

void main() {
  group('RealProcessRunner.startElevated', () {
    test(
      'uses plain CreateProcess when TrayForge is already elevated',
      () async {
        final runner = _RecordingRunner(() => true);
        final handle = await runner.startElevated(
          'child.exe',
          ['--flag'],
          workingDirectory: r'C:\work',
          environment: {'CHILD_VAR': '1'},
        );

        expect(identical(handle, runner.handle), isTrue);
        expect(handle.launchKind, LaunchKind.direct);
        expect(runner.startCalls, 1);
        expect(runner.executable, 'child.exe');
        expect(runner.arguments, ['--flag']);
        expect(runner.workingDirectory, r'C:\work');
        expect(runner.environment?['CHILD_VAR'], '1');
      },
      skip: !Platform.isWindows,
    );

    test(
      'stays on the UAC broker when TrayForge is not elevated',
      () async {
        final runner = _RecordingRunner(() => false);

        // A missing executable is rejected before the broker is invoked, so
        // the broker branch is exercised without showing a UAC prompt.
        await expectLater(
          runner.startElevated(
            r'C:\trayforge-test\definitely-missing.exe',
            const [],
          ),
          throwsA(isA<ElevationException>()),
        );
        expect(
          runner.startCalls,
          0,
          reason: 'a plain launch would not elevate at all',
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'falls back to the UAC broker when the elevation probe throws',
      () async {
        final runner = _RecordingRunner(
          () => throw StateError('token query failed'),
        );

        await expectLater(
          runner.startElevated(
            r'C:\trayforge-test\definitely-missing.exe',
            const [],
          ),
          throwsA(isA<ElevationException>()),
        );
        expect(
          runner.startCalls,
          0,
          reason: 'a failed probe must keep the elevating path',
        );
      },
      skip: !Platform.isWindows,
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/process_elevation_win32.dart';

void main() {
  test('reports this process token elevation', () async {
    if (!Platform.isWindows) {
      expect(
        isCurrentProcessElevated(),
        isFalse,
        reason: 'UAC elevation does not exist outside Windows',
      );
      return;
    }

    // Cross-check the token query against the integrity level the OS reports
    // for the same token: an elevated process runs at High integrity
    // (S-1-16-12288), a UAC-filtered one at Medium (S-1-16-8192). A SYSTEM
    // token is elevated at System integrity (S-1-16-16384). The SIDs are
    // locale-independent, unlike the label text.
    final groups = await Process.run('whoami', ['/groups']);
    final output = groups.stdout.toString();
    final highIntegrity =
        output.contains('S-1-16-12288') || output.contains('S-1-16-16384');

    expect(
      isCurrentProcessElevated(),
      highIntegrity,
      reason: 'TokenElevation must agree with the reported integrity level',
    );
  });
}

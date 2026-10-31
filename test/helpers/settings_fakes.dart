import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/autostart.dart';
import 'package:trayforge/services/process_manager.dart';

/// A [ProcessManager] with no config-reload events and no process state.
///
/// Enough to construct a `SettingsViewModel` (and the Dashboard over an empty
/// config) in widget tests that are only about rendering.
class StubProcessManager extends Fake implements ProcessManager {
  @override
  Stream<void> get onConfigReloaded => const Stream.empty();

  @override
  Stream<ProcState> stateStream(String name) => const Stream.empty();

  @override
  Stream<String> outputStream(String name) => const Stream.empty();
}

/// An [Autostart] that reports "not registered" without touching the registry.
class StubAutostart extends Fake implements Autostart {
  @override
  bool isEnabled() => false;
}

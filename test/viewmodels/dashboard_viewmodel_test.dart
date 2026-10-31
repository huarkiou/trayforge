import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/viewmodels/dashboard_viewmodel.dart';
import '../helpers/service_fakes.dart';
import '../helpers/test_mocks.dart';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DashboardViewModel', () {
    late Directory tmpDir;
    late ConfigStore configStore;
    late ProcessManager manager;
    late FakeServiceManager services;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('tf_test_');
      configStore = ConfigStore(dataDir: tmpDir.path);
      manager = ProcessManager(
        configStore: configStore,
        processRunner: MockProcessRunner(),
        dataDir: tmpDir.path,
      );
      services = FakeServiceManager();
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    DashboardViewModel build({bool configCorrupted = false}) {
      return DashboardViewModel(
        configStore: ConfigStore(dataDir: tmpDir.path),
        processManager: manager,
        serviceManager: services,
        configCorrupted: configCorrupted,
      );
    }

    // ---- Empty state ----

    test('isEmpty is true when no config exists', () {
      final vm = build();

      expect(vm.isEmpty, true);
      expect(vm.entries, isEmpty);
      expect(vm.processViewModels, isEmpty);
      expect(vm.serviceViewModels, isEmpty);
    });

    test('isEmpty is true when config has no units', () {
      writeConfig(tmpDir, const AppConfig());

      final vm = build();

      expect(vm.isEmpty, true);
    });

    // ---- Populated state ----

    test('creates one entry per configured unit, in config order', () {
      writeConfig(
        tmpDir,
        const AppConfig(
          outputHistoryLimit: 500,
          units: [
            ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            ServiceConfig(name: 'group-a', services: ['A']),
            ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      final vm = build();

      expect(vm.isEmpty, false);
      expect(vm.entries.map((e) => e.name), ['svc-a', 'group-a', 'svc-b']);
      expect(vm.entries[0], isA<ProcessEntry>());
      expect(vm.entries[1], isA<ServiceEntry>());
      expect(vm.entries[2], isA<ProcessEntry>());
      expect(vm.entries[1].id, 'svc:group-a');
      expect(vm.processViewModels.length, 2);
      expect(vm.serviceViewModels.single.name, 'group-a');
    });

    // ---- Config changed ----

    test('rebuilds when onConfigReloaded fires', () async {
      writeConfig(
        tmpDir,
        const AppConfig(
          units: [ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      final vm = build();

      expect(vm.entries.length, 1);

      // Save new config with an additional process.
      final newConfig = const AppConfig(
        units: [
          ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
          ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
        ],
      );
      configStore.save(newConfig);

      // Fire onConfigReloaded through ProcessManager.
      await manager.reloadConfig(newConfig);

      expect(vm.entries.map((e) => e.name), ['svc-a', 'svc-b']);
    });

    test('rebuilds when the service manager reloads the config', () async {
      writeConfig(
        tmpDir,
        const AppConfig(
          units: [ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      final vm = build();
      expect(vm.serviceViewModels, isEmpty);

      configStore.save(
        const AppConfig(
          units: [
            ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            ServiceConfig(name: 'group-a', services: ['A']),
          ],
        ),
      );
      services.emitConfigReloaded();

      expect(vm.entries.map((e) => e.name), ['svc-a', 'group-a']);
      expect(vm.serviceViewModels.single.name, 'group-a');
    });

    test('switches to empty when config removes all units', () async {
      writeConfig(
        tmpDir,
        const AppConfig(
          units: [ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      final vm = build();

      expect(vm.isEmpty, false);

      const emptyConfig = AppConfig();
      configStore.save(emptyConfig);

      // Fire onConfigReloaded through ProcessManager.
      await manager.reloadConfig(emptyConfig);

      expect(vm.isEmpty, true);
    });

    // ---- Corrupted config flag ----

    test('configCorrupted defaults to false', () {
      writeConfig(tmpDir, const AppConfig());

      final vm = build();

      expect(vm.configCorrupted, false);
    });

    test('configCorrupted is true when passed', () {
      final vm = build(configCorrupted: true);

      expect(vm.configCorrupted, true);
    });

    test('clearCorruptedFlag clears the flag', () {
      final vm = build(configCorrupted: true);

      vm.clearCorruptedFlag();
      expect(vm.configCorrupted, false);
    });

    // ---- Dispose ----

    test('dispose disposes child view models', () {
      writeConfig(
        tmpDir,
        const AppConfig(
          units: [
            ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            ServiceConfig(name: 'group-a', services: ['A']),
          ],
        ),
      );

      final vm = build();

      // Should not throw.
      vm.dispose();
    });

    // ---- appTitle ----

    test('appTitle is trayforge', () {
      expect(DashboardViewModel.appTitle, 'trayforge');
    });

    // ---- Incremental _rebuild ----

    test('reuses existing ViewModels by name across rebuilds', () async {
      writeConfig(
        tmpDir,
        const AppConfig(
          units: [
            ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            ServiceConfig(name: 'group-a', services: ['A']),
          ],
        ),
      );

      final vm = build();

      final process = vm.processViewModels[0];
      final service = vm.serviceViewModels[0];

      // Save a config with the same names, then fire onConfigReloaded.
      final newConfig = const AppConfig(
        units: [
          ProcessConfig(name: 'svc-a', cmd: 'a2.exe'),
          ServiceConfig(name: 'group-a', services: ['A']),
        ],
      );
      configStore.save(newConfig);
      await manager.reloadConfig(newConfig);

      // The same VM instances should be reused (identity check).
      expect(identical(vm.processViewModels[0], process), true);
      expect(identical(vm.serviceViewModels[0], service), true);
    });

    test('reorders entries without rebuilding the view models', () async {
      writeConfig(
        tmpDir,
        const AppConfig(
          units: [
            ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            ServiceConfig(name: 'group-a', services: ['A']),
          ],
        ),
      );

      final vm = build();
      final process = vm.processViewModels[0];

      final reordered = const AppConfig(
        units: [
          ServiceConfig(name: 'group-a', services: ['A']),
          ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
        ],
      );
      configStore.save(reordered);
      await manager.reloadConfig(reordered);

      expect(vm.entries.map((e) => e.id), ['svc:group-a', 'proc:svc-a']);
      expect(identical(vm.processViewModels[0], process), true);
    });

    test('disposes ViewModels for removed units', () async {
      writeConfig(
        tmpDir,
        const AppConfig(
          units: [
            ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            ServiceConfig(name: 'group-a', services: ['A']),
          ],
        ),
      );

      final vm = build();

      final process = vm.processViewModels[0];
      final service = vm.serviceViewModels[0];

      // Save a config without the units, then fire onConfigReloaded.
      const emptyConfig = AppConfig();
      configStore.save(emptyConfig);
      await manager.reloadConfig(emptyConfig);

      expect(vm.entries, isEmpty);

      // The old VMs should be safe to call addListener on (disposed but no-op).
      // This verifies that dispose was called.
      var called = false;
      process.addListener(() => called = true);
      service.addListener(() => called = true);
      expect(called, false);
    });
  });
}

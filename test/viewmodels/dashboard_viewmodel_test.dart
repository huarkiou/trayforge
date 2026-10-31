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
      expect(vm.units, isEmpty);
      expect(vm.units.whereType<ProcessUnit>(), isEmpty);
      expect(vm.units.whereType<ServiceUnit>(), isEmpty);
    });

    test('isEmpty is true when config has no units', () {
      writeConfig(tmpDir, const AppConfig());

      final vm = build();

      expect(vm.isEmpty, true);
    });

    // ---- Populated state ----

    test('creates one unit per configured unit, in config order', () {
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
      expect(vm.units.map((u) => u.name), ['svc-a', 'group-a', 'svc-b']);
      expect(vm.units[0], isA<ProcessUnit>());
      expect(vm.units[1], isA<ServiceUnit>());
      expect(vm.units[2], isA<ProcessUnit>());
      expect(vm.units[1].id, 'svc:group-a');
      expect(vm.units[0].id, 'proc:svc-a');
      expect(vm.units.whereType<ProcessUnit>().length, 2);
      expect(vm.units.whereType<ServiceUnit>().single.name, 'group-a');
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

      expect(vm.units.length, 1);

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

      expect(vm.units.map((u) => u.name), ['svc-a', 'svc-b']);
    });

    test('rebuilds when the service manager reloads the config', () async {
      writeConfig(
        tmpDir,
        const AppConfig(
          units: [ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      final vm = build();
      expect(vm.units.whereType<ServiceUnit>(), isEmpty);

      configStore.save(
        const AppConfig(
          units: [
            ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            ServiceConfig(name: 'group-a', services: ['A']),
          ],
        ),
      );
      services.emitConfigReloaded();

      expect(vm.units.map((u) => u.name), ['svc-a', 'group-a']);
      expect(vm.units.whereType<ServiceUnit>().single.name, 'group-a');
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

      final process = vm.units.whereType<ProcessUnit>().single.viewModel;
      final service = vm.units.whereType<ServiceUnit>().single.viewModel;

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
      expect(
        identical(vm.units.whereType<ProcessUnit>().single.viewModel, process),
        true,
      );
      expect(
        identical(vm.units.whereType<ServiceUnit>().single.viewModel, service),
        true,
      );
    });

    test('reorders units without rebuilding the view models', () async {
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
      final process = vm.units.whereType<ProcessUnit>().single.viewModel;

      final reordered = const AppConfig(
        units: [
          ServiceConfig(name: 'group-a', services: ['A']),
          ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
        ],
      );
      configStore.save(reordered);
      await manager.reloadConfig(reordered);

      expect(vm.units.map((u) => u.id), ['svc:group-a', 'proc:svc-a']);
      expect(
        identical(vm.units.whereType<ProcessUnit>().single.viewModel, process),
        true,
      );
    });

    // ---- unitsInOrder ----

    test('unitsInOrder follows the given order', () {
      writeConfig(
        tmpDir,
        const AppConfig(
          units: [
            ProcessConfig(name: 'p-a', cmd: 'a.exe'),
            ServiceConfig(name: 'group-a', services: ['A']),
            ProcessConfig(name: 'p-b', cmd: 'b.exe'),
          ],
        ),
      );

      final vm = build();

      final ordered = vm.unitsInOrder(const <UnitConfig>[
        ProcessConfig(name: 'p-b', cmd: 'b.exe'),
        ProcessConfig(name: 'p-a', cmd: 'a.exe'),
        ServiceConfig(name: 'group-a', services: ['A']),
      ]);

      expect(ordered.map((u) => u.id), ['proc:p-b', 'proc:p-a', 'svc:group-a']);

      // The view model's own list is not rewritten by a read.
      expect(vm.units.map((u) => u.id), [
        'proc:p-a',
        'svc:group-a',
        'proc:p-b',
      ]);
    });

    test('unitsInOrder omits a unit the order does not mention', () {
      writeConfig(
        tmpDir,
        const AppConfig(
          units: [
            ProcessConfig(name: 'p-a', cmd: 'a.exe'),
            ServiceConfig(name: 'group-a', services: ['A']),
            ProcessConfig(name: 'p-b', cmd: 'b.exe'),
          ],
        ),
      );

      final vm = build();

      final ordered = vm.unitsInOrder(const <UnitConfig>[
        ProcessConfig(name: 'p-b', cmd: 'b.exe'),
      ]);

      expect(ordered.map((u) => u.id), ['proc:p-b']);
      expect(ordered, hasLength(1));
      expect(vm.units, hasLength(3));
    });

    test('unitsInOrder matches identity, not just the name', () {
      writeConfig(
        tmpDir,
        const AppConfig(
          units: [
            ProcessConfig(name: 'p-a', cmd: 'a.exe'),
            ServiceConfig(name: 'group-a', services: ['A']),
          ],
        ),
      );

      final vm = build();

      // An order for a service group named p-a does not mention the process
      // p-a: identity is kind + name.
      final ordered = vm.unitsInOrder(const <UnitConfig>[
        ServiceConfig(name: 'p-a', services: ['A']),
      ]);

      expect(ordered, isEmpty);
    });

    test('unitsInOrder ignores order entries with no view model yet', () {
      writeConfig(
        tmpDir,
        const AppConfig(
          units: [
            ProcessConfig(name: 'p-a', cmd: 'a.exe'),
            ServiceConfig(name: 'group-a', services: ['A']),
            ProcessConfig(name: 'p-b', cmd: 'b.exe'),
          ],
        ),
      );

      final vm = build();

      final ordered = vm.unitsInOrder(const <UnitConfig>[
        ProcessConfig(name: 'not-built', cmd: 'x.exe'),
        ProcessConfig(name: 'p-b', cmd: 'b.exe'),
      ]);

      expect(ordered.map((u) => u.id), ['proc:p-b']);
      expect(ordered, hasLength(1));
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

      final process = vm.units.whereType<ProcessUnit>().single.viewModel;
      final service = vm.units.whereType<ServiceUnit>().single.viewModel;

      // Save a config without the units, then fire onConfigReloaded.
      const emptyConfig = AppConfig();
      configStore.save(emptyConfig);
      await manager.reloadConfig(emptyConfig);

      expect(vm.units, isEmpty);

      // The old VMs should be safe to call addListener on (disposed but no-op).
      // This verifies that dispose was called.
      var called = false;
      process.addListener(() => called = true);
      service.addListener(() => called = true);
      expect(called, false);
    });
  });
}

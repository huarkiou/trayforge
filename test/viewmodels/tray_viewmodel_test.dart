import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/foundation/service_status.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/services/service_manager.dart';
import 'package:trayforge/viewmodels/tray_viewmodel.dart';

import '../helpers/localized_app.dart';
import '../helpers/service_fakes.dart';
import '../helpers/test_mocks.dart';

AppConfig _testConfig({String name = 'test-svc'}) {
  return AppConfig(
    units: [
      ProcessConfig(name: name, cmd: 'test.exe'),
      const ServiceConfig(name: 'Licenses', services: ['A']),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TrayViewModel', () {
    late Directory tmpDir;
    late ConfigStore configStore;
    late MockProcessRunner mockRunner;
    late ProcessManager manager;
    late FakeServiceHost host;
    late ServiceManager serviceManager;

    setUp(() async {
      tmpDir = Directory.systemTemp.createTempSync('tf_tray_test_');
      configStore = ConfigStore(dataDir: tmpDir.path);
      mockRunner = MockProcessRunner();
      manager = ProcessManager(
        configStore: configStore,
        processRunner: mockRunner,
        dataDir: tmpDir.path,
      );
      host = FakeServiceHost(states: {'A': ServiceState.stopped});
      serviceManager = ServiceManager(
        configStore: configStore,
        host: host,
        settleTimeout: const Duration(milliseconds: 100),
        operationPollInterval: const Duration(milliseconds: 5),
      );
      writeConfig(tmpDir, _testConfig());

      // Materialize controllers for configured names; the manager no
      // longer lazily reads the config from disk on a miss.
      await manager.init();
      await serviceManager.init();
    });

    tearDown(() {
      manager.dispose();
      serviceManager.dispose();
      tmpDir.deleteSync(recursive: true);
    });

    TrayViewModel createTrayVm({
      ServiceManager? withServices,
      Future<void> Function()? onReloadConfig,
    }) {
      return TrayViewModel(
        configStore: configStore,
        processManager: manager,
        serviceManager: withServices,
        onShowDashboard: () {},
        onExit: () async {},
        onReloadConfig: onReloadConfig,
      );
    }

    test('menu click on stopped process starts it via toggle', () async {
      mockRunner.nextHandle = MockProcessHandle(pid: 1000);
      final vm = createTrayVm();

      final item = vm.buildMenu(enStrings).findByKey('proc:test-svc')!;
      vm.handleMenuAction(item.key!);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(manager.getState('test-svc'), ProcState.running);
      expect(mockRunner.starts.length, 1);
    });

    test('reload action goes through the shared reload path', () async {
      var reloads = 0;
      final vm = createTrayVm(
        onReloadConfig: () async {
          reloads++;
        },
      );

      vm.handleMenuAction('reload');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(reloads, 1);
    });

    test('menu lists a service group and toggles it', () async {
      final vm = createTrayVm(withServices: serviceManager);

      final before = vm.buildMenu(enStrings).findByKey('svc:Licenses')!;
      expect(before.label, isNot(contains('\u2713')));

      vm.handleMenuAction(before.key!);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(serviceManager.getState('Licenses'), ProcState.running);
      expect(host.startCalls, isNotEmpty);

      // The menu label follows the live state.
      final after = vm.buildMenu(enStrings).findByKey('svc:Licenses')!;
      expect(after.label, contains('\u2713'));
    });

    test('a service group added by a reload reaches the tray', () async {
      var notifications = 0;
      final vm = createTrayVm(withServices: serviceManager);
      vm.addListener(() => notifications++);
      expect(vm.buildMenu(enStrings).findByKey('svc:Added'), isNull);

      final onDisk = configStore.load()!;
      final updated = AppConfig(
        units: [
          ...onDisk.units,
          const ServiceConfig(name: 'Added', services: ['A']),
        ],
      );
      writeConfig(tmpDir, updated);
      await serviceManager.reloadConfig(updated);
      await Future<void>.delayed(Duration.zero);

      expect(
        notifications,
        greaterThan(0),
        reason: 'the tray still listens for config reloads',
      );
      expect(vm.buildMenu(enStrings).findByKey('svc:Added'), isNotNull);
    });

    test('menu follows the unit order across kinds', () async {
      final vm = createTrayVm(withServices: serviceManager);
      final items = vm.buildMenu(enStrings).items;
      final keys = items.map((item) => item.key).toList();

      // Config order is process, then service group; a separator marks the
      // kind change, and a second one divides the fixed items.
      expect(keys, [
        'proc:test-svc',
        null,
        'svc:Licenses',
        null,
        'reload',
        'dashboard',
        'exit',
      ]);

      final separators = items.where((item) => item.key == null).length;
      expect(separators, 2, reason: 'kind change + the fixed-item divider');
    });

    test('a same-kind list has only the fixed divider', () async {
      writeConfig(
        tmpDir,
        const AppConfig(
          units: [
            ProcessConfig(name: 'one', cmd: 'one.exe'),
            ProcessConfig(name: 'two', cmd: 'two.exe'),
          ],
        ),
      );
      final vm = createTrayVm(withServices: serviceManager);

      final items = vm.buildMenu(enStrings).items;
      expect(items.map((item) => item.key), [
        'proc:one',
        'proc:two',
        null,
        'reload',
        'dashboard',
        'exit',
      ]);

      final separators = items.where((item) => item.key == null).length;
      expect(separators, 1, reason: 'the fixed-item divider only');
    });

    test('reordering the units reorders the menu', () async {
      final vm = createTrayVm(withServices: serviceManager);

      writeConfig(
        tmpDir,
        const AppConfig(
          units: [
            ServiceConfig(name: 'Licenses', services: ['A']),
            ProcessConfig(name: 'test-svc', cmd: 'test.exe'),
          ],
        ),
      );
      await serviceManager.reloadConfig(configStore.load()!);

      final items = vm.buildMenu(enStrings).items;
      expect(items.map((item) => item.key), [
        'svc:Licenses',
        null,
        'proc:test-svc',
        null,
        'reload',
        'dashboard',
        'exit',
      ]);

      // Still one kind change, even though the kinds swapped places.
      final separators = items.where((item) => item.key == null).length;
      expect(separators, 2);
    });

    test('the fixed items follow the caller language', () async {
      final vm = createTrayVm(withServices: serviceManager);

      final labels = vm
          .buildMenu(zhStrings)
          .items
          .where((item) => item.key != null)
          .map((item) => item.label)
          .toList();

      expect(labels, contains('重新加载设置'));
      expect(labels, contains('仪表盘'));
      expect(labels, contains('退出'));
      // Unit names are configured data, not UI copy: they stay verbatim.
      expect(labels, contains('   test-svc'));
    });

    test('the fixed items keep their English labels', () async {
      final vm = createTrayVm(withServices: serviceManager);

      final labels = vm
          .buildMenu(enStrings)
          .items
          .where((item) => item.key != null)
          .map((item) => item.label)
          .toList();

      expect(labels, contains('Reload Settings'));
      expect(labels, contains('Dashboard'));
      expect(labels, contains('Exit'));
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/foundation/service_operator.dart';
import 'package:trayforge/foundation/service_status.dart';
import 'package:trayforge/services/autostart.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/services/service_manager.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';

import '../helpers/service_fakes.dart';
import '../helpers/test_mocks.dart';

void main() {
  late Directory tmpDir;
  late ConfigStore configStore;
  late ProcessManager processManager;
  late ServiceManager serviceManager;
  late FakeServiceHost host;
  late SettingsViewModel viewModel;

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('trayforge_settings_test_');
    configStore = ConfigStore(dataDir: tmpDir.path);

    const config = AppConfig(
      dashboardLayout: DashboardLayout.list,
      servicePollMs: 5000,
      units: [
        ProcessConfig(name: 'proc', cmd: 'app.exe'),
        ServiceConfig(name: 'Licenses', services: ['A']),
      ],
    );
    writeConfig(tmpDir, config);

    processManager = ProcessManager(
      configStore: configStore,
      processRunner: MockProcessRunner(),
      dataDir: tmpDir.path,
    );
    await processManager.init();

    host = FakeServiceHost(states: {'A': ServiceState.stopped});
    serviceManager = ServiceManager(
      configStore: configStore,
      host: host,
      operator: ServiceOperator(host: host),
    );
    await serviceManager.init();

    viewModel = SettingsViewModel(
      configStore: configStore,
      processManager: processManager,
      serviceManager: serviceManager,
      autostart: Autostart(),
    );
  });

  tearDown(() {
    viewModel.dispose();
    serviceManager.dispose();
    processManager.dispose();
    tmpDir.deleteSync(recursive: true);
  });

  group('SettingsViewModel', () {
    test('loaded units are exposed in order', () {
      expect(viewModel.units.map((u) => u.name), ['proc', 'Licenses']);
      expect(viewModel.processes.single.name, 'proc');
      expect(viewModel.services.single.name, 'Licenses');
      expect(viewModel.servicePollMs, 5000);
    });

    test('saving a global keeps every unit on disk', () {
      viewModel.setServicePollMs(2000);

      final saved = configStore.load()!;
      expect(saved.servicePollMs, 2000);
      expect(saved.units.map((u) => u.name), ['proc', 'Licenses']);
    });

    test('adding a process appends it after the existing units', () {
      viewModel.addProcess(
        const ProcessConfig(name: 'second', cmd: 'other.exe'),
      );

      final saved = configStore.load()!;
      expect(saved.units.map((u) => u.name), ['proc', 'Licenses', 'second']);
      expect(saved.processes.map((p) => p.name), ['proc', 'second']);
    });

    test('adding a service persists it and reloads the manager', () async {
      viewModel.addService(
        const ServiceConfig(name: 'Spooler', services: ['A']),
      );

      final saved = configStore.load()!;
      expect(saved.units.map((u) => u.name), ['proc', 'Licenses', 'Spooler']);
      expect(saved.services.map((s) => s.name), ['Licenses', 'Spooler']);

      // The manager now knows the new group.
      expect(serviceManager.getState('Spooler'), ProcState.stopped);
    });

    test('deleting a service leaves the services themselves alone', () {
      viewModel.deleteUnit(1);

      final saved = configStore.load()!;
      expect(saved.services, isEmpty);
      expect(saved.processes.single.name, 'proc');
      expect(host.states['A'], ServiceState.stopped);
    });

    test('editing a process keeps the unit position', () {
      viewModel.editProcess(
        0,
        const ProcessConfig(name: 'proc', cmd: 'edited.exe'),
      );

      final saved = configStore.load()!;
      expect(saved.units.map((u) => u.name), ['proc', 'Licenses']);
      expect(saved.processes.single.cmd, 'edited.exe');
    });

    test('editing a service group keeps the unit position', () {
      viewModel.editService(
        1,
        const ServiceConfig(name: 'Licenses', services: ['A', 'B']),
      );

      final saved = configStore.load()!;
      expect(saved.units.map((u) => u.name), ['proc', 'Licenses']);
      expect(saved.services.single.services, ['A', 'B']);
    });

    test('reorders a unit across kinds and persists the new order', () {
      viewModel.reorderItem(1, 0);

      final saved = configStore.load()!;
      expect(saved.units.map((u) => u.name), ['Licenses', 'proc']);
      expect(saved.units[0], isA<ServiceConfig>());
      expect(saved.units[1], isA<ProcessConfig>());
    });

    test('copying a service group inserts it right after itself', () {
      viewModel.copyUnit(1);

      final saved = configStore.load()!;
      expect(saved.units.map((u) => u.name), [
        'proc',
        'Licenses',
        'Licenses (copy)',
      ]);
      expect(saved.services.last.services, ['A']);
    });

    test('copying a process keeps its kind and the carried globals', () {
      viewModel.copyUnit(0);

      final saved = configStore.load()!;
      expect(saved.units.map((u) => u.name), [
        'proc',
        'proc (copy)',
        'Licenses',
      ]);
      expect(saved.processes.first.cmd, 'app.exe');
      expect(saved.dashboardLayout, DashboardLayout.list);
    });

    test('reloadFromDisk applies a config edited on disk', () async {
      // Someone edits config.json behind the running app's back.
      final onDisk = configStore.load()!;
      writeConfig(
        tmpDir,
        AppConfig(
          servicePollMs: onDisk.servicePollMs,
          dashboardLayout: onDisk.dashboardLayout,
          units: [
            ...onDisk.units,
            const ProcessConfig(name: 'added', cmd: 'added.exe'),
            const ServiceConfig(name: 'NewGroup', services: ['A']),
          ],
        ),
      );

      final reloaded = await viewModel.reloadFromDisk();

      expect(reloaded, isTrue);
      expect(viewModel.units.map((u) => u.name), [
        'proc',
        'Licenses',
        'added',
        'NewGroup',
      ]);
      expect(
        serviceManager.statuses('NewGroup'),
        isNotEmpty,
        reason: 'the manager materialized the group from the disk config',
      );
    });

    test(
      'reloadFromDisk leaves everything alone for an unreadable file',
      () async {
        File('${tmpDir.path}/config.json').writeAsStringSync('{ not json');

        final reloaded = await viewModel.reloadFromDisk();

        expect(reloaded, isFalse);
        expect(viewModel.services.single.name, 'Licenses');
      },
    );

    test('invalid service configs are rejected', () {
      expect(
        viewModel.validateServiceConfig(
          const ServiceConfig(name: 'x/y', services: ['A']),
        ),
        isNotNull,
      );
      expect(
        viewModel.validateServiceConfig(
          const ServiceConfig(name: 'ok', services: []),
        ),
        isNotNull,
      );
      expect(
        viewModel.validateServiceConfig(
          const ServiceConfig(name: 'ok', services: ['A']),
        ),
        isNull,
      );
    });
  });
}

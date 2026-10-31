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
      processes: [ProcessConfig(name: 'proc', cmd: 'app.exe')],
      services: [
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
    test('loaded services are exposed', () {
      expect(viewModel.services.single.name, 'Licenses');
      expect(viewModel.servicePollMs, 5000);
    });

    test('saving a global keeps processes and services on disk', () {
      viewModel.setServicePollMs(2000);

      final saved = configStore.load()!;
      expect(saved.servicePollMs, 2000);
      expect(saved.processes.single.name, 'proc');
      expect(saved.services.single.name, 'Licenses');
    });

    test('saving processes keeps services on disk', () {
      viewModel.add(const ProcessConfig(name: 'second', cmd: 'other.exe'));

      final saved = configStore.load()!;
      expect(saved.processes.map((p) => p.name), ['proc', 'second']);
      expect(saved.services.single.name, 'Licenses');
    });

    test('adding a service persists it and reloads the manager', () async {
      viewModel.addService(
        const ServiceConfig(name: 'Spooler', services: ['A']),
      );

      final saved = configStore.load()!;
      expect(saved.services.map((s) => s.name), ['Licenses', 'Spooler']);
      expect(saved.processes.single.name, 'proc');

      // The manager now knows the new group.
      expect(serviceManager.getState('Spooler'), ProcState.stopped);
    });

    test('deleting a service leaves the services themselves alone', () {
      viewModel.deleteService(0);

      final saved = configStore.load()!;
      expect(saved.services, isEmpty);
      expect(saved.processes.single.name, 'proc');
      expect(host.states['A'], ServiceState.stopped);
    });

    test('reloadFromDisk applies a config edited on disk', () async {
      // Someone edits config.json behind the running app's back.
      final onDisk = configStore.load()!;
      writeConfig(
        tmpDir,
        AppConfig(
          servicePollMs: onDisk.servicePollMs,
          dashboardLayout: onDisk.dashboardLayout,
          processes: [
            ...onDisk.processes,
            const ProcessConfig(name: 'added', cmd: 'added.exe'),
          ],
          services: [
            ...onDisk.services,
            const ServiceConfig(name: 'NewGroup', services: ['A']),
          ],
        ),
      );

      final reloaded = await viewModel.reloadFromDisk();

      expect(reloaded, isTrue);
      expect(viewModel.processes.map((p) => p.name), contains('added'));
      expect(viewModel.services.map((s) => s.name), contains('NewGroup'));
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

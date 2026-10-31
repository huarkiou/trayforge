import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/foundation/service_operator.dart';
import 'package:trayforge/foundation/service_status.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/service_manager.dart';

import '../helpers/service_fakes.dart';
import '../helpers/test_mocks.dart';

void main() {
  late Directory tmpDir;
  late ConfigStore configStore;
  late FakeServiceHost host;
  late ServiceManager manager;

  AppConfig configWith(List<ServiceConfig> groups) =>
      AppConfig(servicePollMs: 1000, units: groups);

  void write(AppConfig config) => writeConfig(tmpDir, config);

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('trayforge_svc_test_');
    configStore = ConfigStore(dataDir: tmpDir.path);
    host = FakeServiceHost(
      states: {'a': ServiceState.stopped, 'b': ServiceState.stopped},
    );
    manager = ServiceManager(
      configStore: configStore,
      host: host,
      operator: ServiceOperator(host: host),
      settleTimeout: const Duration(milliseconds: 200),
      operationPollInterval: const Duration(milliseconds: 5),
    );
    addTearDown(manager.dispose);
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('ServiceManager', () {
    test('init materializes groups and queries their state', () async {
      write(
        configWith([
          const ServiceConfig(name: 'grp', services: ['a', 'b']),
        ]),
      );

      await manager.init();

      expect(manager.getState('grp'), ProcState.stopped);
      expect(manager.statuses('grp'), hasLength(2));
    });

    test('toggle delegates to the controller', () async {
      write(
        configWith([
          const ServiceConfig(name: 'grp', services: ['a']),
        ]),
      );
      await manager.init();

      await manager.toggle('grp');

      expect(manager.getState('grp'), ProcState.running);
      expect(host.startCalls.single, ['a']);
    });

    test('unknown names are inert', () async {
      write(configWith([]));
      await manager.init();

      await manager.toggle('nope');
      expect(host.startCalls, isEmpty);
      expect(manager.getState('nope'), ProcState.stopped);
      expect(manager.statuses('nope'), isEmpty);
    });

    test('reload removes a group without stopping its services', () async {
      write(
        configWith([
          const ServiceConfig(name: 'grp', services: ['a']),
        ]),
      );
      await manager.init();

      final empty = configWith([]);
      write(empty);
      await manager.reloadConfig(empty);

      expect(manager.getState('grp'), ProcState.stopped);
      await manager.toggle('grp');
      expect(host.startCalls, isEmpty, reason: 'removed groups are inert');
      expect(
        host.states['a'],
        ServiceState.stopped,
        reason: 'removal must not stop the service itself',
      );
    });

    test('reload keeps a group and applies its new member list', () async {
      write(
        configWith([
          const ServiceConfig(name: 'grp', services: ['a']),
        ]),
      );
      await manager.init();
      final startsBefore = host.startCalls.length;

      final updated = configWith([
        const ServiceConfig(name: 'grp', services: ['a', 'b']),
      ]);
      write(updated);
      await manager.reloadConfig(updated);

      await manager.toggle('grp');

      expect(host.startCalls.length, startsBefore + 1);
      expect(host.startCalls.last, ['a', 'b']);
    });

    test('applyPollInterval is safe with no groups', () {
      expect(() => manager.applyPollInterval(2500), returnsNormally);
    });
  });
}

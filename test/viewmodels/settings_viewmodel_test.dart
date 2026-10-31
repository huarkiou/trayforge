import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/foundation/service_operator.dart';
import 'package:trayforge/foundation/service_status.dart';
import 'package:trayforge/l10n/validation_text.dart';
import 'package:trayforge/services/autostart.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/services/service_manager.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';

import '../helpers/localized_app.dart';
import '../helpers/service_fakes.dart';
import '../helpers/test_mocks.dart';

void main() {
  late Directory tmpDir;
  late ConfigStore configStore;
  late MockProcessRunner mockRunner;
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

    mockRunner = MockProcessRunner();
    processManager = ProcessManager(
      configStore: configStore,
      processRunner: mockRunner,
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
      expect(viewModel.units.whereType<ProcessConfig>().single.name, 'proc');
      expect(
        viewModel.units.whereType<ServiceConfig>().single.name,
        'Licenses',
      );
      expect(viewModel.servicePollMs, 5000);
    });

    test('saving a global keeps every unit on disk', () {
      viewModel.setServicePollMs(2000);

      final saved = configStore.load()!;
      expect(saved.servicePollMs, 2000);
      expect(saved.units.map((u) => u.name), ['proc', 'Licenses']);
    });

    test('adding a process appends it after the existing units', () {
      viewModel.addUnit(const ProcessConfig(name: 'second', cmd: 'other.exe'));

      final saved = configStore.load()!;
      expect(saved.units.map((u) => u.name), ['proc', 'Licenses', 'second']);
      expect(saved.processes.map((p) => p.name), ['proc', 'second']);
    });

    test('adding a service persists it and reloads the manager', () async {
      viewModel.addUnit(const ServiceConfig(name: 'Spooler', services: ['A']));

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
      viewModel.editUnit(
        0,
        const ProcessConfig(name: 'proc', cmd: 'edited.exe'),
      );

      final saved = configStore.load()!;
      expect(saved.units.map((u) => u.name), ['proc', 'Licenses']);
      expect(saved.processes.single.cmd, 'edited.exe');
    });

    test('editing a service group keeps the unit position', () {
      viewModel.editUnit(
        1,
        const ServiceConfig(name: 'Licenses', services: ['A', 'B']),
      );

      final saved = configStore.load()!;
      expect(saved.units.map((u) => u.name), ['proc', 'Licenses']);
      expect(saved.services.single.services, ['A', 'B']);
    });

    test('moves a unit across kinds and persists the new order', () {
      viewModel.moveUnitBefore(
        UnitKind.service,
        'Licenses',
        before: (UnitKind.process, 'proc'),
      );

      final saved = configStore.load()!;
      expect(saved.units.map((u) => u.name), ['Licenses', 'proc']);
      expect(saved.units[0], isA<ServiceConfig>());
      expect(saved.units[1], isA<ProcessConfig>());
    });

    test('moving a unit that is not in the list is a no-op', () {
      viewModel.moveUnitBefore(
        UnitKind.process,
        'missing',
        before: (UnitKind.service, 'Licenses'),
      );

      expect(viewModel.units.map((u) => u.name), ['proc', 'Licenses']);
      // No-op means no write either: ConfigStore.save would have left a backup.
      expect(
        Directory('${tmpDir.path}/backups').existsSync(),
        isFalse,
        reason: 'a no-op must not persist the config again',
      );
    });

    test('an unknown before appends the unit at the end', () {
      viewModel.moveUnitBefore(
        UnitKind.process,
        'proc',
        before: (UnitKind.service, 'missing'),
      );

      expect(configStore.load()!.units.map((u) => u.name), [
        'Licenses',
        'proc',
      ]);
    });

    test('naming the moved unit itself is a no-op', () {
      viewModel.moveUnitBefore(
        UnitKind.process,
        'proc',
        before: (UnitKind.process, 'proc'),
      );

      expect(viewModel.units.map((u) => u.name), ['proc', 'Licenses']);
    });

    test(
      'moveUnitBefore persists the order without reloading the managers',
      () async {
        // An autostart process: reloadConfig would start it again from `stopped`.
        writeConfig(
          tmpDir,
          const AppConfig(
            units: [
              ProcessConfig(name: 'auto', cmd: 'auto.exe', autostart: true),
              ProcessConfig(name: 'manual', cmd: 'manual.exe'),
            ],
          ),
        );
        mockRunner.nextHandle = MockProcessHandle(pid: 9001);
        await processManager.reloadConfig(configStore.load()!);
        expect(processManager.getState('auto'), ProcState.running);

        // Stop the autostarted process by hand; a drag must leave it stopped.
        await processManager.stop('auto');
        expect(processManager.getState('auto'), ProcState.stopped);
        final startsBefore = mockRunner.starts.length;

        viewModel.moveUnitBefore(UnitKind.process, 'auto');

        final saved = configStore.load()!;
        expect(saved.units.map((u) => u.name), ['manual', 'auto']);
        expect(processManager.getState('auto'), ProcState.stopped);
        expect(mockRunner.starts.length, startsBefore);
      },
    );

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
        expect(
          viewModel.units.whereType<ServiceConfig>().single.name,
          'Licenses',
        );
      },
    );

    test('invalid unit configs are rejected', () {
      expect(
        viewModel.validateUnit(
          const ServiceConfig(name: 'x/y', services: ['A']),
        ),
        isNotNull,
      );
      expect(
        viewModel.validateUnit(const ServiceConfig(name: 'ok', services: [])),
        isNotNull,
      );
      expect(
        viewModel.validateUnit(
          const ServiceConfig(name: 'ok', services: ['A']),
        ),
        isNull,
      );
      expect(
        viewModel.validateUnit(const ProcessConfig(name: '', cmd: 'run')),
        isNotNull,
      );
      expect(
        viewModel.validateUnit(const ProcessConfig(name: 'ok', cmd: 'run')),
        isNull,
      );
    });

    // ---- Language ----

    group('language', () {
      test('defaults to following the system', () {
        expect(viewModel.language, isNull);
        expect(viewModel.locale, isNull);
      });

      test('setLanguage persists the tag and notifies', () {
        var notifications = 0;
        viewModel.addListener(() => notifications++);

        viewModel.setLanguage('zh');

        expect(viewModel.language, 'zh');
        expect(viewModel.locale, const Locale('zh'));
        expect(viewModel.localizations.settingsTitle, '设置');
        expect(configStore.load()?.language, 'zh');
        expect(notifications, greaterThan(0));
      });

      test('setLanguage(null) drops the override', () {
        viewModel.setLanguage('zh');

        viewModel.setLanguage(null);

        expect(viewModel.language, isNull);
        expect(configStore.load()?.language, isNull);
      });

      test('a hand-edited zh-CN reads back as the shipped zh tag', () async {
        writeConfig(tmpDir, const AppConfig(language: 'zh-CN'));

        await viewModel.reloadFromDisk();

        expect(viewModel.language, 'zh');
        expect(viewModel.locale, const Locale('zh'));
      });

      test('an unsupported tag reads as "follow the system"', () async {
        writeConfig(tmpDir, const AppConfig(language: 'ja'));

        await viewModel.reloadFromDisk();

        expect(viewModel.language, isNull);
        expect(viewModel.locale, isNull);
      });

      test('validateUnit returns the structured rejection', () {
        // Every rule the store enforces, so a new rule cannot ship without a
        // matching reason and a localized rendering.
        final noServices = viewModel.validateUnit(
          const ServiceConfig(name: 'g', services: []),
        );
        final emptyName = viewModel.validateUnit(
          const ServiceConfig(name: '  ', services: ['A']),
        );
        final separator = viewModel.validateUnit(
          const ProcessConfig(name: 'a/b', cmd: 'run'),
        );
        final badPattern = viewModel.validateUnit(
          const ProcessConfig(name: 'p', cmd: 'run', webuiPattern: '[unclosed'),
        );

        expect(noServices?.reason, UnitValidationReason.noServices);
        expect(emptyName?.reason, UnitValidationReason.emptyName);
        expect(separator?.reason, UnitValidationReason.nameSeparator);
        expect(badPattern?.reason, UnitValidationReason.invalidWebuiPattern);

        expect(noServices?.unitName, 'g');
        expect(emptyName?.unitKind, UnitKind.service);
        expect(separator?.unitName, 'a/b');

        expect(
          noServices?.describe(enStrings),
          'Service group "g" needs at least one service',
        );
        expect(noServices?.describe(zhStrings), '服务组“g”至少需要一个服务');
        expect(emptyName?.describe(zhStrings), '服务组名称不能为空');
        expect(separator?.describe(zhStrings), r'进程名称“a/b”不能包含 / 或 \');
        expect(
          badPattern?.describe(zhStrings),
          startsWith('无效的 webui_pattern 正则表达式：'),
        );
      });
    });
  });
}

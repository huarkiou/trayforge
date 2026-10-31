import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';

void main() {
  group('ProcState', () {
    test('has six states', () {
      expect(ProcState.values.length, 6);
      expect(ProcState.values, [
        ProcState.stopped,
        ProcState.starting,
        ProcState.running,
        ProcState.stopping,
        ProcState.crashed,
        ProcState.cooldown,
      ]);
    });
  });

  group('UnitKind', () {
    test('has one JSON value per kind and parses it back', () {
      expect(UnitKind.values, hasLength(2));
      for (final kind in UnitKind.values) {
        expect(UnitKind.tryParse(kind.jsonValue), kind);
      }
    });

    test('carries the label and key prefix used by validation and cards', () {
      expect(UnitKind.process.jsonValue, 'process');
      expect(UnitKind.process.label, 'Process');
      expect(UnitKind.process.keyPrefix, 'proc:');

      expect(UnitKind.service.jsonValue, 'service');
      expect(UnitKind.service.label, 'Service group');
      expect(UnitKind.service.keyPrefix, 'svc:');
    });

    test('tryParse returns null for anything but the two JSON values', () {
      expect(UnitKind.tryParse('contraband'), isNull);
      expect(UnitKind.tryParse(''), isNull);
      expect(UnitKind.tryParse('Process'), isNull);
      expect(UnitKind.tryParse('proc:'), isNull);
    });

    test('each unit config reports its kind', () {
      expect(const ProcessConfig(name: 'p', cmd: 'c').kind, UnitKind.process);
      expect(
        const ServiceConfig(name: 'g', services: ['A']).kind,
        UnitKind.service,
      );
    });
  });

  group('ProcessConfig', () {
    test('creates with required fields', () {
      final config = ProcessConfig(name: 'test', cmd: 'echo hello');
      expect(config.name, 'test');
      expect(config.cmd, 'echo hello');
      expect(config.cwd, isNull);
      expect(config.encoding, isNull);
      expect(config.singleton, false);
      expect(config.autostart, false);
      expect(config.webuiPattern, isNull);
      expect(config.deleteBeforeStart, isEmpty);
      expect(config.maxRestarts, isNull);
      expect(config.env, isNull);
    });

    test('creates with all fields', () {
      final config = ProcessConfig(
        name: 'full',
        cwd: '/tmp',
        cmd: 'run.sh --verbose',
        encoding: 'utf-8',
        singleton: true,
        autostart: true,
        webuiPattern: r'http://[\d.:]+',
        deleteBeforeStart: ['file.lock'],
        maxRestarts: 5,
        env: {'KEY': 'value'},
      );
      expect(config.name, 'full');
      expect(config.cwd, '/tmp');
      expect(config.cmd, 'run.sh --verbose');
      expect(config.encoding, 'utf-8');
      expect(config.singleton, true);
      expect(config.autostart, true);
      expect(config.webuiPattern, r'http://[\d.:]+');
      expect(config.deleteBeforeStart, ['file.lock']);
      expect(config.maxRestarts, 5);
      expect(config.env, {'KEY': 'value'});
    });

    group('toJson', () {
      test('serializes with only non-null optional fields', () {
        final config = ProcessConfig(name: 'minimal', cmd: 'app.exe');
        final json = config.toJson();
        expect(json['name'], 'minimal');
        expect(json['cmd'], 'app.exe');
        expect(json.containsKey('cwd'), false);
        expect(json.containsKey('encoding'), false);
        expect(json.containsKey('webui_pattern'), false);
        expect(json.containsKey('max_restarts'), false);
        expect(json.containsKey('env'), false);
      });

      test('serializes all fields', () {
        final config = ProcessConfig(
          name: 'full',
          cwd: '/app',
          cmd: 'run',
          encoding: 'latin1',
          singleton: true,
          autostart: true,
          webuiPattern: r'http://.*',
          deleteBeforeStart: ['a.lock', 'b.lock'],
          maxRestarts: 3,
          env: {'A': '1'},
        );
        final json = config.toJson();
        expect(json['name'], 'full');
        expect(json['cwd'], '/app');
        expect(json['cmd'], 'run');
        expect(json['encoding'], 'latin1');
        expect(json['singleton'], true);
        expect(json['autostart'], true);
        expect(json['webui_pattern'], r'http://.*');
        expect(json['delete_before_start'], ['a.lock', 'b.lock']);
        expect(json['max_restarts'], 3);
        expect(json['env'], {'A': '1'});
      });
    });

    group('fromJson', () {
      test('deserializes minimal json', () {
        final json = {'name': 'test', 'cmd': 'app.exe'};
        final config = ProcessConfig.fromJson(json);
        expect(config.name, 'test');
        expect(config.cmd, 'app.exe');
        expect(config.cwd, isNull);
        expect(config.singleton, false);
      });

      test('deserializes full json with snake_case keys', () {
        final json = {
          'name': 'full',
          'cwd': '/app',
          'cmd': 'run',
          'encoding': 'utf-8',
          'singleton': true,
          'autostart': true,
          'webui_pattern': r'http://.*',
          'delete_before_start': ['lock.file'],
          'max_restarts': 3,
          'env': {'KEY': 'val'},
        };
        final config = ProcessConfig.fromJson(json);
        expect(config.name, 'full');
        expect(config.cwd, '/app');
        expect(config.cmd, 'run');
        expect(config.encoding, 'utf-8');
        expect(config.singleton, true);
        expect(config.autostart, true);
        expect(config.webuiPattern, r'http://.*');
        expect(config.deleteBeforeStart, ['lock.file']);
        expect(config.maxRestarts, 3);
        expect(config.env, {'KEY': 'val'});
      });

      test('deserializes elevated and defaults it to false', () {
        expect(
          ProcessConfig.fromJson({
            'name': 'elev',
            'cmd': 'run',
            'elevated': true,
          }).elevated,
          isTrue,
        );
        expect(
          ProcessConfig.fromJson({'name': 'plain', 'cmd': 'run'}).elevated,
          isFalse,
        );
      });

      test('serializes elevated only when set', () {
        final minimal = ProcessConfig(name: 'min', cmd: 'run').toJson();
        expect(minimal.containsKey('elevated'), isFalse);
        expect(
          ProcessConfig(
            name: 'elev',
            cmd: 'run',
            elevated: true,
          ).toJson()['elevated'],
          isTrue,
        );
      });

      test('round-trips log_file', () {
        final json = ProcessConfig(
          name: 'logs',
          cmd: 'run',
          logFile: r'logs\app.log',
        ).toJson();
        expect(json['log_file'], r'logs\app.log');
        expect(ProcessConfig.fromJson(json).logFile, r'logs\app.log');
        expect(
          ProcessConfig(
            name: 'plain',
            cmd: 'run',
          ).toJson().containsKey('log_file'),
          isFalse,
        );
      });

      test('deserializes with defaults for missing fields', () {
        final json = {'name': 'min', 'cmd': 'run'};
        final config = ProcessConfig.fromJson(json);
        expect(config.singleton, false);
        expect(config.autostart, false);
        expect(config.deleteBeforeStart, isEmpty);
        expect(config.maxRestarts, isNull);
      });

      test('migrates old bool delete_before_start to empty list', () {
        final json = {
          'name': 'old',
          'cmd': 'run',
          'delete_before_start': true, // old Flutter format
        };
        final config = ProcessConfig.fromJson(json);
        expect(config.deleteBeforeStart, isEmpty);
      });
    });

    group('copyWith', () {
      test('returns new instance with changed fields', () {
        final original = ProcessConfig(name: 'orig', cwd: '/tmp', cmd: 'cmd');
        final copy = original.copyWith(name: 'new');
        expect(copy.name, 'new');
        expect(copy.cwd, '/tmp');
        expect(copy.cmd, 'cmd');
      });
    });
  });

  group('ServiceConfig', () {
    test('round-trips name, services and stop_dependents', () {
      const config = ServiceConfig(
        name: 'Licenses',
        services: ['A', 'B'],
        stopDependents: true,
      );
      final json = config.toJson();

      expect(json['name'], 'Licenses');
      expect(json['services'], ['A', 'B']);
      expect(json['stop_dependents'], true);
      expect(ServiceConfig.fromJson(json), config);
    });

    test('omits stop_dependents when false and defaults it on parse', () {
      const config = ServiceConfig(name: 'g', services: ['A']);
      expect(config.toJson().containsKey('stop_dependents'), isFalse);
      expect(
        ServiceConfig.fromJson({
          'name': 'g',
          'services': ['A'],
        }).stopDependents,
        isFalse,
      );
    });

    test('tolerates a missing or malformed services list', () {
      expect(ServiceConfig.fromJson({'name': 'g'}).services, isEmpty);
      expect(
        ServiceConfig.fromJson({'name': 'g', 'services': 'A'}).services,
        isEmpty,
      );
    });

    test('equality covers the member list', () {
      expect(
        const ServiceConfig(name: 'g', services: ['A', 'B']),
        const ServiceConfig(name: 'g', services: ['A', 'B']),
      );
      expect(
        const ServiceConfig(name: 'g', services: ['A']),
        isNot(const ServiceConfig(name: 'g', services: ['A', 'B'])),
      );
    });
  });

  group('AppConfig services', () {
    test('defaults to no services and a 5s poll', () {
      const config = AppConfig();
      expect(config.services, isEmpty);
      expect(config.servicePollMs, 5000);
    });

    test('round-trips services and service_poll_ms', () {
      const config = AppConfig(
        servicePollMs: 2000,
        units: [
          ServiceConfig(name: 'g', services: ['A']),
        ],
      );
      final json = config.toJson();
      expect(json['service_poll_ms'], 2000);
      final units = json['units'] as List<dynamic>;
      expect(units, hasLength(1));
      expect((units.single as Map<String, dynamic>)['kind'], 'service');

      final parsed = AppConfig.fromJson(json);
      expect(parsed.servicePollMs, 2000);
      expect(parsed.services.single, config.services.single);
    });

    test('parses a config without the new keys', () {
      final parsed = AppConfig.fromJson({'processes': <dynamic>[]});
      expect(parsed.services, isEmpty);
      expect(parsed.servicePollMs, 5000);
    });
  });

  group('AppConfig units', () {
    test('keeps the configured order across kinds', () {
      const config = AppConfig(
        units: [
          ProcessConfig(name: 'p1', cmd: 'c1'),
          ServiceConfig(name: 'g1', services: ['A']),
          ProcessConfig(name: 'p2', cmd: 'c2'),
        ],
      );

      expect(config.units.map((u) => u.name), ['p1', 'g1', 'p2']);
      expect(config.processes.map((p) => p.name), ['p1', 'p2']);
      expect(config.services.map((s) => s.name), ['g1']);
    });

    test('round-trips order and kinds', () {
      const config = AppConfig(
        units: [
          ServiceConfig(name: 'g1', services: ['A'], stopDependents: true),
          ProcessConfig(name: 'p1', cmd: 'c1'),
        ],
      );

      final parsed = AppConfig.fromJson(config.toJson());

      expect(parsed.units, hasLength(2));
      expect(parsed.units[0], isA<ServiceConfig>());
      expect(parsed.units[1], isA<ProcessConfig>());
      expect(parsed.services.single, config.services.single);
      expect(parsed.processes.single.name, 'p1');
    });

    test('migrates a legacy processes + services config, processes first', () {
      final parsed = AppConfig.fromJson({
        'processes': [
          {'name': 'p1', 'cmd': 'c1'},
        ],
        'services': [
          {
            'name': 'g1',
            'services': ['A'],
          },
        ],
      });

      expect(parsed.units.map((u) => u.name), ['p1', 'g1']);
      expect(parsed.units[0], isA<ProcessConfig>());
      expect(parsed.units[1], isA<ServiceConfig>());
    });

    test('infers the kind when a hand-written entry omits it', () {
      final parsed = AppConfig.fromJson({
        'units': [
          {'name': 'p1', 'cmd': 'c1'},
          {
            'name': 'g1',
            'services': ['A'],
          },
        ],
      });

      expect(parsed.units[0], isA<ProcessConfig>());
      expect(parsed.units[1], isA<ServiceConfig>());
    });

    test('an explicit kind wins over the entry shape', () {
      final parsed = AppConfig.fromJson({
        'units': [
          {
            'kind': 'process',
            'name': 'p1',
            'cmd': 'c1',
            'services': ['A'],
          },
        ],
      });

      expect(parsed.units.single, isA<ProcessConfig>());
    });

    test('an unknown kind is a parse failure, not a skipped unit', () {
      expect(
        () => AppConfig.fromJson({
          'units': [
            {'kind': 'contraband', 'name': 'x'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('renamed keeps the kind and swaps the name', () {
      const process = ProcessConfig(name: 'p1', cmd: 'c1');
      final renamed = process.renamed('p2');
      expect(renamed, isA<ProcessConfig>());
      expect(renamed.name, 'p2');
      expect(renamed.cmd, 'c1');

      const group = ServiceConfig(name: 'g1', services: ['A']);
      final renamedGroup = group.renamed('g2');
      expect(renamedGroup, isA<ServiceConfig>());
      expect(renamedGroup.services, ['A']);
    });
  });

  group('AppConfig', () {
    test('creates with defaults', () {
      final config = AppConfig();
      expect(config.outputHistoryLimit, 1000);
      expect(config.outputRefreshMs, 500);
      expect(config.dashboardLayout, DashboardLayout.list);
      expect(config.processes, isEmpty);
    });

    test('creates with custom values', () {
      final processes = [ProcessConfig(name: 'p1', cmd: 'c1')];
      final config = AppConfig(
        outputHistoryLimit: 500,
        outputRefreshMs: 50,
        dashboardLayout: DashboardLayout.grid,
        units: processes,
      );
      expect(config.outputHistoryLimit, 500);
      expect(config.outputRefreshMs, 50);
      expect(config.dashboardLayout, DashboardLayout.grid);
      expect(config.processes, processes);
    });

    test('defaultConfig provides NapCat and AstrBot', () {
      final config = AppConfig.defaultConfig();
      expect(config.outputHistoryLimit, 1000);
      expect(config.outputRefreshMs, 500);
      expect(config.processes.length, 2);

      final napcat = config.processes[0];
      expect(napcat.name, 'NapCat');
      expect(napcat.cmd, r'napcat.exe');
      expect(napcat.singleton, true);
      expect(napcat.autostart, true);
      expect(napcat.maxRestarts, 3);

      final astrbot = config.processes[1];
      expect(astrbot.name, 'AstrBot');
      expect(astrbot.cmd, r'astrbot.exe');
      expect(astrbot.singleton, true);
      expect(astrbot.autostart, true);
      expect(astrbot.maxRestarts, 3);
    });

    group('toJson', () {
      test('serializes config with processes', () {
        final config = AppConfig(
          outputHistoryLimit: 200,
          outputRefreshMs: 50,
          dashboardLayout: DashboardLayout.grid,
          units: [ProcessConfig(name: 'p1', cmd: 'c1')],
        );
        final json = config.toJson();
        expect(json['output_history_limit'], 200);
        expect(json['output_refresh_ms'], 50);
        expect(json['dashboard_layout'], 'grid');
        expect(json.containsKey('processes'), isFalse);
        expect(json.containsKey('services'), isFalse);
        final units = json['units'] as List<dynamic>;
        expect(units, hasLength(1));
        expect((units.single as Map<String, dynamic>)['kind'], 'process');
      });
    });

    group('fromJson', () {
      test('deserializes with defaults', () {
        final json = <String, dynamic>{};
        final config = AppConfig.fromJson(json);
        expect(config.outputHistoryLimit, 1000);
        expect(config.outputRefreshMs, 500);
        expect(config.dashboardLayout, DashboardLayout.list);
        expect(config.processes, isEmpty);
      });

      test('round-trips dashboard_layout list and grid', () {
        for (final layout in DashboardLayout.values) {
          final config = AppConfig.fromJson(
            AppConfig(dashboardLayout: layout).toJson(),
          );
          expect(config.dashboardLayout, layout);
        }
      });

      test('defaults to list for unknown dashboard_layout value', () {
        final json = {'dashboard_layout': 'bogus'};
        expect(AppConfig.fromJson(json).dashboardLayout, DashboardLayout.list);
      });

      test('defaults to list for non-string dashboard_layout value', () {
        final json = {'dashboard_layout': 42};
        expect(AppConfig.fromJson(json).dashboardLayout, DashboardLayout.list);
      });

      test('deserializes a migrated legacy config', () {
        final json = {
          'output_history_limit': 500,
          'output_refresh_ms': 200,
          'processes': [
            {'name': 'p1', 'cmd': 'c1'},
            {'name': 'p2', 'cmd': 'c2', 'singleton': true},
          ],
        };
        final config = AppConfig.fromJson(json);
        expect(config.outputHistoryLimit, 500);
        expect(config.outputRefreshMs, 200);
        expect(config.processes.length, 2);
        expect(config.processes[0].name, 'p1');
        expect(config.processes[1].singleton, true);
        expect(config.units, hasLength(2));
        expect(config.units.every((u) => u is ProcessConfig), isTrue);
      });
    });
  });
}

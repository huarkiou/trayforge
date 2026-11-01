import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/service_host.dart';
import 'package:trayforge/foundation/service_host_linux.dart';
import 'package:trayforge/foundation/service_status.dart';

/// Records every command and answers with canned results keyed by the first
/// argument (the `systemctl`/`pkexec` verb).
class _Commands {
  final List<List<String>> calls = [];
  final Map<String, ProcessResult> byVerb = {};

  ProcessResult answer(String verb) =>
      byVerb[verb] ?? ProcessResult(0, 1, '', 'unexpected command');

  ServiceCommandRunner get runner => (executable, arguments) async {
    calls.add([executable, ...arguments]);
    final key = executable == 'pkexec' ? 'pkexec' : arguments.first;
    return byVerb[key] ?? ProcessResult(0, 1, '', 'unexpected command');
  };
}

ProcessResult _ok([String stdout = '']) => ProcessResult(0, 0, stdout, '');
ProcessResult _fail([String stderr = 'boom']) =>
    ProcessResult(0, 1, '', stderr);

void main() {
  group('LinuxServiceHost.query', () {
    test('maps active/inactive/activating states', () async {
      final commands = _Commands()
        ..byVerb['show'] = _ok(
          'LoadState=loaded\n'
          'ActiveState=active\n'
          'SubState=running\n',
        );
      final host = LinuxServiceHost(runner: commands.runner);

      final statuses = await host.query(['a.service']);

      expect(statuses.single.state, ServiceState.running);
      expect(
        commands.calls.single,
        containsAllInOrder(['systemctl', 'show', 'a.service']),
      );
    });

    test('reports not-installed units', () async {
      final commands = _Commands()
        ..byVerb['show'] = _ok(
          'LoadState=not-found\nActiveState=inactive\nSubState=dead\n',
        );
      final host = LinuxServiceHost(runner: commands.runner);

      expect(
        (await host.query(['nope.service'])).single.state,
        ServiceState.notInstalled,
      );
    });

    test('maps a failed unit to failed', () async {
      final commands = _Commands()
        ..byVerb['show'] = _ok(
          'LoadState=loaded\nActiveState=failed\nSubState=failed\n',
        );
      final host = LinuxServiceHost(runner: commands.runner);

      expect(
        (await host.query(['x.service'])).single.state,
        ServiceState.failed,
      );
    });
  });

  group('LinuxServiceHost start/stop', () {
    test('one systemctl call for the whole group', () async {
      final commands = _Commands()..byVerb['start'] = _ok();
      final host = LinuxServiceHost(runner: commands.runner);

      final results = await host.start(['a.service', 'b.service']);

      expect(results.every((r) => r.ok), isTrue);
      expect(commands.calls.single, [
        'systemctl',
        'start',
        '--',
        'a.service',
        'b.service',
      ]);
    });

    test('retries through pkexec when polkit needs authentication', () async {
      final commands = _Commands()
        ..byVerb['start'] = _fail('Interactive authentication required.')
        ..byVerb['pkexec'] = _ok()
        ..byVerb['show'] = _ok(
          'LoadState=loaded\nActiveState=active\nSubState=running\n',
        );
      final host = LinuxServiceHost(runner: commands.runner);

      final results = await host.start(['a.service']);

      expect(results.single.ok, isTrue);
      expect(commands.calls.map((c) => c.first).toList(), [
        'systemctl',
        'pkexec',
        'systemctl',
      ], reason: 'direct attempt, escalation, then a verifying re-query');
      expect(commands.calls[1], [
        'pkexec',
        'systemctl',
        'start',
        '--',
        'a.service',
      ]);
      expect(
        commands.calls.last,
        containsAllInOrder(['systemctl', 'show', 'a.service']),
      );
    });

    test('reports per-service truth when the operation fails', () async {
      final commands = _Commands()..byVerb['start'] = _fail('disabled');
      final host = LinuxServiceHost(runner: commands.runner);
      // Second query (after the failure) shows the unit still inactive.
      commands.byVerb['show'] = _ok(
        'LoadState=loaded\nActiveState=inactive\nSubState=dead\n',
      );

      final results = await host.start(['a.service']);

      expect(results.single.ok, isFalse);
      expect(results.single.failure, ServiceFailure.unknown);
      expect(results.single.message, contains('disabled'));
    });

    test('pkexec missing is not fatal', () async {
      final commands = _Commands()..byVerb['stop'] = _fail('Access denied');
      final host = LinuxServiceHost(
        runner: (executable, arguments) async {
          commands.calls.add([executable, ...arguments]);
          if (executable == 'pkexec') {
            throw ProcessException('pkexec', arguments);
          }
          return commands.answer(arguments.first);
        },
      );
      commands.byVerb['show'] = _ok(
        'LoadState=loaded\nActiveState=active\nSubState=running\n',
      );

      final results = await host.stop(['a.service']);

      expect(results.single.ok, isFalse);
      expect(results.single.failure, ServiceFailure.accessDenied);
    });
  });

  group('LinuxServiceHost.dependents', () {
    test(
      'parses the reverse dependency list and drops the unit itself',
      () async {
        final commands = _Commands()
          ..byVerb['list-dependencies'] = _ok('a.service\nb.service\n');
        final host = LinuxServiceHost(runner: commands.runner);

        final dependents = await host.dependents('a.service');

        expect(dependents, ['b.service']);
      },
    );

    test('returns an empty list on failure', () async {
      final commands = _Commands()
        ..byVerb['list-dependencies'] = _fail('no such unit');
      final host = LinuxServiceHost(runner: commands.runner);

      expect(await host.dependents('a.service'), isEmpty);
    });
  });
}

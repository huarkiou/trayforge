import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/foundation/service_host.dart';
import 'package:trayforge/foundation/service_operator.dart';
import 'package:trayforge/foundation/service_status.dart';
import 'package:trayforge/services/service_controller.dart';

import '../helpers/service_fakes.dart';

void main() {
  late FakeServiceHost host;
  late ServiceController controller;
  late List<String> logs;
  late List<ProcState> states;

  ServiceConfig groupConfig({
    List<String> services = const ['a', 'b'],
    bool stopDependents = false,
  }) => ServiceConfig(
    name: 'grp',
    services: services,
    stopDependents: stopDependents,
  );

  void build({
    ServiceConfig? config,
    FakeServiceHost? fake,
    ServiceOperator? operator,
    Duration pollInterval = const Duration(hours: 1),
    Duration settleTimeout = const Duration(milliseconds: 300),
    Duration operationTimeout = const Duration(minutes: 5),
  }) {
    host =
        fake ??
        FakeServiceHost(
          states: {'a': ServiceState.stopped, 'b': ServiceState.stopped},
        );
    controller = ServiceController(
      name: 'grp',
      config: config ?? groupConfig(),
      host: host,
      operator: operator ?? ServiceOperator(host: host),
      pollInterval: pollInterval,
      settleTimeout: settleTimeout,
      operationPollInterval: const Duration(milliseconds: 5),
      operationTimeout: operationTimeout,
    );
    logs = [];
    states = [];
    controller.output.listen(logs.add);
    controller.state.listen(states.add);
    addTearDown(controller.dispose);
  }

  group('init', () {
    test('queries the group and logs a summary', () async {
      build();
      await controller.init();

      expect(controller.currentState, ProcState.stopped);
      expect(controller.statuses, hasLength(2));
      expect(logs.any((l) => l.contains('grp: 0/2 running')), isTrue);
    });

    test('reports a missing service as crashed with the name', () async {
      build(
        config: groupConfig(services: ['a', 'missing']),
        fake: FakeServiceHost(states: {'a': ServiceState.stopped}),
      );
      await controller.init();

      expect(controller.currentState, ProcState.crashed);
      expect(logs.any((l) => l.contains('not installed: missing')), isTrue);
    });

    test('a failing query lands on crashed', () async {
      final fake = FakeServiceHost(states: {})..failQueries = true;
      build(fake: fake);
      await controller.init();

      expect(controller.currentState, ProcState.crashed);
      expect(logs.any((l) => l.contains('fake query failure')), isTrue);
    });
  });

  group('toggle', () {
    test('starts every member when the group is down', () async {
      build();
      await controller.init();

      await controller.toggle();

      expect(host.startCalls.single, ['a', 'b']);
      expect(controller.currentState, ProcState.running);
      expect(
        controller.statuses.every((s) => s.state == ServiceState.running),
        isTrue,
      );
      expect(logs.any((l) => l.contains('a: Running')), isTrue);
      expect(logs.any((l) => l.contains('grp: 2/2 running')), isTrue);
    });

    test('stops every member when any member is up', () async {
      build(
        fake: FakeServiceHost(
          states: {'a': ServiceState.running, 'b': ServiceState.stopped},
        ),
      );
      await controller.init();

      await controller.toggle();

      expect(host.stopCalls.single, ['a', 'b']);
      expect(controller.currentState, ProcState.stopped);
      expect(logs.any((l) => l.contains('grp: all stopped')), isTrue);
    });

    test('only moves the members that need moving', () async {
      build(
        fake: FakeServiceHost(
          states: {'a': ServiceState.stopped, 'b': ServiceState.running},
        ),
      );
      await controller.init();

      // a is down, b is up → "any up → stop all": a is already down.
      await controller.toggle();

      expect(host.stopCalls.single, ['a', 'b']);
      expect(controller.currentState, ProcState.stopped);
    });

    test('a failed operation lands on a sticky crashed state', () async {
      final fake = FakeServiceHost(
        states: {'a': ServiceState.stopped, 'b': ServiceState.stopped},
      )..opFailure = ServiceFailure.disabled;
      build(fake: fake);
      await controller.init();

      await controller.toggle();

      expect(controller.currentState, ProcState.crashed);
      expect(logs.any((l) => l.contains('failed —')), isTrue);
      expect(controller.statuses, hasLength(2));
    });

    test('a result that looked failed is not a problem once settled', () async {
      // The helper returns while the SCM still says STOP_PENDING; the settle
      // phase then sees the target state. No problem may be reported.
      final fake = FakeServiceHost(states: {'a': ServiceState.running})
        ..failuresByService['a'] = ServiceFailure.unknown
        ..moveStateEvenWhenFailing = true;
      build(
        fake: fake,
        config: groupConfig(services: ['a']),
      );
      await controller.init();

      await controller.toggle();

      expect(controller.currentState, ProcState.stopped);
      expect(logs.any((l) => l.contains('problem(s)')), isFalse);
      expect(logs.any((l) => l.contains('failed —')), isFalse);
    });

    test(
      'a failed member that never settles is one problem, not two',
      () async {
        final fake = FakeServiceHost(states: {'a': ServiceState.running})
          ..failuresByService['a'] = ServiceFailure.unknown;
        build(
          fake: fake,
          config: groupConfig(services: ['a']),
        );
        await controller.init();

        await controller.toggle();

        expect(controller.currentState, ProcState.crashed);
        expect(
          logs.where((l) => l.contains('problem(s)')).single,
          contains('grp: 1 problem(s)'),
        );
      },
    );

    test('a member that never settles is reported as a timeout', () async {
      final fake = FakeServiceHost(
        states: {'a': ServiceState.stopped},
        settleOnOp: false,
      );
      build(fake: fake);
      await controller.init();

      await controller.toggle();

      expect(controller.currentState, ProcState.crashed);
      expect(logs.any((l) => l.contains('did not reach Running')), isTrue);
    });

    test('a second toggle while busy is ignored', () async {
      build();
      await controller.init();

      final first = controller.toggle();
      final second = controller.toggle();
      await Future.wait([first, second]);

      expect(host.startCalls, hasLength(1));
    });

    test(
      'refuses a toggle while a timed-out operation is still alive',
      () async {
        final fake = _SlowStartHost(states: {'a': ServiceState.stopped});
        build(
          fake: fake,
          config: groupConfig(services: ['a']),
          settleTimeout: const Duration(milliseconds: 30),
          operationTimeout: const Duration(milliseconds: 30),
        );
        await controller.init();

        // The operator's future never completes: the timeout gives up on the
        // operation, but the helper is still (notionally) alive.
        final first = controller.toggle();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await first;

        expect(controller.busy, isFalse);
        await controller.toggle();
        expect(fake.startCalls, isEmpty, reason: 'no second helper may start');
        expect(
          logs.any((l) => l.contains('a previous operation is still running')),
          isTrue,
        );

        // The late helper finally finishes: the guard is released, once.
        fake.gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(fake.startCalls, hasLength(1));
        expect(
          logs.any((l) => l.contains('a previous operation finished late')),
          isTrue,
        );

        // A new operation is allowed again, and the late one really moved `a`.
        await controller.toggle();
        expect(fake.stopCalls, hasLength(1));
      },
    );
  });

  group('idle polling', () {
    test('picks up a change made outside TrayForge', () async {
      build(pollInterval: const Duration(milliseconds: 20));
      await controller.init();
      expect(controller.currentState, ProcState.stopped);

      host.states['a'] = ServiceState.running;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controller.currentState, ProcState.running);
      expect(logs.any((l) => l.contains('changed outside TrayForge')), isTrue);
    });

    test('logs a member-level change even when the aggregate holds', () async {
      build(
        pollInterval: const Duration(milliseconds: 20),
        fake: FakeServiceHost(
          states: {'a': ServiceState.running, 'b': ServiceState.running},
        ),
      );
      await controller.init();

      host.states['b'] = ServiceState.stopped;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controller.currentState, ProcState.running);
      expect(
        logs.any(
          (l) =>
              l.contains('b: Running → Stopped') &&
              l.contains('changed outside TrayForge'),
        ),
        isTrue,
      );
    });

    test('an external change un-pins a crashed group', () async {
      final fake = FakeServiceHost(states: {'a': ServiceState.stopped})
        ..opFailure = ServiceFailure.disabled;
      build(
        fake: fake,
        config: groupConfig(services: ['a']),
        pollInterval: const Duration(milliseconds: 20),
      );
      await controller.init();

      await controller.toggle();
      expect(controller.currentState, ProcState.crashed);

      // Someone starts the service outside TrayForge.
      fake.states['a'] = ServiceState.running;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controller.currentState, ProcState.running);
      expect(logs.any((l) => l.contains('changed outside TrayForge')), isTrue);
    });

    test('un-pins when the aggregate is crashed on both sides', () async {
      // `missing` keeps the aggregate crashed, so comparing aggregates could
      // never see the change: the member states have to decide.
      final fake = FakeServiceHost(states: {'a': ServiceState.stopped})
        ..failuresByService['missing'] = ServiceFailure.notInstalled;
      build(
        fake: fake,
        config: groupConfig(services: ['a', 'missing']),
        pollInterval: const Duration(milliseconds: 20),
        settleTimeout: const Duration(milliseconds: 30),
      );
      await controller.init();

      await controller.toggle(); // `a` starts, `missing` fails
      expect(controller.currentState, ProcState.crashed);

      // Someone stops `a` outside TrayForge; `missing` is still not installed,
      // so the aggregate stays crashed.
      fake.states['a'] = ServiceState.stopped;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(logs.any((l) => l.contains('changed outside TrayForge')), isTrue);
      expect(controller.currentState, ProcState.crashed);

      // The pin is gone: when `missing` appears, the group recovers.
      fake.states['missing'] = ServiceState.running;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controller.currentState, ProcState.running);
    });

    test('a recovered query is not reported as an external change', () async {
      final fake = FakeServiceHost(states: {'a': ServiceState.stopped})
        ..failQueries = true;
      build(
        fake: fake,
        config: groupConfig(services: ['a']),
        pollInterval: const Duration(milliseconds: 20),
      );
      await controller.init();
      expect(controller.currentState, ProcState.crashed);

      // The query starts working again: the pinned crash is cleared silently.
      fake.failQueries = false;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controller.currentState, ProcState.stopped);
      expect(logs.any((l) => l.contains('changed outside TrayForge')), isFalse);
    });
  });

  group('problem reporting', () {
    test('logs the OS code for a failing member at startup', () async {
      build(
        config: groupConfig(services: ['a', 'missing']),
        fake: FakeServiceHost(states: {'a': ServiceState.stopped})
          ..win32Codes['missing'] = 1060,
      );
      await controller.init();

      expect(
        logs.any(
          (l) => l.contains('missing: Not installed') && l.contains('1060'),
        ),
        isTrue,
      );
    });

    test('names the dependents that block a stop', () async {
      final fake = FakeServiceHost(states: {'a': ServiceState.running})
        ..opFailure = ServiceFailure.dependentsRunning
        ..dependentsOf = ['child-a', 'child-b'];
      build(
        fake: fake,
        config: groupConfig(services: ['a']),
        settleTimeout: const Duration(milliseconds: 30),
      );
      await controller.init();

      await controller.toggle();

      expect(fake.dependentsCalls, ['a']);
      expect(
        logs.any(
          (l) =>
              l.contains('still running: child-a, child-b') &&
              l.contains('Stop dependent services'),
        ),
        isTrue,
      );
    });

    test('names dependents when the stop failed generically', () async {
      // A generic failure must not hide the dependents: the report is derived
      // from what is still up, not from the operator's failure kind.
      final fake = FakeServiceHost(states: {'a': ServiceState.running})
        ..failuresByService['a'] = ServiceFailure.unknown
        ..dependentsOf = ['child-a', 'child-b'];
      build(
        fake: fake,
        config: groupConfig(services: ['a']),
        settleTimeout: const Duration(milliseconds: 30),
      );
      await controller.init();

      await controller.toggle();

      expect(fake.dependentsCalls, ['a']);
      expect(
        logs.any(
          (l) =>
              l.contains('still running: child-a, child-b') &&
              l.contains('Stop dependent services'),
        ),
        isTrue,
      );
    });

    test('names dependents when an elevated stop came back generic', () async {
      // After a UAC hop the operator rebuilds its results from the OS, so the
      // failure kind is `unknown`, never `dependentsRunning`.
      final fake = FakeServiceHost(states: {'a': ServiceState.running})
        ..opFailure = ServiceFailure.accessDenied
        ..dependentsOf = ['child-a'];
      final operator = ServiceOperator(
        host: fake,
        elevated: FakeElevatedServiceRunner(),
      );
      build(
        fake: fake,
        operator: operator,
        config: groupConfig(services: ['a']),
        settleTimeout: const Duration(milliseconds: 30),
      );
      await controller.init();

      await controller.toggle();

      expect(fake.dependentsCalls, ['a']);
      expect(logs.any((l) => l.contains('still running: child-a')), isTrue);
    });

    test('logs no dependents when nothing is still up', () async {
      final fake = FakeServiceHost(states: {'a': ServiceState.running})
        ..dependentsOf = ['child-a'];
      build(
        fake: fake,
        config: groupConfig(services: ['a']),
        settleTimeout: const Duration(milliseconds: 30),
      );
      await controller.init();

      await controller.toggle();

      expect(controller.currentState, ProcState.stopped);
      expect(fake.dependentsCalls, isEmpty);
      expect(logs.any((l) => l.contains('still running:')), isFalse);
    });
  });

  group('updateConfig', () {
    test('targets the new member list on the next operation', () async {
      build();
      await controller.init();

      controller.updateConfig(groupConfig(services: ['a', 'b', 'c']));
      host.states['c'] = ServiceState.stopped;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await controller.toggle();

      expect(host.startCalls.last, ['a', 'b', 'c']);
    });
  });
}

/// [FakeServiceHost] whose `start` waits for [gate].
///
/// Lets a test keep the operator's future alive after the controller has
/// already timed out, which is the case a late UAC consent produces.
class _SlowStartHost extends FakeServiceHost {
  _SlowStartHost({super.states});

  final Completer<void> gate = Completer<void>();

  @override
  Future<List<ServiceOpResult>> start(List<String> names) async {
    await gate.future;
    return super.start(names);
  }
}

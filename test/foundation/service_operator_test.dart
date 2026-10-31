import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/elevated_process_win32.dart';
import 'package:trayforge/foundation/service_host.dart';
import 'package:trayforge/foundation/service_operator.dart';
import 'package:trayforge/foundation/service_status.dart';

import '../helpers/service_fakes.dart';

void main() {
  const op = ServiceGroupOp(kind: ServiceOpKind.start, services: ['a', 'b']);

  group('ServiceOperator', () {
    test('stays direct when no elevation is needed', () async {
      final host = FakeServiceHost(states: {'a': ServiceState.stopped});
      final elevated = FakeElevatedServiceRunner();
      final operator = ServiceOperator(host: host, elevated: elevated);

      final results = await operator.run(op);

      expect(results.every((r) => r.ok), isTrue);
      expect(host.startCalls.single, ['a', 'b']);
      expect(elevated.calls, isEmpty);
    });

    test(
      'elevates once for the whole group and verifies the outcome',
      () async {
        final host = FakeServiceHost(
          states: {'a': ServiceState.stopped, 'b': ServiceState.stopped},
        )..opFailure = ServiceFailure.accessDenied;
        final elevated = FakeElevatedServiceRunner(
          onRun: (groupOp) {
            // The elevated helper actually performs the operation.
            host.opFailure = null;
            for (final name in groupOp.services) {
              host.states[name] = ServiceState.running;
            }
          },
        );
        final operator = ServiceOperator(host: host, elevated: elevated);

        final results = await operator.run(op);

        expect(elevated.calls, hasLength(1), reason: 'one UAC for the group');
        expect(elevated.calls.single.services, ['a', 'b']);
        expect(results.every((r) => r.ok), isTrue);
      },
    );

    test(
      'reports a declined UAC prompt as cancelled for every service',
      () async {
        final host = FakeServiceHost(states: {'a': ServiceState.stopped})
          ..opFailure = ServiceFailure.accessDenied;
        final elevated = FakeElevatedServiceRunner(
          throwOnRun: const ElevationException('UAC elevation was cancelled'),
        );
        final operator = ServiceOperator(host: host, elevated: elevated);

        final results = await operator.run(op);

        expect(results, hasLength(2));
        expect(
          results.every((r) => r.failure == ServiceFailure.cancelled),
          isTrue,
        );
        expect(results.first.message, contains('cancelled'));
      },
    );

    test(
      'a declined UAC prompt marks only the services that needed it',
      () async {
        final host = FakeServiceHost(
          states: {'a': ServiceState.stopped, 'b': ServiceState.stopped},
        )..failuresByService['a'] = ServiceFailure.accessDenied;
        final elevated = FakeElevatedServiceRunner(
          throwOnRun: const ElevationException('UAC elevation was cancelled'),
        );
        final operator = ServiceOperator(host: host, elevated: elevated);

        final results = await operator.run(op);

        final byName = {for (final result in results) result.service: result};
        expect(byName['a']!.failure, ServiceFailure.cancelled);
        expect(
          byName['b']!.ok,
          isTrue,
          reason: 'b never needed elevation, so its result stands',
        );
      },
    );

    test(
      'reports services that did not reach the target after elevation',
      () async {
        final host = FakeServiceHost(states: {'a': ServiceState.stopped})
          ..opFailure = ServiceFailure.accessDenied;
        // The elevated helper claims success but the SCM never changed.
        final elevated = FakeElevatedServiceRunner();
        final operator = ServiceOperator(host: host, elevated: elevated);

        final results = await operator.run(op);

        expect(results.first.ok, isFalse);
        expect(results.first.message, contains('still stopped'));
      },
    );
  });

  group('performServiceOp', () {
    test('stops dependents first, then the group members', () async {
      final host = _DependentsHost();

      final results = await performServiceOp(
        host,
        const ServiceGroupOp(
          kind: ServiceOpKind.stop,
          services: ['a'],
          stopDependents: true,
        ),
      );

      expect(host.dependentsCalls, ['a']);
      expect(host.stopCalls, [
        ['child'], // dependents first
        ['a'], // then the group member
      ]);
      // Dependent results come first, then the member results.
      expect(results.map((r) => r.service), ['child', 'a']);
      expect(results.every((r) => r.ok), isTrue);
    });

    test('dedupes dependents and skips ones already in the group', () async {
      final host = _DependentsHost(dependentsOf: const ['child', 'a', 'child']);

      final results = await performServiceOp(
        host,
        const ServiceGroupOp(
          kind: ServiceOpKind.stop,
          services: ['a'],
          stopDependents: true,
        ),
      );

      expect(host.stopCalls, [
        ['child'], // 'a' is a group member and 'child' appears once
        ['a'],
      ]);
      expect(results.map((r) => r.service), ['child', 'a']);
    });

    test('leaves the failure alone when stop_dependents is off', () async {
      final host = _DependentsHost();

      final results = await performServiceOp(
        host,
        const ServiceGroupOp(kind: ServiceOpKind.stop, services: ['a']),
      );

      expect(results.single.failure, ServiceFailure.dependentsRunning);
      expect(host.dependentsCalls, isEmpty);
      expect(host.stopCalls, [
        ['a'],
      ]);
    });
  });
}

/// Host whose service `a` refuses to stop until its dependent is stopped.
class _DependentsHost implements ServiceHost {
  _DependentsHost({this.dependentsOf = const ['child']});

  final List<String> dependentsOf;

  final List<String> dependentsCalls = [];
  final List<List<String>> stopCalls = [];

  bool _childStopped = false;

  @override
  Future<List<ServiceStatus>> query(List<String> names) async => [
    for (final name in names)
      ServiceStatus(
        name,
        name == 'child' && _childStopped
            ? ServiceState.stopped
            : ServiceState.running,
      ),
  ];

  @override
  Future<List<ServiceOpResult>> start(List<String> names) async => [
    for (final name in names) ServiceOpResult.ok(name),
  ];

  @override
  Future<List<ServiceOpResult>> stop(List<String> names) async {
    stopCalls.add(List<String>.from(names));
    return [
      for (final name in names)
        if (name == 'a' && !_childStopped)
          const ServiceOpResult.failed(
            'a',
            ServiceFailure.dependentsRunning,
            'child is running',
          )
        else
          ServiceOpResult.ok(name),
    ];
  }

  @override
  Future<List<String>> dependents(String name) async {
    dependentsCalls.add(name);
    // Stopping the dependent is what unblocks `a`.
    _childStopped = true;
    return dependentsOf;
  }
}

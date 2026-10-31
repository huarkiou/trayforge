import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/foundation/service_status.dart';

void main() {
  group('aggregateState', () {
    test('an empty group is stopped', () {
      expect(aggregateState(const []), ProcState.stopped);
    });

    test('any running member makes the group running', () {
      expect(
        aggregateState(const [
          ServiceStatus('a', ServiceState.running),
          ServiceStatus('b', ServiceState.stopped),
        ]),
        ProcState.running,
      );
    });

    test('a paused member counts as up', () {
      expect(
        aggregateState(const [ServiceStatus('a', ServiceState.paused)]),
        ProcState.running,
      );
    });

    test('a start-pending member makes the group starting', () {
      expect(
        aggregateState(const [
          ServiceStatus('a', ServiceState.stopped),
          ServiceStatus('b', ServiceState.startPending),
        ]),
        ProcState.starting,
      );
    });

    test('a stop-pending member makes the group stopping', () {
      expect(
        aggregateState(const [
          ServiceStatus('a', ServiceState.running),
          ServiceStatus('b', ServiceState.stopPending),
        ]),
        ProcState.stopping,
      );
    });

    test('all stopped members make the group stopped', () {
      expect(
        aggregateState(const [
          ServiceStatus('a', ServiceState.stopped),
          ServiceStatus('b', ServiceState.stopped),
        ]),
        ProcState.stopped,
      );
    });

    test('a missing service is a crashed group (config problem)', () {
      expect(
        aggregateState(const [
          ServiceStatus('a', ServiceState.running),
          ServiceStatus('b', ServiceState.notInstalled),
        ]),
        ProcState.crashed,
      );
    });

    test('failed and unknown members are crashed', () {
      expect(
        aggregateState(const [ServiceStatus('a', ServiceState.failed)]),
        ProcState.crashed,
      );
      expect(
        aggregateState(const [ServiceStatus('a', ServiceState.unknown)]),
        ProcState.crashed,
      );
    });
  });

  group('anyServiceUp', () {
    test('is the toggle rule input', () {
      expect(
        anyServiceUp(const [ServiceStatus('a', ServiceState.stopped)]),
        isFalse,
      );
      expect(
        anyServiceUp(const [ServiceStatus('a', ServiceState.running)]),
        isTrue,
      );
      expect(
        anyServiceUp(const [ServiceStatus('a', ServiceState.paused)]),
        isTrue,
      );
    });
  });

  group('ServiceState', () {
    test('isPending only covers transitions', () {
      expect(ServiceState.startPending.isPending, isTrue);
      expect(ServiceState.stopPending.isPending, isTrue);
      expect(ServiceState.running.isPending, isFalse);
      expect(ServiceState.stopped.isPending, isFalse);
    });

    test('has a display label for every value', () {
      for (final state in ServiceState.values) {
        expect(state.label, isNotEmpty);
      }
    });
  });
}

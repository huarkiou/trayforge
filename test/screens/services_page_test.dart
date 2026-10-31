import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/foundation/service_operator.dart';
import 'package:trayforge/foundation/service_status.dart';
import 'package:trayforge/screens/service_detail_page.dart';
import 'package:trayforge/screens/services_page.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/service_manager.dart';
import 'package:trayforge/viewmodels/services_viewmodel.dart';

import '../helpers/service_fakes.dart';
import '../helpers/test_mocks.dart';

void main() {
  late Directory tmpDir;
  late ConfigStore configStore;
  late FakeServiceHost host;
  late ServiceManager manager;
  late ServicesViewModel viewModel;

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('trayforge_services_page_');
    configStore = ConfigStore(dataDir: tmpDir.path);
    host = FakeServiceHost(
      states: {'FLEXnet': ServiceState.stopped, 'Tomcat': ServiceState.running},
    );
    manager = ServiceManager(
      configStore: configStore,
      host: host,
      operator: ServiceOperator(host: host),
      settleTimeout: const Duration(milliseconds: 100),
      operationPollInterval: const Duration(milliseconds: 5),
    );
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  /// Widget tests check for pending timers at the end of the body, so the
  /// polling timers must be cancelled inside the test, not in tearDown.
  void disposeAll() {
    viewModel.dispose();
    manager.dispose();
  }

  Future<void> pumpPage(WidgetTester tester, AppConfig config) async {
    writeConfig(tmpDir, config);
    await manager.init();
    viewModel = ServicesViewModel(
      configStore: configStore,
      serviceManager: manager,
    );
    await tester.pumpWidget(
      MaterialApp(home: ServicesPage(viewModel: viewModel)),
    );
    await tester.pump();
  }

  final config = AppConfig(
    servicePollMs: 1000,
    services: const [
      ServiceConfig(name: 'Licenses', services: ['FLEXnet', 'Tomcat']),
    ],
  );

  testWidgets('shows the group with its members and their states', (
    tester,
  ) async {
    await pumpPage(tester, config);

    expect(find.text('Licenses'), findsOneWidget);
    expect(find.text('FLEXnet'), findsOneWidget);
    expect(find.text('Tomcat'), findsOneWidget);
    expect(find.text('Running'), findsWidgets);
    expect(find.text('Stopped'), findsWidgets);
    expect(find.text('1/2 running · Running'), findsOneWidget);
    disposeAll();
  });

  testWidgets('the detail page renders service names as selectable text', (
    tester,
  ) async {
    await pumpPage(tester, config);

    await tester.tap(find.text('Licenses'));
    await tester.pumpAndSettle();

    expect(find.byType(ServiceDetailPage), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
    disposeAll();
  });

  testWidgets('toggling the group runs the operation', (tester) async {
    await pumpPage(tester, config);

    // The group has a running member, so the toggle stops everything.
    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(host.stopCalls, isNotEmpty);
    expect(
      host.states.values.every((state) => state == ServiceState.stopped),
      isTrue,
    );
    disposeAll();
  });

  testWidgets('offers Stop when a crashed group still has a running member', (
    tester,
  ) async {
    // FLEXnet runs, Tomcat is missing → the aggregate is crashed, but the
    // toggle would still stop the group: the button must say Stop.
    host.states['FLEXnet'] = ServiceState.running;
    host.states.remove('Tomcat');
    await pumpPage(tester, config);

    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(host.stopCalls, isNotEmpty);
    disposeAll();
  });

  testWidgets('shows the empty state without groups', (tester) async {
    await pumpPage(tester, const AppConfig());

    expect(find.text('No service groups configured'), findsOneWidget);
    expect(find.text('Add Service Group'), findsOneWidget);
    disposeAll();
  });
}

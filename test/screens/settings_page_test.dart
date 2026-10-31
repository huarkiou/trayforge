import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/screens/settings_page.dart';
import 'package:trayforge/services/autostart.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';

import '../helpers/recording_config_store.dart';

/// No config reloads and no registry access are needed for the stepper tests.
class _FakeProcessManager extends Fake implements ProcessManager {
  @override
  Stream<void> get onConfigReloaded => const Stream.empty();
}

class _FakeAutostart extends Fake implements Autostart {
  @override
  bool isEnabled() => false;
}

void main() {
  Future<SettingsViewModel> pumpSettings(
    WidgetTester tester,
    int servicePollMs,
  ) async {
    final store = RecordingConfigStore(AppConfig(servicePollMs: servicePollMs));
    final viewModel = SettingsViewModel(
      configStore: store,
      processManager: _FakeProcessManager(),
      autostart: _FakeAutostart(),
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(viewModel: viewModel)),
    );
    return viewModel;
  }

  testWidgets('the service poll stepper clamps to its maximum', (tester) async {
    // One step short of the 1 h maximum: the step would overshoot it.
    final viewModel = await pumpSettings(tester, 3599500);

    // The service poll field is the last stepper on the page.
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up).last);
    await tester.pump();

    expect(viewModel.servicePollMs, 3600000);
  });

  testWidgets('the service poll stepper clamps to its minimum', (tester) async {
    final viewModel = await pumpSettings(tester, 1500);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down).last);
    await tester.pump();

    expect(viewModel.servicePollMs, 1000);
  });
}

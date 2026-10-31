import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/screens/dashboard_screen.dart';
import 'package:trayforge/screens/settings_page.dart';
import 'package:trayforge/viewmodels/dashboard_viewmodel.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';
import 'package:trayforge/widgets/status_dot.dart';

import '../helpers/localized_app.dart';
import '../helpers/recording_config_store.dart';
import '../helpers/service_fakes.dart';
import '../helpers/settings_fakes.dart';

Future<({SettingsViewModel viewModel, RecordingConfigStore store})>
_pumpSettings(
  WidgetTester tester, {
  Locale? locale,
  AppConfig config = const AppConfig(),
}) async {
  final store = RecordingConfigStore(config);
  final viewModel = SettingsViewModel(
    configStore: store,
    processManager: StubProcessManager(),
    autostart: StubAutostart(),
  );
  addTearDown(viewModel.dispose);
  await tester.pumpWidget(
    localizedApp(
      home: SettingsPage(viewModel: viewModel),
      locale: locale,
    ),
  );
  return (viewModel: viewModel, store: store);
}

Future<void> _pumpDashboard(WidgetTester tester, {Locale? locale}) async {
  final store = RecordingConfigStore(const AppConfig());
  final viewModel = DashboardViewModel(
    configStore: store,
    processManager: StubProcessManager(),
    serviceManager: FakeServiceManager(),
  );
  addTearDown(viewModel.dispose);
  await tester.pumpWidget(
    localizedApp(
      home: DashboardScreen(viewModel: viewModel),
      locale: locale,
    ),
  );
}

DropdownButton<String> _languagePicker(WidgetTester tester) =>
    tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>));

/// The labels of the language picker's entries, in order.
List<String?> _languageOptions(WidgetTester tester) => _languagePicker(
  tester,
).items!.map((item) => (item.child as Text).data).toList(growable: false);

/// Opens the picker and selects the entry labelled [label].
Future<void> _pickLanguage(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButton<String>));
  await tester.pumpAndSettle();
  // `hitTestable` skips the hidden items `DropdownButton` lays out to size
  // itself, leaving the ones in the open menu.
  await tester.tap(find.text(label).hitTestable());
  await tester.pumpAndSettle();
}

void main() {
  group('Dashboard', () {
    testWidgets('renders the welcome screen in English by default', (
      tester,
    ) async {
      await _pumpDashboard(tester);

      expect(find.text('Dashboard'), findsOneWidget);
      expect(
        find.text('No processes or service groups configured'),
        findsOneWidget,
      );
      expect(find.text('Add Process'), findsOneWidget);
    });

    testWidgets('renders the welcome screen in Chinese under zh', (
      tester,
    ) async {
      await _pumpDashboard(tester, locale: const Locale('zh'));

      expect(find.text('仪表盘'), findsOneWidget);
      expect(find.text('尚未配置任何进程或服务组'), findsOneWidget);
      expect(find.text('添加进程'), findsOneWidget);
      expect(find.text('Add Process'), findsNothing);
    });
  });

  group('Settings', () {
    testWidgets('renders in Chinese under zh', (tester) async {
      await _pumpSettings(tester, locale: const Locale('zh'));

      expect(find.text('设置'), findsOneWidget);
      expect(find.text('输出刷新间隔（毫秒）'), findsOneWidget);
      expect(find.text('语言'), findsOneWidget);
      expect(find.text('跟随系统'), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('the picker offers "System default" and both languages', (
      tester,
    ) async {
      await _pumpSettings(tester);

      // Each language is listed in itself, so the picker is readable whatever
      // the current UI language is; "System default" comes from the UI language.
      expect(_languageOptions(tester), ['System default', 'English', '简体中文']);
    });

    testWidgets('picking a language persists it and re-localizes in place', (
      tester,
    ) async {
      final (:viewModel, :store) = await _pumpSettings(tester);

      await _pickLanguage(tester, '简体中文');

      expect(viewModel.language, 'zh');
      expect(store.lastSaved?.language, 'zh');
      expect(_languagePicker(tester).value, 'zh');
      expect(viewModel.localeListenable.value, const Locale('zh'));

      // `main` builds the MaterialApp from the same locale listenable, so this
      // reproduces the in-place switch: the page's own strings follow.
      await tester.pumpWidget(
        localizedApp(
          home: SettingsPage(viewModel: viewModel),
          locale: viewModel.locale,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('"System default" clears the override', (tester) async {
      final (:viewModel, :store) = await _pumpSettings(
        tester,
        locale: const Locale('zh'),
        config: const AppConfig(language: 'zh'),
      );
      expect(_languagePicker(tester).value, 'zh');

      await _pickLanguage(tester, '跟随系统');

      expect(viewModel.language, isNull);
      expect(store.lastSaved?.language, isNull);
      expect(viewModel.localeListenable.value, isNull);
    });
  });

  group('state labels', () {
    testWidgets('a card label follows the language', (tester) async {
      await tester.pumpWidget(
        localizedApp(
          home: const Scaffold(body: StateLabel(state: ProcState.crashed)),
          locale: const Locale('zh'),
        ),
      );

      expect(find.text('已崩溃'), findsOneWidget);
    });
  });
}

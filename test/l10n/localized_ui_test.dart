import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/app_theme.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/screens/dashboard_screen.dart';
import 'package:trayforge/screens/process_detail_screen.dart';
import 'package:trayforge/screens/process_edit_page.dart';
import 'package:trayforge/screens/service_detail_page.dart';
import 'package:trayforge/screens/settings_page.dart';
import 'package:trayforge/viewmodels/dashboard_viewmodel.dart';
import 'package:trayforge/viewmodels/process_viewmodel.dart';
import 'package:trayforge/viewmodels/service_viewmodel.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';
import 'package:trayforge/widgets/process_card.dart';
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

ProcessViewModel _processViewModel(String name) => ProcessViewModel(
  name: name,
  processManager: StubProcessManager(),
  outputHistoryLimit: 20,
);

DropdownButton<String> _languagePicker(WidgetTester tester) =>
    tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>));

/// Opens the picker and selects the entry labelled [label].
Future<void> _pickLanguage(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButton<String>));
  await tester.pumpAndSettle();
  // `hitTestable` skips the hidden items `DropdownButton` lays out to size
  // itself, leaving the visible ones in the open menu.
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
    testWidgets('renders in English under en', (tester) async {
      await _pumpSettings(tester, locale: const Locale('en'));

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('System default'), findsOneWidget);
      expect(find.text('设置'), findsNothing);
    });

    testWidgets('renders in Chinese under zh', (tester) async {
      await _pumpSettings(tester, locale: const Locale('zh'));

      expect(find.text('设置'), findsOneWidget);
      expect(find.text('输出刷新间隔（毫秒）'), findsOneWidget);
      expect(find.text('语言'), findsOneWidget);
      expect(find.text('跟随系统'), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('the open picker lists "System default" and both languages', (
      tester,
    ) async {
      await _pumpSettings(tester);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // Only the entries in the open menu are hit-testable; each language is
      // listed in itself so the picker stays readable in any UI language.
      expect(find.text('System default').hitTestable(), findsOneWidget);
      expect(find.text('English').hitTestable(), findsOneWidget);
      expect(find.text('简体中文').hitTestable(), findsOneWidget);
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

  group('Process card', () {
    testWidgets('renders its state label and empty hint in Chinese', (
      tester,
    ) async {
      final viewModel = _processViewModel('demo');
      addTearDown(viewModel.dispose);

      // The grid tile carries the state label; the list card carries the
      // output placeholder.
      await tester.pumpWidget(
        localizedApp(
          home: Scaffold(
            body: ProcessGridCard(viewModel: viewModel, onTap: () {}),
          ),
          locale: const Locale('zh'),
        ),
      );
      expect(find.text('已停止'), findsOneWidget);
      expect(find.text('Stopped'), findsNothing);

      await tester.pumpWidget(
        localizedApp(
          home: Scaffold(
            body: ProcessCard(viewModel: viewModel, onTap: () {}),
          ),
          locale: const Locale('zh'),
        ),
      );
      expect(find.text('暂无输出'), findsOneWidget);
      expect(find.text('No output yet'), findsNothing);
    });
  });

  group('Process detail', () {
    testWidgets('renders its toolbar and placeholder in Chinese', (
      tester,
    ) async {
      final viewModel = _processViewModel('demo');
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        localizedApp(
          home: ProcessDetailPage(viewModel: viewModel, onEditTap: () {}),
          locale: const Locale('zh'),
        ),
      );

      expect(find.byTooltip('编辑进程'), findsOneWidget);
      expect(find.byTooltip('清空输出'), findsOneWidget);
      expect(find.byTooltip('搜索输出'), findsOneWidget);
      expect(find.text('暂无输出'), findsOneWidget);
    });
  });

  group('Process edit form', () {
    testWidgets('renders the add form in Chinese', (tester) async {
      final store = RecordingConfigStore(const AppConfig());
      final viewModel = SettingsViewModel(
        configStore: store,
        processManager: StubProcessManager(),
        autostart: StubAutostart(),
      );
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        localizedApp(
          home: ProcessEditPage(settingsViewModel: viewModel),
          locale: const Locale('zh'),
        ),
      );

      expect(find.text('添加进程'), findsOneWidget);
      expect(find.text('名称 *'), findsOneWidget);
      expect(find.text('单实例'), findsOneWidget);
      expect(find.byTooltip('浏览…'), findsOneWidget);
    });

    testWidgets('renders the delete dialog in Chinese', (tester) async {
      const config = ProcessConfig(name: 'demo', cmd: 'run.exe');
      final store = RecordingConfigStore(const AppConfig(units: [config]));
      final viewModel = SettingsViewModel(
        configStore: store,
        processManager: StubProcessManager(),
        autostart: StubAutostart(),
      );
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        localizedApp(
          home: ProcessEditPage(
            settingsViewModel: viewModel,
            initial: config,
            editIndex: 0,
          ),
          locale: const Locale('zh'),
        ),
      );

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.text('删除进程？'), findsOneWidget);
      expect(find.textContaining('demo'), findsWidgets);
      expect(find.text('取消'), findsOneWidget);
    });
  });

  group('Service detail', () {
    testWidgets(
      'renders its placeholder and log in the mono stack in Chinese',
      (tester) async {
        final manager = FakeServiceManager();
        final viewModel = ServiceViewModel(
          name: 'demo',
          serviceManager: manager,
          outputHistoryLimit: 20,
        );
        addTearDown(viewModel.dispose);

        await tester.pumpWidget(
          localizedApp(
            home: ServiceDetailPage(viewModel: viewModel),
            locale: const Locale('zh'),
          ),
        );

        expect(find.text('暂无活动'), findsOneWidget);
        expect(find.byTooltip('清空日志'), findsOneWidget);

        manager.emitOutput('demo', 'Spooler: 已停止');
        await tester.pump();

        final log = tester.widget<SelectableText>(find.byType(SelectableText));
        expect(log.style?.fontFamily, monoFontFamily);
        expect(log.style?.fontFamilyFallback, monoFontFallback);
      },
    );
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

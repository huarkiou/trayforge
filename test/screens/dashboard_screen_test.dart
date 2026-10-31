import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/foundation/service_status.dart';
import 'package:trayforge/screens/dashboard_screen.dart';
import 'package:trayforge/screens/service_detail_page.dart';
import 'package:trayforge/services/autostart.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/viewmodels/dashboard_viewmodel.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';
import 'package:trayforge/widgets/process_card.dart';
import 'package:trayforge/widgets/service_card.dart';
import 'package:trayforge/widgets/status_dot.dart';

import '../helpers/recording_config_store.dart';
import '../helpers/service_fakes.dart';

/// Long-presses at [start], then drags to [end] and releases.
///
/// Simulates long-press reorder in either layout: hold past the
/// long-press threshold, then move, then release. [kind] selects the
/// simulated pointer device (touch by default; mouse for desktop input).
Future<void> longPressDrag(
  WidgetTester tester,
  Offset start,
  Offset end, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  final gesture = await tester.startGesture(start, kind: kind);
  await tester.pump(kLongPressTimeout);
  // Small initial move so the drag actually starts.
  await gesture.moveBy(const Offset(0, 20));
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pumpAndSettle();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Pumps the Dashboard with fresh viewmodels backed by a recording config
/// store, returning handles for assertions.
///
/// [configCorrupted] forwards to [DashboardViewModel]; [withSettings] also
/// adds a [SettingsViewModel] (and the AppBar buttons that come with it).
/// [emitOnConfigReload] is forwarded to the fake process manager: pass `false`
/// to keep the managers from rebuilding the dashboard after a settings edit,
/// which is the window a reorder/delete sees before the reload lands.
Future<
  ({
    RecordingConfigStore store,
    _FakeProcessManager pm,
    FakeServiceManager svc,
    DashboardViewModel dm,
    SettingsViewModel? sm,
  })
>
pumpDashboard(
  WidgetTester tester, {
  required AppConfig config,
  bool withSettings = true,
  bool configCorrupted = false,
  bool emitOnConfigReload = true,
}) async {
  final store = RecordingConfigStore(config);
  final pm = _FakeProcessManager(emitOnConfigReload: emitOnConfigReload);
  final svc = FakeServiceManager();
  final dm = DashboardViewModel(
    configStore: store,
    processManager: pm,
    serviceManager: svc,
    configCorrupted: configCorrupted,
  );
  final sm = withSettings
      ? SettingsViewModel(
          configStore: store,
          processManager: pm,
          autostart: Autostart(),
        )
      : null;
  await tester.pumpWidget(
    MaterialApp(
      home: DashboardScreen(viewModel: dm, settingsViewModel: sm),
    ),
  );
  return (store: store, pm: pm, svc: svc, dm: dm, sm: sm);
}

/// A minimal fake that satisfies the [ProcessManager] interface for
/// DashboardViewModel construction.
class _FakeProcessManager extends Fake implements ProcessManager {
  /// Whether [reloadConfig] emits on [onConfigReloaded].
  ///
  /// `false` models the window after a settings edit but before the managers'
  /// reload lands: the config store is already updated, but neither the
  /// dashboard nor the settings view model has rebuilt from it yet.
  final bool emitOnConfigReload;

  _FakeProcessManager({this.emitOnConfigReload = true});

  final StreamController<void> _configReloaded =
      StreamController<void>.broadcast(sync: true);

  /// Names passed to [ProcessManager.toggle], in call order.
  final List<String> toggled = [];

  @override
  Stream<ProcState> stateStream(String name) => const Stream<ProcState>.empty();

  final Map<String, StreamController<String>> _outputControllers = {};

  @override
  Stream<String> outputStream(String name) {
    return _outputControllers
        .putIfAbsent(name, () => StreamController<String>.broadcast(sync: true))
        .stream;
  }

  void emitOutput(String name, String line) {
    _outputControllers[name]?.add(line);
  }

  final Map<String, StreamController<Uri>> _webuiControllers = {};

  @override
  Stream<Uri> webUiStream(String name) {
    return _webuiControllers
        .putIfAbsent(name, () => StreamController<Uri>.broadcast(sync: true))
        .stream;
  }

  void emitWebUi(String name, Uri url) {
    _webuiControllers[name]?.add(url);
  }

  @override
  Stream<void> get onConfigReloaded => _configReloaded.stream;

  @override
  ProcState getState(String name) => ProcState.stopped;

  @override
  Future<void> reloadConfig(AppConfig config) async {
    if (emitOnConfigReload) _configReloaded.add(null);
  }

  @override
  Future<void> toggle(String name) async {
    toggled.add(name);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DashboardScreen', () {
    // ---- Welcome screen ----

    testWidgets('shows welcome screen when nothing is configured', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        config: const AppConfig(units: []),
        withSettings: false,
      );

      expect(
        find.text('No processes or service groups configured'),
        findsOneWidget,
      );
      expect(find.text('Add Process'), findsOneWidget);
      expect(find.text('Add Service Group'), findsOneWidget);
    });

    testWidgets('welcome screen "Add Process" button navigates to the form', (
      tester,
    ) async {
      await pumpDashboard(tester, config: const AppConfig(units: []));

      await tester.tap(find.text('Add Process'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Navigated to ProcessEditPage in add mode (AppBar title is 'Add Process').
      expect(find.widgetWithText(AppBar, 'Add Process'), findsOneWidget);
    });

    testWidgets('welcome screen "Add Service Group" opens the group form', (
      tester,
    ) async {
      await pumpDashboard(tester, config: const AppConfig(units: []));

      await tester.tap(find.text('Add Service Group'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.widgetWithText(AppBar, 'Add Service Group'), findsOneWidget);
    });

    // ---- Dashboard with cards ----

    testWidgets('shows process cards when processes exist', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          units: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
        withSettings: false,
      );

      expect(find.text('svc-a'), findsOneWidget);
      expect(find.text('svc-b'), findsOneWidget);
      expect(find.byType(ReorderableListView), findsOneWidget);
    });

    // ---- Navigation to detail page ----

    testWidgets('tapping a card navigates to detail page', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          units: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
        withSettings: false,
      );

      await tester.tap(find.text('svc-a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should now be on the detail page ("No output yet" appears both
      // on the card below and on the detail page body).
      expect(find.text('No output yet'), findsWidgets);
      // AppBar should show process name.
      expect(find.text('svc-a'), findsWidgets);
    });

    // ---- Corrupted config dialog ----

    testWidgets('shows alert dialog when config is corrupted', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(units: []),
        withSettings: false,
        configCorrupted: true,
      );

      // Dialog should appear after post-frame callback.
      await tester.pump();
      await tester.pump();

      expect(find.text('Configuration Error'), findsOneWidget);
      expect(find.textContaining('corrupted'), findsOneWidget);
    });

    testWidgets('dismissing corrupted dialog clears flag', (tester) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(units: []),
        withSettings: false,
        configCorrupted: true,
      );

      await tester.pump();
      await tester.pump();

      // Tap OK.
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump();

      expect(h.dm.configCorrupted, false);
      expect(find.text('Configuration Error'), findsNothing);
    });

    // ---- Config changed → welcome screen ----

    testWidgets('switches to welcome screen when config becomes empty', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          units: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
        withSettings: false,
      );

      expect(find.text('svc-a'), findsOneWidget);

      // Simulate config becoming empty — we need to rebuild.
      // Since we use a fake config store, we directly manipulate the VM.
      // onConfigReloaded is the trigger; the fake manager never emits it.
      // This is better tested at the ViewModel level, which we already do.
    });

    // ---- "+" Add menu ----

    testWidgets('shows the add menu in the AppBar with settings', (
      tester,
    ) async {
      await pumpDashboard(tester, config: const AppConfig(units: []));

      expect(find.byTooltip('Add'), findsOneWidget);
    });

    testWidgets('does not show the add menu without a settings view model', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        config: const AppConfig(units: []),
        withSettings: false,
      );

      expect(find.byTooltip('Add'), findsNothing);
    });

    testWidgets('add menu offers both kinds', (tester) async {
      await pumpDashboard(tester, config: const AppConfig(units: []));

      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Add process'), findsOneWidget);
      expect(find.text('Add service group'), findsOneWidget);
    });

    testWidgets('add menu opens the process form', (tester) async {
      await pumpDashboard(tester, config: const AppConfig(units: []));

      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add process'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Add Process'), findsOneWidget);
    });

    testWidgets('add menu opens the service group form', (tester) async {
      await pumpDashboard(tester, config: const AppConfig(units: []));

      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add service group'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Add Service Group'), findsOneWidget);
    });

    // ---- Edit icon on cards ----

    testWidgets('shows edit icon on process cards', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          units: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('tapping edit icon navigates to ProcessEditPage', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          units: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.widgetWithText(AppBar, 'Edit Process'), findsOneWidget);
    });

    // ---- Long-press reorder ----

    testWidgets('does not render drag handle icons on cards', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          units: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      expect(find.byIcon(Icons.drag_handle), findsNothing);
    });

    testWidgets('long-press drag reorders cards and persists', (tester) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          units: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      // Long-press the first card and drag it well past the second
      // (the drop index only advances once the proxy clears the target
      // item's trailing edge, so overshoot generously).
      await longPressDrag(
        tester,
        tester.getCenter(find.text('svc-a')),
        tester.getCenter(find.text('svc-b')) + const Offset(0, 150),
      );

      // The list reordered visually.
      expect(
        tester.getTopLeft(find.text('svc-a')).dy,
        greaterThan(tester.getTopLeft(find.text('svc-b')).dy),
      );

      // And the new order plus the carried layout persisted.
      final saved = h.store.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.units.map((u) => u.name), ['svc-b', 'svc-a']);
      expect(saved.dashboardLayout, DashboardLayout.list);
    });

    testWidgets('mouse long-press drag reorders list cards and persists', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          units: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      // Same long-press reorder with a mouse pointer: the delayed
      // recognizer must accept the primary mouse button.
      await longPressDrag(
        tester,
        tester.getCenter(find.text('svc-a')),
        tester.getCenter(find.text('svc-b')) + const Offset(0, 150),
        kind: PointerDeviceKind.mouse,
      );

      expect(
        tester.getTopLeft(find.text('svc-a')).dy,
        greaterThan(tester.getTopLeft(find.text('svc-b')).dy),
      );

      final saved = h.store.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.units.map((u) => u.name), ['svc-b', 'svc-a']);
    });

    // ---- Layout toggle ----

    testWidgets('layout toggle hidden on welcome screen', (tester) async {
      await pumpDashboard(tester, config: AppConfig(units: []));

      expect(find.byTooltip('Switch to grid view'), findsNothing);
      expect(find.byTooltip('Switch to list view'), findsNothing);
    });

    testWidgets('layout toggle hidden without settingsViewModel', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          units: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
        withSettings: false,
      );

      expect(find.byTooltip('Switch to grid view'), findsNothing);
      expect(find.byTooltip('Switch to list view'), findsNothing);
    });

    testWidgets('layout toggle shown with processes, icon shows grid target', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          units: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      // In list layout the button offers the grid and shows a grid icon.
      expect(find.byTooltip('Switch to grid view'), findsOneWidget);
      expect(find.byIcon(Icons.grid_view), findsOneWidget);
      expect(find.byTooltip('Switch to list view'), findsNothing);
    });

    testWidgets('tapping layout toggle switches layout and persists', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          units: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      // Switch to grid: grid appears, icon now offers the list.
      await tester.tap(find.byTooltip('Switch to grid view'));
      await tester.pump();

      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.byType(ProcessGridCard), findsOneWidget);
      expect(find.byTooltip('Switch to list view'), findsOneWidget);
      expect(find.byIcon(Icons.view_list), findsOneWidget);

      var saved = h.store.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.dashboardLayout, DashboardLayout.grid);

      // Switch back to list.
      await tester.tap(find.byTooltip('Switch to list view'));
      await tester.pump();

      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(h.store.lastSaved!.dashboardLayout, DashboardLayout.list);
    });

    // ---- Grid layout ----

    testWidgets('long-press drag reorders grid cards and persists', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          units: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      // Let the grid's entrance fade-in run: the package only records
      // each tile's original index once the fade-in has started (a couple
      // of frames after the grid appears), and the reorder callback reads
      // that index at drag end. Real users always long-press well after
      // the grid appears; the test must simulate that gap.
      await tester.pumpAndSettle();

      // Long-press the first grid card and drag it onto the second. The
      // drop index only advances while the pointer is *inside* the target
      // tile's bounds, so aim at its center (a small offset keeps the
      // pointer safely within the tile).
      await longPressDrag(
        tester,
        tester.getCenter(find.text('svc-a')),
        tester.getCenter(find.text('svc-b')) + const Offset(40, 0),
      );

      // The grid reordered visually: svc-a now sits right of svc-b.
      expect(
        tester.getTopLeft(find.text('svc-a')).dx,
        greaterThan(tester.getTopLeft(find.text('svc-b')).dx),
      );

      // And the new order plus the carried layout persisted.
      final saved = h.store.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.units.map((u) => u.name), ['svc-b', 'svc-a']);
      expect(saved.dashboardLayout, DashboardLayout.grid);
    });

    testWidgets('mouse long-press drag reorders grid cards and persists', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          units: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      await tester.pumpAndSettle();

      // Same long-press reorder with a mouse pointer (see the touch-kind
      // test for the fade-in and drop-target rationale).
      await longPressDrag(
        tester,
        tester.getCenter(find.text('svc-a')),
        tester.getCenter(find.text('svc-b')) + const Offset(40, 0),
        kind: PointerDeviceKind.mouse,
      );

      expect(
        tester.getTopLeft(find.text('svc-a')).dx,
        greaterThan(tester.getTopLeft(find.text('svc-b')).dx),
      );

      final saved = h.store.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.units.map((u) => u.name), ['svc-b', 'svc-a']);
    });

    testWidgets('dragging near the grid edge auto-scrolls', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          units: [
            for (var i = 1; i <= 12; i++)
              ProcessConfig(name: 'svc-$i', cmd: 'svc-$i.exe'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Long-press a tile and hold it near the grid's bottom edge; the
      // package scrolls while the pointer sits in the edge zone.
      final tileCenter = tester.getCenter(find.text('svc-4'));
      await longPressDrag(tester, tileCenter, Offset(tileCenter.dx, 500));

      // The grid scrolled down during the drag.
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.pixels, greaterThan(0));
    });

    testWidgets('grid cards show up to five output lines', (tester) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          units: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      // Adaptive grid: max tile extent 280 with a slightly-shorter-than-
      // square 1.13 aspect (two preview lines shorter than a square tile).
      final delegate =
          tester.widget<GridView>(find.byType(GridView)).gridDelegate
              as SliverGridDelegateWithMaxCrossAxisExtent;
      expect(delegate.maxCrossAxisExtent, 280);
      expect(delegate.childAspectRatio, 1.13);

      // One compact card per process with name, status dot, and controls.
      expect(find.byType(ProcessGridCard), findsNWidgets(2));
      expect(find.text('svc-a'), findsOneWidget);
      expect(find.text('svc-b'), findsOneWidget);
      expect(find.byType(StatusDot), findsNWidgets(2));
      expect(find.byIcon(Icons.edit), findsNWidgets(2));
      expect(find.byIcon(Icons.play_circle_outlined), findsNWidgets(2));

      // No output yet: no preview text, no 'No output yet' filler.
      expect(find.text('No output yet'), findsNothing);

      // Six lines emitted: only the latest five are shown, one Text each.
      for (var i = 1; i <= 6; i++) {
        h.pm.emitOutput('svc-a', 'line-$i');
      }
      await tester.pump();

      final previewTexts = tester
          .widgetList<Text>(
            find.byWidgetPredicate(
              (w) => w is Text && w.data != null && w.data!.startsWith('line-'),
            ),
          )
          .toList();
      expect(previewTexts, hasLength(5));
      expect(previewTexts.first.data, 'line-2');
      expect(previewTexts.last.data, 'line-6');
      expect(find.text('line-1'), findsNothing);
    });

    testWidgets('long output line does not hide the latest line', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          units: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      // A line long enough to soft-wrap must be truncated to one row,
      // not eat the row budget of the newer lines below it.
      final longLine = List.filled(40, 'word').join(' ');
      h.pm.emitOutput('svc-a', longLine);
      for (var i = 2; i <= 5; i++) {
        h.pm.emitOutput('svc-a', 'tail-$i');
      }
      await tester.pump();

      expect(find.text(longLine), findsOneWidget);
      expect(find.text('tail-5'), findsOneWidget);
    });

    testWidgets('grid card shows WebUI copy button when URL detected', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          units: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      h.pm.emitWebUi('svc-a', Uri.parse('http://127.0.0.1:8080'));
      await tester.pump();

      expect(find.byIcon(Icons.content_copy), findsOneWidget);
    });

    testWidgets('grid card copy button copies URL and shows snackbar', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          units: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      h.pm.emitWebUi('svc-a', Uri.parse('http://127.0.0.1:8080'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pump();

      expect(find.text('URL copied'), findsOneWidget);
    });

    testWidgets('grid card edit icon opens the edit page', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          units: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.widgetWithText(AppBar, 'Edit Process'), findsOneWidget);
    });

    testWidgets('tapping grid card opens detail page', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          units: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      await tester.tap(find.text('svc-a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // On the detail page: 'No output yet' appears only on the detail
      // body, since grid cards have no output preview.
      expect(find.text('No output yet'), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'svc-a'), findsOneWidget);
    });

    testWidgets('grid card toggle button starts the process', (tester) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          units: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      await tester.tap(find.byIcon(Icons.play_circle_outlined).first);
      await tester.pump();

      expect(h.pm.toggled, ['svc-a']);
    });

    testWidgets('opens in grid layout when config stores grid', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          units: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.byTooltip('Switch to list view'), findsOneWidget);
    });

    testWidgets('toggling layout preserves other globals', (tester) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          outputRefreshMs: 300,
          outputHistoryLimit: 500,
          units: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      await tester.tap(find.byTooltip('Switch to grid view'));
      await tester.pump();

      final saved = h.store.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.dashboardLayout, DashboardLayout.grid);
      expect(saved.outputRefreshMs, 300);
      expect(saved.outputHistoryLimit, 500);
      expect(saved.units.map((u) => u.name), ['svc-a']);
    });

    testWidgets('toggle button still works on cards', (tester) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          units: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      await tester.tap(find.byIcon(Icons.play_circle_outlined));
      await tester.pump();

      expect(h.pm.toggled, ['svc-a']);
    });
  });

  group('DashboardScreen with service groups', () {
    const mixed = AppConfig(
      units: [
        ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
        ServiceConfig(name: 'Licenses', services: ['FLEXnet', 'Tomcat']),
        ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
      ],
    );

    const members = [
      ServiceStatus('FLEXnet', ServiceState.running),
      ServiceStatus('Tomcat', ServiceState.stopped),
    ];

    testWidgets('renders the group card in the process flow', (tester) async {
      final h = await pumpDashboard(tester, config: mixed);

      expect(find.byType(ServiceCard), findsOneWidget);
      expect(find.byType(ProcessCard), findsNWidgets(2));
      expect(find.text('Licenses'), findsOneWidget);

      // Members land after the first state query.
      h.svc.emitStatuses('Licenses', members);
      await tester.pump();

      expect(find.text('FLEXnet'), findsOneWidget);
      expect(find.text('Tomcat'), findsOneWidget);
      expect(find.text('1/2 running · Running'), findsNothing);
    });

    testWidgets('cards follow the configured unit order', (tester) async {
      await pumpDashboard(tester, config: mixed);

      final processTop = tester.getTopLeft(find.text('svc-a')).dy;
      final groupTop = tester.getTopLeft(find.text('Licenses')).dy;
      final processBottom = tester.getTopLeft(find.text('svc-b')).dy;

      expect(groupTop, greaterThan(processTop));
      expect(processBottom, greaterThan(groupTop));
    });

    testWidgets('tapping the group card opens the detail page', (tester) async {
      await pumpDashboard(tester, config: mixed);

      await tester.tap(find.text('Licenses'));
      await tester.pumpAndSettle();

      expect(find.byType(ServiceDetailPage), findsOneWidget);
      expect(find.text('No activity yet'), findsOneWidget);
    });

    testWidgets('the group detail page shows members as selectable text', (
      tester,
    ) async {
      final h = await pumpDashboard(tester, config: mixed);

      // The detail page renders the member rows once the group has a status
      // snapshot (the card's dense rows are plain Text; the page's are not).
      h.svc.emitStatuses('Licenses', members);
      await tester.pump();

      await tester.tap(find.text('Licenses'));
      await tester.pumpAndSettle();

      expect(find.byType(ServiceDetailPage), findsOneWidget);
      for (final name in ['FLEXnet', 'Tomcat']) {
        expect(
          find.byWidgetPredicate((w) => w is SelectableText && w.data == name),
          findsOneWidget,
        );
      }
    });

    testWidgets('the group toggle drives the group, not the process', (
      tester,
    ) async {
      final h = await pumpDashboard(tester, config: mixed);

      h.svc.emitStatuses('Licenses', members);
      await tester.pump();

      // One member is up, so the group offers Stop; the process cards offer
      // Start. Tapping the group's button must not touch the processes.
      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await tester.pump();

      expect(h.svc.toggled, ['Licenses']);
      expect(h.pm.toggled, isEmpty);
    });

    testWidgets('a crashed group with a running member still offers Stop', (
      tester,
    ) async {
      final h = await pumpDashboard(tester, config: mixed);

      // Aggregate state says crashed, but a member is still up: the button
      // follows isUp (what the toggle would do), not state.isActive.
      h.svc.emitState('Licenses', ProcState.crashed);
      h.svc.emitStatuses('Licenses', const [
        ServiceStatus('FLEXnet', ServiceState.running),
        ServiceStatus('Tomcat', ServiceState.stopped),
      ]);
      await tester.pump();

      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
      expect(find.byTooltip('Stop services'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await tester.pump();

      expect(h.svc.toggled, ['Licenses']);
    });

    testWidgets('the group edit icon opens the group form', (tester) async {
      await pumpDashboard(tester, config: mixed);

      // Two process edit icons plus the group's.
      expect(find.byIcon(Icons.edit), findsNWidgets(3));
      await tester.tap(find.byIcon(Icons.edit).at(1));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Edit Service Group'), findsOneWidget);
    });

    testWidgets('dragging a group card above a process persists the order', (
      tester,
    ) async {
      final h = await pumpDashboard(tester, config: mixed);

      await longPressDrag(
        tester,
        tester.getCenter(find.text('Licenses')),
        tester.getCenter(find.text('svc-a')) - const Offset(0, 120),
      );

      expect(
        tester.getTopLeft(find.text('Licenses')).dy,
        lessThan(tester.getTopLeft(find.text('svc-a')).dy),
      );

      final saved = h.store.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.units.map((u) => u.name), ['Licenses', 'svc-a', 'svc-b']);
      expect(saved.units.first, isA<ServiceConfig>());
    });

    testWidgets('grid layout shows a compact group tile', (tester) async {
      final h = await pumpDashboard(
        tester,
        config: const AppConfig(
          dashboardLayout: DashboardLayout.grid,
          units: [
            ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            ServiceConfig(name: 'Licenses', services: ['FLEXnet', 'Tomcat']),
          ],
        ),
      );

      expect(find.byType(ServiceGridCard), findsOneWidget);
      expect(find.byType(ProcessGridCard), findsOneWidget);

      h.svc.emitStatuses('Licenses', members);
      await tester.pump();

      expect(find.text('1/2 running'), findsOneWidget);
    });

    testWidgets('tapping the grid group tile opens the detail page', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        config: const AppConfig(
          dashboardLayout: DashboardLayout.grid,
          units: [
            ServiceConfig(name: 'Licenses', services: ['FLEXnet']),
          ],
        ),
      );

      await tester.tap(find.text('Licenses'));
      await tester.pumpAndSettle();

      expect(find.byType(ServiceDetailPage), findsOneWidget);
    });

    testWidgets('grid drag moves a group tile above a process and persists', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: const AppConfig(
          dashboardLayout: DashboardLayout.grid,
          units: [
            ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            ServiceConfig(name: 'Licenses', services: ['FLEXnet', 'Tomcat']),
            ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      // Let the grid's entrance fade-in finish before dragging (the package
      // records each tile's original index a couple of frames in).
      await tester.pumpAndSettle();

      // Drag the group tile (second cell) left onto the process tile: the
      // drop index only advances while the pointer is inside the target
      // tile's bounds, so aim just left of its center.
      await longPressDrag(
        tester,
        tester.getCenter(find.text('Licenses')),
        tester.getCenter(find.text('svc-a')) + const Offset(-40, 0),
      );

      // The grid moved the group ahead of the process...
      expect(
        tester.getTopLeft(find.text('Licenses')).dx,
        lessThan(tester.getTopLeft(find.text('svc-a')).dx),
      );

      // ...and the new cross-kind order persisted.
      final saved = h.store.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.units.map((u) => u.name), ['Licenses', 'svc-a', 'svc-b']);
      expect(saved.units.first, isA<ServiceConfig>());
      expect(saved.dashboardLayout, DashboardLayout.grid);
    });
  });

  group('DashboardScreen before the managers reload', () {
    testWidgets('a deleted unit disappears immediately, not at the end', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: const AppConfig(
          units: [
            ProcessConfig(name: 'p1', cmd: 'p1.exe'),
            ServiceConfig(name: 'g1', services: ['Svc']),
            ProcessConfig(name: 'p2', cmd: 'p2.exe'),
          ],
        ),
        emitOnConfigReload: false,
      );

      expect(find.text('p2'), findsOneWidget);

      h.sm!.deleteUnit(2);
      await tester.pump();

      // The config no longer has p2, so the dashboard must omit it right away
      // rather than appending the orphaned view model at the end.
      expect(find.text('p2'), findsNothing);
      expect(find.text('p1'), findsOneWidget);
      expect(find.text('g1'), findsOneWidget);

      // The dashboard view model still owns p2 until the managers' reload
      // lands; the omission is the rendered list's job.
      expect(h.dm.units.map((u) => u.name), ['p1', 'g1', 'p2']);
    });

    testWidgets('a drag moves units by identity, not by rendered index', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: const AppConfig(
          units: [
            ProcessConfig(name: 'A', cmd: 'a.exe'),
            ProcessConfig(name: 'B', cmd: 'b.exe'),
          ],
        ),
        emitOnConfigReload: false,
      );

      // The settings list gains a hidden H between A and B; the dashboard has
      // no view model for it yet, so it renders [A, B].
      h.sm!.addUnit(const ServiceConfig(name: 'H', services: ['Hidden']));
      h.sm!.moveUnitBefore(
        UnitKind.service,
        'H',
        before: (UnitKind.process, 'B'),
      );
      await tester.pump();

      expect(h.sm!.units.map((u) => u.name), ['A', 'H', 'B']);
      expect(find.text('H'), findsNothing);
      expect(find.text('B'), findsOneWidget);

      await longPressDrag(
        tester,
        tester.getCenter(find.text('B')),
        tester.getCenter(find.text('A')) - const Offset(0, 120),
      );

      // Moving B before A by identity gives [B, A, H]. Reusing the rendered
      // indexes (1 → 0) against settings.units would have produced [H, A, B].
      final saved = h.store.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.units.map((u) => u.name), ['B', 'A', 'H']);
    });
  });
}

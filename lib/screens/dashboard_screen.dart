import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/screens/process_detail_screen.dart';
import 'package:trayforge/screens/process_edit_page.dart';
import 'package:trayforge/screens/service_detail_page.dart';
import 'package:trayforge/screens/service_edit_page.dart';
import 'package:trayforge/screens/settings_page.dart';
import 'package:trayforge/viewmodels/dashboard_viewmodel.dart';
import 'package:trayforge/viewmodels/process_viewmodel.dart';
import 'package:trayforge/viewmodels/service_viewmodel.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';
import 'package:trayforge/widgets/process_card.dart';
import 'package:trayforge/widgets/service_card.dart';

/// What the AppBar "+" menu can add.
enum _AddKind { process, serviceGroup }

/// Dashboard screen: one card flow of processes and service groups.
///
/// When nothing is configured, displays a welcome screen with both add
/// actions. Otherwise shows the configured layout: a scrollable list of cards
/// or an adaptive grid of compact tiles, switchable via an AppBar toggle. Both
/// kinds share one ordered list (`AppConfig.units`), so a long-press drag moves
/// a service group between process cards and back. On startup, if a corrupted
/// config was detected, shows an alert dialog before rendering.
class DashboardScreen extends StatefulWidget {
  final DashboardViewModel viewModel;
  final SettingsViewModel? settingsViewModel;

  const DashboardScreen({
    super.key,
    required this.viewModel,
    this.settingsViewModel,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// Shared by the reorderable grid builder and the [GridView] itself; the
  /// package requires one controller for drag-scroll calculations.
  final _gridScrollController = ScrollController();

  /// On the grid itself; the package uses it to locate the scrollable for
  /// edge auto-scroll while dragging.
  final _gridViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.viewModel.configCorrupted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showCorruptedDialog();
      });
    }
  }

  void _showCorruptedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configuration Error'),
        content: const Text(
          'The configuration file is corrupted and has been backed up. '
          'Please check your config file.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.viewModel.clearCorruptedFlag();
              Navigator.of(ctx).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsViewModel = widget.settingsViewModel;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.viewModel, ?settingsViewModel]),
      builder: (context, _) {
        final isEmpty = widget.viewModel.isEmpty;
        final isListLayout =
            settingsViewModel?.dashboardLayout == DashboardLayout.list;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Dashboard'),
            actions: [
              if (settingsViewModel != null && !isEmpty)
                IconButton(
                  icon: Icon(isListLayout ? Icons.grid_view : Icons.view_list),
                  tooltip: isListLayout
                      ? 'Switch to grid view'
                      : 'Switch to list view',
                  onPressed: () => settingsViewModel.setDashboardLayout(
                    isListLayout ? DashboardLayout.grid : DashboardLayout.list,
                  ),
                ),
              if (settingsViewModel != null)
                PopupMenuButton<_AddKind>(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add',
                  onSelected: (kind) => switch (kind) {
                    _AddKind.process => _addProcess(),
                    _AddKind.serviceGroup => _addServiceGroup(),
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _AddKind.process,
                      child: Text('Add process'),
                    ),
                    PopupMenuItem(
                      value: _AddKind.serviceGroup,
                      child: Text('Add service group'),
                    ),
                  ],
                ),
              if (settingsViewModel != null)
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SettingsPage(viewModel: settingsViewModel),
                      ),
                    );
                  },
                ),
            ],
          ),
          body: isEmpty
              ? _buildWelcomeBody(context)
              : _buildDashboardBody(context),
        );
      },
    );
  }

  Widget _buildWelcomeBody(BuildContext context) {
    final canEdit = widget.settingsViewModel != null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'No processes or service groups configured',
            style: TextStyle(fontSize: 18, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: canEdit ? _addProcess : null,
                icon: const Icon(Icons.add),
                label: const Text('Add Process'),
              ),
              OutlinedButton.icon(
                onPressed: canEdit ? _addServiceGroup : null,
                icon: const Icon(Icons.dns_outlined),
                label: const Text('Add Service Group'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardBody(BuildContext context) {
    final layout =
        widget.settingsViewModel?.dashboardLayout ?? DashboardLayout.list;
    if (layout == DashboardLayout.grid) {
      return _buildGridBody(context);
    }
    return _buildListBody(context);
  }

  /// The cards to render, in the settings view model's current order.
  ///
  /// A reorder is persisted without reloading the managers, so the dashboard
  /// view model is not rebuilt by a drag; [DashboardViewModel.orderedBy]
  /// applies the newer settings order immediately, without a second ordering
  /// list in the screen.
  List<DashboardUnit> get _units => widget.settingsViewModel == null
      ? widget.viewModel.units
      : widget.viewModel.orderedBy(widget.settingsViewModel!.units);

  Widget _buildListBody(BuildContext context) {
    final units = _units;
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: units.length,
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) {
        widget.settingsViewModel?.reorderItem(oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final unit = units[index];
        // Long-press anywhere on the card to start a reorder drag;
        // quick taps pass through to the card's own handlers.
        return ReorderableDelayedDragStartListener(
          key: ValueKey(unit.id),
          index: index,
          child: switch (unit) {
            ProcessUnit(:final viewModel) => ProcessCard(
              viewModel: viewModel,
              onEditTap: () => _editProcess(viewModel.name),
              onTap: () => _openProcessDetail(context, viewModel),
            ),
            ServiceUnit(:final viewModel) => ServiceCard(
              viewModel: viewModel,
              onEditTap: () => _editServiceGroup(viewModel.name),
              onTap: () => _openServiceDetail(context, viewModel),
            ),
          },
        );
      },
    );
  }

  /// Adaptive grid of compact square cards; columns adapt to window width.
  ///
  /// Wrapped in [ReorderableBuilder] for long-press drag reordering. The
  /// package's `onReorderPositions` delivers final positions (the same
  /// pre-adjusted index contract as `ReorderableListView.onReorderItem`),
  /// so the entities pass through to the settings reorder path unchanged.
  Widget _buildGridBody(BuildContext context) {
    final units = _units;
    return ReorderableBuilder.builder(
      scrollController: _gridScrollController,
      itemCount: units.length,
      onReorderPositions: (entities) {
        for (final entity in entities) {
          widget.settingsViewModel?.reorderItem(
            entity.oldIndex,
            entity.newIndex,
          );
        }
      },
      childBuilder: (itemBuilder) => GridView.builder(
        key: _gridViewKey,
        controller: _gridScrollController,
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 280,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          // Slightly shorter than square (1.0): at the default 800px-wide
          // window a tile is 253px wide and 224px tall — two preview lines
          // shorter than a square tile, with room left for a WebUI URL.
          childAspectRatio: 1.13,
        ),
        itemCount: units.length,
        itemBuilder: (context, index) {
          final unit = units[index];
          return itemBuilder(switch (unit) {
            ProcessUnit(:final viewModel) => ProcessGridCard(
              key: ValueKey(unit.id),
              viewModel: viewModel,
              onEditTap: () => _editProcess(viewModel.name),
              onTap: () => _openProcessDetail(context, viewModel),
            ),
            ServiceUnit(:final viewModel) => ServiceGridCard(
              key: ValueKey(unit.id),
              viewModel: viewModel,
              onEditTap: () => _editServiceGroup(viewModel.name),
              onTap: () => _openServiceDetail(context, viewModel),
            ),
          }, index);
        },
      ),
    );
  }

  @override
  void dispose() {
    _gridScrollController.dispose();
    super.dispose();
  }

  void _openProcessDetail(BuildContext context, ProcessViewModel vm) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessDetailPage(
          viewModel: vm,
          onEditTap: () => _editProcess(vm.name),
        ),
      ),
    );
  }

  void _openServiceDetail(BuildContext context, ServiceViewModel vm) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceDetailPage(
          viewModel: vm,
          onEditTap: () => _editServiceGroup(vm.name),
        ),
      ),
    );
  }

  // ---- Add / edit navigation ----

  void _addProcess() => _pushProcessForm(context, null, null);

  void _editProcess(String name) {
    final settings = widget.settingsViewModel;
    if (settings == null) return;
    final index = settings.units.indexWhere(
      (u) => u is ProcessConfig && u.name == name,
    );
    if (index == -1) return;
    _pushProcessForm(context, settings.units[index] as ProcessConfig, index);
  }

  void _pushProcessForm(
    BuildContext context,
    ProcessConfig? initial,
    int? editIndex,
  ) {
    final settings = widget.settingsViewModel;
    if (settings == null) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessEditPage(
          settingsViewModel: settings,
          initial: initial,
          editIndex: editIndex,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  void _addServiceGroup() => _pushServiceForm(context, null, null);

  void _editServiceGroup(String name) {
    final settings = widget.settingsViewModel;
    if (settings == null) return;
    final index = settings.units.indexWhere(
      (u) => u is ServiceConfig && u.name == name,
    );
    if (index == -1) return;
    _pushServiceForm(context, settings.units[index] as ServiceConfig, index);
  }

  void _pushServiceForm(
    BuildContext context,
    ServiceConfig? initial,
    int? editIndex,
  ) {
    final settings = widget.settingsViewModel;
    if (settings == null) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceEditPage(
          settingsViewModel: settings,
          initial: initial,
          editIndex: editIndex,
        ),
      ),
      (route) => route.isFirst,
    );
  }
}

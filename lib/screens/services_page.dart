import 'package:flutter/material.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/screens/service_detail_page.dart';
import 'package:trayforge/screens/service_edit_page.dart';
import 'package:trayforge/viewmodels/service_viewmodel.dart';
import 'package:trayforge/viewmodels/services_viewmodel.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';
import 'package:trayforge/widgets/service_card.dart';

/// Page listing the configured service groups.
///
/// Services live on their own page rather than in the process dashboard: they
/// are a different kind of thing (system-owned, no pid, no stdout) and mixing
/// both kinds in one reorderable list would fork the ordering and reorder
/// semantics (see ADR 005).
class ServicesPage extends StatelessWidget {
  final ServicesViewModel viewModel;
  final SettingsViewModel? settingsViewModel;

  const ServicesPage({
    super.key,
    required this.viewModel,
    this.settingsViewModel,
  });

  @override
  Widget build(BuildContext context) {
    final settings = settingsViewModel;
    return ListenableBuilder(
      listenable: Listenable.merge([viewModel, ?settings]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Services'),
            actions: [
              if (settings != null)
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add service group',
                  onPressed: () => _openEdit(context, null),
                ),
            ],
          ),
          body: viewModel.isEmpty
              ? _buildWelcomeBody(context)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: viewModel.serviceViewModels.length,
                  itemBuilder: (context, index) {
                    final vm = viewModel.serviceViewModels[index];
                    return ServiceCard(
                      key: ValueKey(vm.name),
                      viewModel: vm,
                      onEditTap: () => _openEdit(context, vm.name),
                      onTap: () => _openDetail(context, vm),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _buildWelcomeBody(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'No service groups configured',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'A group lists Windows services (or systemd units) that are '
            'started and stopped together.',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _openEdit(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Add Service Group'),
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, ServiceViewModel vm) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceDetailPage(
          viewModel: vm,
          onEditTap: () => _openEdit(context, vm.name),
        ),
      ),
    );
  }

  void _openEdit(BuildContext context, String? name) {
    final settings = settingsViewModel;
    if (settings == null) return;

    ServiceConfig? initial;
    int? editIndex;
    if (name != null) {
      final index = settings.services.indexWhere((s) => s.name == name);
      if (index == -1) return;
      initial = settings.services[index];
      editIndex = index;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceEditPage(
          settingsViewModel: settings,
          initial: initial,
          editIndex: editIndex,
        ),
      ),
    );
  }
}

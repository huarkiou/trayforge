import 'package:flutter/material.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';

/// Add/edit form for one service group.
class ServiceEditPage extends StatefulWidget {
  final SettingsViewModel settingsViewModel;
  final ServiceConfig? initial;
  final int? editIndex;

  const ServiceEditPage({
    super.key,
    required this.settingsViewModel,
    this.initial,
    this.editIndex,
  });

  bool get isEditing => editIndex != null;

  @override
  State<ServiceEditPage> createState() => _ServiceEditPageState();
}

class _ServiceEditPageState extends State<ServiceEditPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _servicesController;
  bool _stopDependents = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _servicesController = TextEditingController(
      text: (initial?.services ?? const <String>[]).join('\n'),
    );
    _stopDependents = initial?.stopDependents ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _servicesController.dispose();
    super.dispose();
  }

  List<String> get _serviceNames => _servicesController.text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  ServiceConfig _buildConfig() => ServiceConfig(
    name: _nameController.text.trim(),
    services: _serviceNames,
    stopDependents: _stopDependents,
  );

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final config = _buildConfig();
    final error = widget.settingsViewModel.validateServiceConfig(config);
    if (error != null) {
      // Surface the rejection instead of letting ConfigStore throw.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (widget.isEditing) {
      widget.settingsViewModel.editService(widget.editIndex!, config);
    } else {
      widget.settingsViewModel.addService(config);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final index = widget.editIndex;
    if (index == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete service group?'),
        content: Text(
          'Remove "${widget.initial?.name}" from TrayForge?\n\n'
          'The services themselves keep running — TrayForge only stops '
          'managing them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    widget.settingsViewModel.deleteUnit(index);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing ? 'Edit Service Group' : 'Add Service Group',
        ),
        actions: [
          if (widget.isEditing)
            TextButton(onPressed: _confirmDelete, child: const Text('Delete')),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name *',
                helperText: 'Must not contain / or \\',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final name = value?.trim() ?? '';
                if (name.isEmpty) return 'Name is required';
                if (name.contains('/') || name.contains('\\')) {
                  return 'Name must not contain / or \\';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _servicesController,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: 'Services *',
                helperText:
                    'One Windows service name (or systemd unit) per line. '
                    'They are started and stopped together.',
                hintText: 'Spooler\nMyService',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (_) => _serviceNames.isEmpty
                  ? 'At least one service is required'
                  : null,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _stopDependents,
              title: const Text('Stop dependent services too'),
              subtitle: const Text(
                'When a stop fails because other services depend on a member, '
                'stop those dependants first.',
              ),
              onChanged: (value) => setState(() => _stopDependents = value),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),
            Text(
              'Control operations need administrator rights: TrayForge asks '
              'for them once per start/stop. Status queries never prompt.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

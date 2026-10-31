import 'package:flutter/material.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/l10n/app_localizations.dart';
import 'package:trayforge/l10n/validation_text.dart';
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
    final error = widget.settingsViewModel.validateUnit(config);
    if (error != null) {
      // Surface the rejection instead of letting ConfigStore throw, in the UI
      // language rather than the English ArgumentError message.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.describe(AppLocalizations.of(context))),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (widget.isEditing) {
      widget.settingsViewModel.editUnit(widget.editIndex!, config);
    } else {
      widget.settingsViewModel.addUnit(config);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final index = widget.editIndex;
    if (index == null) return;

    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.serviceDeleteTitle),
        content: Text(l10n.serviceDeleteBody(widget.initial?.name ?? '')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing ? l10n.serviceEditTitle : l10n.serviceAddTitle,
        ),
        actions: [
          if (widget.isEditing)
            TextButton(onPressed: _confirmDelete, child: Text(l10n.delete)),
          TextButton(onPressed: _save, child: Text(l10n.save)),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.fieldName,
                helperText: l10n.fieldNameHelper,
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                final name = value?.trim() ?? '';
                if (name.isEmpty) return l10n.nameRequired;
                if (name.contains('/') || name.contains('\\')) {
                  return l10n.nameSeparator;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _servicesController,
              minLines: 4,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: l10n.fieldServices,
                helperText: l10n.fieldServicesHelper,
                hintText: l10n.fieldServicesHint,
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (_) =>
                  _serviceNames.isEmpty ? l10n.servicesRequired : null,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _stopDependents,
              title: Text(l10n.stopDependentsTitle),
              subtitle: Text(l10n.stopDependentsSubtitle),
              onChanged: (value) => setState(() => _stopDependents = value),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),
            Text(
              l10n.serviceElevationNote,
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

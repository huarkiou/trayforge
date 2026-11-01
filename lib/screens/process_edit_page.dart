import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trayforge/app_theme.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/l10n/app_localizations.dart';
import 'package:trayforge/l10n/validation_text.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';

/// Full-screen form for creating or editing a [ProcessConfig].
///
/// Used by [SettingsPage] for both add (empty form) and edit (pre-filled).
/// Validation errors are shown inline; the save button is disabled until
/// the form is valid.
class ProcessEditPage extends StatefulWidget {
  final SettingsViewModel settingsViewModel;
  final ProcessConfig? initial;
  final int? editIndex;

  const ProcessEditPage({
    super.key,
    required this.settingsViewModel,
    this.initial,
    this.editIndex,
  });

  bool get isEditing => editIndex != null;

  @override
  State<ProcessEditPage> createState() => _ProcessEditPageState();
}

class _ProcessEditPageState extends State<ProcessEditPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _cwdController;
  late final TextEditingController _cmdController;
  late final TextEditingController _webuiPatternController;
  late final TextEditingController _deleteBeforeStartController;
  late final TextEditingController _maxRestartsController;
  late final TextEditingController _logFileController;

  String _encoding = 'utf-8';
  bool _singleton = false;
  bool _autostart = false;
  bool _cleanupCwd = false;
  bool _elevated = false;
  List<_EnvRow> _envRows = [];

  String? _regexError;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _nameController = TextEditingController(text: p?.name ?? '');
    _cwdController = TextEditingController(text: p?.cwd ?? '');
    _cmdController = TextEditingController(text: p?.cmd ?? '');
    _encoding = p?.encoding ?? 'utf-8';
    _singleton = p?.singleton ?? false;
    _autostart = p?.autostart ?? false;
    _cleanupCwd = p?.cleanupCwd ?? false;
    _elevated = p?.elevated ?? false;
    _webuiPatternController = TextEditingController(
      text: p?.webuiPattern ?? '',
    );
    _deleteBeforeStartController = TextEditingController(
      text: (p?.deleteBeforeStart ?? []).join('\n'),
    );
    _maxRestartsController = TextEditingController(
      text: p?.maxRestarts?.toString() ?? '',
    );
    _logFileController = TextEditingController(text: p?.logFile ?? '');
    _envRows =
        (p?.env?.entries.map((e) => _EnvRow(e.key, e.value)).toList() ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cwdController.dispose();
    _cmdController.dispose();
    _webuiPatternController.dispose();
    _deleteBeforeStartController.dispose();
    _maxRestartsController.dispose();
    _logFileController.dispose();
    for (final row in _envRows) {
      row.dispose();
    }
    super.dispose();
  }

  ProcessConfig _buildConfig() {
    return ProcessConfig(
      name: _nameController.text.trim(),
      cwd: _cwdController.text.trim().isEmpty
          ? null
          : _cwdController.text.trim(),
      cmd: _cmdController.text.trim(),
      encoding: _encoding == 'utf-8' ? null : _encoding,
      singleton: _singleton,
      autostart: _autostart,
      cleanupCwd: _cleanupCwd,
      elevated: _elevated,
      webuiPattern: _webuiPatternController.text.trim().isEmpty
          ? null
          : _webuiPatternController.text.trim(),
      deleteBeforeStart: _deleteBeforeStartController.text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList(),
      maxRestarts: int.tryParse(_maxRestartsController.text.trim()),
      logFile: _logFileController.text.trim().isEmpty
          ? null
          : _logFileController.text.trim(),
      env: _envRows.isEmpty
          ? null
          : {
              for (final r in _envRows)
                r.keyController.text: r.valueController.text,
            },
    );
  }

  void _validateRegex(String pattern) {
    if (pattern.isEmpty) {
      setState(() => _regexError = null);
      return;
    }
    try {
      RegExp(pattern);
      setState(() => _regexError = null);
    } on FormatException catch (e) {
      setState(
        () => _regexError = AppLocalizations.of(
          context,
        ).validationWebuiPattern(e.message),
      );
    }
  }

  // ---- CWD browse ----

  Future<void> _browseCwd() async {
    final path = await getDirectoryPath();
    if (path != null) {
      _cwdController.text = path;
    }
  }

  // ---- Multi-line cmd editor ----

  Future<void> _editCmdMultiLine() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: _cmdController.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.editCommandTitle),
        content: SizedBox(
          width: 500,
          height: 240,
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: monoStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: l10n.editCommandHint,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (result != null) {
      // Collapse newlines to spaces for single-line command.
      _cmdController.text = result.replaceAll('\n', ' ').trim();
    }
    controller.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_regexError != null) return;

    final l10n = AppLocalizations.of(context);
    final config = _buildConfig();
    final vm = widget.settingsViewModel;

    final vmError = vm.validateUnit(config);
    if (vmError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(vmError.describe(l10n)),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final wasRunning = widget.isEditing && vm.isRunning(config.name);

    if (widget.isEditing) {
      vm.editUnit(widget.editIndex!, config);
    } else {
      vm.addUnit(config);
    }

    if (wasRunning) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.processRunningNotice)));
    }

    Navigator.of(context).pop();
  }

  void _duplicate() {
    widget.settingsViewModel.copyUnit(widget.editIndex!);
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final name = widget.initial?.name ?? '';
    final isRunning = widget.settingsViewModel.isRunning(name);
    final l10n = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isRunning ? l10n.processDeleteRunningTitle : l10n.processDeleteTitle,
        ),
        content: Text(
          isRunning
              ? l10n.processDeleteRunningBody(name)
              : l10n.processDeleteBody(name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(
              isRunning ? l10n.processDeleteRunningAction : l10n.delete,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (isRunning) {
      // Fire-and-forget: do not wait for process exit.
      widget.settingsViewModel.stopProcess(name);
    }
    widget.settingsViewModel.deleteUnit(widget.editIndex!);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing ? l10n.processEditTitle : l10n.processAddTitle,
        ),
        actions: [
          if (widget.isEditing)
            TextButton(
              onPressed: _confirmDelete,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.delete),
            ),
          if (widget.isEditing)
            TextButton(onPressed: _duplicate, child: Text(l10n.duplicate)),
          TextButton(
            onPressed: _regexError == null ? _save : null,
            child: Text(l10n.save),
          ),
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
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return l10n.nameRequired;
                }
                if (v.contains('/') || v.contains('\\')) {
                  return l10n.nameSeparator;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cwdController,
                    decoration: InputDecoration(
                      labelText: l10n.fieldCwd,
                      hintText: l10n.fieldCwdHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.folder_open),
                  tooltip: l10n.browseTooltip,
                  onPressed: _browseCwd,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cmdController,
                    decoration: InputDecoration(
                      labelText: l10n.fieldCommand,
                      hintText: l10n.fieldCommandHint,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return l10n.commandRequired;
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.open_in_full),
                  tooltip: l10n.multiLineEditorTooltip,
                  onPressed: _editCmdMultiLine,
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _encoding,
              decoration: InputDecoration(
                labelText: l10n.fieldEncoding,
                border: const OutlineInputBorder(),
              ),
              // Encoding names are technical identifiers, not UI copy.
              items: const [
                DropdownMenuItem(value: 'utf-8', child: Text('UTF-8')),
                DropdownMenuItem(value: 'gbk', child: Text('GBK')),
                DropdownMenuItem(value: 'cp936', child: Text('CP936')),
                DropdownMenuItem(value: 'latin-1', child: Text('Latin-1')),
              ],
              onChanged: (v) => setState(() => _encoding = v ?? 'utf-8'),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _singleton,
              title: Text(l10n.singletonTitle),
              subtitle: Text(l10n.singletonSubtitle),
              onChanged: (v) => setState(() => _singleton = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _autostart,
              title: Text(l10n.autostartTitle),
              subtitle: Text(l10n.autostartSubtitle),
              onChanged: (v) => setState(() => _autostart = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _cleanupCwd,
              title: Text(l10n.cleanupCwdTitle),
              subtitle: Text(l10n.cleanupCwdSubtitle),
              onChanged: (v) => setState(() => _cleanupCwd = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _elevated,
              title: Text(l10n.elevatedTitle),
              subtitle: Text(l10n.elevatedSubtitle),
              onChanged: (v) => setState(() => _elevated = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _webuiPatternController,
              decoration: InputDecoration(
                labelText: l10n.fieldWebuiPattern,
                hintText: l10n.fieldWebuiPatternHint,
                border: const OutlineInputBorder(),
                errorText: _regexError,
              ),
              onChanged: _validateRegex,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _logFileController,
              decoration: InputDecoration(
                labelText: l10n.fieldLogFile,
                helperText: l10n.fieldLogFileHelper,
                hintText: l10n.fieldLogFileHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _maxRestartsController,
              decoration: InputDecoration(
                labelText: l10n.fieldMaxRestarts,
                hintText: l10n.fieldMaxRestartsHint,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 24),
            Text(
              l10n.deleteBeforeStartTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.deleteBeforeStartHelper,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.secondaryTextColor,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _deleteBeforeStartController,
              decoration: InputDecoration(
                hintText: l10n.deleteBeforeStartHint,
                border: const OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  l10n.envVarsTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _envRows.add(_EnvRow('', ''))),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.add),
                ),
              ],
            ),
            ..._envRows.asMap().entries.map((entry) {
              final idx = entry.key;
              final row = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: row.keyController,
                        decoration: InputDecoration(
                          labelText: l10n.fieldKey,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: row.valueController,
                        decoration: InputDecoration(
                          labelText: l10n.fieldValue,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: l10n.remove,
                      onPressed: () => setState(() {
                        row.dispose();
                        _envRows.removeAt(idx);
                      }),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

/// Mutable key-value pair for the env table, with its own controllers.
class _EnvRow {
  final TextEditingController keyController;
  final TextEditingController valueController;

  _EnvRow(String key, String value)
    : keyController = TextEditingController(text: key),
      valueController = TextEditingController(text: value);

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

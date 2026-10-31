import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trayforge/l10n/app_localizations.dart';
import 'package:trayforge/l10n/language_names.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';

/// Sentinel dropdown value for "follow the system locale".
///
/// `DropdownButton` treats a `null` value as "nothing selected", so the
/// system-default entry needs its own value; it never reaches the config.
const String _systemLanguageTag = '__system__';

/// Settings page showing only global configuration options.
///
/// Process CRUD has moved to the Dashboard and process edit form.
class SettingsPage extends StatefulWidget {
  final SettingsViewModel viewModel;

  const SettingsPage({super.key, required this.viewModel});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsViewModel get _vm => widget.viewModel;

  late final TextEditingController _refreshCtrl;
  late final TextEditingController _historyCtrl;
  late final TextEditingController _servicePollCtrl;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onChanged);
    _refreshCtrl = TextEditingController(text: _vm.outputRefreshMs.toString());
    _historyCtrl = TextEditingController(
      text: _vm.outputHistoryLimit.toString(),
    );
    _servicePollCtrl = TextEditingController(
      text: _vm.servicePollMs.toString(),
    );
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    _refreshCtrl.dispose();
    _historyCtrl.dispose();
    _servicePollCtrl.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  void _applyRefreshMs(int val) {
    _vm.setOutputRefreshMs(val);
    _refreshCtrl.text = val.toString();
  }

  void _applyHistoryLimit(int val) {
    _vm.setOutputHistoryLimit(val);
    _historyCtrl.text = val.toString();
  }

  void _applyServicePollMs(int val) {
    _vm.setServicePollMs(val);
    _servicePollCtrl.text = val.toString();
  }

  /// Re-reads config.json and reports the outcome.
  ///
  /// Uses State.context (not the shadowing build parameter) so the mounted
  /// guard is the one the analyzer understands.
  Future<void> _reloadFromDisk() async {
    final reloaded = await _vm.reloadFromDisk();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          reloaded ? l10n.settingsReloaded : l10n.settingsReloadFailed,
        ),
        backgroundColor: reloaded ? null : Colors.red,
      ),
    );
  }

  Widget _buildStepperField({
    required String label,
    required String tooltip,
    required TextEditingController controller,
    required int value,
    required int min,
    required int max,
    required int step,
    required ValueChanged<int> onChanged,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 4),
        Tooltip(
          message: tooltip,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextFormField(
                  controller: controller,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onFieldSubmitted: (v) {
                    final val = int.tryParse(v);
                    if (val != null && val >= min && val <= max) {
                      onChanged(val);
                    } else {
                      controller.text = value.toString();
                    }
                  },
                ),
              ),
              const SizedBox(width: 4),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 32,
                    height: 24,
                    child: IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                      onPressed: value < max
                          ? () => onChanged(math.min(value + step, max))
                          : null,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    height: 24,
                    child: IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                      onPressed: value > min
                          ? () => onChanged(math.max(value - step, min))
                          : null,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hint ?? AppLocalizations.of(context).settingsTakesEffectOnStart,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
      ],
    );
  }

  /// The language row: "System default" plus one entry per shipped locale.
  Widget _buildLanguageTile() {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.translate),
      title: Text(l10n.settingsLanguage),
      trailing: DropdownButton<String>(
        value: _vm.language ?? _systemLanguageTag,
        underline: const SizedBox.shrink(),
        onChanged: (value) => _vm.setLanguage(
          value == null || value == _systemLanguageTag ? null : value,
        ),
        items: [
          DropdownMenuItem(
            value: _systemLanguageTag,
            child: Text(l10n.settingsLanguageSystem),
          ),
          for (final locale in AppLocalizations.supportedLocales)
            DropdownMenuItem(
              value: locale.toLanguageTag(),
              // A language is always listed in itself, so the picker stays
              // readable whatever the current UI language is.
              child: Text(languageDisplayName(locale)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStepperField(
            label: l10n.settingsOutputRefresh,
            tooltip: l10n.settingsOutputRefreshTip,
            controller: _refreshCtrl,
            value: _vm.outputRefreshMs,
            min: 100,
            max: 5000,
            step: 100,
            onChanged: _applyRefreshMs,
          ),
          const SizedBox(height: 16),
          _buildStepperField(
            label: l10n.settingsHistoryLimit,
            tooltip: l10n.settingsHistoryLimitTip,
            controller: _historyCtrl,
            value: _vm.outputHistoryLimit,
            min: 100,
            max: 100000,
            step: 500,
            onChanged: _applyHistoryLimit,
          ),
          const SizedBox(height: 16),
          _buildStepperField(
            label: l10n.settingsServicePoll,
            tooltip: l10n.settingsServicePollTip,
            controller: _servicePollCtrl,
            value: _vm.servicePollMs,
            min: 1000,
            max: 3600000,
            step: 1000,
            onChanged: _applyServicePollMs,
            hint: l10n.settingsAppliesImmediately,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text(l10n.settingsAutostart),
            value: _vm.autostartEnabled,
            onChanged: (_) => _vm.toggleAutostart(),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(),
          _buildLanguageTile(),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.refresh),
            title: Text(l10n.settingsReload),
            subtitle: Text(l10n.settingsReloadSubtitle),
            onTap: _reloadFromDisk,
          ),
        ],
      ),
    );
  }
}

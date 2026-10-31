// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get ok => 'OK';

  @override
  String get add => 'Add';

  @override
  String get remove => 'Remove';

  @override
  String get duplicate => 'Duplicate';

  @override
  String get windowTitleAdministrator => 'trayforge (Administrator)';

  @override
  String get trayReloadSettings => 'Reload Settings';

  @override
  String get trayDashboard => 'Dashboard';

  @override
  String get trayExit => 'Exit';

  @override
  String get kindProcess => 'Process';

  @override
  String get kindServiceGroup => 'Service group';

  @override
  String get dashboardTitle => 'Dashboard';

  @override
  String get dashboardSwitchToGrid => 'Switch to grid view';

  @override
  String get dashboardSwitchToList => 'Switch to list view';

  @override
  String get dashboardAddProcess => 'Add process';

  @override
  String get dashboardAddServiceGroup => 'Add service group';

  @override
  String get dashboardAddProcessButton => 'Add Process';

  @override
  String get dashboardAddServiceGroupButton => 'Add Service Group';

  @override
  String get dashboardSettings => 'Settings';

  @override
  String get dashboardEmpty => 'No processes or service groups configured';

  @override
  String get configErrorTitle => 'Configuration Error';

  @override
  String get configErrorBody =>
      'The configuration file is corrupted and has been backed up. Please check your config file.';

  @override
  String get editProcessTooltip => 'Edit process';

  @override
  String get processClearOutput => 'Clear output';

  @override
  String get processSearchOutput => 'Search output';

  @override
  String get processCloseSearch => 'Close search';

  @override
  String get processFilterHint => 'Filter output...';

  @override
  String get processNoMatchingLines => 'No matching lines';

  @override
  String get noOutputYet => 'No output yet';

  @override
  String get toggleStart => 'Start';

  @override
  String get toggleStop => 'Stop';

  @override
  String get copyWebuiTooltip =>
      'Copy WebUI URL (right-click: open in browser)';

  @override
  String get urlCopied => 'URL copied';

  @override
  String get editCommandTitle => 'Edit Command';

  @override
  String get editCommandHint => 'Enter command (Ctrl+Enter to save)';

  @override
  String get fieldName => 'Name *';

  @override
  String get fieldNameHelper => 'Must not contain / or \\';

  @override
  String get nameRequired => 'Name is required';

  @override
  String get nameSeparator => 'Name must not contain / or \\';

  @override
  String get fieldCwd => 'Working Directory (cwd)';

  @override
  String get fieldCwdHint => 'e.g. C:\\MyApp';

  @override
  String get browseTooltip => 'Browse…';

  @override
  String get fieldCommand => 'Command *';

  @override
  String get fieldCommandHint => 'e.g. myapp.exe --flag';

  @override
  String get commandRequired => 'Command is required';

  @override
  String get multiLineEditorTooltip => 'Multi-line editor…';

  @override
  String get fieldEncoding => 'Encoding';

  @override
  String get singletonTitle => 'Singleton';

  @override
  String get singletonSubtitle =>
      'Prevent starting if a process with the same name is already running';

  @override
  String get autostartTitle => 'Autostart';

  @override
  String get autostartSubtitle => 'Start this process automatically on launch';

  @override
  String get cleanupCwdTitle => 'Cleanup CWD';

  @override
  String get cleanupCwdSubtitle =>
      'Kill residual processes from the same working directory before start';

  @override
  String get elevatedTitle => 'Run as administrator';

  @override
  String get elevatedSubtitle =>
      'Launch with administrator rights. Windows shows a UAC prompt only while TrayForge itself is not elevated; when it is, output and env vars are captured like any other process.';

  @override
  String get fieldWebuiPattern => 'WebUI Pattern';

  @override
  String get fieldWebuiPatternHint => 'e.g. WebUI started at (http://[\\d.:]+)';

  @override
  String get fieldLogFile => 'Log File';

  @override
  String get fieldLogFileHelper =>
      'Tail this file into the output pane (relative to cwd). The only output channel for elevated processes while TrayForge is not elevated.';

  @override
  String get fieldLogFileHint => 'e.g. logs\\app.log';

  @override
  String get fieldMaxRestarts => 'Max Restarts';

  @override
  String get fieldMaxRestartsHint => 'e.g. 3';

  @override
  String get deleteBeforeStartTitle => 'Delete Before Start';

  @override
  String get deleteBeforeStartHelper =>
      'One file path per line, relative to working directory';

  @override
  String get deleteBeforeStartHint => 'temp.lock\ncache.dat';

  @override
  String get envVarsTitle => 'Environment Variables';

  @override
  String get fieldKey => 'Key';

  @override
  String get fieldValue => 'Value';

  @override
  String get processEditTitle => 'Edit Process';

  @override
  String get processAddTitle => 'Add Process';

  @override
  String get processRunningNotice =>
      'Process is running — changes will take effect on next start';

  @override
  String get processDeleteTitle => 'Delete process?';

  @override
  String get processDeleteRunningTitle => 'Stop and delete?';

  @override
  String processDeleteBody(String name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

  @override
  String processDeleteRunningBody(String name) {
    return '\"$name\" is currently running. It will be stopped and the configuration deleted.';
  }

  @override
  String get processDeleteRunningAction => 'Stop and Delete';

  @override
  String invalidRegex(String message) {
    return 'Invalid regex: $message';
  }

  @override
  String get editServiceGroupTooltip => 'Edit service group';

  @override
  String get serviceStartTooltip => 'Start services';

  @override
  String get serviceStopTooltip => 'Stop services';

  @override
  String serviceSummary(int running, int total, String state) {
    return '$running/$total running · $state';
  }

  @override
  String serviceGridSummary(int running, int total) {
    return '$running/$total running';
  }

  @override
  String get serviceEditTitle => 'Edit Service Group';

  @override
  String get serviceAddTitle => 'Add Service Group';

  @override
  String get serviceDeleteTitle => 'Delete service group?';

  @override
  String serviceDeleteBody(String name) {
    return 'Remove \"$name\" from TrayForge?\n\nThe services themselves keep running — TrayForge only stops managing them.';
  }

  @override
  String get serviceClearLog => 'Clear log';

  @override
  String get serviceQuerying => 'Querying services…';

  @override
  String get serviceNoActivity => 'No activity yet';

  @override
  String get fieldServices => 'Services *';

  @override
  String get fieldServicesHelper =>
      'One Windows service name (or systemd unit) per line. They are started and stopped together.';

  @override
  String get fieldServicesHint => 'Spooler\nMyService';

  @override
  String get servicesRequired => 'At least one service is required';

  @override
  String get stopDependentsTitle => 'Stop dependent services too';

  @override
  String get stopDependentsSubtitle =>
      'When a stop fails because other services depend on a member, stop those dependants first.';

  @override
  String get serviceElevationNote =>
      'Control operations need administrator rights: TrayForge asks for them once per start/stop. Status queries never prompt.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsOutputRefresh => 'Output refresh (ms)';

  @override
  String get settingsOutputRefreshTip => 'Lower = smoother, higher = less CPU';

  @override
  String get settingsHistoryLimit => 'History limit';

  @override
  String get settingsHistoryLimitTip => 'Max lines per process';

  @override
  String get settingsServicePoll => 'Service poll (ms)';

  @override
  String get settingsServicePollTip =>
      'How often service groups re-query their state. Status queries never prompt for elevation.';

  @override
  String get settingsAppliesImmediately => 'Applies immediately';

  @override
  String get settingsTakesEffectOnStart => 'Takes effect on next process start';

  @override
  String get settingsAutostart => 'Launch at startup';

  @override
  String get settingsReload => 'Reload config from disk';

  @override
  String get settingsReloadSubtitle =>
      'Re-reads config.json and applies process and service changes without restarting. Processes removed from the file are stopped.';

  @override
  String get settingsReloaded => 'Configuration reloaded';

  @override
  String get settingsReloadFailed =>
      'config.json could not be read (a corrupted file is backed up next to it)';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get stateStopped => 'Stopped';

  @override
  String get stateStarting => 'Starting';

  @override
  String get stateRunning => 'Running';

  @override
  String get stateStopping => 'Stopping';

  @override
  String get stateCrashed => 'Crashed';

  @override
  String get stateCooldown => 'Cooldown';

  @override
  String get serviceStateNotInstalled => 'Not installed';

  @override
  String get serviceStatePaused => 'Paused';

  @override
  String get serviceStateFailed => 'Failed';

  @override
  String get serviceStateUnknown => 'Unknown';

  @override
  String validationEmptyName(String kind) {
    return '$kind name must not be empty';
  }

  @override
  String validationNameSeparator(String kind, String name) {
    return '$kind name \"$name\" must not contain / or \\';
  }

  @override
  String validationNoServices(String name) {
    return 'Service group \"$name\" needs at least one service';
  }

  @override
  String validationWebuiPattern(String message) {
    return 'Invalid webui_pattern regex: $message';
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @duplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicate;

  /// No description provided for @windowTitleAdministrator.
  ///
  /// In en, this message translates to:
  /// **'trayforge (Administrator)'**
  String get windowTitleAdministrator;

  /// No description provided for @trayReloadSettings.
  ///
  /// In en, this message translates to:
  /// **'Reload Settings'**
  String get trayReloadSettings;

  /// No description provided for @trayDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get trayDashboard;

  /// No description provided for @trayExit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get trayExit;

  /// No description provided for @kindProcess.
  ///
  /// In en, this message translates to:
  /// **'Process'**
  String get kindProcess;

  /// No description provided for @kindServiceGroup.
  ///
  /// In en, this message translates to:
  /// **'Service group'**
  String get kindServiceGroup;

  /// No description provided for @dashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboardTitle;

  /// No description provided for @dashboardSwitchToGrid.
  ///
  /// In en, this message translates to:
  /// **'Switch to grid view'**
  String get dashboardSwitchToGrid;

  /// No description provided for @dashboardSwitchToList.
  ///
  /// In en, this message translates to:
  /// **'Switch to list view'**
  String get dashboardSwitchToList;

  /// No description provided for @dashboardAddProcess.
  ///
  /// In en, this message translates to:
  /// **'Add process'**
  String get dashboardAddProcess;

  /// No description provided for @dashboardAddServiceGroup.
  ///
  /// In en, this message translates to:
  /// **'Add service group'**
  String get dashboardAddServiceGroup;

  /// No description provided for @dashboardAddProcessButton.
  ///
  /// In en, this message translates to:
  /// **'Add Process'**
  String get dashboardAddProcessButton;

  /// No description provided for @dashboardAddServiceGroupButton.
  ///
  /// In en, this message translates to:
  /// **'Add Service Group'**
  String get dashboardAddServiceGroupButton;

  /// No description provided for @dashboardSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get dashboardSettings;

  /// No description provided for @dashboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'No processes or service groups configured'**
  String get dashboardEmpty;

  /// No description provided for @configErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Configuration Error'**
  String get configErrorTitle;

  /// No description provided for @configErrorBody.
  ///
  /// In en, this message translates to:
  /// **'The configuration file is corrupted and has been backed up. Please check your config file.'**
  String get configErrorBody;

  /// No description provided for @editProcessTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit process'**
  String get editProcessTooltip;

  /// No description provided for @processClearOutput.
  ///
  /// In en, this message translates to:
  /// **'Clear output'**
  String get processClearOutput;

  /// No description provided for @processSearchOutput.
  ///
  /// In en, this message translates to:
  /// **'Search output'**
  String get processSearchOutput;

  /// No description provided for @processCloseSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get processCloseSearch;

  /// No description provided for @processFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Filter output...'**
  String get processFilterHint;

  /// No description provided for @processNoMatchingLines.
  ///
  /// In en, this message translates to:
  /// **'No matching lines'**
  String get processNoMatchingLines;

  /// No description provided for @noOutputYet.
  ///
  /// In en, this message translates to:
  /// **'No output yet'**
  String get noOutputYet;

  /// No description provided for @toggleStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get toggleStart;

  /// No description provided for @toggleStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get toggleStop;

  /// No description provided for @copyWebuiTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy WebUI URL (right-click: open in browser)'**
  String get copyWebuiTooltip;

  /// No description provided for @urlCopied.
  ///
  /// In en, this message translates to:
  /// **'URL copied'**
  String get urlCopied;

  /// No description provided for @editCommandTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Command'**
  String get editCommandTitle;

  /// No description provided for @editCommandHint.
  ///
  /// In en, this message translates to:
  /// **'Enter command (Ctrl+Enter to save)'**
  String get editCommandHint;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Name *'**
  String get fieldName;

  /// No description provided for @fieldNameHelper.
  ///
  /// In en, this message translates to:
  /// **'Must not contain / or \\'**
  String get fieldNameHelper;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameRequired;

  /// No description provided for @nameSeparator.
  ///
  /// In en, this message translates to:
  /// **'Name must not contain / or \\'**
  String get nameSeparator;

  /// No description provided for @fieldCwd.
  ///
  /// In en, this message translates to:
  /// **'Working Directory (cwd)'**
  String get fieldCwd;

  /// No description provided for @fieldCwdHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. C:\\MyApp'**
  String get fieldCwdHint;

  /// No description provided for @browseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Browse…'**
  String get browseTooltip;

  /// No description provided for @fieldCommand.
  ///
  /// In en, this message translates to:
  /// **'Command *'**
  String get fieldCommand;

  /// No description provided for @fieldCommandHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. myapp.exe --flag'**
  String get fieldCommandHint;

  /// No description provided for @commandRequired.
  ///
  /// In en, this message translates to:
  /// **'Command is required'**
  String get commandRequired;

  /// No description provided for @multiLineEditorTooltip.
  ///
  /// In en, this message translates to:
  /// **'Multi-line editor…'**
  String get multiLineEditorTooltip;

  /// No description provided for @fieldEncoding.
  ///
  /// In en, this message translates to:
  /// **'Encoding'**
  String get fieldEncoding;

  /// No description provided for @singletonTitle.
  ///
  /// In en, this message translates to:
  /// **'Singleton'**
  String get singletonTitle;

  /// No description provided for @singletonSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Prevent starting if a process with the same name is already running'**
  String get singletonSubtitle;

  /// No description provided for @autostartTitle.
  ///
  /// In en, this message translates to:
  /// **'Autostart'**
  String get autostartTitle;

  /// No description provided for @autostartSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start this process automatically on launch'**
  String get autostartSubtitle;

  /// No description provided for @cleanupCwdTitle.
  ///
  /// In en, this message translates to:
  /// **'Cleanup CWD'**
  String get cleanupCwdTitle;

  /// No description provided for @cleanupCwdSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Kill residual processes from the same working directory before start'**
  String get cleanupCwdSubtitle;

  /// No description provided for @elevatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Run as administrator'**
  String get elevatedTitle;

  /// No description provided for @elevatedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Launch with administrator rights. Windows shows a UAC prompt only while TrayForge itself is not elevated; when it is, output and env vars are captured like any other process.'**
  String get elevatedSubtitle;

  /// No description provided for @fieldWebuiPattern.
  ///
  /// In en, this message translates to:
  /// **'WebUI Pattern'**
  String get fieldWebuiPattern;

  /// No description provided for @fieldWebuiPatternHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. WebUI started at (http://[\\d.:]+)'**
  String get fieldWebuiPatternHint;

  /// No description provided for @fieldLogFile.
  ///
  /// In en, this message translates to:
  /// **'Log File'**
  String get fieldLogFile;

  /// No description provided for @fieldLogFileHelper.
  ///
  /// In en, this message translates to:
  /// **'Tail this file into the output pane (relative to cwd). The only output channel for elevated processes while TrayForge is not elevated.'**
  String get fieldLogFileHelper;

  /// No description provided for @fieldLogFileHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. logs\\app.log'**
  String get fieldLogFileHint;

  /// No description provided for @fieldMaxRestarts.
  ///
  /// In en, this message translates to:
  /// **'Max Restarts'**
  String get fieldMaxRestarts;

  /// No description provided for @fieldMaxRestartsHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 3'**
  String get fieldMaxRestartsHint;

  /// No description provided for @deleteBeforeStartTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Before Start'**
  String get deleteBeforeStartTitle;

  /// No description provided for @deleteBeforeStartHelper.
  ///
  /// In en, this message translates to:
  /// **'One file path per line, relative to working directory'**
  String get deleteBeforeStartHelper;

  /// No description provided for @deleteBeforeStartHint.
  ///
  /// In en, this message translates to:
  /// **'temp.lock\ncache.dat'**
  String get deleteBeforeStartHint;

  /// No description provided for @envVarsTitle.
  ///
  /// In en, this message translates to:
  /// **'Environment Variables'**
  String get envVarsTitle;

  /// No description provided for @fieldKey.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get fieldKey;

  /// No description provided for @fieldValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get fieldValue;

  /// No description provided for @processEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Process'**
  String get processEditTitle;

  /// No description provided for @processAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Process'**
  String get processAddTitle;

  /// No description provided for @processRunningNotice.
  ///
  /// In en, this message translates to:
  /// **'Process is running — changes will take effect on next start'**
  String get processRunningNotice;

  /// No description provided for @processDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete process?'**
  String get processDeleteTitle;

  /// No description provided for @processDeleteRunningTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop and delete?'**
  String get processDeleteRunningTitle;

  /// No description provided for @processDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? This cannot be undone.'**
  String processDeleteBody(String name);

  /// No description provided for @processDeleteRunningBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is currently running. It will be stopped and the configuration deleted.'**
  String processDeleteRunningBody(String name);

  /// No description provided for @processDeleteRunningAction.
  ///
  /// In en, this message translates to:
  /// **'Stop and Delete'**
  String get processDeleteRunningAction;

  /// No description provided for @editServiceGroupTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit service group'**
  String get editServiceGroupTooltip;

  /// No description provided for @serviceStartTooltip.
  ///
  /// In en, this message translates to:
  /// **'Start services'**
  String get serviceStartTooltip;

  /// No description provided for @serviceStopTooltip.
  ///
  /// In en, this message translates to:
  /// **'Stop services'**
  String get serviceStopTooltip;

  /// No description provided for @serviceSummary.
  ///
  /// In en, this message translates to:
  /// **'{running}/{total} running · {state}'**
  String serviceSummary(int running, int total, String state);

  /// No description provided for @serviceGridSummary.
  ///
  /// In en, this message translates to:
  /// **'{running}/{total} running'**
  String serviceGridSummary(int running, int total);

  /// No description provided for @serviceEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Service Group'**
  String get serviceEditTitle;

  /// No description provided for @serviceAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Service Group'**
  String get serviceAddTitle;

  /// No description provided for @serviceDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete service group?'**
  String get serviceDeleteTitle;

  /// No description provided for @serviceDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from TrayForge?\n\nThe services themselves keep running — TrayForge only stops managing them.'**
  String serviceDeleteBody(String name);

  /// No description provided for @serviceClearLog.
  ///
  /// In en, this message translates to:
  /// **'Clear log'**
  String get serviceClearLog;

  /// No description provided for @serviceQuerying.
  ///
  /// In en, this message translates to:
  /// **'Querying services…'**
  String get serviceQuerying;

  /// No description provided for @serviceNoActivity.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get serviceNoActivity;

  /// No description provided for @fieldServices.
  ///
  /// In en, this message translates to:
  /// **'Services *'**
  String get fieldServices;

  /// No description provided for @fieldServicesHelper.
  ///
  /// In en, this message translates to:
  /// **'One Windows service name (or systemd unit) per line. They are started and stopped together.'**
  String get fieldServicesHelper;

  /// No description provided for @fieldServicesHint.
  ///
  /// In en, this message translates to:
  /// **'Spooler\nMyService'**
  String get fieldServicesHint;

  /// No description provided for @servicesRequired.
  ///
  /// In en, this message translates to:
  /// **'At least one service is required'**
  String get servicesRequired;

  /// No description provided for @stopDependentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop dependent services too'**
  String get stopDependentsTitle;

  /// No description provided for @stopDependentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When a stop fails because other services depend on a member, stop those dependants first.'**
  String get stopDependentsSubtitle;

  /// No description provided for @serviceElevationNote.
  ///
  /// In en, this message translates to:
  /// **'Control operations need administrator rights: TrayForge asks for them once per start/stop. Status queries never prompt.'**
  String get serviceElevationNote;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsOutputRefresh.
  ///
  /// In en, this message translates to:
  /// **'Output refresh (ms)'**
  String get settingsOutputRefresh;

  /// No description provided for @settingsOutputRefreshTip.
  ///
  /// In en, this message translates to:
  /// **'Lower = smoother, higher = less CPU'**
  String get settingsOutputRefreshTip;

  /// No description provided for @settingsHistoryLimit.
  ///
  /// In en, this message translates to:
  /// **'History limit'**
  String get settingsHistoryLimit;

  /// No description provided for @settingsHistoryLimitTip.
  ///
  /// In en, this message translates to:
  /// **'Max lines per process'**
  String get settingsHistoryLimitTip;

  /// No description provided for @settingsServicePoll.
  ///
  /// In en, this message translates to:
  /// **'Service poll (ms)'**
  String get settingsServicePoll;

  /// No description provided for @settingsServicePollTip.
  ///
  /// In en, this message translates to:
  /// **'How often service groups re-query their state. Status queries never prompt for elevation.'**
  String get settingsServicePollTip;

  /// No description provided for @settingsAppliesImmediately.
  ///
  /// In en, this message translates to:
  /// **'Applies immediately'**
  String get settingsAppliesImmediately;

  /// No description provided for @settingsTakesEffectOnStart.
  ///
  /// In en, this message translates to:
  /// **'Takes effect on next process start'**
  String get settingsTakesEffectOnStart;

  /// No description provided for @settingsAutostart.
  ///
  /// In en, this message translates to:
  /// **'Launch at startup'**
  String get settingsAutostart;

  /// No description provided for @settingsReload.
  ///
  /// In en, this message translates to:
  /// **'Reload config from disk'**
  String get settingsReload;

  /// No description provided for @settingsReloadSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Re-reads config.json and applies process and service changes without restarting. Processes removed from the file are stopped.'**
  String get settingsReloadSubtitle;

  /// No description provided for @settingsReloaded.
  ///
  /// In en, this message translates to:
  /// **'Configuration reloaded'**
  String get settingsReloaded;

  /// No description provided for @settingsReloadFailed.
  ///
  /// In en, this message translates to:
  /// **'config.json could not be read (a corrupted file is backed up next to it)'**
  String get settingsReloadFailed;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// No description provided for @stateStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get stateStopped;

  /// No description provided for @stateStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get stateStarting;

  /// No description provided for @stateRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get stateRunning;

  /// No description provided for @stateStopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping'**
  String get stateStopping;

  /// No description provided for @stateCrashed.
  ///
  /// In en, this message translates to:
  /// **'Crashed'**
  String get stateCrashed;

  /// No description provided for @stateCooldown.
  ///
  /// In en, this message translates to:
  /// **'Cooldown'**
  String get stateCooldown;

  /// No description provided for @serviceStateNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get serviceStateNotInstalled;

  /// No description provided for @serviceStatePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get serviceStatePaused;

  /// No description provided for @serviceStateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get serviceStateFailed;

  /// No description provided for @serviceStateUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get serviceStateUnknown;

  /// No description provided for @validationEmptyName.
  ///
  /// In en, this message translates to:
  /// **'{kind} name must not be empty'**
  String validationEmptyName(String kind);

  /// No description provided for @validationNameSeparator.
  ///
  /// In en, this message translates to:
  /// **'{kind} name \"{name}\" must not contain / or \\'**
  String validationNameSeparator(String kind, String name);

  /// No description provided for @validationNoServices.
  ///
  /// In en, this message translates to:
  /// **'Service group \"{name}\" needs at least one service'**
  String validationNoServices(String name);

  /// No description provided for @validationWebuiPattern.
  ///
  /// In en, this message translates to:
  /// **'Invalid webui_pattern regex: {message}'**
  String validationWebuiPattern(String message);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

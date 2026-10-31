import 'package:flutter/material.dart';
import 'package:trayforge/l10n/app_localizations.dart';

/// English strings for tests that exercise non-widget code — the tray menu
/// builder and the window title, which take the resolved `AppLocalizations` as
/// a parameter instead of reading it from a `BuildContext`.
final AppLocalizations enStrings = lookupAppLocalizations(const Locale('en'));

/// The Chinese strings, for the same call sites.
final AppLocalizations zhStrings = lookupAppLocalizations(const Locale('zh'));

/// Wraps [home] in a `MaterialApp` carrying the real localization delegates.
///
/// Widget tests must use this instead of a bare `MaterialApp`: the pages read
/// `AppLocalizations.of(context)`, and a bare `MaterialApp` only installs the
/// Material/Widgets defaults. Passing [locale] forces a language (e.g.
/// `Locale('zh')`); `null` follows the test platform locale (en_US).
Widget localizedApp({required Widget home, Locale? locale}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

/// Locale plumbing for code that has no [BuildContext].
///
/// The widget tree resolves its locale through `MaterialApp` and the generated
/// [AppLocalizations] delegates. The tray menu and the window title are built
/// outside the widget tree, so they need the same answer synchronously — that
/// is what this file provides.
library;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:trayforge/l10n/app_localizations.dart';

/// The locale [tag] names, or `null` when it is absent or unsupported.
///
/// `-` and `_` are both accepted as the separator (`zh-CN` / `zh_CN`), and the
/// comparison is case-insensitive. Only the language part is matched: the ARB
/// set ships one variant per language, so `zh-TW` and `zh-Hans-CN` are reported
/// as the `zh` (Simplified Chinese) locale rather than falling back to English.
Locale? parseLanguageTag(String? tag) {
  final normalized = tag?.trim().replaceAll('_', '-').toLowerCase() ?? '';
  if (normalized.isEmpty) return null;
  return _shippedLocale(normalized.split('-').first);
}

/// The locale the app runs in: [configuredTag] when it is one we ship,
/// otherwise [systemLocale] matched against [AppLocalizations.supportedLocales],
/// otherwise English.
///
/// Never throws: an unparsable or unsupported tag is treated like "follow the
/// system", and an unsupported system locale falls back to the first supported
/// locale (English).
Locale resolveAppLocale(String? configuredTag, {Locale? systemLocale}) {
  final configured = parseLanguageTag(configuredTag);
  if (configured != null) return configured;

  final system = systemLocale ?? PlatformDispatcher.instance.locale;
  return _shippedLocale(system.languageCode) ??
      AppLocalizations.supportedLocales.first;
}

/// The resolved [AppLocalizations] for [configuredTag].
///
/// For non-widget consumers (tray menu, window title) and for `main`, which
/// needs the app title before the first frame.
AppLocalizations localizationsFor(
  String? configuredTag, {
  Locale? systemLocale,
}) => lookupAppLocalizations(
  resolveAppLocale(configuredTag, systemLocale: systemLocale),
);

/// The shipped locale for [languageCode], or `null` when we do not ship one.
Locale? _shippedLocale(String languageCode) {
  for (final supported in AppLocalizations.supportedLocales) {
    if (supported.languageCode == languageCode) return supported;
  }
  return null;
}

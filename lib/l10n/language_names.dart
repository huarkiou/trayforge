/// Native display names for the languages the app ships.
///
/// A language is always listed in itself, so the Settings picker stays
/// readable whatever the current UI language is. That is also why the names do
/// not live in the ARB files: translating "English" for a Chinese UI would
/// defeat the point.
///
/// **Adding a language** means an ARB file, a `supportedLocales` entry (both
/// generated) and an entry here — otherwise the picker falls back to the raw
/// language tag.
library;

import 'package:flutter/widgets.dart';

const Map<String, String> _nativeLanguageNames = {
  'en': 'English',
  'zh': '简体中文',
};

/// The name of [locale] in its own language ("English", "简体中文").
String languageDisplayName(Locale locale) =>
    _nativeLanguageNames[locale.languageCode] ?? locale.toLanguageTag();

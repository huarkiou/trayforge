import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/l10n/app_localizations.dart';
import 'package:trayforge/l10n/language_names.dart';
import 'package:trayforge/l10n/locale_resolution.dart';

void main() {
  group('parseLanguageTag', () {
    test('parses the shipped tags', () {
      expect(parseLanguageTag('en'), const Locale('en'));
      expect(parseLanguageTag('zh'), const Locale('zh'));
    });

    test('accepts either separator, case, and a country/script variant', () {
      expect(parseLanguageTag('zh-CN'), const Locale('zh'));
      expect(parseLanguageTag('zh_CN'), const Locale('zh'));
      expect(parseLanguageTag('zh-Hans-CN'), const Locale('zh'));
      expect(parseLanguageTag('ZH'), const Locale('zh'));
      expect(parseLanguageTag(' en '), const Locale('en'));
    });

    test('returns null for an absent, blank, or unsupported tag', () {
      expect(parseLanguageTag(null), isNull);
      expect(parseLanguageTag(''), isNull);
      expect(parseLanguageTag('   '), isNull);
      expect(parseLanguageTag('ja'), isNull);
      expect(parseLanguageTag('ja-JP'), isNull);
    });
  });

  group('resolveAppLocale', () {
    test('the configured tag wins over the system locales', () {
      expect(
        resolveAppLocale('zh', systemLocales: const [Locale('en', 'US')]),
        const Locale('zh'),
      );
      expect(
        resolveAppLocale('en', systemLocales: const [Locale('zh', 'CN')]),
        const Locale('en'),
      );
    });

    test('follows the system locales when no tag is configured', () {
      expect(
        resolveAppLocale(null, systemLocales: const [Locale('zh')]),
        const Locale('zh'),
      );
      expect(
        resolveAppLocale(null, systemLocales: const [Locale('zh', 'CN')]),
        const Locale('zh'),
      );
    });

    test('matches a system locale whose country/script we do not ship', () {
      expect(
        resolveAppLocale(null, systemLocales: const [Locale('zh', 'TW')]),
        const Locale('zh'),
        reason: 'one variant per language ships, and it is the best match',
      );
    });

    test('falls back to English for unsupported system locales', () {
      expect(
        resolveAppLocale(null, systemLocales: const [Locale('ja', 'JP')]),
        const Locale('en'),
      );
    });

    test('walks the preferred locale list in order', () {
      // MaterialApp resolves the whole list; the tray menu and the window title
      // must land on the same language, not on English just because the first
      // preferred language is one we do not ship.
      expect(
        resolveAppLocale(
          null,
          systemLocales: const [Locale('ja', 'JP'), Locale('zh', 'CN')],
        ),
        const Locale('zh'),
      );
      expect(
        resolveAppLocale(
          null,
          systemLocales: const [Locale('ja', 'JP'), Locale('en', 'US')],
        ),
        const Locale('en'),
      );
    });

    test('an unsupported configured tag is treated as "follow the system"', () {
      expect(
        resolveAppLocale('ja', systemLocales: const [Locale('zh')]),
        const Locale('zh'),
      );
    });
  });

  group('localizationsFor', () {
    test('renders both shipped languages', () {
      expect(localizationsFor('en').settingsTitle, 'Settings');
      expect(localizationsFor('zh').settingsTitle, '设置');
    });

    test('accepts a country-specific tag, which is what a config carries', () {
      expect(localizationsFor('zh-CN').settingsTitle, '设置');
      expect(localizationsFor('zh_CN').settingsTitle, '设置');
      expect(localizationsFor('en-US').settingsTitle, 'Settings');
    });

    test('never throws for an unusable tag', () {
      expect(
        localizationsFor(
          'ja',
          systemLocales: const [Locale('en')],
        ).settingsTitle,
        'Settings',
      );
    });
  });

  group('languageDisplayName', () {
    test('names each language in itself', () {
      expect(languageDisplayName(const Locale('en')), 'English');
      expect(languageDisplayName(const Locale('zh')), '简体中文');
    });
  });

  test('supportedLocales lists exactly the shipped languages', () {
    expect(
      AppLocalizations.supportedLocales.map((locale) => locale.languageCode),
      ['en', 'zh'],
    );
  });
}

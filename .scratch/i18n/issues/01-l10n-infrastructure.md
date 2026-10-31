# Localization infrastructure: gen-l10n, ARB files, locale resolution

Status: resolved
Type: task

## Problem

There is no localization pipeline at all: no `flutter_localizations`, no ARB
files, no generated `AppLocalizations`, and no way for non-widget code (tray
menu, window title) to obtain a translated string.

## Work

1. `pubspec.yaml`: add `flutter_localizations` (SDK) and `intl: any`; set
   `flutter: generate: true`.
2. `l10n.yaml`: `arb-dir: lib/l10n`, `template-arb-file: app_en.arb`,
   `output-localization-file: app_localizations.dart`, `nullable-getter: false`,
   output into `lib/l10n/` (no synthetic package).
3. `lib/l10n/app_en.arb` (template, with placeholder metadata) and
   `lib/l10n/app_zh.arb`: every key in the spec — common actions, tray/window
   title, dashboard, process/service edit and detail pages, settings, the six
   `ProcState` and four service-only labels, and the validation messages.
4. Run `flutter gen-l10n` and commit the generated `app_localizations*.dart`.
5. `lib/l10n/locale_resolution.dart`:
   - `parseLanguageTag(String?)` → supported `Locale?` (`-` and `_` accepted),
   - `resolveAppLocale(String?)` → configured tag, else the platform locale
     matched against `AppLocalizations.supportedLocales` by language code, else
     English; never throws,
   - `localizationsFor(String?)` → synchronous `AppLocalizations`,
   - `languageDisplayName(Locale)` → "English" / "简体中文".
6. `lib/l10n/state_labels.dart`: `localizedLabel(AppLocalizations)` extensions
   for `ProcState` and `ServiceState` (the domain getters stay).
7. `lib/l10n/validation_text.dart`: `describe(AppLocalizations)` on
   `UnitValidationError`.

## Acceptance

- `flutter gen-l10n` completes without warnings about missing template keys.
- A unit test shows `localizationsFor('zh-CN').settingsTitle == '设置'` and
  `localizationsFor('en').settingsTitle == 'Settings'`.
- `parseLanguageTag`/`resolveAppLocale` return the fallback for absent,
  malformed and unsupported tags instead of throwing.

## Comments

Done: `flutter_localizations` + `intl`, `l10n.yaml`, `lib/l10n/app_en.arb` (~120 keys) and `app_zh.arb`, generated classes committed, `locale_resolution.dart` / `state_labels.dart` / `validation_text.dart`. `supportedLocales` is `[en, zh]` (gen-l10n needs a base-language ARB beside any `zh_CN` one), so a `zh-CN` tag normalizes to `zh`. Covered by `test/l10n/locale_resolution_test.dart` (13 tests).

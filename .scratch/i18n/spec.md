# Internationalization (English + Simplified Chinese)

**Status:** ready-for-human
**Date:** 2026-11-01

## Problem Statement

Every user-visible string in TrayForge is a hardcoded English literal, spread
across the widget layer (cards, detail pages, edit forms, Settings, dialogs,
tooltips), the tray menu builder, and the labels the domain enums expose
(`ProcState.label`, `ServiceState.label`, the validation messages
`ConfigStore.validate` throws). A user whose system runs in Chinese sees an
English application, and adding a second language today would mean touching
every screen again.

## Solution

Introduce Flutter's official localization pipeline (`flutter gen-l10n` over ARB
files) with two locales — **English** (`en`, the template/fallback) and
**Simplified Chinese** (`zh`) — and move every user-visible string into it.

The active language follows the **operating system** by default. The Settings
page gains a **Language** selector with a "System default" entry; an explicit
choice is persisted as `language` in `config.json` and applies immediately
(widget tree, window title and tray menu) without a restart.

## User Stories

1. As a Chinese Windows/Linux user, I want TrayForge to come up in Chinese when
   my system is Chinese, without configuring anything, so that I can read the
   app from the first launch.
2. As a user, I want a Language selector in Settings listing "System default",
   English and 简体中文, so that I can override the system locale.
3. As a user, I want my language choice to persist in `config.json` and to be
   applied on the next launch, so that it survives restarts.
4. As a user, I want choosing a language to take effect immediately — pages,
   dialogs, the window title and the tray menu — so that I do not need to
   restart the app.
5. As a user, I want an unsupported or hand-edited `language` value to fall back
   to the system locale (and ultimately English) instead of breaking startup, so
   that a bad config entry is harmless.
6. As an English user with no `language` in the config, I want the app to behave
   exactly as before, so that this feature is invisible to me.
7. As a user reading a card, the detail page or the settings page, I want status
   labels ("Running", "Crashed", "Not installed", …) in my language, so that the
   UI is consistently translated.
8. As a user who saves an invalid process or service group, I want the
   validation error in my language, so that the rejection is understandable.
9. As a Chinese user with TrayForge running elevated, I want the window title's
   administrator marker in Chinese, so that the privilege signal is readable.

## Implementation Decisions

### Tooling and layout

- **`flutter_localizations` (SDK) + `intl`** are added as dependencies and
  `flutter: generate: true` turns on code generation. `intl` is pinned by
  `flutter_localizations`; the pubspec asks for `any` to avoid a version fight.
- ARB files live in `lib/l10n/`: `app_en.arb` is the template (default text and
  placeholder metadata), `app_zh.arb` the Chinese translation. `l10n.yaml`
  writes the generated classes into `lib/l10n/` (no synthetic package: that
  mechanism is gone), with `nullable-getter: false` so `AppLocalizations.of(context)`
  is non-nullable and widget code stays terse.
- The generated files (`app_localizations*.dart`) are **committed**: analysis
  and tests then work from a fresh checkout without a codegen step, and a
  missing key fails review rather than runtime.
- `untranslated-messages-file` is not enabled; a missing zh translation falls
  back to English, which `flutter test` covers by rendering the zh locale.

### Locale resolution

- **`config.json` gains `language`**: a language tag string (`"en"`, `"zh"`).
  `zh-CN`/`zh_CN` are accepted and normalized to the shipped `zh` tag, and
  absent/`null`/unsupported means **follow the system**. It is a config global
  like `dashboard_layout`: read by the settings reload path and carried by both
  save paths. (The ARB set ships one variant per language, `app_en.arb` /
  `app_zh.arb`, so `AppLocalizations.supportedLocales` is `[en, zh]` — that is
  also what Flutter's generator requires: a country-specific ARB needs a base
  language ARB beside it.)
- **`lib/l10n/locale_resolution.dart`** owns the non-widget side of the choice:
  `parseLanguageTag` (tag → supported `Locale`, or `null` when absent or
  unsupported), `resolveAppLocale` (configured tag, else
  `PlatformDispatcher.instance.locale`, matched against
  `AppLocalizations.supportedLocales` by language code — a `zh_Hans_CN` system
  locale resolves to `zh` — else English) and `localizationsFor` (synchronous
  `AppLocalizations` for code that has no `BuildContext`: tray menu, window
  title). The native display names ("English", "简体中文") live in
  `lib/l10n/language_names.dart`: they are deliberately not translated, so they
  cannot live in the ARB files, and one more entry there is part of adding a
  language.
- **The widget tree** gets `locale: settingsViewModel.locale` (null = let
  Flutter resolve the system locale), plus the generated delegates and supported
  locales, from a `ValueListenableBuilder` on the locale-only
  `SettingsViewModel.localeListenable` in `main.dart` — a stepper edit notifies
  the settings view model but must not rebuild the app. A language change
  rebuilds `MaterialApp`, which replaces the `Localizations` above the
  `Navigator`, so pushed routes re-localize too.
- **The non-widget consumers take the strings as a parameter**:
  `TrayViewModel.buildMenu(AppLocalizations)` and
  `DashboardViewModel.windowTitle({required bool elevated, required AppLocalizations l10n})`.
  No global localization singleton. `main.dart` listens to `SettingsViewModel`,
  and when the language tag actually changed (guarded, so stepper edits do not
  rebuild the tray) re-sets the window title and the tray context menu.

### What gets localized

- Every string in `lib/screens/`, `lib/widgets/`, the tray menu and the window
  title, including tooltips, dialogs, snackbars, hints, helper texts and the
  corrupted-config dialog.
- **Status labels**: `ProcState` and `ServiceState` keep their English `label`
  getters (log lines and `toString` use them — see below) and gain a
  `localizedLabel(AppLocalizations)` extension in `lib/l10n/state_labels.dart`,
  used by every widget.
- **Validation messages**: `ConfigStore.validate` starts throwing
  `UnitValidationError` (an `ArgumentError` subclass in `models.dart`) that
  carries a reason enum plus the offending name/kind/detail and builds the same
  English message as before, so persisted logs and existing tests are unaffected.
  `SettingsViewModel.validateUnit` returns that error, and the edit pages format
  it through `describe(AppLocalizations)` (`lib/l10n/validation_text.dart`).
- **Enum display labels that are not user-visible stay English**: the strings
  service/process controllers append to the output log (`Tomcat: Stopped →
  Running (changed outside TrayForge)`, `still running after the timeout`) are
  console-style diagnostics — the output pane is a transcript, not chrome — and
  stay untranslated. `UnitKind.label` stays too: it is the config-layer
  vocabulary used to build the English `ArgumentError` message.

### Settings surface

- `SettingsViewModel` exposes `language` (raw tag or `null`), `locale`
  (tag → `Locale?`), `localizations` (resolved instance for `main.dart`) and
  `setLanguage(String?)`, which persists through the globals-only path
  (`_persistWithoutReload`) and notifies listeners.
- The Settings page gets a `ListTile` with a `DropdownButton` whose items are
  "System default" plus one entry per `AppLocalizations.supportedLocales`,
  labelled in the language itself.

## Testing Decisions

Tests assert external behaviour: what the user sees and what is persisted.

- **Seam 1 — language persistence and resolution** (`settings_viewmodel_test`,
  `models_test`): `language` round-trips through `AppConfig` JSON
  (`"en"`, `"zh"`, absent → `null`); `setLanguage` writes the config, notifies
  and moves `localeListenable`; `validateUnit` returns a `UnitValidationError`
  for **all four** rules (empty name, separator, no services, bad regex), and
  `l10n/validation_text_test` pins each English `message` to its ARB rendering
  and checks the Chinese text.
- **Seam 2 — locale resolution** (new `l10n/locale_resolution_test`): supported
  tags parse, `_`/`-` both work, unknown/malformed tags and absent values resolve
  to the system locale (passing `systemLocale` explicitly, so the test does not
  depend on the host locale) and never throw; `localizationsFor('zh-CN')` yields
  Chinese text.
- **Seam 3 — widget rendering** (new `l10n/localized_ui_test`, plus the existing
  screen tests): a shared `test/helpers/localized_app.dart` wraps a page in a
  `MaterialApp` with the real delegates; pumping the Settings page and the
  Dashboard with `locale: Locale('zh')` shows Chinese titles/labels, with `en`
  unchanged; picking a language taps the real dropdown and then re-localizes the
  pumped page. Every existing screen/card test is switched to that helper so the
  English assertions keep working.
- **Seam 4 — non-widget consumers** (`tray_viewmodel_test`,
  `dashboard_viewmodel_test`): the tray menu and the window title render the
  localized strings for the passed `AppLocalizations` (English and Chinese), and
  the English labels are asserted unchanged.
- No new seam is invented for the log output: diagnostics stay English and their
  existing tests stand.

## Out of Scope

- Languages other than English and Simplified Chinese (adding one is an ARB
  file, the generated `supportedLocales` entry, and a native name in
  `lib/l10n/language_names.dart`).
- Localizing controller/manager log lines in the output pane, and the
  `ArgumentError` message text itself (English stays as the developer-facing
  fallback).
- Right-to-left layout work, locale-specific number/date formatting (no dates or
  numbers are rendered today), and localized packaging metadata
  (`.desktop` files, installer strings).
- A language switch that reloads the config or restarts the app.
- Localizing the product name ("trayforge").

## Further Notes

- The `language` key is optional and absent by default, so existing
  `config.json` files keep working untouched; the first save after a language
  change writes it.
- `flutter gen-l10n` runs as part of `flutter pub get` / build when
  `generate: true` is set; the committed generated files are refreshed by the
  same command.
- See [ADR 007](../../docs/adr/007-localization.md) for the decisions above.
- The tray and window title are rebuilt only when the tag changes, so the
  Settings page's numeric steppers do not thrash the tray.

# ADR 007: Localization — English and Simplified Chinese

**Status:** Accepted
**Date:** 2026-11-01

## Context

Every user-visible string was a hardcoded English literal: the cards, the
detail pages, the two edit forms, Settings, the dialogs, the tray menu, and the
labels the domain enums exposed (`ProcState.label`, `ServiceState.label`) plus
the `ArgumentError` messages `ConfigStore.validate` threw. A user whose system
runs in Chinese saw an English application, and a second language would have
meant editing every screen again.

The codebase already carries Chinese developer comments, so the natural second
language is Simplified Chinese. Two consumers live **outside** the widget tree —
the tray menu and the window title — and cannot reach a `BuildContext`, which is
the one structural problem the framework's `AppLocalizations.of(context)` does not
solve.

## Decision

1. **Flutter's own pipeline, not a hand-rolled table.** `flutter_localizations`
   + `intl` + `flutter: generate: true`, ARB files in `lib/l10n/`
   (`app_en.arb` is the template), generated `AppLocalizations` written into the
   same directory and committed. `nullable-getter: false` keeps widget code
   terse. A hand-rolled map was rejected: no plural/placeholder tooling, no
   `Locale` resolution, no tooling to spot a missing key.
2. **One language variant per language.** `app_en.arb` + `app_zh.arb` →
   `supportedLocales` is `[en, zh]`. `flutter gen-l10n` requires a base-language
   ARB beside any country-specific one, and shipping a single Simplified Chinese
   variant means a `zh_CN` file would only duplicate it. A `zh-CN` tag is
   therefore accepted and normalized to `zh`; `zh_TW` resolves to `zh` too
   (documented, not silently English).
3. **The language is config state, not a build flag.** `AppConfig.language`
   (`language` in `config.json`, optional) holds a shipped tag; **absent means
   follow the OS**. It is a global like `dashboard_layout`: read on reload,
   carried by both save paths, written only when the user picks something.
   Resolution order — config tag → platform locale (matched by language code) →
   English — lives in `lib/l10n/locale_resolution.dart` and never throws; an
   unsupported or malformed tag is treated as "follow the OS" rather than as a
   corrupted config, because a cosmetic field must not cost the user their units.
4. **Non-widget consumers take the strings as a parameter.**
   `TrayViewModel.buildMenu(AppLocalizations)` and
   `DashboardViewModel.windowTitle(elevated:, l10n:)`. A global localization
   singleton was rejected: it would hide the dependency and make the tray menu
   untestable without global state. `main` owns the change: it listens to
   `SettingsViewModel`, guards on the tag actually changing (the numeric steppers
   notify too), and re-sets the window title and the tray menu.
5. **Validation errors become structured.** `ConfigStore.validate` throws
   `UnitValidationError` — still an `ArgumentError`, keeping every existing
   handler and the English `message` — carrying a reason enum plus the offending
   kind/name/detail. The edit pages format it with
   `describe(AppLocalizations)`. Threading a localizer into `ConfigStore` was
   rejected: the persistence module must not depend on the UI language.
6. **Diagnostics stay English.** The process/service controllers' output-pane
   lines and `toString` labels are a console transcript, not chrome: they are not
   localized. `UnitKind.label` stays for the same reason (it builds the English
   `ArgumentError` message).

## Consequences

- A new language is an ARB file, the generated `supportedLocales` entry, **and**
  a native display name in `lib/l10n/language_names.dart` (the picker labels a
  language in itself, which cannot be translated, so it cannot live in the ARB
  files); no widget changes.
- The language switch is immediate: `MaterialApp.locale` follows
  `SettingsViewModel.localeListenable` (a locale-only notifier, so a stepper
  edit does not rebuild the app), and replacing the `Localizations` above the
  `Navigator` re-localizes pushed routes too.
- Widget tests must pump through `test/helpers/localized_app.dart` (real
  delegates); a bare `MaterialApp` no longer suffices.
- Two surfaces remain English by design, and the `language` key is optional, so
  nothing changes for an English user with an older `config.json`.

## Alternatives rejected

- **An `AppLanguage` enum in the model**, mirroring `DashboardLayout`. It reads
  well, but it hardcodes the shipped list: adding a language would then need a
  model change, an ARB file **and** a `supportedLocales` update, and the config
  would carry an enum name instead of a language tag. A normalized tag string
  keeps "add a language" a data change. The cost is two normalization points
  (`SettingsViewModel` read and write, both through `_applyLanguage`) and one
  `DropdownButton` sentinel for "follow the system", since that widget reads a
  `null` value as "nothing selected".
- **A hand-written `Strings` class with a map per language.** No placeholder or
  plural handling, no `Locale` matching, and every new key needs code.
- **A global `L10n.current` singleton** for the tray and window title. Hidden
  dependency, awkward tests, and a second source of truth next to
  `MaterialApp.locale`.
- **Passing `AppLocalizations` into `ConfigStore`/controllers.** Pulls the UI
  language into modules that are deliberately platform- and UI-free.
- **A `zh_CN` ARB file as well.** Duplicate translations for one variant.

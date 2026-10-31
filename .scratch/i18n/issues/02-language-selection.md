# Language selection: config field, Settings selector, live re-localization

Status: resolved
Type: task

## Problem

The active language must follow the OS by default, be overridable, and the
choice has to survive a restart. Today the app has no notion of a language, and
the tray menu and window title are built outside the widget tree, so nothing
re-localizes them.

## Work

1. `models.dart`: `AppConfig.language` (`String?`, JSON `language`, absent →
   `null` = follow system) in the constructor, `toJson` and `fromJson`.
2. `SettingsViewModel`: `language` getter, `locale` getter (`parseLanguageTag`),
   `localizations` getter (resolved instance for `main.dart`), and
   `setLanguage(String?)` persisting through `_persistWithoutReload()`;
   `_reload()` and `_buildConfig()` carry the field (the globals round-trip:
   missing it in either place silently resets the choice).
3. `main.dart`:
   - root `MaterialApp` wrapped in a `ListenableBuilder` on
     `SettingsViewModel`, passing `locale`, `localizationsDelegates` and
     `supportedLocales`;
   - window title computed from `localizationsFor(config?.language)` at startup;
   - a guarded `SettingsViewModel` listener that re-sets the window title and the
     tray context menu only when the language tag changed.
4. `TrayViewModel.buildMenu(AppLocalizations)`: fixed items ("Reload Settings",
   "Dashboard", "Exit") come from the passed localization.
5. `DashboardViewModel.windowTitle({required bool elevated, required
   AppLocalizations l10n})`.
6. `SettingsPage`: a Language `ListTile` with a `DropdownButton` listing "System
   default" plus every supported locale in its own language.

## Acceptance

- Picking 简体中文 switches every visible page immediately, without a restart,
  and writes the shipped tag — `"language": "zh"` — to `config.json` (a
  hand-edited `zh-CN` is read as `zh`; see the spec's normalization note).
- The tray menu and the window title are in the new language right away.
- Picking "System default" removes the override (tag `null`) and the app follows
  the OS again.
- Editing the numeric steppers does not rebuild the tray menu.
- A config with an unknown or malformed `language` starts normally in the
  system/fallback language.

## Comments

Done: `AppConfig.language` (+ `_parseLanguage`, tolerant of non-strings), `SettingsViewModel.language/locale/localeListenable/localizations/setLanguage` (`_applyLanguage` is the single normalization point for the read and the write path), Language dropdown in Settings, `TrayViewModel.buildMenu(AppLocalizations)`, `DashboardViewModel.windowTitle(elevated:, l10n:)`, and the guarded `SettingsViewModel` listener in `main.dart` that re-sets the window title and tray menu only when the tag changes. `main` builds the `MaterialApp` from `localeListenable`, so a stepper edit no longer rebuilds it. Covered by `settings_viewmodel_test` (language group), `localized_ui_test` (picker tapped, then the page re-localized in place) and the tray/window-title zh assertions.

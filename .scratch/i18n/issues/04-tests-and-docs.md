# Tests and docs for the localized app

Status: resolved
Type: task

## Problem

Every widget test pumps a bare `MaterialApp` with no localization delegates, so
`AppLocalizations.of(context)` would throw; the tray and window-title tests
assert the old signatures. Nothing covers the language setting, the locale
resolution or the Chinese rendering.

## Work

1. `test/helpers/localized_app.dart`: `localizedApp(Widget home, {Locale?
   locale})` returning a `MaterialApp` with `AppLocalizations.localizationsDelegates`
   / `supportedLocales` (and the optional forced locale). Switch
   `dashboard_screen_test`, `process_detail_screen_test`, `process_edit_page_test`,
   `settings_page_test`, `process_card_test`, `webui_copy_button_test` to it.
2. Update the signature call sites: `tray_viewmodel_test` (`buildMenu(l10n)`),
   `dashboard_viewmodel_test` (`windowTitle(elevated:, l10n:)`), and any
   `validateUnit` assertion that needs the typed error.
3. New coverage:
   - `foundation/models_test`: `language` round-trips and defaults to `null`;
   - `viewmodels/settings_viewmodel_test`: `setLanguage` persists + notifies,
     `language`/`locale` reflect the config, an unsupported stored tag reads as
     `null`;
   - `l10n/locale_resolution_test`: tag parsing (`-`, `_`, unknown, absent) and
     `localizationsFor` for both locales;
   - `l10n/localized_ui_test`: the Settings page and the Dashboard render
     Chinese strings under `Locale('zh')` and English under `Locale('en')`;
     a tray menu built with the zh localization shows the Chinese fixed items
     and the window title shows the Chinese administrator marker
     (`tray_viewmodel_test` / `dashboard_viewmodel_test`).
4. Docs: a `CONTEXT.md` glossary entry for "Language" (config field, resolution
   order, what is deliberately left English), and the spec/issue set under
   `.scratch/i18n/`.

## Acceptance

- `flutter test` passes, including the new localization tests.
- The docs describe the resolution order (config tag → OS locale → English) and
  the "diagnostics stay English" decision.
- `dart format lib/ test/`, `dart analyze lib/ test/` clean.

## Comments

Done: `test/helpers/localized_app.dart` (`localizedApp`, `enStrings`, `zhStrings`), the six widget-test files switched to it, the tray/window-title signature call sites updated, new coverage in `test/l10n/` and the view model/model tests, plus README config docs, the `Language` glossary entry and ADR 007. `flutter test`: 487 passed, including the review follow-ups (all four validation reasons, the message/ARB parity test, a tapped picker, shared test fakes, English tray labels).

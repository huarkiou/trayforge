# Extract every user-visible string and localize validation errors

Status: resolved
Type: task

## Problem

Roughly 130 English literals are spread across the five screens and the card
widgets, plus the state labels and the validation messages `ConfigStore.validate`
throws. Without extracting them the language switch only changes the Settings
page.

## Work

1. `lib/screens/dashboard_screen.dart`, `process_detail_screen.dart`,
   `process_edit_page.dart`, `service_detail_page.dart`,
   `service_edit_page.dart`, `settings_page.dart`: every `Text`, tooltip, hint,
   helper text, dialog title/body, snackbar and menu item reads from
   `AppLocalizations.of(context)`; `const` widgets become non-const where the
   string is now runtime.
2. `lib/widgets/`: `process_card.dart`, `service_card.dart`, `status_dot.dart`
   (`StateLabel`), `service_status_row.dart`, `toggle_button.dart`,
   `webui_copy_button.dart`, `copy_snackbar.dart` — same treatment; the
   `running/total · state` summaries become ARB messages with placeholders.
3. State labels: `ProcState` / `ServiceState` render through
   `localizedLabel(l10n)`; the English getters stay for the log lines.
4. Validation: `models.dart` gains `UnitValidationReason` + `UnitValidationError
   extends ArgumentError` (same English message as before, plus the structured
   reason/kind/name/detail); `ConfigStore.validate` throws it;
   `SettingsViewModel.validateUnit` returns it; both edit pages show
   `error.describe(l10n)`.

## Acceptance

- No user-visible English literal remains in `lib/screens/` or `lib/widgets/`
  (examples kept as-is: `UTF-8`/`GBK`/`CP936`/`Latin-1`, command and regex
  example hints are localized, month/date-free so no other formatting needed).
- `grep` for the old literals ("Edit process", "No output yet", "Settings", …)
  finds them only in the ARB files and tests.
- A Chinese locale renders Chinese for a card header, a detail page, an edit
  form, a delete dialog and the tray menu.
- `ConfigStore.validate` still throws an `ArgumentError` whose message contains
  the same English fragments the existing tests assert.
- `dart format lib/ test/` and `dart analyze lib/ test/` are clean.

## Comments

Done: all six screens and seven card/tool widgets read `AppLocalizations`; state labels go through `localizedLabel`; `ConfigStore.validate` throws `UnitValidationError` and both edit pages show `describe(l10n)`. The only English literals left in `lib/screens` + `lib/widgets` are the encoding names (UTF-8/GBK/CP936/Latin-1). `dart format lib/ test/` and `dart analyze lib/ test/` are clean.

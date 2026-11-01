# Readability of the localized UI

Status: resolved
Type: task

## Problem

The first Chinese build looked washed out in the grid and detail views: secondary
text (state labels, `running/total · state` summaries, the WebUI URL, "no output
yet", hints and helper texts) was `Colors.grey` (#9E9E9E) at 11 px, about 2:1
against the card surface. Next to the near-black process names the Chinese
glyphs read as faint, and the generic `fontFamily: 'monospace'` resolved
differently from the rest of the UI.

## Work

1. `lib/app_theme.dart`: `buildAppTheme()` with the CJK fallback chain pinned to
   Microsoft YaHei UI (Latin stays on the platform face), plus the shared
   `secondaryTextColor` (theme `onSurfaceVariant`), `neutralStatusColor`,
   `monoFontFamily`/`monoFontFallback` and `monoStyle()`.
2. Secondary text: 13 `Colors.grey` sites moved to `context.secondaryTextColor`.
3. Small text: state labels, grid summaries, the WebUI URL and the output
   previews go from 11 to 12 px; the neutral status colour moves from `grey` to
   `#6B6B6B`.
4. Output panes (process detail, service detail, cards' preview and the
   multi-line command editor) all use `monoStyle()` — one place for the family
   pair, so a pane cannot keep the generic `monospace` by accident.
5. Tests: the two "renders output lines in monospace" cases assert the stack;
   the dot-colour case asserts `neutralStatusColor` rather than a literal shade.

## Acceptance

- The Chinese secondary text is legible against the card surface (contrast well
  above the previous ~2:1) at the shipped sizes.
- No output pane uses the generic `monospace` family.
- `dart format lib/ test/`, `dart analyze lib/ test/` clean; `flutter test`
  green.

## Comments

Merged as `fix: make the small secondary text readable`. A later review found
`lib/screens/service_detail_page.dart` still on `'monospace'`; that pane and the
missing zh render tests are fixed in the follow-up commit, and `monoStyle()` now
exists so the family pair is stated once.

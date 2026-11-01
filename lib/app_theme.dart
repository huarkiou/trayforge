/// The application theme, tuned for the app's bilingual UI.
///
/// Two things matter here beyond colours:
///
/// - **CJK glyphs.** Latin text uses the platform UI face (Segoe UI on Windows),
///   but every Chinese glyph goes through the fallback chain below. Pinning it
///   makes those glyphs come from the UI-optimised YaHei face instead of
///   whatever the system picks last, which is what keeps 11–13 px Chinese from
///   looking soft next to the crisp Latin names.
/// - **Secondary text.** `Colors.grey` (#9E9E9E) is about 2:1 against the card
///   surface, which reads as washed out at 11–13 px; [secondaryTextColor] uses
///   Material's `onSurfaceVariant` instead.
library;

import 'package:flutter/material.dart';

/// Fallback chain for glyphs the primary family does not cover.
///
/// Latin text is unaffected: fallbacks are consulted per missing glyph only.
const List<String> cjkFontFallback = [
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'PingFang SC',
  'Noto Sans CJK SC',
  'Source Han Sans SC',
  'WenQuanYi Micro Hei',
];

/// Family for the output panes and other fixed-width text.
///
/// Not the generic `monospace`: resolving that name is platform-dependent, and a
/// proportional fallback makes log columns drift. Consolas ships with Windows;
/// the others cover macOS and Linux.
const String monoFontFamily = 'Consolas';

/// Fallbacks for [monoFontFamily], in order of preference.
const List<String> monoFontFallback = [
  'Cascadia Mono',
  'Courier New',
  'DejaVu Sans Mono',
  'Menlo',
];

/// The fixed-width style used by every output pane.
///
/// One place for the family pair, so a pane cannot silently keep the old generic
/// family while its neighbours are updated; callers vary [fontSize], [height]
/// and [color] only.
TextStyle monoStyle({double fontSize = 12, double? height, Color? color}) =>
    TextStyle(
      fontFamily: monoFontFamily,
      fontFamilyFallback: monoFontFallback,
      fontSize: fontSize,
      height: height,
      color: color,
    );

/// Secondary text colour: hints, placeholders, summaries and labels.
///
/// Darker than `Colors.grey`, and derived from the theme instead of hardcoded,
/// so it stays readable in any colour scheme.
extension SecondaryTextColor on BuildContext {
  Color get secondaryTextColor => Theme.of(this).colorScheme.onSurfaceVariant;
}

/// Colour for the "nothing is happening" status: stopped, starting, stopping,
/// cooldown, and a service that is not running.
///
/// A fixed neutral rather than a theme colour on purpose: this is a *status*
/// signal that must read the same in any colour scheme and sit well below the
/// green/red states. The value is picked for contrast on the card surface
/// (~4.9:1), well above the ~2:1 of the `Colors.grey` it replaced.
const Color neutralStatusColor = Color(0xFF6B6B6B);

/// Builds the app theme.
ThemeData buildAppTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: cjkFontFallback),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamilyFallback: cjkFontFallback,
    ),
  );
}

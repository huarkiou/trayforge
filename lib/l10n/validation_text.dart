/// Localized rendering of a [UnitValidationError].
///
/// [ConfigStore.validate] keeps an English `ArgumentError.message` (the
/// developer-facing fallback, and what the logs and existing tests show); the
/// edit pages call [UnitValidationErrorText.describe] so the user sees the
/// rejection in the UI language.
library;

import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/l10n/app_localizations.dart';
import 'package:trayforge/l10n/state_labels.dart';

extension UnitValidationErrorText on UnitValidationError {
  /// The rejection in [l10n]'s language.
  String describe(AppLocalizations l10n) => switch (reason) {
    UnitValidationReason.emptyName => l10n.validationEmptyName(
      _kindLabel(l10n),
    ),
    UnitValidationReason.nameSeparator => l10n.validationNameSeparator(
      _kindLabel(l10n),
      unitName ?? '',
    ),
    UnitValidationReason.noServices => l10n.validationNoServices(
      unitName ?? '',
    ),
    UnitValidationReason.invalidWebuiPattern => l10n.validationWebuiPattern(
      detail ?? '',
    ),
  };

  /// The localized name of the rejected kind.
  ///
  /// Name errors always carry a kind; the default keeps the formatter total.
  String _kindLabel(AppLocalizations l10n) =>
      (unitKind ?? UnitKind.process).localizedLabel(l10n);
}

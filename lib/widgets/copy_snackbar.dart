import 'package:flutter/material.dart';
import 'package:trayforge/l10n/app_localizations.dart';

/// Shows a compact floating snackbar confirming a clipboard copy.
void showCopySnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(AppLocalizations.of(context).urlCopied),
      duration: const Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
      width: 160,
    ),
  );
}

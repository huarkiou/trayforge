import 'package:flutter/material.dart';

/// The pencil action shared by the process and service cards.
///
/// One look for both kinds and both layouts: a 20 px icon in a compact hit
/// box, so a service card's edit button is not larger than a process card's.
class EditIconButton extends StatelessWidget {
  final VoidCallback onPressed;

  /// Tooltip naming what the button edits ("Edit process" / "Edit service
  /// group").
  final String tooltip;

  const EditIconButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.edit, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
    );
  }
}

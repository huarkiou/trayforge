import 'package:flutter/material.dart';
import 'package:trayforge/app_theme.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/l10n/app_localizations.dart';
import 'package:trayforge/l10n/state_labels.dart';

/// Colour used for [ProcState] in [StatusDot] and status labels.
///
/// Green = running, red = crashed, neutral = stopped/starting/stopping/cooldown
/// (see [neutralStatusColor]).
Color statusColor(ProcState state) {
  switch (state) {
    case ProcState.running:
      return Colors.green;
    case ProcState.crashed:
      return Colors.red;
    case ProcState.stopped:
    case ProcState.starting:
    case ProcState.stopping:
    case ProcState.cooldown:
      return neutralStatusColor;
  }
}

/// A small coloured circle indicating process status.
///
/// See [statusColor] for the colour mapping.
class StatusDot extends StatelessWidget {
  final ProcState state;

  const StatusDot({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: statusColor(state),
      ),
    );
  }
}

/// Status dot plus the state label, as shown at the top of a grid card.
///
/// Shared by the process and service grid tiles so both kinds render their
/// state the same way: dot, a short gap, then the label in [statusColor].
class StateLabel extends StatelessWidget {
  final ProcState state;

  const StateLabel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusDot(state: state),
        const SizedBox(width: 6),
        Text(
          state.localizedLabel(AppLocalizations.of(context)),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: statusColor(state),
          ),
        ),
      ],
    );
  }
}

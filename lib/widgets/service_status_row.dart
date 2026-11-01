import 'package:flutter/material.dart';
import 'package:trayforge/app_theme.dart';
import 'package:trayforge/foundation/service_status.dart';
import 'package:trayforge/l10n/app_localizations.dart';
import 'package:trayforge/l10n/state_labels.dart';

/// Colour for one service's state label.
Color serviceStateColor(ServiceState state) {
  if (state.isUp) return Colors.green;
  if (state == ServiceState.failed ||
      state == ServiceState.notInstalled ||
      state == ServiceState.unknown) {
    return Colors.red;
  }
  return neutralStatusColor;
}

/// One "service name — state" row, shared by the group card and the detail
/// page so both render the same information the same way.
class ServiceStatusRow extends StatelessWidget {
  final ServiceStatus status;

  /// Card rows are compact; the detail page has room for a slightly larger name.
  final bool dense;

  const ServiceStatusRow({super.key, required this.status, this.dense = true});

  @override
  Widget build(BuildContext context) {
    final color = serviceStateColor(status.state);
    final nameStyle = dense
        ? Theme.of(context).textTheme.bodySmall
        : const TextStyle(fontSize: 13);
    // The detail page uses an explicit style: inheriting bodySmall would bring
    // its letter spacing and line height along, which the card gets instead.
    final labelStyle = dense
        ? Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          )
        : TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 1 : 2),
      child: Row(
        children: [
          Expanded(
            child: dense
                ? Text(
                    status.name,
                    style: nameStyle,
                    overflow: TextOverflow.ellipsis,
                  )
                : SelectableText(status.name, style: nameStyle),
          ),
          const SizedBox(width: 8),
          Text(
            status.state.localizedLabel(AppLocalizations.of(context)),
            style: labelStyle,
          ),
        ],
      ),
    );
  }
}

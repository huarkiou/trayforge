import 'package:flutter/material.dart';
import 'package:trayforge/app_theme.dart';
import 'package:trayforge/l10n/app_localizations.dart';
import 'package:trayforge/viewmodels/process_viewmodel.dart';
import 'package:trayforge/widgets/edit_icon_button.dart';
import 'package:trayforge/widgets/status_dot.dart';
import 'package:trayforge/widgets/toggle_button.dart';
import 'package:trayforge/widgets/webui_copy_button.dart';

/// A Material [Card] widget that displays a single process.
///
/// Shows the process name, a coloured status dot, last ~15 lines of output,
/// a start/stop toggle button, and an optional WebUI copy-to-clipboard button.
class ProcessCard extends StatelessWidget {
  final ProcessViewModel viewModel;
  final VoidCallback onTap;
  final VoidCallback? onEditTap;

  /// Number of output lines to display in the card body.
  static const int previewLines = 15;

  const ProcessCard({
    super.key,
    required this.viewModel,
    required this.onTap,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProcessCardHeader(viewModel: viewModel, onEditTap: onEditTap),
                  const SizedBox(height: 8),
                  _OutputPreview(viewModel: viewModel),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Header row for the List card: status dot, name, then the shared
/// [ProcessCardActions] (WebUI copy, toggle, edit).
class ProcessCardHeader extends StatelessWidget {
  final ProcessViewModel viewModel;
  final VoidCallback? onEditTap;

  const ProcessCardHeader({super.key, required this.viewModel, this.onEditTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        StatusDot(state: viewModel.state),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            viewModel.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ProcessCardActions(viewModel: viewModel, onEditTap: onEditTap),
      ],
    );
  }
}

/// Action buttons shared by the List card header and the Grid card:
/// WebUI copy (when a URL is known), start/stop toggle, edit.
class ProcessCardActions extends StatelessWidget {
  final ProcessViewModel viewModel;
  final VoidCallback? onEditTap;

  const ProcessCardActions({
    super.key,
    required this.viewModel,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final editButton = onEditTap != null
        ? EditIconButton(
            onPressed: onEditTap!,
            tooltip: AppLocalizations.of(context).editProcessTooltip,
          )
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (viewModel.webuiUrl != null) ...[
          WebUiCopyButton(url: viewModel.webuiUrl!, compact: true),
          const SizedBox(width: 4),
        ],
        ToggleButton(
          viewModel: viewModel,
          visualDensity: VisualDensity.compact,
        ),
        if (editButton != null) ...[const SizedBox(width: 4), editButton],
      ],
    );
  }
}

/// A compact square card for the Dashboard Grid layout.
///
/// Layered to fill the square tile: status dot + label and the process
/// name on top, WebUI URL (when present) and the latest five output lines
/// in the middle, action buttons along the bottom.
class ProcessGridCard extends StatelessWidget {
  final ProcessViewModel viewModel;
  final VoidCallback onTap;
  final VoidCallback? onEditTap;

  const ProcessGridCard({
    super.key,
    required this.viewModel,
    required this.onTap,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StateLabel(state: viewModel.state),
                  const SizedBox(height: 6),
                  Text(
                    viewModel.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  if (viewModel.webuiUrl != null)
                    Text(
                      viewModel.webuiUrl.toString(),
                      style: monoStyle(color: context.secondaryTextColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  // Latest five output lines; nothing when there is no
                  // output yet (the card must stay compact).
                  _OutputPreview(
                    viewModel: viewModel,
                    maxLines: 5,
                    showEmptyHint: false,
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ProcessCardActions(
                        viewModel: viewModel,
                        onEditTap: onEditTap,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Monospace output preview showing the last [maxLines] lines.
///
/// Shows the localized "No output yet" hint when there is no output; pass
/// [showEmptyHint] `false` to render nothing instead (used by the compact grid
/// cards).
class _OutputPreview extends StatelessWidget {
  final ProcessViewModel viewModel;
  final int maxLines;
  final bool showEmptyHint;

  const _OutputPreview({
    required this.viewModel,
    this.maxLines = ProcessCard.previewLines,
    this.showEmptyHint = true,
  });

  @override
  Widget build(BuildContext context) {
    final lines = viewModel.outputLines;
    if (lines.isEmpty) {
      if (!showEmptyHint) return const SizedBox.shrink();
      return Text(
        AppLocalizations.of(context).noOutputYet,
        style: monoStyle(color: context.secondaryTextColor),
      );
    }

    final preview = lines.length > maxLines
        ? lines.sublist(lines.length - maxLines)
        : lines;

    // One Text per output line: each renders on a single row (long lines
    // are truncated, never soft-wrapped), so [maxLines] counts *output*
    // lines and the latest lines always stay visible.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in preview)
          Text(
            line,
            style: monoStyle(height: 1.3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

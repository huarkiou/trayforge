import 'package:flutter/material.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/viewmodels/service_viewmodel.dart';
import 'package:trayforge/widgets/service_status_row.dart';
import 'package:trayforge/widgets/status_dot.dart';

/// Start/stop toggle for a service group, with a spinner while the operation
/// runs.
class ServiceToggleButton extends StatelessWidget {
  final ServiceViewModel viewModel;

  /// Tighter hit box, used by the compact grid tile.
  final bool compact;

  const ServiceToggleButton({
    super.key,
    required this.viewModel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // The button owns its listener because the detail page's AppBar places it
    // outside any builder of its own. The cards already rebuild around it, so
    // the nested rebuild there is harmless — the AppBar is the reason it must
    // listen at all.
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        if (viewModel.isTransitioning) {
          return const SizedBox(
            width: 24,
            height: 24,
            child: Padding(
              padding: EdgeInsets.all(2),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        // What the button offers must match what the toggle will do: "any
        // member up → stop all", which is not the same as the aggregate state
        // being active (a crashed group with a member running still stops).
        final isUp = viewModel.isUp;
        return IconButton(
          icon: Icon(
            isUp ? Icons.stop_circle_outlined : Icons.play_circle_outlined,
            color: isUp ? Colors.red : Colors.green,
            size: compact ? 20 : 24,
          ),
          visualDensity: compact ? VisualDensity.compact : null,
          tooltip: isUp ? 'Stop services' : 'Start services',
          onPressed: () => viewModel.toggle(),
        );
      },
    );
  }
}

/// Action buttons shared by the List card header and the Grid tile:
/// start/stop toggle plus the optional edit button.
class ServiceCardActions extends StatelessWidget {
  final ServiceViewModel viewModel;
  final VoidCallback? onEditTap;

  /// Smaller icons and a tighter hit box, used by the compact grid tile.
  final bool compact;

  const ServiceCardActions({
    super.key,
    required this.viewModel,
    this.onEditTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final editButton = onEditTap != null
        ? IconButton(
            icon: Icon(Icons.edit, size: compact ? 20 : null),
            tooltip: 'Edit service group',
            onPressed: onEditTap,
            visualDensity: compact ? VisualDensity.compact : null,
          )
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ServiceToggleButton(viewModel: viewModel, compact: compact),
        if (editButton != null) ...[const SizedBox(width: 4), editButton],
      ],
    );
  }
}

/// Card for one service group: aggregate state, per-service detail, actions.
class ServiceCard extends StatelessWidget {
  final ServiceViewModel viewModel;
  final VoidCallback? onEditTap;
  final VoidCallback? onTap;

  const ServiceCard({
    super.key,
    required this.viewModel,
    this.onEditTap,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Follows the view model: state, member rows and the operation log all
    // change after the card is first built. The nested listener inside
    // [ServiceToggleButton] is intentional (the detail AppBar needs it), not a
    // second cancellation trick: the card rebuilds its own contents, the
    // button rebuilds only itself.
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    StatusDot(state: viewModel.state),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            viewModel.name,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${viewModel.runningCount}/${viewModel.totalCount} '
                            'running · ${viewModel.state.label}',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    ServiceCardActions(
                      viewModel: viewModel,
                      onEditTap: onEditTap,
                    ),
                  ],
                ),
                if (viewModel.statuses.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final status in viewModel.statuses)
                    ServiceStatusRow(status: status),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact square tile for a service group, used by the Dashboard grid.
///
/// Same shape as [ProcessGridCard]: state dot + label on top, the group name,
/// how many members are up, and the actions along the bottom. The member rows
/// stay in the list card and the detail page.
class ServiceGridCard extends StatelessWidget {
  final ServiceViewModel viewModel;
  final VoidCallback onTap;
  final VoidCallback? onEditTap;

  const ServiceGridCard({
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
                  // The member count is what a process card never shows, so
                  // the two kinds stay distinguishable at a glance.
                  Text(
                    '${viewModel.runningCount}/${viewModel.totalCount} running',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ServiceCardActions(
                        viewModel: viewModel,
                        onEditTap: onEditTap,
                        compact: true,
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

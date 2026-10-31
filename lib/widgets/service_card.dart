import 'package:flutter/material.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/viewmodels/service_viewmodel.dart';
import 'package:trayforge/widgets/service_status_row.dart';
import 'package:trayforge/widgets/status_dot.dart';

/// Start/stop toggle for a service group, with a spinner while the operation
/// runs.
class ServiceToggleButton extends StatelessWidget {
  final ServiceViewModel viewModel;

  const ServiceToggleButton({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
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

    // What the button offers must match what the toggle will do: "any member
    // up → stop all", which is not the same as the aggregate state being
    // active (a crashed group with a member running still stops).
    final isUp = viewModel.isUp;
    return IconButton(
      icon: Icon(
        isUp ? Icons.stop_circle_outlined : Icons.play_circle_outlined,
        color: isUp ? Colors.red : Colors.green,
      ),
      tooltip: isUp ? 'Stop services' : 'Start services',
      onPressed: () => viewModel.toggle(),
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
    return Card(
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
                  ServiceToggleButton(viewModel: viewModel),
                  if (onEditTap != null)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit service group',
                      onPressed: onEditTap,
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
    );
  }
}

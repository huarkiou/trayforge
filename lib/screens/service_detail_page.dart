import 'package:flutter/material.dart';
import 'package:trayforge/l10n/app_localizations.dart';
import 'package:trayforge/viewmodels/service_viewmodel.dart';
import 'package:trayforge/widgets/follow_scroll.dart';
import 'package:trayforge/widgets/service_card.dart';
import 'package:trayforge/widgets/service_status_row.dart';
import 'package:trayforge/widgets/status_dot.dart';

/// Full detail page for one service group: per-service state plus the
/// operation log (every request, result and error line).
class ServiceDetailPage extends StatefulWidget {
  final ServiceViewModel viewModel;
  final VoidCallback? onEditTap;

  const ServiceDetailPage({super.key, required this.viewModel, this.onEditTap});

  @override
  State<ServiceDetailPage> createState() => _ServiceDetailPageState();
}

class _ServiceDetailPageState extends State<ServiceDetailPage> {
  final FollowLatestController _follow = FollowLatestController();

  ServiceViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onChanged);
    _follow.attach();
    // Opening the page always starts pinned to the newest line.
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow.jumpToBottom());
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    _follow.detach();
    super.dispose();
  }

  void _onChanged() => _follow.onContentChanged();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusDot(state: _vm.state),
              const SizedBox(width: 8),
              Flexible(child: Text(_vm.name, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
        actions: [
          if (widget.onEditTap != null)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: l10n.editServiceGroupTooltip,
              onPressed: widget.onEditTap,
            ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: l10n.serviceClearLog,
            onPressed: () {
              _follow.reset();
              _vm.clearOutput();
            },
          ),
          ServiceToggleButton(viewModel: _vm),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatusList(),
          const Divider(height: 1),
          Expanded(child: _buildLog()),
        ],
      ),
    );
  }

  Widget _buildStatusList() {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        if (_vm.statuses.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              AppLocalizations.of(context).serviceQuerying,
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final status in _vm.statuses)
                ServiceStatusRow(status: status, dense: false),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLog() {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final lines = _vm.outputLines;
        if (lines.isEmpty) {
          return Center(
            child: Text(
              AppLocalizations.of(context).serviceNoActivity,
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }
        return SingleChildScrollView(
          controller: _follow.scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SelectableText(
            lines.join('\n'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.4,
            ),
          ),
        );
      },
    );
  }
}

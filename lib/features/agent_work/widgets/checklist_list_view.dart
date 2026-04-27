import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/checklist_provider.dart';
import '../../../core/models/agent_checklist.dart';
import '../../../core/models/agent_checklist_item.dart';

/// List view showing all checklists (owned + shared).
class ChecklistListView extends StatelessWidget {
  const ChecklistListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChecklistProvider>(
      builder: (context, provider, _) {
        final checklists = provider.myChecklists;

        if (checklists.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.checklist, size: 64, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                Text(
                  'No checklists yet',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Checklists are created automatically by agents that have the agent-work capability enabled.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => provider.refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: checklists.length,
            itemBuilder: (context, index) {
              final checklist = checklists[index];
              return _ChecklistCard(checklist: checklist);
            },
          ),
        );
      },
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  final AgentChecklist checklist;

  const _ChecklistCard({required this.checklist});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _ChecklistDetailView(checklist: checklist),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      checklist.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _VisibilityBadge(visibility: checklist.visibility),
                ],
              ),
              if (checklist.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  checklist.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Policy: ${checklist.validationPolicy.name} · ${checklist.requiredConsecutivePasses} passes',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisibilityBadge extends StatelessWidget {
  final ChecklistVisibility visibility;

  const _VisibilityBadge({required this.visibility});

  @override
  Widget build(BuildContext context) {
    final colors = switch (visibility) {
      ChecklistVisibility.private => Theme.of(context).colorScheme.secondary,
      ChecklistVisibility.shared => Theme.of(context).colorScheme.tertiary,
      ChecklistVisibility.team => Theme.of(context).colorScheme.primary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        visibility.name,
        style: TextStyle(fontSize: 11, color: colors),
      ),
    );
  }
}

/// Inline detail view for a single checklist.
class _ChecklistDetailView extends StatelessWidget {
  final AgentChecklist checklist;

  const _ChecklistDetailView({required this.checklist});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(checklist.title)),
      body: Consumer<ChecklistProvider>(
        builder: (context, provider, _) {
          final items = provider.getItemsForChecklist(checklist.id);
          if (items.isEmpty) {
            return const Center(child: Text('No items in this checklist.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _ItemTile(item: item);
            },
          );
        },
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final AgentChecklistItem item;

  const _ItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.status) {
      ChecklistItemStatus.open => Icons.radio_button_unchecked,
      ChecklistItemStatus.inProgress => Icons.play_circle_outline,
      ChecklistItemStatus.blocked => Icons.block,
      ChecklistItemStatus.verificationPending => Icons.pending,
      ChecklistItemStatus.passedOnce => Icons.check_circle_outline,
      ChecklistItemStatus.completed => Icons.check_circle,
      ChecklistItemStatus.failed => Icons.cancel,
      ChecklistItemStatus.skipped => Icons.skip_next,
      ChecklistItemStatus.archived => Icons.archive,
    };

    final color = switch (item.status) {
      ChecklistItemStatus.completed => Colors.green,
      ChecklistItemStatus.failed => Colors.red,
      ChecklistItemStatus.blocked => Colors.orange,
      _ => Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
    };

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        item.title,
        style: TextStyle(
          decoration: item.status == ChecklistItemStatus.completed
              ? TextDecoration.lineThrough
              : null,
        ),
      ),
      subtitle: item.instructions.isNotEmpty
          ? Text(
              item.instructions,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: Text(
        item.status.name,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

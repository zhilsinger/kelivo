import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/agent_audit_provider.dart';
import '../../../core/models/agent_audit_event.dart';

/// Scrollable audit log timeline.
class AuditLogView extends StatelessWidget {
  const AuditLogView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AgentAuditProvider>(
      builder: (context, provider, _) {
        final events = provider.recentEvents;

        if (events.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history, size: 64, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                Text(
                  'No audit events yet',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => provider.refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              return _AuditEventTile(event: event);
            },
          ),
        );
      },
    );
  }
}

class _AuditEventTile extends StatelessWidget {
  final AgentAuditEvent event;

  const _AuditEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final icon = switch (event.action) {
      'create' => Icons.add_circle_outline,
      'update' => Icons.edit,
      'delete' => Icons.delete_outline,
      'complete' => Icons.check_circle,
      'block' => Icons.block,
      'verify' => Icons.verified,
      'cancel' => Icons.cancel,
      'dispatch' => Icons.send,
      _ => Icons.circle,
    };

    final timestamp = event.createdAt.toLocal();
    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              timeStr,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
            ),
          ),
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '[${event.entityType}] ${event.action} by ${event.actorName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/agent_timer_provider.dart';
import '../../../core/models/agent_timer_job.dart';

/// List view showing all timers (active + missed).
class TimerListView extends StatelessWidget {
  const TimerListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AgentTimerProvider>(
      builder: (context, provider, _) {
        final timers = provider.activeTimers;

        if (timers.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_off, size: 64, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                Text(
                  'No active timers',
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
            itemCount: timers.length,
            itemBuilder: (context, index) {
              final timer = timers[index];
              return _TimerCard(timer: timer);
            },
          ),
        );
      },
    );
  }
}

class _TimerCard extends StatelessWidget {
  final AgentTimerJob timer;

  const _TimerCard({required this.timer});

  @override
  Widget build(BuildContext context) {
    final remaining = timer.dueAt.difference(DateTime.now());
    final isOverdue = remaining.isNegative;
    final remainingStr = _formatDuration(remaining.abs());

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isOverdue ? Icons.timer_off : Icons.timer,
                  color: isOverdue ? Colors.red : Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    timer.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  timer.status.name,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isOverdue
                            ? Colors.red
                            : Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isOverdue ? 'Overdue by $remainingStr' : '$remainingStr remaining',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isOverdue ? Colors.red : null,
                  ),
            ),
            if (timer.prompt.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                timer.prompt,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }
}

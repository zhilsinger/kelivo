import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/checklist_provider.dart';
import '../../../core/models/agent_checklist_item.dart';
import '../../../core/models/agent_check_result.dart';

/// Detailed verification report for a single checklist item.
class VerificationReportPage extends StatelessWidget {
  final String itemId;

  const VerificationReportPage({super.key, required this.itemId});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChecklistProvider>(
      builder: (context, provider, _) {
        final item = provider.getItem(itemId);
        if (item == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Not Found')),
            body: const Center(child: Text('Item not found')),
          );
        }

        final results = provider.getResultsForItem(itemId);
        final consecutivePasses = _countConsecutivePasses(results);

        return Scaffold(
          appBar: AppBar(
            title: Text(item.title),
            actions: [
              _StatusChip(status: item.status),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Item header
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${item.requiredConsecutivePasses} consecutive passes required',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: item.requiredConsecutivePasses > 0
                            ? consecutivePasses / item.requiredConsecutivePasses
                            : 0,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              ),
              // Instructions
              if (item.instructions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Instructions',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(item.instructions),
                      ],
                    ),
                  ),
                ),
              ],
              // Acceptance criteria
              if (item.acceptanceCriteria.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Acceptance Criteria',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(item.acceptanceCriteria),
                      ],
                    ),
                  ),
                ),
              ],
              // Verification history
              const SizedBox(height: 20),
              Text('Verification History',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (results.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No verification results yet.'),
                  ),
                )
              else
                ...results.map((result) => _ResultTile(result: result)),
            ],
          ),
        );
      },
    );
  }

  int _countConsecutivePasses(List<AgentCheckResult> results) {
    int count = 0;
    for (int i = results.length - 1; i >= 0; i--) {
      if (results[i].passed) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }
}

class _StatusChip extends StatelessWidget {
  final ChecklistItemStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ChecklistItemStatus.completed => Colors.green,
      ChecklistItemStatus.failed => Colors.red,
      ChecklistItemStatus.blocked => Colors.orange,
      _ => Colors.grey,
    };

    return Chip(
      label: Text(status.name),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide.none,
      labelStyle: TextStyle(color: color, fontSize: 12),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ResultTile extends StatelessWidget {
  final AgentCheckResult result;

  const _ResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.passed ? Icons.check_circle : Icons.cancel,
                  color: result.passed ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text('#${result.sequenceNumber} by ${result.actorName}'),
                const Spacer(),
                Text(
                  '${result.confidencePercent}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (result.summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(result.summary),
            ],
            if (result.issuesFound.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...result.issuesFound.map((issue) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                        const SizedBox(width: 4),
                        Expanded(child: Text(issue, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

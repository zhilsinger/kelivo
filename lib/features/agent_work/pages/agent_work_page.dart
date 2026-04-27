import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/checklist_provider.dart';
import '../../../core/providers/agent_timer_provider.dart';
import '../../../core/providers/agent_audit_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/checklist_list_view.dart';
import '../widgets/timer_list_view.dart';
import '../widgets/audit_log_view.dart';

/// Main hub for agent work features: checklists, timers, audit log.
class AgentWorkPage extends StatelessWidget {
  const AgentWorkPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Agent Work'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Checklists'),
              Tab(text: 'Timers'),
              Tab(text: 'Audit Log'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ChecklistListView(),
            TimerListView(),
            AuditLogView(),
          ],
        ),
        floatingActionButton: const _ContextualFAB(),
      ),
    );
  }
}

/// Context-aware FAB that changes action based on active tab.
class _ContextualFAB extends StatelessWidget {
  const _ContextualFAB();

  @override
  Widget build(BuildContext context) {
    final tabController = DefaultTabController.of(context);
    final l10n = AppLocalizations.of(context)!;

    return ListenableBuilder(
      listenable: tabController,
      builder: (context, _) {
        switch (tabController.index) {
          case 0: // Checklists
            return FloatingActionButton.extended(
              onPressed: () => _showCreateChecklistDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Checklist'),
            );
          case 1: // Timers
            return FloatingActionButton.extended(
              onPressed: () => _showCreateTimerDialog(context),
              icon: const Icon(Icons.timer),
              label: const Text('Timer'),
            );
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }

  void _showCreateChecklistDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Checklist'),
        content: TextField(
          controller: titleCtrl,
          decoration: const InputDecoration(hintText: 'Checklist title'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final title = titleCtrl.text.trim();
              if (title.isNotEmpty) {
                context.read<ChecklistProvider>().createChecklist(title);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showCreateTimerDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final promptCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Timer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(hintText: 'Timer label'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: promptCtrl,
              decoration: const InputDecoration(hintText: 'Prompt when timer fires'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final title = titleCtrl.text.trim();
              final prompt = promptCtrl.text.trim();
              if (title.isNotEmpty) {
                context.read<AgentTimerProvider>().scheduleTimer(
                      title: title,
                      prompt: prompt,
                      dueAt: DateTime.now().add(const Duration(minutes: 5)),
                    );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }
}

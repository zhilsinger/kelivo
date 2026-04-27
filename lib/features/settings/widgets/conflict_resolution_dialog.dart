import 'package:flutter/material.dart';
import '../../../core/models/supabase_sync_conflict.dart';
import '../../../l10n/app_localizations.dart';

/// Dialog for resolving a sync conflict manually.
/// Shows local vs remote state and offers resolution actions.
class ConflictResolutionDialog extends StatelessWidget {
  final SyncConflict conflict;
  final void Function(String resolution) onResolve;

  const ConflictResolutionDialog({
    super.key,
    required this.conflict,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.syncConflictTitle),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _StateCard(label: l10n.syncConflictLocalLabel, state: conflict.localState),
          const SizedBox(height: 12),
          _StateCard(label: l10n.syncConflictRemoteLabel, state: conflict.remoteState),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () { onResolve('dismiss'); Navigator.pop(context); },
          child: Text(l10n.syncConflictDismiss),
        ),
        TextButton(
          onPressed: () { onResolve('take_remote'); Navigator.pop(context); },
          child: Text(l10n.syncConflictTakeRemote),
        ),
        FilledButton(
          onPressed: () { onResolve('keep_local'); Navigator.pop(context); },
          child: Text(l10n.syncConflictKeepLocal),
        ),
      ],
    );
  }
}

class _StateCard extends StatelessWidget {
  final String label;
  final Map<String, dynamic> state;
  const _StateCard({required this.label, required this.state});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(
            state.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ],
      ),
    ),
  );
}

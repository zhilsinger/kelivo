import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/supabase/supabase_sync_status.dart';
import '../../../core/services/supabase/sync_orchestrator.dart';
import '../../../l10n/app_localizations.dart';

/// Composable widget showing current sync status.
/// Drop into any settings page app bar or header.
class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SupabaseSyncStatus>();
    final l10n = AppLocalizations.of(context)!;

    if (!sync.isInitialized) return const SizedBox.shrink();

    IconData icon;
    String label;
    switch (sync.status) {
      case SyncStatus.syncing:
        icon = Icons.sync;
        label = l10n.syncStatusSyncing;
      case SyncStatus.paused:
        icon = Icons.pause_circle_outline;
        label = l10n.syncStatusPaused;
      case SyncStatus.error:
        icon = Icons.cloud_off;
        label = l10n.syncStatusFailed;
      case SyncStatus.idle:
      default:
        if (sync.pendingCount > 0) {
          icon = Icons.cloud_upload_outlined;
          label = l10n.syncStatusPending(sync.pendingCount);
        } else {
          icon = Icons.cloud_done_outlined;
          label = l10n.syncStatusIdle;
        }
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: sync.status == SyncStatus.error
          ? Theme.of(context).colorScheme.error
          : null),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 13)),
      if (sync.deadLetterCount > 0) ...[const SizedBox(width: 6),
        Badge(
          label: Text('${sync.deadLetterCount}',
              style: const TextStyle(fontSize: 10)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      ],
    ]);
  }
}

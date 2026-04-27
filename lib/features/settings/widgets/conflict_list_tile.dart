import 'package:flutter/material.dart';
import '../../../core/models/supabase_sync_conflict.dart';
import '../../../l10n/app_localizations.dart';
import 'conflict_resolution_dialog.dart';

/// List tile for a single sync conflict.
/// Tapping opens the resolution dialog.
class ConflictListTile extends StatelessWidget {
  final SyncConflict conflict;
  final Future<void> Function(String id, String resolution) onResolve;

  const ConflictListTile({
    super.key,
    required this.conflict,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
      title: Text('${l10n.syncConflictTitle}: ${conflict.threadId.substring(0, 8)}...'),
      subtitle: Text(conflict.type.name),
      trailing: Text(l10n.syncConflictResolved),
      onTap: () => showDialog(
        context: context,
        builder: (_) => ConflictResolutionDialog(
          conflict: conflict,
          onResolve: (resolution) => onResolve(conflict.id, resolution),
        ),
      ),
    );
  }
}

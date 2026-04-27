import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:kelivo/core/models/assistant_memory.dart';
import 'package:kelivo/core/models/cloud_memory_metadata.dart';
import 'package:kelivo/core/providers/memory_provider.dart';
import 'package:kelivo/core/providers/assistant_provider.dart';
import 'package:kelivo/core/services/cloud_memory_metadata_store.dart';
import 'package:kelivo/core/services/supabase/supabase_client_service.dart';
import 'package:kelivo/l10n/app_localizations.dart';
import 'package:kelivo/features/memory/widgets/memory_source_badge.dart';
import 'package:kelivo/features/memory/widgets/memory_score_indicator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Standalone page for reviewing all memories the AI has learned.
///
/// Merges local [AssistantMemory] records with cloud [CloudMemoryMetadata]
/// into a unified view. Sections: Important Facts, Decisions, Pending Review.
class MemoryReviewPage extends StatefulWidget {
  const MemoryReviewPage({super.key, this.assistantId});

  /// If provided, filters to memories belonging to this assistant.
  final String? assistantId;

  @override
  State<MemoryReviewPage> createState() => _MemoryReviewPageState();
}

class _MemoryReviewPageState extends State<MemoryReviewPage> {
  bool _cloudLoading = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadCloud();
  }

  Future<void> _maybeLoadCloud() async {
    if (!SupabaseClientService.instance.isConfigured) return;
    if (_cloudLoading) return;
    setState(() => _cloudLoading = true);
    try {
      final mp = context.read<MemoryProvider>();
      await mp.loadCloudMetadata();
    } finally {
      if (mounted) setState(() => _cloudLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final mp = context.watch<MemoryProvider>();

    // Wait for local memories to be initialized.
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        mp.initialize();
      });
    } catch (_) {}

    final allMemories = widget.assistantId != null
        ? mp.getForAssistant(widget.assistantId!)
        : mp.memories;

    final cloudMeta = mp.cloudMetadata;

    // Partition by review status.
    final pinned = <AssistantMemory>[];
    final reviewed = <AssistantMemory>[];
    final pending = <AssistantMemory>[];

    for (final m in allMemories) {
      final meta = cloudMeta[m.id];
      if (meta != null && meta.pinned) {
        pinned.add(m);
      } else if (meta != null && meta.reviewed) {
        reviewed.add(m);
      } else {
        pending.add(m);
      }
    }

    // If no cloud metadata loaded yet, everything goes to pending.
    final showPartitions = cloudMeta.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.memoryReviewPageTitle),
      ),
      body: _cloudLoading
          ? const Center(child: CircularProgressIndicator())
          : allMemories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Lucide.Brain, size: 48, color: cs.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text(
                        l10n.memoryReviewNoMemories,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
                  children: [
                    if (showPartitions && pinned.isNotEmpty) ...[
                      _sectionHeader(l10n.memoryReviewSectionImportantFacts, Lucide.Pin, cs),
                      ...pinned.map((m) => _memoryTile(context, m, cloudMeta[m.id])),
                    ],
                    if (showPartitions && reviewed.isNotEmpty) ...[
                      _sectionHeader(l10n.memoryReviewSectionDecisions, Lucide.CheckCheck, cs),
                      ...reviewed.map((m) => _memoryTile(context, m, cloudMeta[m.id])),
                    ],
                    if (pending.isNotEmpty) ...[
                      _sectionHeader(
                        showPartitions ? l10n.memoryReviewSectionPendingReview : l10n.memoryReviewPageTitle,
                        Lucide.Clock,
                        cs,
                      ),
                      ...pending.map((m) => _memoryTile(context, m, cloudMeta[m.id])),
                    ],
                  ],
                ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _memoryTile(
    BuildContext context,
    AssistantMemory memory,
    CloudMemoryMetadata? meta,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mp = context.read<MemoryProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
            width: 0.6,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (meta != null)
                    MemorySourceBadge(source: meta.source),
                  const Spacer(),
                  if (meta != null) ...[
                    MemoryScoreIndicator(score: meta.memoryScore),
                    const SizedBox(width: 8),
                  ],
                  _actionButton(
                    context,
                    icon: meta?.pinned == true ? Lucide.PinOff : Lucide.Pin,
                    color: cs.primary,
                    onTap: () => mp.pinMemory(memory.id, !(meta?.pinned ?? false)),
                  ),
                  const SizedBox(width: 4),
                  _actionButton(
                    context,
                    icon: Lucide.Pencil,
                    color: cs.primary,
                    onTap: () {
                      // Edit is handled by the existing memory tab flow.
                      // For the standalone page, show a simple edit dialog.
                      _showEditDialog(context, memory, mp);
                    },
                  ),
                  const SizedBox(width: 4),
                  _actionButton(
                    context,
                    icon: Lucide.Trash2,
                    color: cs.error,
                    onTap: () async {
                      await mp.delete(id: memory.id);
                      await mp.deleteCloudMetadata(memory.id);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                memory.content,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              if (meta?.sourceThreadId != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Source: thread ${meta!.sourceThreadId}',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.45),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  Future<void> _showEditDialog(
    BuildContext context,
    AssistantMemory memory,
    MemoryProvider mp,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: memory.content);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.memoryReviewActionEdit),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: l10n.assistantEditMemoryDialogHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.homePageCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l10n.backupPageSave),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      await mp.update(id: memory.id, content: result);
    }
  }
}

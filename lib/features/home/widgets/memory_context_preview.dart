import 'package:flutter/material.dart';
import '../../../core/models/supabase_memory_context.dart';
import '../../../l10n/app_localizations.dart';

/// A modal bottom sheet that previews what Supabase AI memory will be
/// injected on the next send.
///
/// Shows sources with relevance scores, estimated token count,
/// and per-source remove / search-again controls.
class MemoryContextPreviewSheet extends StatelessWidget {
  const MemoryContextPreviewSheet({
    super.key,
    required this.contextPackage,
    this.onRemoveSource,
    this.onSearchAgain,
    this.onDismiss,
  });

  final AiMemoryContextPackage contextPackage;
  final void Function(String threadId)? onRemoveSource;
  final VoidCallback? onSearchAgain;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title row
            Row(
              children: [
                Icon(Icons.psychology_outlined, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.supabaseMemoryContextPreviewTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  l10n.supabaseMemoryContextPreviewTokens(
                    contextPackage.estimatedTokens.toString(),
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.supabaseMemoryContextPreviewSources(
                contextPackage.chunkCount.toString(),
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 12),

            // Source list
            if (contextPackage.sources.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    l10n.supabaseMemoryContextPreviewEmpty,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: contextPackage.sources.length,
                  itemBuilder: (ctx, idx) {
                    final src = contextPackage.sources[idx];
                    return _SourceTile(
                      source: src,
                      onRemove: onRemoveSource != null
                          ? () => onRemoveSource!(src.threadId)
                          : null,
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),

            // Action buttons
            if (onSearchAgain != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onSearchAgain,
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(l10n.supabaseMemoryContextPreviewAddMore),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source, this.onRemove});

  final MemoryContextSource source;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final date = source.messageDate.toIso8601String().substring(0, 10);
    final pct = (source.relevanceScore * 100).toStringAsFixed(0);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        title: Text(
          source.threadTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '$date — $pct% match',
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
        ),
        trailing: onRemove != null
            ? IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onRemove,
                tooltip: AppLocalizations.of(
                  context,
                )!.supabaseMemoryContextPreviewRemove,
              )
            : null,
      ),
    );
  }
}

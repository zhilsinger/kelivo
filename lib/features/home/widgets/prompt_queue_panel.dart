import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/providers/prompt_queue_provider.dart';
import '../../../core/models/chat_input_data.dart';
import '../../../theme/design_tokens.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_tactile.dart';

/// A full management panel for the prompt queue.
///
/// Shows all queued items with drag-to-reorder, inline editing, and deletion.
/// Includes an auto-process toggle and a Clear All button.
///
/// Designed to be shown via `showModalBottomSheet` or as a standalone page.
class PromptQueuePanel extends StatefulWidget {
  const PromptQueuePanel({super.key});

  @override
  State<PromptQueuePanel> createState() => _PromptQueuePanelState();
}

class _PromptQueuePanelState extends State<PromptQueuePanel> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Consumer<PromptQueueProvider>(
      builder: (context, provider, _) {
        final queue = provider.queue;
        final hasItems = queue.isNotEmpty;

        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white30
                        : Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.queue_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hasItems
                          ? l10n.promptQueueTitleWithCount(queue.length.toString())
                          : l10n.promptQueueTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (hasItems)
                      IosCardPress(
                        onTap: () => _confirmClearAll(context, provider),
                        borderRadius: BorderRadius.circular(10),
                        baseColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        child: Text(
                          l10n.promptQueueClearAll,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Queue list
              if (!hasItems)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inbox_rounded,
                            size: 48,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.25,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.promptQueueEmpty,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ReorderableListView.builder(
                    key: ValueKey('queue_${queue.length}'),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: queue.length,
                    onReorder: (oldIndex, newIndex) {
                      provider.reorderQueue(oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final item = queue[index];
                      return _QueueItemTile(
                        key: ValueKey(item.id),
                        prompt: item,
                        index: index,
                        total: queue.length,
                        onEdit: () => _showEditDialog(
                          context,
                          provider,
                          item,
                        ),
                        onDelete: () => provider.removeFromQueue(item.id),
                      );
                    },
                  ),
                ),
              // Bottom bar with auto-process toggle
              if (hasItems) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.autorenew_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.promptQueueAutoProcess,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      IosSwitch(
                        value: provider.isAutoProcess,
                        onChanged: (v) => provider.toggleAutoProcess(v),
                      ),
                    ],
                  ),
                ),
              ],
              // Safe area bottom padding
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        );
      },
    );
  }

  void _confirmClearAll(BuildContext context, PromptQueueProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.promptQueueClearAll),
        content: Text(l10n.promptQueueDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.homePageCancel),
          ),
          TextButton(
            onPressed: () {
              provider.clearQueue();
              Navigator.of(ctx).pop();
            },
            child: Text(
              l10n.promptQueueDeleteConfirm,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    PromptQueueProvider provider,
    QueuedPrompt prompt,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: prompt.input.text);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.promptQueueEditPrompt),
        content: IosFormTextField(
          controller: controller,
          hintText: l10n.promptQueueEditPrompt,
          maxLines: 5,
          minLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.homePageCancel),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                provider.editInQueue(prompt.id, text);
              }
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.homePageDone),
          ),
        ],
      ),
    );
  }
}

/// A single tile in the queue panel's list.
class _QueueItemTile extends StatelessWidget {
  final QueuedPrompt prompt;
  final int index;
  final int total;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _QueueItemTile({
    super.key,
    required this.prompt,
    required this.index,
    required this.total,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      child: IosCardPress(
        onTap: () {},
        borderRadius: BorderRadius.circular(12),
        baseColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle & index
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Text preview
                    Text(
                      prompt.input.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.3,
                      ),
                    ),
                    // Image / file indicator
                    if (prompt.input.imagePaths.isNotEmpty ||
                        prompt.input.documents.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (prompt.input.imagePaths.isNotEmpty) ...[
                            Icon(
                              Icons.image_outlined,
                              size: 14,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${prompt.input.imagePaths.length}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ],
                          if (prompt.input.documents.isNotEmpty) ...[
                            if (prompt.input.imagePaths.isNotEmpty)
                              const SizedBox(width: 8),
                            Icon(
                              Icons.insert_drive_file_outlined,
                              size: 14,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${prompt.input.documents.length}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    // Position indicator
                    const SizedBox(height: 2),
                    Text(
                      '#${index + 1}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.35,
                        ),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Actions
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IosIconButton(
                    size: 18,
                    padding: const EdgeInsets.all(6),
                    onTap: onEdit,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    icon: Icons.edit_outlined,
                  ),
                  const SizedBox(width: 4),
                  IosIconButton(
                    size: 18,
                    padding: const EdgeInsets.all(6),
                    onTap: onDelete,
                    color: theme.colorScheme.error,
                    icon: Icons.delete_outline_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

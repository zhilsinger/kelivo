import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/models/assistant.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../utils/avatar_cache.dart';
import '../../../utils/sandbox_path_resolver.dart';

/// Shows a bottom sheet allowing the user to select multiple assistants
/// and clone them all at once.
Future<void> showAssistantCloneSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final cs = Theme.of(context).colorScheme;
  final provider = context.read<AssistantProvider>();
  final assistants = List<Assistant>.of(provider.assistants);
  final maxHeight = MediaQuery.of(context).size.height * 0.8;

  if (assistants.isEmpty) {
    showAppSnackBar(
      context,
      message: 'No assistants to clone',
      type: NotificationType.warning,
    );
    return;
  }

  final selectedIds = <String>{};

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final hasSelection = selectedIds.isNotEmpty;
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  // Title
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l10n.assistantSettingsCloneSheetTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // List
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: assistants.length,
                      itemBuilder: (_, i) {
                        final a = assistants[i];
                        final selected = selectedIds.contains(a.id);
                        return _CloneRow(
                          assistant: a,
                          selected: selected,
                          onToggle: () {
                            setSheetState(() {
                              if (selected) {
                                selectedIds.remove(a.id);
                              } else {
                                selectedIds.add(a.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  // Bottom bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: hasSelection
                            ? () async {
                                int successCount = 0;
                                final failedNames = <String>[];

                                for (final id in selectedIds) {
                                  try {
                                    final newId = await provider
                                        .duplicateAssistant(id, l10n: l10n);
                                    if (newId != null) {
                                      successCount++;
                                    } else {
                                      final a = provider.getById(id);
                                      failedNames.add(a?.name ?? id);
                                    }
                                  } catch (_) {
                                    final a = provider.getById(id);
                                    failedNames.add(a?.name ?? id);
                                  }
                                }

                                if (!ctx.mounted) return;
                                Navigator.of(ctx).pop();

                                if (successCount > 0) {
                                  showAppSnackBar(
                                    context,
                                    message: l10n
                                        .assistantSettingsCloneSuccessMultiple(
                                            successCount),
                                    type: NotificationType.success,
                                  );
                                }
                                if (failedNames.isNotEmpty) {
                                  showAppSnackBar(
                                    context,
                                    message:
                                        'Failed to clone: ${failedNames.join(', ')}',
                                    type: NotificationType.error,
                                  );
                                }
                              }
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                          disabledBackgroundColor:
                              cs.primary.withValues(alpha: 0.3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          l10n.assistantSettingsCloneSheetMakeClones,
                          style: TextStyle(
                            color: hasSelection
                                ? cs.onPrimary
                                : cs.onPrimary.withValues(alpha: 0.5),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _CloneRow extends StatelessWidget {
  const _CloneRow({
    required this.assistant,
    required this.selected,
    required this.onToggle,
  });

  final Assistant assistant;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => onToggle(),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _assistantAvatar(context, assistant, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    assistant.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Inline duplicated avatar widgets (from assistant_select_sheet.dart) ---

Widget _assistantAvatar(BuildContext context, Assistant a,
    {double size = 28}) {
  final cs = Theme.of(context).colorScheme;
  final av = (a.avatar ?? '').trim();
  if (av.isNotEmpty) {
    if (av.startsWith('http')) {
      return FutureBuilder<String?>(
        future: AvatarCache.getPath(av),
        builder: (ctx, snap) {
          final p = snap.data;
          if (p != null && File(p).existsSync()) {
            return ClipOval(
              child: Image(
                image: FileImage(File(p)),
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            );
          }
          return ClipOval(
            child: Image.network(
              av,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => _assistantInitial(cs, a.name, size),
            ),
          );
        },
      );
    } else if (!kIsWeb && (av.startsWith('/') || av.contains(':'))) {
      final fixed = SandboxPathResolver.fix(av);
      final f = File(fixed);
      if (f.existsSync()) {
        return ClipOval(
          child: Image(
            image: FileImage(f),
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      }
    } else {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          (av.isNotEmpty ? av : '🙂').characters.take(1).toString(),
          style: TextStyle(fontSize: size * 0.5),
        ),
      );
    }
  }
  return _assistantInitial(cs, a.name, size);
}

Widget _assistantInitial(ColorScheme cs, String name, double size) {
  final letter = name.trim().isNotEmpty ? name.trim()[0] : '?';
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: cs.primary.withValues(alpha: 0.15),
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Text(
      letter,
      style: TextStyle(
        color: cs.primary,
        fontSize: size * 0.42,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

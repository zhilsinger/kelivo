import 'package:flutter/material.dart';
import 'package:kelivo/core/models/cloud_memory_metadata.dart';

/// A small chip showing whether a memory originated locally or from the cloud.
class MemorySourceBadge extends StatelessWidget {
  const MemorySourceBadge({
    super.key,
    required this.source,
    this.showIcon = true,
  });

  final CloudMemorySource source;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCloud = source == CloudMemorySource.supabase;

    final icon = isCloud ? Icons.cloud_outlined : Icons.phone_android_outlined;
    final bg = isCloud
        ? (isDark ? Colors.blue.shade800 : Colors.blue.shade50)
        : (isDark ? Colors.green.shade800 : Colors.green.shade50);
    final fg = isCloud
        ? (isDark ? Colors.blue.shade200 : Colors.blue.shade700)
        : (isDark ? Colors.green.shade200 : Colors.green.shade700);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            isCloud ? 'Cloud' : 'Local',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

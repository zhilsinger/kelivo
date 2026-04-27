import 'package:flutter/material.dart';

/// Five dots representing memory importance (0–5).
class MemoryScoreIndicator extends StatelessWidget {
  const MemoryScoreIndicator({
    super.key,
    required this.score,
  });

  final int score;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final clamped = score.clamp(0, 5);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < clamped;
        return Padding(
          padding: EdgeInsets.only(
            left: i > 0 ? 3 : 0,
          ),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled
                  ? cs.primary.withValues(alpha: 0.8)
                  : cs.onSurface.withValues(alpha: 0.15),
            ),
          ),
        );
      }),
    );
  }
}

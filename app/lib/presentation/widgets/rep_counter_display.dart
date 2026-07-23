import 'package:flutter/material.dart';

/// Large rep counter with optional quality ring (SPEC §6.3 / P2-2, P2-3).
class RepCounterDisplay extends StatelessWidget {
  const RepCounterDisplay({
    super.key,
    required this.repCount,
    this.qualityScore,
  });

  final int repCount;
  final double? qualityScore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Wiederholungen: $repCount',
      value: '$repCount',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              if (qualityScore != null)
                SizedBox(
                  width: 160,
                  height: 160,
                  child: CircularProgressIndicator(
                    value: qualityScore!.clamp(0.0, 1.0),
                    strokeWidth: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _qualityColor(qualityScore!),
                    ),
                  ),
                ),
              // Glanceability (P2-3): readable from ~1–2 m
              Text(
                '$repCount',
                style: theme.textTheme.displayLarge?.copyWith(
                      fontSize: 120,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ) ??
                    const TextStyle(
                      fontSize: 120,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Wiederholungen',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (qualityScore != null) ...[
            const SizedBox(height: 8),
            Text(
              'Qualität: ${(qualityScore! * 100).round()}%',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Color _qualityColor(double score) {
    if (score >= 0.8) return Colors.green;
    if (score >= 0.5) return Colors.orange;
    return Colors.red;
  }
}

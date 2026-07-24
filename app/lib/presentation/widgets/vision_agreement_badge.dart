import 'package:flutter/material.dart';

/// Compact product badge: pose agreement vs IMU during a set (Audit U-02 / P2).
///
/// IMU remains authoritative — this only shows how often pose confirmed a rep.
/// Hidden when [cameraEnabled] is false.
class VisionAgreementBadge extends StatelessWidget {
  final bool cameraEnabled;
  final int fusedReps;
  final int imuOnlyReps;
  final bool compact;

  const VisionAgreementBadge({
    super.key,
    required this.cameraEnabled,
    this.fusedReps = 0,
    this.imuOnlyReps = 0,
    this.compact = true,
  });

  int get imuDecided => fusedReps + imuOnlyReps;

  String get label {
    if (imuDecided == 0) return 'Pose bereit';
    return 'Pose bestätigt $fusedReps/$imuDecided';
  }

  double? get ratio {
    if (imuDecided == 0) return null;
    return fusedReps / imuDecided;
  }

  Color _accent(ThemeData theme) {
    final r = ratio;
    if (r == null) return theme.colorScheme.outline;
    if (r >= 0.7) return Colors.teal.shade700;
    if (r >= 0.4) return Colors.orange.shade800;
    return theme.colorScheme.error;
  }

  @override
  Widget build(BuildContext context) {
    if (!cameraEnabled) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final color = _accent(theme);

    if (compact) {
      return Tooltip(
        message:
            'Form-Check: wie oft Pose die IMU-Rep im Zeitfenster bestätigte. '
            'Zähler bleibt IMU — Kamera überschreibt nicht.',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.accessibility_new, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.accessibility_new, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.titleSmall),
                  Text(
                    'IMU zählt — Pose nur Bestätigung',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (ratio != null)
              Text(
                '${(ratio! * 100).round()}%',
                style: theme.textTheme.titleMedium?.copyWith(color: color),
              ),
          ],
        ),
      ),
    );
  }
}

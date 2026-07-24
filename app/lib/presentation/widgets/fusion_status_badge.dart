import 'package:flutter/material.dart';

import '../../domain/vision/fusion_engine.dart';

/// Compact badge showing last fusion source / camera status (CV-04 UI).
///
/// Product line uses „Pose bestätigt X/Y“; chips remain for diagnose.
class FusionStatusBadge extends StatelessWidget {
  final bool cameraEnabled;
  final int imuOnlyReps;
  final int cameraOnlyReps;
  final int fusedReps;
  final int poseReps;
  final double? lastElbowAngle;
  final String? diagnostic;

  const FusionStatusBadge({
    super.key,
    required this.cameraEnabled,
    this.imuOnlyReps = 0,
    this.cameraOnlyReps = 0,
    this.fusedReps = 0,
    this.poseReps = 0,
    this.lastElbowAngle,
    this.diagnostic,
  });

  int get _imuDecided => fusedReps + imuOnlyReps;

  String get _agreementLabel {
    if (!cameraEnabled) return 'IMU only';
    if (_imuDecided == 0) return 'Pose bereit';
    return 'Pose bestätigt $fusedReps/$_imuDecided';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  cameraEnabled ? Icons.videocam : Icons.videocam_off,
                  size: 18,
                  color: cameraEnabled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _agreementLabel,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                _chip(theme, 'both $fusedReps', theme.colorScheme.primary),
                const SizedBox(width: 4),
                _chip(theme, 'imu $imuOnlyReps', Colors.blueGrey),
                const SizedBox(width: 4),
                _chip(theme, 'cam $poseReps', Colors.teal),
              ],
            ),
            if (cameraEnabled) ...[
              const SizedBox(height: 4),
              Text(
                'IMU zählt — Pose bestätigt optional',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (lastElbowAngle != null) ...[
              const SizedBox(height: 6),
              Text(
                'Ellenbogen: ${lastElbowAngle!.toStringAsFixed(0)}°',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (diagnostic != null && diagnostic!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                diagnostic!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(ThemeData theme, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

/// Maps [RepSource] to a short German label.
String fusionSourceLabel(RepSource source) {
  switch (source) {
    case RepSource.both:
      return 'Beide';
    case RepSource.imuOnly:
      return 'Nur IMU';
    case RepSource.cameraOnly:
      return 'Nur Kamera';
  }
}

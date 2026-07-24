import 'package:flutter/material.dart';

import '../../domain/coaching/rule_coaching.dart';
import '../../domain/metrics/velocity_metrics.dart';
import '../../domain/models/workout_models.dart';
import 'rep_timeline.dart';

/// Session-Zusammenfassung nach „Training beenden" (P0-3).
class SessionSummaryDialog extends StatelessWidget {
  final int totalSets;
  final int totalReps;
  final Duration? duration;
  final VoidCallback onDismiss;

  /// Optional completed sets for VBT / timeline / coaching (Doc 15).
  final List<ExerciseSet>? sets;

  /// Prior history for PR detection (FR-B4).
  final List<WorkoutSession>? priorSessions;

  /// Whether a reps PR was set this session.
  final bool showPrBadge;

  final List<String>? coachingTips;

  const SessionSummaryDialog({
    super.key,
    required this.totalSets,
    required this.totalReps,
    required this.duration,
    required this.onDismiss,
    this.sets,
    this.priorSessions,
    this.showPrBadge = false,
    this.coachingTips,
  });

  @override
  Widget build(BuildContext context) {
    final setList = sets ?? const <ExerciseSet>[];
    double? avgLoss;
    if (setList.isNotEmpty) {
      final losses = setList
          .map((s) => VelocityMetrics.setVelocityLossPct(s.reps))
          .whereType<double>()
          .toList();
      if (losses.isNotEmpty) {
        avgLoss = losses.reduce((a, b) => a + b) / losses.length;
      }
    }
    final tips = coachingTips ??
        (setList.isEmpty
            ? const <String>[]
            : RuleCoaching.tipsForSession(
                WorkoutSession(
                  id: 'summary',
                  startedAt: DateTime.now(),
                  sets: setList,
                ),
              ));

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Training beendet')),
          if (showPrBadge)
            const Chip(
              label: Text('PR'),
              visualDensity: VisualDensity.compact,
              labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatRow(
              icon: Icons.fitness_center,
              label: 'Sätze',
              value: '$totalSets',
            ),
            const SizedBox(height: 8),
            _StatRow(
              icon: Icons.repeat,
              label: 'Wiederholungen (effektiv)',
              value: '$totalReps',
            ),
            if (setList.isNotEmpty) ...[
              const SizedBox(height: 8),
              _StatRow(
                icon: Icons.memory,
                label: 'Engine (roh)',
                value: '${setList.fold<int>(0, (a, s) => a + s.countedReps)}',
              ),
            ],
            if (duration != null) ...[
              const SizedBox(height: 8),
              _StatRow(
                icon: Icons.timer,
                label: 'Dauer',
                value: _formatDuration(duration!),
              ),
            ],
            if (avgLoss != null) ...[
              const SizedBox(height: 8),
              _StatRow(
                icon: Icons.speed,
                label: 'Velocity-Loss (rel.)',
                value: '${avgLoss.toStringAsFixed(0)} %',
              ),
            ],
            for (var i = 0; i < setList.length; i++) ...[
              const SizedBox(height: 12),
              Text(
                'Satz ${i + 1} — '
                'Engine ${setList[i].countedReps}'
                '${setList[i].correctedReps != null ? ' · Korrigiert ${setList[i].correctedReps}' : ''}'
                ' — Peaks',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              RepTimeline(reps: setList[i].reps, height: 40),
              if (VelocityMetrics.setVelocityLossPct(setList[i].reps) != null)
                Text(
                  'Loss ${VelocityMetrics.setVelocityLossPct(setList[i].reps)!.toStringAsFixed(0)} %',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            if (tips.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Hinweise', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              ...tips.take(4).map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $t',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: onDismiss,
          child: const Text('Fertig'),
        ),
      ],
    );
  }

  static String _formatDuration(Duration d) {
    if (d.inMinutes < 1) {
      return '${d.inSeconds} s';
    }
    return '${d.inMinutes} min';
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}

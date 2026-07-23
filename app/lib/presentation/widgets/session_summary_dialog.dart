import 'package:flutter/material.dart';

/// Session-Zusammenfassung nach „Training beenden" (P0-3).
class SessionSummaryDialog extends StatelessWidget {
  final int totalSets;
  final int totalReps;
  final Duration? duration;
  final VoidCallback onDismiss;

  const SessionSummaryDialog({
    super.key,
    required this.totalSets,
    required this.totalReps,
    required this.duration,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Training beendet'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatRow(
            icon: Icons.fitness_center,
            label: 'Sätze',
            value: '$totalSets',
          ),
          const SizedBox(height: 8),
          _StatRow(
            icon: Icons.repeat,
            label: 'Wiederholungen',
            value: '$totalReps',
          ),
          if (duration != null) ...[
            const SizedBox(height: 8),
            _StatRow(
              icon: Icons.timer,
              label: 'Dauer',
              value: _formatDuration(duration!),
            ),
          ],
        ],
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

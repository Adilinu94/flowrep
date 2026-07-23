import 'package:flutter/material.dart';

/// Korrektur-Dialog (SPEC §5.1.4 / P0-1): Nach Satzende kann der Benutzer
/// die gezählten Wiederholungen manuell korrigieren.
///
/// Nachricht: „Danke, das hilft uns die Erkennung zu verbessern."
/// NICHT: „Die KI lernt dazu" (V1 hat kein ML).
class CorrectionDialog extends StatelessWidget {
  final int countedReps;
  final int userReps;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const CorrectionDialog({
    super.key,
    required this.countedReps,
    required this.userReps,
    required this.onIncrement,
    required this.onDecrement,
    required this.onConfirm,
    required this.onDismiss,
  });

  /// Exact copy required by SPEC / DoD — do not change wording.
  static const String thankYouMessage =
      'Danke, das hilft uns die Erkennung zu verbessern.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wasCorrected = userReps != countedReps;

    return AlertDialog(
      title: const Text('Satz abgeschlossen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Gezählt: $countedReps Wiederholungen',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filled(
                onPressed: onDecrement,
                tooltip: 'Eine Wiederholung weniger',
                icon: const Icon(Icons.remove, size: 28),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red.shade100,
                  foregroundColor: Colors.red.shade800,
                ),
              ),
              const SizedBox(width: 24),
              Text(
                '$userReps',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: wasCorrected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 24),
              IconButton.filled(
                onPressed: onIncrement,
                tooltip: 'Eine Wiederholung mehr',
                icon: const Icon(Icons.add, size: 28),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.green.shade100,
                  foregroundColor: Colors.green.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (wasCorrected)
            Text(
              thankYouMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onDismiss,
          child: const Text('Überspringen'),
        ),
        FilledButton(
          onPressed: onConfirm,
          child: Text(wasCorrected ? 'Korrigieren' : 'Bestätigen'),
        ),
      ],
    );
  }
}

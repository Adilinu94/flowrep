import 'package:flutter/material.dart';

/// Onboarding-Banner: Zeigt dem Benutzer die nächsten Schritte,
/// wenn noch keine Kalibrierung vorliegt.
///
/// Schritte: 1) Verbinden → 2) Kalibrieren → 3) Zählen starten
class OnboardingBanner extends StatelessWidget {
  final bool isConnected;
  final bool hasCalibration;
  final VoidCallback? onCalibratePressed;

  const OnboardingBanner({
    super.key,
    required this.isConnected,
    required this.hasCalibration,
    this.onCalibratePressed,
  });

  @override
  Widget build(BuildContext context) {
    // Kein Banner wenn bereits kalibriert
    if (hasCalibration) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final step = !isConnected ? 1 : 2;

    return Card(
      elevation: 2,
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline,
                    color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Text(
                  'Erste Schritte',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StepRow(
              number: 1,
              label: 'Mit Sensor verbinden',
              done: isConnected,
              theme: theme,
            ),
            const SizedBox(height: 8),
            _StepRow(
              number: 2,
              label: 'Übung kalibrieren (5 Reps)',
              done: false,
              theme: theme,
              action: step == 2
                  ? TextButton(
                      onPressed: onCalibratePressed,
                      child: const Text('Jetzt kalibrieren'),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            _StepRow(
              number: 3,
              label: 'Zählen starten & trainieren',
              done: false,
              theme: theme,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int number;
  final String label;
  final bool done;
  final ThemeData theme;
  final Widget? action;

  const _StepRow({
    required this.number,
    required this.label,
    required this.done,
    required this.theme,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: done
              ? Colors.green
              : theme.colorScheme.onSecondaryContainer.withOpacity(0.2),
          child: done
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              decoration: done ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

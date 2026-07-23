import 'package:flutter/material.dart';

/// Pausen-Timer-Widget (SPEC Phase 2, §5.2.1 / P0-2).
///
/// Zeigt einen kreisförmigen Countdown nach Satzende.
/// Der Benutzer kann die Pause überspringen.
class RestTimerWidget extends StatelessWidget {
  final int secondsRemaining;
  final int totalSeconds;
  final VoidCallback onSkip;

  const RestTimerWidget({
    super.key,
    required this.secondsRemaining,
    required this.totalSeconds,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress =
        totalSeconds > 0 ? secondsRemaining / totalSeconds : 0.0;
    final minutes = secondsRemaining ~/ 60;
    final seconds = secondsRemaining % 60;

    return Semantics(
      label:
          'Pausen-Timer: $minutes Minuten $seconds Sekunden verbleibend',
      child: Card(
        elevation: 2,
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Pause',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 100,
                height: 100,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      strokeWidth: 8,
                      backgroundColor:
                          theme.colorScheme.tertiaryContainer,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.tertiary,
                      ),
                    ),
                    Text(
                      '$minutes:${seconds.toString().padLeft(2, '0')}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onSkip,
                child: const Text('Pause überspringen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

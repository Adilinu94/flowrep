import 'package:flutter/material.dart';

/// Expliziter Start-Knopf mit Countdown (Bauplan Phase 2 / Teil 2.B).
///
/// Ersetzt den früheren Direkt-Start: ein Tap löst [onPressed] aus; während
/// [isCountdownActive] zeigt dieses Widget nur noch den Countdown, bis der
/// Aufrufer nach Ablauf selbst den Zählstart auslöst. Nur aktiv, wenn
/// [enabled] (Kalibrierung vorhanden).
class StartCountdownButton extends StatelessWidget {
  final bool enabled;
  final bool isCountdownActive;
  final int secondsRemaining;
  final VoidCallback onPressed;

  const StartCountdownButton({
    super.key,
    required this.enabled,
    required this.isCountdownActive,
    required this.secondsRemaining,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (isCountdownActive) {
      return Semantics(
        liveRegion: true,
        label: 'Start in $secondsRemaining',
        child: Container(
          width: double.infinity,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.green.shade700,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Start in $secondsRemaining…',
            style: const TextStyle(
              fontSize: 18,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: const Icon(Icons.play_circle_outline, size: 28),
        label: const Text('Zählen starten', style: TextStyle(fontSize: 18)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green.shade700,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}

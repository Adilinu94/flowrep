import 'package:flutter/material.dart';

import '../providers/workout_ui_state.dart';

/// Compact gym-glance status: BEREIT / ZÄHLT / GHOST / … (Audit QW-1).
enum CountingStatusKind {
  disconnected,
  connecting,
  reconnecting,
  ready,
  counting,
  ghostPaused,
  resting,
}

class CountingStatusChip extends StatelessWidget {
  final WorkoutUiState uiState;

  const CountingStatusChip({super.key, required this.uiState});

  static CountingStatusKind kindFor(WorkoutUiState s) {
    if (s.isReconnecting) return CountingStatusKind.reconnecting;
    if (s.isConnecting) return CountingStatusKind.connecting;
    if (!s.isConnected) return CountingStatusKind.disconnected;
    if (s.isCountingActive && s.ghostGatePaused && !s.ghostBannerDismissed) {
      return CountingStatusKind.ghostPaused;
    }
    if (s.isCountingActive && s.ghostGatePaused) {
      return CountingStatusKind.ghostPaused;
    }
    if (s.isCountingActive) return CountingStatusKind.counting;
    if (s.isRestTimerActive) return CountingStatusKind.resting;
    if (s.hasCalibration) return CountingStatusKind.ready;
    return CountingStatusKind.ready; // connected, maybe uncalibrated
  }

  @override
  Widget build(BuildContext context) {
    final kind = kindFor(uiState);
    final (label, color, icon) = _visual(kind, uiState);

    return Material(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static (String, Color, IconData) _visual(
    CountingStatusKind kind,
    WorkoutUiState s,
  ) {
    switch (kind) {
      case CountingStatusKind.disconnected:
        return ('GETRENNT', Colors.grey.shade600, Icons.link_off);
      case CountingStatusKind.connecting:
        return ('VERBINDE…', Colors.orange.shade800, Icons.bluetooth_searching);
      case CountingStatusKind.reconnecting:
        return (
          'RECONNECT ${s.reconnectAttempt}',
          Colors.orange.shade800,
          Icons.sync
        );
      case CountingStatusKind.counting:
        return ('ZÄHLT', Colors.green.shade700, Icons.play_circle_filled);
      case CountingStatusKind.ghostPaused:
        return ('PAUSE (GHOST)', Colors.amber.shade900, Icons.pause_circle);
      case CountingStatusKind.resting:
        return ('PAUSE', Colors.blue.shade700, Icons.timer);
      case CountingStatusKind.ready:
        if (!s.hasCalibration) {
          return ('VERBUNDEN', Colors.blueGrey, Icons.bluetooth_connected);
        }
        return ('BEREIT', Colors.teal.shade700, Icons.flag);
    }
  }
}

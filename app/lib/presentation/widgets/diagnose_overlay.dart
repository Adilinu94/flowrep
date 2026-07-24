import 'package:flutter/material.dart';

import '../../domain/workout_engine.dart';
import '../providers/workout_ui_state.dart';

/// FR-B10 developer diagnose panel (envelope, θ, ghost, shadow, BLE).
class DiagnoseOverlay extends StatelessWidget {
  const DiagnoseOverlay({
    super.key,
    required this.uiState,
    required this.engine,
    required this.packetLossHint,
  });

  final WorkoutUiState uiState;
  final WorkoutEngine engine;
  final String? packetLossHint;

  @override
  Widget build(BuildContext context) {
    final shadow = engine.shadowStats;
    final lastShadow =
        engine.shadowReport.lines.isEmpty ? null : engine.shadowReport.lines.last;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: Colors.greenAccent,
          height: 1.35,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'DIAGNOSE (Dev)',
              style: TextStyle(
                color: Colors.cyanAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'env=${engine.diagEnvelope.toStringAsFixed(2)}  '
              '|gP|=${engine.diagGpAbs?.toStringAsFixed(1) ?? "–"}  '
              'θ=${engine.diagGpThreshold?.toStringAsFixed(1) ?? engine.diagEngineSampleCount.toString()}',
            ),
            Text(
              'reps=${uiState.repsInCurrentSet}  samples=${engine.diagEngineSampleCount}  '
              'ghost=${engine.ghostGatePaused ? "PAUSED" : "ok"}',
              style: TextStyle(
                color: engine.ghostGatePaused
                    ? Colors.orangeAccent
                    : Colors.greenAccent,
              ),
            ),
            Text(
              'shadow pipeline L=${shadow.legacyReps} N=${shadow.newReps} '
              'Δ=${shadow.diff}  magShadow=${engine.magnitudeShadowReps}',
            ),
            if (lastShadow != null)
              Text(
                'last shadow ${lastShadow.source} Δ=${lastShadow.delta}',
                style: const TextStyle(color: Colors.white70),
              ),
            if (uiState.mtu != null) ...[
              Text(
                'BLE mtu=${uiState.mtu} batches=${uiState.receivedBatches} '
                'rate=${uiState.pollingRateHz?.toStringAsFixed(1) ?? "–"}Hz '
                'parseErr=${uiState.parseErrors ?? 0}',
              ),
            ],
            if (packetLossHint != null)
              Text(
                packetLossHint!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            if (uiState.batteryPercent != null)
              Text('battery=${uiState.batteryPercent}%'),
          ],
        ),
      ),
    );
  }
}

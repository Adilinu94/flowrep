import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import '../providers/workout_ui_state.dart';

/// Debug-Ansicht für BLE/Engine-Diagnostik (SPEC TEIL 6, §6.3).
///
/// Nur in kDebugMode sichtbar. Zeigt MTU, Batches, Polling-Rate,
/// Engine-Samples, Threshold und Baseline.
class SignalDebugView extends StatelessWidget {
  const SignalDebugView({
    super.key,
    required this.uiState,
    required this.workoutStateName,
  });

  final WorkoutUiState uiState;
  final String workoutStateName;

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (uiState.mtu != null) ...[
            _debugLine('MTU: ${uiState.mtu}'),
            _debugLine('Batches: ${uiState.receivedBatches}'),
            _debugLine(
                'Rate: ${uiState.pollingRateHz?.toStringAsFixed(1) ?? "–"} Hz'),
            _debugLine('Parse-Fehler: ${uiState.parseErrors}'),
            const SizedBox(height: 4),
          ],
          _debugLine(
            'ENG: samples=${uiState.engineSampleCount ?? 0} '
            'state=$workoutStateName '
            'thresh=${(uiState.engineThreshold ?? 0).toStringAsFixed(3)} '
            'base=${(uiState.engineBaseline ?? 0).toStringAsFixed(3)}',
            color: Colors.cyanAccent,
          ),
        ],
      ),
    );
  }

  Widget _debugLine(String text, {Color color = Colors.greenAccent}) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 9,
        fontFamily: 'monospace',
        color: color,
      ),
    );
  }
}

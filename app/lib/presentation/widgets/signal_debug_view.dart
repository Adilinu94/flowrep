import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import '../providers/workout_ui_state.dart';

/// Debug-Ansicht für BLE/Engine-Diagnostik (SPEC TEIL 6, §6.3).
///
/// Nur in debug builds. Collapsed by default (Audit QW-6) so the home
/// screen stays gym-focused; expand for MTU / samples / threshold.
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

    final sampleLine =
        'samples=${uiState.engineSampleCount ?? 0} · $workoutStateName';

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Card(
        color: Colors.grey.shade900,
        margin: const EdgeInsets.only(bottom: 8),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          iconColor: Colors.greenAccent,
          collapsedIconColor: Colors.greenAccent,
          title: Text(
            'Diagnose · $sampleLine',
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: Colors.greenAccent,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (uiState.mtu != null) ...[
                    _debugLine('MTU: ${uiState.mtu}'),
                    _debugLine('Batches: ${uiState.receivedBatches}'),
                    _debugLine(
                      'Rate: ${uiState.pollingRateHz?.toStringAsFixed(1) ?? "–"} Hz',
                    ),
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
            ),
          ],
        ),
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

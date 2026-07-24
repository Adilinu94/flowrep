/// Session/set quality proxy for trust UI (Audit §60d set quality).
///
/// Combines form consistency with stream/sensor health flags.
/// Not a claim of biomechanical "correct form".
library;

import '../models/workout_models.dart';
import 'form_quality.dart';

class SetQualityResult {
  final double score01;
  final String label;
  final List<String> notes;

  const SetQualityResult({
    required this.score01,
    required this.label,
    required this.notes,
  });

  int get percent => (score01 * 100).round();
}

class SetQualityScore {
  SetQualityScore._();

  static SetQualityResult forSet({
    required List<Rep> reps,
    bool packetLossWarned = false,
    bool sensorUnhealthy = false,
    bool ghostPausedDuringSet = false,
  }) {
    final form = FormQuality.setScore(reps);
    // Empty set → low but not zero (user may have cancelled).
    double base = form == null ? 0.45 : (form / 100.0).clamp(0.0, 1.0);
    final notes = <String>[];

    if (form != null) {
      notes.add('Konsistenz ${(form).round()}%');
    } else {
      notes.add('Keine Peaks im Satz');
    }

    if (packetLossWarned) {
      base *= 0.75;
      notes.add('Paketverlust');
    }
    if (sensorUnhealthy) {
      base *= 0.65;
      notes.add('Sensor-Gesundheit');
    }
    if (ghostPausedDuringSet) {
      base *= 0.90;
      notes.add('Ghost-Pause');
    }

    final score = base.clamp(0.0, 1.0);
    final label = score >= 0.8
        ? 'Gut'
        : score >= 0.55
            ? 'Mittel'
            : 'Schwach';
    return SetQualityResult(score01: score, label: label, notes: notes);
  }
}

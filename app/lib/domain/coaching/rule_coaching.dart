import '../metrics/form_quality.dart';
import '../metrics/velocity_metrics.dart';
import '../models/workout_models.dart';

/// Offline rule-based post-session coaching (Doc 15 FR-A7 fallback).
///
/// No network, no "KI lernt" wording — only aggregates already computed.
class RuleCoaching {
  RuleCoaching._();

  static List<String> tipsForSession(WorkoutSession session) {
    final tips = <String>[];
    if (session.sets.isEmpty) {
      return const ['Keine Sätze in dieser Session.'];
    }

    final totalReps =
        session.sets.fold<int>(0, (s, e) => s + e.effectiveReps);
    tips.add('Session: ${session.sets.length} Sätze, $totalReps Wdh. gesamt.');

    for (var i = 0; i < session.sets.length; i++) {
      final set = session.sets[i];
      final loss = VelocityMetrics.setVelocityLossPct(set.reps);
      if (loss != null && loss >= 15) {
        tips.add(
          'Satz ${i + 1}: Velocity-Loss ≈ ${loss.toStringAsFixed(0)} % '
          '(relativ) — Tempo fiel zum Ende ab.',
        );
      }
      final outliers = FormQuality.outlierIndices(set.reps);
      if (outliers.isNotEmpty) {
        final labels = outliers.map((j) => 'R${j + 1}').join(', ');
        tips.add(
          'Satz ${i + 1}: ungleichmäßige Peaks bei $labels '
          '(Konsistenz-Hinweis, kein Form-Urteil).',
        );
      }
      if (set.correctedReps != null &&
          set.correctedReps != set.countedReps) {
        tips.add(
          'Satz ${i + 1}: Korrektur ${set.countedReps}→${set.correctedReps} '
          'gespeichert (System-Count bleibt Trainings-Signal).',
        );
      }
    }

    if (tips.length == 1) {
      tips.add('Gleichmäßige Sätze — kein starker Velocity-Verlust erkannt.');
    }
    return tips;
  }
}

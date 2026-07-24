/// Shadow exercise recognition interface (Doc 15 FR-A4).
///
/// Product never auto-switches exercise from this. UI may show a suggestion.
/// Real TFLite weights are out of scope without multi-subject training data.
abstract class ExerciseClassifier {
  /// Classify a window of IMU samples. Returns suggestion or null.
  Future<ExerciseSuggestion?> classify(ImuWindow window);
}

class ImuWindow {
  /// Interleaved or per-axis samples; length depends on caller.
  final List<double> samples;
  final double sampleRateHz;
  final DateTime endedAt;

  const ImuWindow({
    required this.samples,
    required this.sampleRateHz,
    required this.endedAt,
  });
}

class ExerciseSuggestion {
  final String exerciseId;
  final double confidence;
  final String source; // e.g. 'heuristic', 'tflite'

  const ExerciseSuggestion({
    required this.exerciseId,
    required this.confidence,
    this.source = 'heuristic',
  });
}

/// Heuristic stub: peak rate + mean magnitude → crude curl vs other.
/// Used only as shadow suggestion until a trained model exists.
class HeuristicExerciseClassifier implements ExerciseClassifier {
  @override
  Future<ExerciseSuggestion?> classify(ImuWindow window) async {
    if (window.samples.length < 20) return null;
    var sum = 0.0;
    var peaks = 0;
    for (var i = 1; i < window.samples.length - 1; i++) {
      final v = window.samples[i].abs();
      sum += v;
      if (v > window.samples[i - 1].abs() &&
          v > window.samples[i + 1].abs() &&
          v > 40) {
        peaks++;
      }
    }
    final mean = sum / window.samples.length;
    final durationS = window.samples.length / window.sampleRateHz;
    final rate = durationS > 0 ? peaks / durationS : 0.0;
    // ~0.3–0.8 Hz typical curl cadence in a short window
    if (rate >= 0.25 && rate <= 1.2 && mean > 15) {
      return ExerciseSuggestion(
        exerciseId: 'bicep_curl',
        confidence: (0.55 + (mean / 200).clamp(0.0, 0.35)).clamp(0.0, 0.9),
        source: 'heuristic',
      );
    }
    return null;
  }
}

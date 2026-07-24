import '../models/workout_models.dart';

/// Relative form / consistency score from IMU peaks and timing (Doc 15 FR-A5).
///
/// Labeled as **consistency**, not "correct form". Scores are relative to
/// the set median so they stay user-independent.
class FormQuality {
  FormQuality._();

  /// Per-rep score 0–100 from ROM proxy (peak) vs set median + tempo.
  static List<double> scoresForSet(List<Rep> reps) {
    if (reps.isEmpty) return const [];
    if (reps.length == 1) return const [100.0];

    final peaks = reps.map((r) => r.peakMagnitude).toList();
    final medianPeak = _median(peaks);
    final intervals = <double>[];
    for (var i = 1; i < reps.length; i++) {
      intervals.add(
        reps[i]
            .timestamp
            .difference(reps[i - 1].timestamp)
            .inMilliseconds
            .toDouble(),
      );
    }
    final medianInterval =
        intervals.isEmpty ? 1.0 : _median(intervals).clamp(1.0, 1e9);

    final scores = <double>[];
    for (var i = 0; i < reps.length; i++) {
      final romRatio = medianPeak <= 0
          ? 1.0
          : (peaks[i] / medianPeak).clamp(0.0, 2.0);
      // Peak at median → 1.0; half peak → 0.5
      final romNorm = romRatio > 1.0 ? (2.0 - romRatio).clamp(0.0, 1.0) : romRatio;

      double tempoNorm = 1.0;
      if (i > 0 && intervals.isNotEmpty) {
        final iv = intervals[i - 1];
        final tRatio = (iv / medianInterval).clamp(0.0, 2.0);
        tempoNorm =
            tRatio > 1.0 ? (2.0 - tRatio).clamp(0.0, 1.0) : tRatio.clamp(0.0, 1.0);
      }

      final raw = 0.6 * romNorm + 0.4 * tempoNorm;
      scores.add((raw * 100.0).clamp(0.0, 100.0));
    }
    return scores;
  }

  /// Mean set score (null if empty).
  static double? setScore(List<Rep> reps) {
    final s = scoresForSet(reps);
    if (s.isEmpty) return null;
    return s.reduce((a, b) => a + b) / s.length;
  }

  /// Indices of outlier reps (score &lt; median − 20 or &lt; 50).
  static List<int> outlierIndices(List<Rep> reps) {
    final s = scoresForSet(reps);
    if (s.length < 2) return const [];
    final med = _median(s);
    final out = <int>[];
    for (var i = 0; i < s.length; i++) {
      if (s[i] < 50 || s[i] < med - 20) out.add(i);
    }
    return out;
  }

  static double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }
}

/// Simple personal-record helpers (Doc 15 FR-B4).
class PersonalRecords {
  PersonalRecords._();

  /// Max effective reps in any set of [sessions] for [exerciseId].
  static int? maxRepsForExercise(
    List<WorkoutSession> sessions,
    String exerciseId,
  ) {
    int? best;
    for (final session in sessions) {
      for (final set in session.sets) {
        if (set.exerciseId != exerciseId) continue;
        final r = set.effectiveReps;
        if (best == null || r > best) best = r;
      }
    }
    return best;
  }

  /// True if [set] sets a new max-reps PR vs prior history (excluding this set).
  static bool isRepsPr({
    required ExerciseSet set,
    required List<WorkoutSession> priorSessions,
  }) {
    final prev = maxRepsForExercise(priorSessions, set.exerciseId) ?? 0;
    return set.effectiveReps > prev;
  }

  /// Best peak magnitude seen for exercise.
  static double? maxPeakForExercise(
    List<WorkoutSession> sessions,
    String exerciseId,
  ) {
    double? best;
    for (final session in sessions) {
      for (final set in session.sets) {
        if (set.exerciseId != exerciseId) continue;
        for (final rep in set.reps) {
          if (best == null || rep.peakMagnitude > best) {
            best = rep.peakMagnitude;
          }
        }
      }
    }
    return best;
  }
}

/// Local correction analytics (Doc 15 FR-B13).
class CorrectionAnalytics {
  CorrectionAnalytics._();

  /// system − user; positive = over-count.
  static int delta(CorrectionEvent e) => e.systemCount - e.userCorrectedCount;

  static Map<String, CorrectionStats> bySetId(List<CorrectionEvent> events) {
    final map = <String, CorrectionStats>{};
    for (final e in events) {
      final d = delta(e);
      final prev = map[e.setId] ?? const CorrectionStats();
      map[e.setId] = CorrectionStats(
        count: prev.count + 1,
        overCountSum: prev.overCountSum + (d > 0 ? d : 0),
        underCountSum: prev.underCountSum + (d < 0 ? -d : 0),
      );
    }
    return map;
  }

  static CorrectionStats aggregate(List<CorrectionEvent> events) {
    var over = 0;
    var under = 0;
    for (final e in events) {
      final d = delta(e);
      if (d > 0) over += d;
      if (d < 0) under += -d;
    }
    return CorrectionStats(
      count: events.length,
      overCountSum: over,
      underCountSum: under,
    );
  }
}

class CorrectionStats {
  final int count;
  final int overCountSum;
  final int underCountSum;

  const CorrectionStats({
    this.count = 0,
    this.overCountSum = 0,
    this.underCountSum = 0,
  });
}

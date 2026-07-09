/// Domain models for FlowRep.
/// Pure Dart, no Flutter or database framework dependency, per the
/// Datenbank-Agnostizismus principle in GYM_TRACKER_ARCHITEKTUR.md (Abschnitt 1.1).
library;

class Rep {
  final DateTime timestamp;
  final double peakMagnitude;

  const Rep({required this.timestamp, required this.peakMagnitude});

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'peakMagnitude': peakMagnitude,
      };

  factory Rep.fromJson(Map<String, dynamic> json) => Rep(
        timestamp: DateTime.parse(json['timestamp'] as String),
        peakMagnitude: (json['peakMagnitude'] as num).toDouble(),
      );
}

class ExerciseSet {
  final String id;
  final String exerciseId;
  final int countedReps;
  final int? correctedReps;
  final DateTime endedAt;
  final List<Rep> reps;

  const ExerciseSet({
    required this.id,
    required this.exerciseId,
    required this.countedReps,
    required this.endedAt,
    required this.reps,
    this.correctedReps,
  });

  /// The value that should be shown/used downstream: the corrected count
  /// if a correction exists, otherwise the system count.
  int get effectiveReps => correctedReps ?? countedReps;

  ExerciseSet copyWith({int? correctedReps}) => ExerciseSet(
        id: id,
        exerciseId: exerciseId,
        countedReps: countedReps,
        endedAt: endedAt,
        reps: reps,
        correctedReps: correctedReps ?? this.correctedReps,
      );
}

class WorkoutSession {
  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<ExerciseSet> sets;

  const WorkoutSession({
    required this.id,
    required this.startedAt,
    required this.sets,
    this.endedAt,
  });

  WorkoutSession copyWith({DateTime? endedAt, List<ExerciseSet>? sets}) =>
      WorkoutSession(
        id: id,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        sets: sets ?? this.sets,
      );
}

/// Every manual correction is stored as its own event, never as an
/// overwrite of ExerciseSet.countedReps — the original system count must
/// survive, since it is the training signal for later ML stages
/// (siehe Architekturdokument, Abschnitt 5.5.3 / 08_DATENMODELL_REFERENZ.md).
class CorrectionEvent {
  final String id;
  final String setId;
  final int systemCount;
  final int userCorrectedCount;
  final DateTime timestamp;

  const CorrectionEvent({
    required this.id,
    required this.setId,
    required this.systemCount,
    required this.userCorrectedCount,
    required this.timestamp,
  });
}

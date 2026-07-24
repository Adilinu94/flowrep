/// Optional per-exercise targets (Doc 15 FR-B9). In-memory / session prefs.
class ExerciseTargets {
  ExerciseTargets({Map<String, ExerciseTarget>? initial})
      : _map = Map<String, ExerciseTarget>.from(initial ?? const {});

  final Map<String, ExerciseTarget> _map;

  ExerciseTarget? of(String exerciseId) => _map[exerciseId];

  void set(String exerciseId, {required int sets, required int reps}) {
    _map[exerciseId] = ExerciseTarget(targetSets: sets, targetReps: reps);
  }

  void clear(String exerciseId) => _map.remove(exerciseId);

  Map<String, ExerciseTarget> get all => Map.unmodifiable(_map);
}

class ExerciseTarget {
  final int targetSets;
  final int targetReps;

  const ExerciseTarget({required this.targetSets, required this.targetReps});
}

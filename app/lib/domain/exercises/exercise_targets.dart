/// Optional per-exercise targets (Doc 15 FR-B9).
///
/// Runtime map; persistence is handled by [UserPrefsStore] (JSON map).
class ExerciseTargets {
  ExerciseTargets({Map<String, ExerciseTarget>? initial})
      : _map = Map<String, ExerciseTarget>.from(initial ?? const {});

  final Map<String, ExerciseTarget> _map;

  ExerciseTarget? of(String exerciseId) => _map[exerciseId];

  void set(String exerciseId, {required int sets, required int reps}) {
    _map[exerciseId] = ExerciseTarget(targetSets: sets, targetReps: reps);
  }

  void clear(String exerciseId) => _map.remove(exerciseId);

  /// Replace all entries (e.g. after prefs load). Clears previous map.
  void replaceAll(Map<String, ExerciseTarget> next) {
    _map
      ..clear()
      ..addAll(next);
  }

  Map<String, ExerciseTarget> get all => Map.unmodifiable(_map);

  /// JSON-safe map for prefs: `{exerciseId: {sets, reps}}`.
  Map<String, dynamic> toJson() => {
        for (final e in _map.entries)
          e.key: {
            'sets': e.value.targetSets,
            'reps': e.value.targetReps,
          },
      };

  /// Parse prefs JSON; invalid entries skipped.
  static Map<String, ExerciseTarget> mapFromJson(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, ExerciseTarget>{};
    raw.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final sets = value['sets'];
      final reps = value['reps'];
      final s = sets is int ? sets : int.tryParse('$sets');
      final r = reps is int ? reps : int.tryParse('$reps');
      if (s == null || r == null || s < 1 || r < 1) return;
      out[key] = ExerciseTarget(targetSets: s, targetReps: r);
    });
    return out;
  }
}

class ExerciseTarget {
  final int targetSets;
  final int targetReps;

  const ExerciseTarget({required this.targetSets, required this.targetReps});
}

/// One entry in the app's exercise list (2026-07-22, Adi: Uebungsauswahl).
///
/// Each exercise gets its own, completely independent, persisted
/// [ExerciseProfile] (see CalibrationStore.loadProfile/saveProfile, both
/// keyed by exerciseId) - running the calibration wizard for one exercise
/// (e.g. Bizeps Curls) never touches another exercise's profile (e.g.
/// Latzug). [HomeScreen] is already parametrized by exerciseId/
/// exerciseDisplayName specifically so this falls out of the existing
/// per-exercise persistence for free, without any new storage code.
class ExerciseDefinition {
  const ExerciseDefinition({required this.id, required this.displayName});

  /// Stable key - used as CalibrationStore's exerciseId and
  /// WorkoutEngine.exerciseId. Never change an existing id once shipped;
  /// that would orphan any already-persisted profile/recordings for it.
  final String id;

  /// What the user sees on the selection screen and the workout screen's
  /// app bar.
  final String displayName;
}

/// To add a new exercise: add an entry here. Nothing else needs to
/// change - ExerciseSelectionScreen renders this list, and HomeScreen
/// already loads/saves a profile per exerciseId.
const List<ExerciseDefinition> kSupportedExercises = [
  ExerciseDefinition(id: 'bicep_curl', displayName: 'Bizeps Curls'),
];

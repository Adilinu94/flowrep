import '../models/workout_models.dart';

/// Abstraction boundary between domain logic and whatever concrete database
/// is used. No file outside a concrete implementation (e.g. DriftWorkoutRepository)
/// may import a database-specific package. See ADR-006 and
/// 08_DATENMODELL_REFERENZ.md for the reasoning (Isar -> Drift decision).
abstract class IWorkoutRepository {
  Future<void> saveSession(WorkoutSession session);
  Future<List<WorkoutSession>> getHistory();
  Future<void> saveCorrection(CorrectionEvent event);

  /// DSGVO-Löschrecht (ADR-010). Must delete every locally stored trace of
  /// the user's data, not just session metadata.
  Future<void> deleteAllUserData();
}

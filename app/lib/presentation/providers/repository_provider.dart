import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/drift_database.dart';
import '../../domain/repositories/i_workout_repository.dart';

/// Riverpod-Provider für das Workout-Repository (SPEC Phase 5.2).
///
/// Singleton: eine DB-Instanz für die gesamte App-Lebensdauer.
final workoutRepositoryProvider = Provider<IWorkoutRepository>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return DriftWorkoutRepository(db);
});

// Drift schema + repository implementation. This is the ONLY file in the
// project allowed to import package:drift - see ADR-006 and
// 08_DATENMODELL_REFERENZ.md ("kein Code außerhalb der konkreten
// Implementierungsklasse darf einen datenbankspezifischen Import
// enthalten").
//
// NOT verified: this project's sandbox has no Dart/Flutter toolchain, so
// the build_runner code generation step (`dart run build_runner build`)
// that normally produces `drift_database.g.dart` has not been run. Running
// that command is the literal first step to take once a real Flutter
// environment is available (see docs/GYM_TRACKER_ARCHITEKTUR.md Phase 1).

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/workout_models.dart' as domain;
import '../../domain/repositories/i_workout_repository.dart';

part 'drift_database.g.dart';

// @DataClassName on all four tables below (2026-07-19 fix for the 6
// "return_of_invalid_type"/"undefined_getter" flutter analyze errors in
// drift_database.g.dart): Drift derives a table's auto-generated data
// class name by singularizing the TABLE class name - "WorkoutSessions"
// (table) -> "WorkoutSession" (auto data class) - which collides with
// the UNRELATED domain model class of the same singular name in
// domain/models/workout_models.dart (imported here as `domain`, and
// consistently used AS `domain.WorkoutSession` etc. throughout this
// file's hand-written repository code below - that part was already
// correct; the collision was specifically in Drift's OWN generated
// code, which has no knowledge of that import alias and generates the
// bare, unprefixed name it derives from the table class). Giving each
// table's generated row/data class an explicit, distinct name removes
// the collision at its source instead of working around it downstream.
// No other change needed in this file: every drift-row usage below is
// through type inference (`final rows = await _db.select(...).get();`),
// never a bare, unqualified type annotation.
@DataClassName('WorkoutSessionRow')
class WorkoutSessions extends Table {
  TextColumn get id => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ExerciseSetRow')
class ExerciseSets extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(WorkoutSessions, #id)();
  TextColumn get exerciseId => text()();
  IntColumn get countedReps => integer()();
  IntColumn get correctedReps => integer().nullable()();
  DateTimeColumn get endedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RepRow')
class Reps extends Table {
  TextColumn get setId => text().references(ExerciseSets, #id)();
  DateTimeColumn get timestamp => dateTime()();
  RealColumn get peakMagnitude => real()();
}

@DataClassName('CorrectionEventRow')
class CorrectionEvents extends Table {
  TextColumn get id => text()();
  TextColumn get setId => text().references(ExerciseSets, #id)();
  IntColumn get systemCount => integer()();
  IntColumn get userCorrectedCount => integer()();
  DateTimeColumn get timestamp => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [WorkoutSessions, ExerciseSets, Reps, CorrectionEvents])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'flowrep.sqlite'));
      // TODO once real toolchain available: wrap with SQLCipher
      // (sqlcipher_flutter_libs) per GYM_TRACKER_ARCHITEKTUR.md
      // Abschnitt 5.2.3 "Lokale Verschlüsselung" - not yet wired up here.
      return NativeDatabase.createInBackground(file);
    });
  }
}

class DriftWorkoutRepository implements IWorkoutRepository {
  DriftWorkoutRepository(this._db);
  final AppDatabase _db;

  @override
  Future<void> saveSession(domain.WorkoutSession session) async {
    await _db.into(_db.workoutSessions).insertOnConflictUpdate(
          WorkoutSessionsCompanion.insert(
            id: session.id,
            startedAt: session.startedAt,
            endedAt: Value(session.endedAt),
          ),
        );
    for (final set in session.sets) {
      await _db.into(_db.exerciseSets).insertOnConflictUpdate(
            ExerciseSetsCompanion.insert(
              id: set.id,
              sessionId: session.id,
              exerciseId: set.exerciseId,
              countedReps: set.countedReps,
              correctedReps: Value(set.correctedReps),
              endedAt: set.endedAt,
            ),
          );
      for (final rep in set.reps) {
        await _db.into(_db.reps).insert(
              RepsCompanion.insert(
                setId: set.id,
                timestamp: rep.timestamp,
                peakMagnitude: rep.peakMagnitude,
              ),
            );
      }
    }
  }

  @override
  Future<List<domain.WorkoutSession>> getHistory() async {
    final sessionRows = await _db.select(_db.workoutSessions).get();
    final result = <domain.WorkoutSession>[];
    for (final row in sessionRows) {
      final setRows = await (_db.select(_db.exerciseSets)
            ..where((t) => t.sessionId.equals(row.id)))
          .get();
      final sets = <domain.ExerciseSet>[];
      for (final setRow in setRows) {
        final repRows = await (_db.select(_db.reps)
              ..where((t) => t.setId.equals(setRow.id)))
            .get();
        sets.add(domain.ExerciseSet(
          id: setRow.id,
          exerciseId: setRow.exerciseId,
          countedReps: setRow.countedReps,
          correctedReps: setRow.correctedReps,
          endedAt: setRow.endedAt,
          reps: repRows
              .map((r) => domain.Rep(timestamp: r.timestamp, peakMagnitude: r.peakMagnitude))
              .toList(),
        ));
      }
      result.add(domain.WorkoutSession(
        id: row.id,
        startedAt: row.startedAt,
        endedAt: row.endedAt,
        sets: sets,
      ));
    }
    return result;
  }

  @override
  Future<void> saveCorrection(domain.CorrectionEvent event) async {
    await _db.into(_db.correctionEvents).insert(
          CorrectionEventsCompanion.insert(
            id: event.id,
            setId: event.setId,
            systemCount: event.systemCount,
            userCorrectedCount: event.userCorrectedCount,
            timestamp: event.timestamp,
          ),
        );
    await (_db.update(_db.exerciseSets)..where((t) => t.id.equals(event.setId)))
        .write(ExerciseSetsCompanion(correctedReps: Value(event.userCorrectedCount)));
  }

  @override
  Future<void> deleteAllUserData() async {
    // ADR-010 / DSGVO-Löschrecht: must clear every table, not just sessions.
    await _db.delete(_db.correctionEvents).go();
    await _db.delete(_db.reps).go();
    await _db.delete(_db.exerciseSets).go();
    await _db.delete(_db.workoutSessions).go();
  }
}

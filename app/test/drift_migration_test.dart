// Tests für die Drift-Schema-Migration v1 -> v2 (weightKg-Spalte auf
// ExerciseSets, Bauplan Phase 3) und für den Repository-Round-Trip.
//
// NOT run in this sandbox: kein Dart/Flutter-Toolchain verfügbar (gleiche
// Lücke wie bei drift_encryption_migration_test.dart). Sorgfältig gegen
// die echte Tabellendefinition in drift_database.dart geschrieben, aber
// bitte vor Vertrauen mit echtem `flutter test` laufen lassen.
//
// Der fragilste Teil ist das von Hand nachgebaute v1-Rohschema in
// _createV1Database() weiter unten - Tabellen-/Spaltennamen sind Driftes
// snake_case-Standardkonvention aus den Dart-Klassennamen abgeleitet und
// DateTime wird als INTEGER (Unix-Millis) angenommen, da drift_database.dart
// keine `storeDateTimeAsText`-Option setzt. Schlägt der Migrationstest schon
// beim ÖFFNEN fehl (nicht erst bei den expect()s), zeigt das am ehesten auf
// eine falsche Rohschema-Annahme hier, nicht auf einen Fehler in der
// migration-Strategie in drift_database.dart selbst.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3pkg;

import 'package:flowrep/data/repositories/drift_database.dart';
import 'package:flowrep/domain/models/workout_models.dart' as domain;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('flowrep_schema_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('Repository-Round-Trip (frisches Schema)', () {
    test('weightKg wird gespeichert und wieder ausgelesen', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = DriftWorkoutRepository(db);
      final session = domain.WorkoutSession(
        id: 'sess-1',
        startedAt: DateTime(2026, 8, 2, 10),
        endedAt: DateTime(2026, 8, 2, 10, 5),
        sets: [
          domain.ExerciseSet(
            id: 'set-1',
            exerciseId: 'hs_row',
            countedReps: 12,
            endedAt: DateTime(2026, 8, 2, 10, 3),
            reps: const [],
            weightKg: 27.5,
          ),
        ],
      );

      await repo.saveSession(session);
      final history = await repo.getHistory();

      expect(history, hasLength(1));
      expect(history.single.sets.single.weightKg, 27.5);
      await db.close();
    });

    test('weightKg bleibt null, wenn nicht gesetzt (z. B. Bodyweight)',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = DriftWorkoutRepository(db);
      final session = domain.WorkoutSession(
        id: 'sess-2',
        startedAt: DateTime(2026, 8, 2, 10),
        endedAt: DateTime(2026, 8, 2, 10, 5),
        sets: [
          domain.ExerciseSet(
            id: 'set-2',
            exerciseId: 'bicep_curl',
            countedReps: 10,
            endedAt: DateTime(2026, 8, 2, 10, 3),
            reps: const [],
          ),
        ],
      );

      await repo.saveSession(session);
      final history = await repo.getHistory();

      expect(history.single.sets.single.weightKg, isNull);
      await db.close();
    });
  });

  group('Schema-Migration v1 -> v2', () {
    test('bestehende Zeilen bleiben erhalten, weightKg ist dort null',
        () async {
      final dbFile = File(p.join(tempDir.path, 'v1.sqlite'));
      _createV1DatabaseWithData(dbFile);

      // Öffnen mit der echten AppDatabase (schemaVersion 2) - Drift sieht
      // PRAGMA user_version=1 in der Datei, schemaVersion=2 im Code, und
      // ruft automatisch migration.onUpgrade(m, 1, 2) auf.
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      final repo = DriftWorkoutRepository(db);
      final history = await repo.getHistory();

      expect(history, hasLength(1));
      final set = history.single.sets.single;
      expect(set.id, 'set-v1');
      expect(set.countedReps, 9);
      expect(set.weightKg, isNull,
          reason: 'v1-Zeilen hatten kein Gewicht - addColumn muss NULL '
              'auffüllen, nicht z. B. 0.0');
      await db.close();
    });
  });
}

/// Baut eine sqlite3-Datei von Hand exakt nach dem v1-Schema (VOR der
/// weightKg-Spalte) und befüllt sie mit einer Test-Session/einem Test-Satz.
/// Nutzt bewusst rohes SQL statt AppDatabase, weil AppDatabase im aktuellen
/// Code-Stand nur noch das NEUE Schema (v2) kennt - das alte Schema muss
/// deshalb manuell nachgebaut werden, um die Migration überhaupt auslösen
/// zu können.
void _createV1DatabaseWithData(File dbFile) {
  final raw = sqlite3pkg.sqlite3.open(dbFile.path);
  raw.execute('PRAGMA user_version = 1;');
  raw.execute('''
    CREATE TABLE workout_sessions (
      id TEXT NOT NULL PRIMARY KEY,
      started_at INTEGER NOT NULL,
      ended_at INTEGER NULL
    );
  ''');
  raw.execute('''
    CREATE TABLE exercise_sets (
      id TEXT NOT NULL PRIMARY KEY,
      session_id TEXT NOT NULL REFERENCES workout_sessions (id),
      exercise_id TEXT NOT NULL,
      counted_reps INTEGER NOT NULL,
      corrected_reps INTEGER NULL,
      ended_at INTEGER NOT NULL
    );
  ''');
  raw.execute('''
    CREATE TABLE reps (
      set_id TEXT NOT NULL REFERENCES exercise_sets (id),
      "timestamp" INTEGER NOT NULL,
      peak_magnitude REAL NOT NULL
    );
  ''');
  raw.execute('''
    CREATE TABLE correction_events (
      id TEXT NOT NULL PRIMARY KEY,
      set_id TEXT NOT NULL REFERENCES exercise_sets (id),
      system_count INTEGER NOT NULL,
      user_corrected_count INTEGER NOT NULL,
      "timestamp" INTEGER NOT NULL
    );
  ''');

  final startedAt = DateTime(2026, 7, 1, 9).millisecondsSinceEpoch;
  final endedAt = DateTime(2026, 7, 1, 9, 10).millisecondsSinceEpoch;
  raw.execute(
    'INSERT INTO workout_sessions VALUES (?, ?, ?);',
    ['session-v1', startedAt, endedAt],
  );
  raw.execute(
    'INSERT INTO exercise_sets VALUES (?, ?, ?, ?, ?, ?);',
    ['set-v1', 'session-v1', 'bicep_curl', 9, null, endedAt],
  );
  raw.close();
}

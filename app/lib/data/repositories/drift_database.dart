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
//
// ENCRYPTION (GYM_TRACKER_ARCHITEKTUR.md §5.2.3 "Lokale Verschlüsselung",
// added 2026-07-19): the architecture doc and this file's own prior TODO
// comment both named `sqlcipher_flutter_libs` as the intended package.
// Checked current status before implementing rather than following that
// stale reference blindly: `sqlcipher_flutter_libs`'s own changelog now
// reads "Deprecate this package... This version removes all code from
// this package" - it would resolve to an empty no-op if depended on today.
// Drift's own current encryption docs (drift.simonbinder.eu/platforms/
// encryption, confirmed via live fetch this session) now recommend
// SQLite3MultipleCiphers instead, available from drift >=2.32.0 via a
// `sqlite3` package build-hook config in pubspec.yaml (`hooks:
// user_defines: sqlite3: source: sqlite3mc`) - no extra native-libs
// package needed. That is what's implemented below. `drift`/`drift_dev`
// bumped 2.20.0 -> ^2.32.0 in pubspec.yaml accordingly.
//
// NOT independently verifiable here: whether the pubspec `hooks:` build-hook
// mechanism itself actually resolves and links SQLite3MultipleCiphers
// correctly requires a real `flutter pub get` + build - unavailable in this
// sandbox (same toolchain gap as above). This is the single least-verified
// part of this change; see the migration/rekey logic below for the other
// genuinely risky piece (existing unencrypted user data).

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3pkg;

import '../../domain/models/workout_models.dart' as domain;
import '../../domain/repositories/i_workout_repository.dart';
import '../security/database_key_manager.dart';

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
  AppDatabase({DatabaseKeyManager? keyManager})
      : super(_openConnection(keyManager ?? DatabaseKeyManager()));

  @override
  int get schemaVersion => 1;

  /// Opens the (now always encrypted) database, migrating an existing
  /// plaintext `flowrep.sqlite` in place on first run after this change.
  ///
  /// Migration design (deliberately more conservative than Drift's own
  /// documented example - see the header comment above for why this
  /// couldn't be verified end-to-end):
  ///  1. A marker file (`flowrep.sqlite.encrypted-v1`) means "already
  ///     migrated / already a fresh encrypted install" - skip everything
  ///     below and just open normally. Checking for a marker file is a
  ///     simple boolean file-existence check, not an attempt to introspect
  ///     SQLCipher/SQLite3MultipleCiphers file-format internals to guess
  ///     whether a given .sqlite file is already encrypted.
  ///  2. No marker, but `flowrep.sqlite` exists: treat it as the old
  ///     plaintext database. `VACUUM INTO` a `.migrating.tmp` copy (leaves
  ///     the original untouched so far), open that copy and `PRAGMA
  ///     rekey` it to encrypt in place - this is Drift's own documented
  ///     pattern (drift.simonbinder.eu/platforms/encryption
  ///     #encrypting-existing-databases), followed closely rather than
  ///     improvised.
  ///  3. Deliberate deviation from that example: instead of deleting the
  ///     original plaintext file once the encrypted copy exists (as
  ///     Drift's example does), RENAME it to `flowrep.sqlite.pre-
  ///     encryption-backup` and keep it. This step cannot be tested end to
  ///     end in this sandbox (no Dart/Flutter toolchain - see header), so
  ///     erring toward "keep a recoverable copy" over "delete on first
  ///     success" until a real run has actually confirmed the migrated,
  ///     encrypted database opens and reads correctly. Deleting that
  ///     backup once confirmed is a manual follow-up, not automated here.
  ///  4. No marker, no existing file: fresh install, nothing to migrate -
  ///     the marker is still written so future launches skip this check.
  static LazyDatabase _openConnection(DatabaseKeyManager keyManager) {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(dir.path, 'flowrep.sqlite'));
      final markerFile = File('${dbFile.path}.encrypted-v1');
      final keyHex = await keyManager.getOrCreateKeyHex();

      await migrateToEncryptedIfNeeded(
        dbFile: dbFile,
        markerFile: markerFile,
        keyHex: keyHex,
      );

      return NativeDatabase.createInBackground(
        dbFile,
        setup: (rawDb) {
          assert(
            rawDb.select('PRAGMA cipher;').isNotEmpty,
            'SQLite3MultipleCiphers not available - encryption support is '
            'missing from this build. See drift_database.dart header '
            'comment (pubspec hooks: user_defines: sqlite3: source: '
            'sqlite3mc).',
          );
          rawDb.execute(DatabaseKeyManager.pragmaKeyStatement(keyHex));
        },
      );
    });
  }

  /// The migration steps 1-4 from the doc comment above, extracted into a
  /// pure, standalone, `await`-able function of plain [File]s and a key -
  /// no [LazyDatabase] closure, no `getApplicationDocumentsDirectory()`.
  /// Behaviourally identical to what was previously inlined directly in
  /// [_openConnection] (2026-07-20: extracted specifically so this - the
  /// single riskiest, previously untested piece of this whole feature -
  /// could get a real test with real temp files and real sqlite3, without
  /// needing to mock Flutter's path_provider platform channel for
  /// something that never actually needed it. See
  /// test/drift_encryption_migration_test.dart.
  static Future<void> migrateToEncryptedIfNeeded({
    required File dbFile,
    required File markerFile,
    required String keyHex,
  }) async {
    if (await markerFile.exists()) return;
    if (await dbFile.exists()) {
      final tmp = File('${dbFile.path}.migrating.tmp');
      if (await tmp.exists()) {
        await tmp.delete();
      }

      final plaintextDb = sqlite3pkg.sqlite3.open(dbFile.path);
      try {
        plaintextDb.execute(
          "VACUUM INTO '${_escapeSqlString(tmp.path)}';",
        );
      } finally {
        plaintextDb.close();
      }

      final encryptingDb = sqlite3pkg.sqlite3.open(tmp.path);
      try {
        encryptingDb.execute(
          "PRAGMA rekey = '${_escapeSqlString(keyHex)}';",
        );
        // Confirms the rekeyed file is actually readable with this key
        // before we touch the original - if this throws, the original
        // plaintext file is left completely untouched below.
        encryptingDb.select('SELECT count(*) FROM sqlite_master;');
      } finally {
        encryptingDb.close();
      }

      final backup = File('${dbFile.path}.pre-encryption-backup');
      if (await backup.exists()) {
        await backup.delete();
      }
      await dbFile.rename(backup.path);
      await tmp.rename(dbFile.path);
    }
    await markerFile.create();
  }

  static String _escapeSqlString(String value) => value.replaceAll("'", "''");
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

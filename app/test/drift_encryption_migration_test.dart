// Tests for AppDatabase.migrateToEncryptedIfNeeded (drift_database.dart) -
// the pure, standalone function extracted specifically for this (see that
// file's doc comment on the method, and its header comment on why this is
// "the single riskiest, previously untested piece" of the encryption
// feature: migrating a real, populated plaintext database, not an empty
// one). Operates on real temp files and the real sqlite3 package - no
// Flutter platform channels involved, so no mocking needed.
//
// NOT run in this sandbox: no Dart/Flutter toolchain available here (same
// gap noted throughout this project's other test files and doc comments).
// Written and reviewed carefully line-by-line against the actual
// migrateToEncryptedIfNeeded implementation, but please run `flutter test`
// for real before trusting it. If the "opening without a key must fail"
// assertion below is the one that fails, that specifically points at the
// pubspec `hooks:` SQLite3MultipleCiphers build-hook not actually being
// linked (see drift_database.dart header) - not at this migration logic
// being wrong.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3pkg;

import 'package:flowrep/data/repositories/drift_database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late File markerFile;
  late File tmpFile;
  late File backupFile;

  const keyHex =
      'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('flowrep_migration_test_');
    dbFile = File(p.join(tempDir.path, 'flowrep.sqlite'));
    markerFile = File('${dbFile.path}.encrypted-v1');
    tmpFile = File('${dbFile.path}.migrating.tmp');
    backupFile = File('${dbFile.path}.pre-encryption-backup');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// A real, populated plaintext sqlite3 database at [dbFile] - not an
  /// empty file. Schema is intentionally generic (not the actual Drift
  /// schema) since migration works at the raw sqlite3 file level and
  /// doesn't care what tables exist.
  void createPlaintextDbWithData() {
    final db = sqlite3pkg.sqlite3.open(dbFile.path);
    db.execute(
      'CREATE TABLE workout_sessions (id TEXT PRIMARY KEY, started_at TEXT);',
    );
    db.execute("INSERT INTO workout_sessions VALUES ('s1', '2026-07-21');");
    db.execute("INSERT INTO workout_sessions VALUES ('s2', '2026-07-22');");
    db.close();
  }

  Future<void> migrate() => AppDatabase.migrateToEncryptedIfNeeded(
        dbFile: dbFile,
        markerFile: markerFile,
        keyHex: keyHex,
      );

  group('fresh install (no existing dbFile)', () {
    test('creates the marker and leaves no db file behind', () async {
      await migrate();

      expect(markerFile.existsSync(), isTrue);
      expect(dbFile.existsSync(), isFalse);
      expect(tmpFile.existsSync(), isFalse);
      expect(backupFile.existsSync(), isFalse);
    });
  });

  group('marker already present', () {
    test('is a no-op, even if a plaintext dbFile also exists', () async {
      createPlaintextDbWithData();
      await markerFile.create();
      final originalBytes = await dbFile.readAsBytes();

      await migrate();

      expect(await dbFile.readAsBytes(), originalBytes);
      expect(backupFile.existsSync(), isFalse);
      expect(tmpFile.existsSync(), isFalse);
    });
  });

  group('existing plaintext db, no marker (the real migration case)', () {
    test(
        'encrypts the db in place, keeps a readable plaintext backup, and '
        'preserves all data', () async {
      createPlaintextDbWithData();

      await migrate();

      expect(markerFile.existsSync(), isTrue);
      expect(tmpFile.existsSync(), isFalse);

      // Proof this is genuinely encrypted, not just a silent PRAGMA rekey
      // no-op: opening the same file WITHOUT the key must fail. Without
      // this check, an unencrypted file would pass the "readable WITH the
      // key" assertion below too (a key is harmless to supply against a
      // plain db), and the whole test would give false confidence.
      expect(
        () {
          final noKey = sqlite3pkg.sqlite3.open(dbFile.path);
          try {
            noKey.select('SELECT * FROM sqlite_master;');
          } finally {
            noKey.close();
          }
        },
        throwsA(anything),
      );

      // Readable WITH the key, and the data survived the round-trip.
      final encrypted = sqlite3pkg.sqlite3.open(dbFile.path);
      encrypted.execute("PRAGMA key = '$keyHex';");
      final rows = encrypted
          .select('SELECT id, started_at FROM workout_sessions ORDER BY id;');
      encrypted.close();
      expect(rows.map((r) => r['id']), ['s1', 's2']);
      expect(rows.map((r) => r['started_at']), ['2026-07-21', '2026-07-22']);

      // The pre-encryption backup is still the original, unencrypted file.
      expect(backupFile.existsSync(), isTrue);
      final plain = sqlite3pkg.sqlite3.open(backupFile.path);
      final backupRows = plain.select('SELECT id FROM workout_sessions ORDER BY id;');
      plain.close();
      expect(backupRows.map((r) => r['id']), ['s1', 's2']);
    });
  });

  group('idempotency', () {
    test('a second call after a successful migration is a no-op', () async {
      createPlaintextDbWithData();
      await migrate();
      final encryptedBytesAfterFirstRun = await dbFile.readAsBytes();
      final backupBytesAfterFirstRun = await backupFile.readAsBytes();

      await migrate();

      expect(await dbFile.readAsBytes(), encryptedBytesAfterFirstRun);
      expect(await backupFile.readAsBytes(), backupBytesAfterFirstRun);
    });
  });

  group('leftover files from a previous interrupted run', () {
    test('an old .migrating.tmp file does not block a fresh migration',
        () async {
      createPlaintextDbWithData();
      await tmpFile.writeAsString('stale leftover from a crashed attempt');

      await migrate();

      expect(markerFile.existsSync(), isTrue);
      // Whether sqlite3's VACUUM INTO itself overwrites vs. requires a
      // clean target isn't the point here - the code deletes any existing
      // tmp file upfront specifically so this can never block. What
      // matters is the end state: migration still completes and the final
      // dbFile is the real encrypted result, not stale leftover content.
      final encrypted = sqlite3pkg.sqlite3.open(dbFile.path);
      encrypted.execute("PRAGMA key = '$keyHex';");
      final rows = encrypted.select('SELECT id FROM workout_sessions ORDER BY id;');
      encrypted.close();
      expect(rows.map((r) => r['id']), ['s1', 's2']);
    });

    test(
        'an old .pre-encryption-backup file is replaced, not left blocking '
        'the rename', () async {
      createPlaintextDbWithData();
      await backupFile.writeAsString('stale backup from an earlier attempt');

      await migrate();

      expect(markerFile.existsSync(), isTrue);
      // The backup now holds THIS run's original plaintext data, not the
      // stale placeholder content written above.
      final plain = sqlite3pkg.sqlite3.open(backupFile.path);
      final rows = plain.select('SELECT id FROM workout_sessions ORDER BY id;');
      plain.close();
      expect(rows.map((r) => r['id']), ['s1', 's2']);
    });
  });

  group('failure safety', () {
    test(
        'a corrupt/unreadable dbFile throws and leaves the original '
        'untouched with no marker', () async {
      await dbFile.writeAsBytes([0, 1, 2, 3, 4]); // not a valid sqlite file

      await expectLater(migrate(), throwsA(anything));

      expect(markerFile.existsSync(), isFalse);
      expect(backupFile.existsSync(), isFalse);
      // Original file was never renamed away - still sitting at dbFile.path,
      // untouched. (Whether sqlite3's failed VACUUM INTO leaves a partial
      // .migrating.tmp behind is an internal SQLite detail not asserted
      // here - the safety property under test is that the ORIGINAL data
      // and the "already migrated" marker never end up in an inconsistent
      // state relative to each other.)
      expect(dbFile.existsSync(), isTrue);
    });
  });
}

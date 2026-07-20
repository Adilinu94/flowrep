import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages the encryption key for the local Drift database
/// (GYM_TRACKER_ARCHITEKTUR.md §5.2.3 "Lokale Verschlüsselung").
///
/// The key is generated once (32 random bytes) and stored in the platform's
/// secure storage (Android Keystore / iOS Keychain) via [FlutterSecureStorage]
/// - the same package [calibration_store.dart] already uses for
/// [ExerciseProfile] persistence, so no new secure-storage mechanism is
/// introduced here.
///
/// PORT NOTE: this class existed already, uncommitted, on `origin/master`
/// (`database_key_manager.dart`) - the core generate/store/retrieve logic
/// below is that implementation, effectively unchanged. Only
/// [getOrCreateKeyHex]'s OUTPUT FORMAT differs from the original: the
/// master version formatted its key as SQLCipher's raw-key literal
/// (`"x'<hex>'"`, quotes included, for `sqlcipher_flutter_libs`). That
/// package is now deprecated (see drift_database.dart's header comment for
/// the research trail) - current drift (>=2.32.0) uses SQLite3MultipleCiphers
/// instead, whose documented `PRAGMA key = 'passphrase';` example uses a
/// plain string, not a raw-key literal. This class now returns the bare hex
/// string; the caller builds the full `PRAGMA key = '...'` statement
/// (see [DatabaseKeyManager.pragmaKeyStatement]).
///
/// IMPORTANT: If the key is ever lost (e.g. app data cleared, secure storage
/// wiped), the database becomes unreadable. For Phase 0/1 this is accepted
/// (matches the original master-branch design note) - a future version may
/// want key rotation or a recovery/export flow.
class DatabaseKeyManager {
  DatabaseKeyManager({
    FlutterSecureStorage? storage,
    this.keyName = _defaultKeyName,
  }) : _storage = storage ?? const FlutterSecureStorage();

  static const _defaultKeyName = 'flowrep_database_key_v1';
  static const _keyLengthBytes = 32;

  final FlutterSecureStorage _storage;
  final String keyName;

  /// Returns the raw encryption key as a lowercase hex string (64 hex
  /// characters for 32 bytes), generating and persisting one on first call.
  Future<String> getOrCreateKeyHex() async {
    var stored = await _storage.read(key: keyName);

    if (stored == null || stored.isEmpty) {
      final bytes = List<int>.generate(
        _keyLengthBytes,
        (_) => _secureRandom.nextInt(256),
      );
      stored = base64Encode(bytes);
      await _storage.write(key: keyName, value: stored);
    }

    final List<int> decoded;
    try {
      decoded = base64Decode(stored);
    } on FormatException catch (e, stack) {
      Error.throwWithStackTrace(
        FormatException('Corrupted database key in secure storage: $e'),
        stack,
      );
    }

    if (decoded.length != _keyLengthBytes) {
      throw StateError(
        'Invalid database key length: expected $_keyLengthBytes bytes, '
        'got ${decoded.length}.',
      );
    }

    return decoded.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Builds a complete, safely-escaped `PRAGMA key = '...';` statement for
  /// the given hex key (single quotes doubled per SQL string-literal
  /// escaping - defensive here since a hex string from [getOrCreateKeyHex]
  /// never actually contains a quote, but the escaping is cheap and this
  /// keeps the statement-building logic in one place rather than repeated
  /// at every call site).
  static String pragmaKeyStatement(String keyHex) {
    final escaped = keyHex.replaceAll("'", "''");
    return "PRAGMA key = '$escaped';";
  }

  /// Deletes the stored key. Use with care — the database will be unreadable
  /// afterwards unless a new key is supplied externally.
  Future<void> deleteKey() async {
    await _storage.delete(key: keyName);
  }

  static final _secureRandom = Random.secure();
}

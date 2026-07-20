import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowrep/data/security/database_key_manager.dart';

/// In-memory stand-in for [FlutterSecureStorage] so [DatabaseKeyManager]
/// can be tested without real platform channels (Android Keystore/iOS
/// Keychain aren't available in a plain test run). Overrides only the
/// three methods [DatabaseKeyManager] actually calls (read/write/delete);
/// everything else falls back to the real implementation, which this test
/// never exercises.
///
/// NOT independently verified: whether `FlutterSecureStorage`'s methods
/// are actually overridable this way (not `final`/sealed in the installed
/// package version) can only be confirmed by a real `flutter test` run -
/// unavailable in this sandbox (see drift_database.dart's header comment
/// for the same toolchain gap). If this fails to compile against the real
/// package, the fix is mechanical (adjust which methods are overridden to
/// match that version's actual API), not a sign the key-manager logic
/// itself is wrong.
class _FakeSecureStorage extends FlutterSecureStorage {
  const _FakeSecureStorage(this._store);
  final Map<String, String> _store;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? woptions,
  }) async =>
      _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? woptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? woptions,
  }) async {
    _store.remove(key);
  }
}

void main() {
  group('DatabaseKeyManager.pragmaKeyStatement (pure function)', () {
    test('wraps the key in a PRAGMA key statement', () {
      expect(
        DatabaseKeyManager.pragmaKeyStatement('deadbeef'),
        "PRAGMA key = 'deadbeef';",
      );
    });

    test('doubles single quotes for SQL string-literal escaping', () {
      // A hex string never actually contains a quote - this defends
      // against a future change to the key format, not today's inputs.
      expect(
        DatabaseKeyManager.pragmaKeyStatement("a'b"),
        "PRAGMA key = 'a''b';",
      );
    });
  });

  group('DatabaseKeyManager.getOrCreateKeyHex (via fake secure storage)', () {
    test('generates a 64-character lowercase hex string (32 bytes)', () async {
      final manager = DatabaseKeyManager(storage: _FakeSecureStorage({}));
      final key = await manager.getOrCreateKeyHex();
      expect(key.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key), isTrue);
    });

    test('returns the same key on repeated calls (persisted, not '
        'regenerated)', () async {
      final store = <String, String>{};
      final manager = DatabaseKeyManager(storage: _FakeSecureStorage(store));
      final first = await manager.getOrCreateKeyHex();
      final second = await manager.getOrCreateKeyHex();
      expect(second, first);
    });

    test('two independently-seeded managers produce different keys', () async {
      final a = await DatabaseKeyManager(storage: _FakeSecureStorage({}))
          .getOrCreateKeyHex();
      final b = await DatabaseKeyManager(storage: _FakeSecureStorage({}))
          .getOrCreateKeyHex();
      expect(a, isNot(b));
    });

    test('a corrupted stored value throws FormatException instead of '
        'silently producing a wrong key', () async {
      final manager = DatabaseKeyManager(
        storage: _FakeSecureStorage({'flowrep_database_key_v1': 'not-base64!!'}),
      );
      expect(manager.getOrCreateKeyHex(), throwsFormatException);
    });

    test('deleteKey removes the stored value so the next call generates a '
        'fresh key', () async {
      final store = <String, String>{};
      final manager = DatabaseKeyManager(storage: _FakeSecureStorage(store));
      final first = await manager.getOrCreateKeyHex();
      await manager.deleteKey();
      final second = await manager.getOrCreateKeyHex();
      expect(second, isNot(first));
    });
  });
}

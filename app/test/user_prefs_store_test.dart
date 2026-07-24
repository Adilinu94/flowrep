import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';
import 'package:flowrep/data/security/user_prefs_store.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:flowrep/presentation/providers/engine_provider.dart';

/// In-memory [FlutterSecureStorage] for prefs tests (no platform channel).
class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> data = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }
}

void main() {
  group('UserPrefsStore', () {
    test('default auto-arm is true when unset', () async {
      final store = UserPrefsStore(storage: _FakeSecureStorage());
      expect(await store.loadAutoArmAfterCalib(), isTrue);
    });

    test('save and load auto-arm false', () async {
      final store = UserPrefsStore(storage: _FakeSecureStorage());
      await store.saveAutoArmAfterCalib(false);
      expect(await store.loadAutoArmAfterCalib(), isFalse);
      await store.saveAutoArmAfterCalib(true);
      expect(await store.loadAutoArmAfterCalib(), isTrue);
    });
  });

  group('EngineNotifier auto-arm persistence', () {
    test('setAutoArmAfterCalib persists across reload', () async {
      final fake = _FakeSecureStorage();
      final prefs = UserPrefsStore(storage: fake);

      final a = EngineNotifier.create(
        sensorProvider: MockSensorProvider(),
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
        userPrefs: prefs,
      );
      await a.setAutoArmAfterCalib(false);
      expect(a.autoArmAfterCalib, isFalse);
      a.dispose();

      final b = EngineNotifier.create(
        sensorProvider: MockSensorProvider(),
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
        userPrefs: UserPrefsStore(storage: fake),
      );
      // create() loads prefs async
      await b.reloadUserPrefsForTest();
      expect(b.autoArmAfterCalib, isFalse);
      b.dispose();
    });

    test('default remains true without stored value', () async {
      final n = EngineNotifier.create(
        sensorProvider: MockSensorProvider(),
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
        userPrefs: UserPrefsStore(storage: _FakeSecureStorage()),
      );
      await n.reloadUserPrefsForTest();
      expect(n.autoArmAfterCalib, isTrue);
      n.dispose();
    });
  });
}

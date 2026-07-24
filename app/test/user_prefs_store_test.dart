import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';
import 'package:flowrep/data/security/user_prefs_store.dart';
import 'package:flowrep/domain/exercises/exercise_targets.dart';
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

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data.remove(key);
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

    test('loadAll returns product defaults when empty', () async {
      final snap = await UserPrefsStore(storage: _FakeSecureStorage()).loadAll();
      expect(snap.autoArmAfterCalib, isTrue);
      expect(snap.haptic, isTrue);
      expect(snap.audio, isFalse);
      expect(snap.restDurationSeconds, 90);
      expect(snap.ghostIdlePauseSeconds, 45);
      expect(snap.cameraEnabled, isFalse);
      expect(snap.diagnoseOverlay, isFalse);
      expect(snap.ghostGate, isTrue);
    });

    test('loadAll reflects saved suite', () async {
      final store = UserPrefsStore(storage: _FakeSecureStorage());
      await store.saveHaptic(false);
      await store.saveAudio(true);
      await store.saveRestDurationSeconds(60);
      await store.saveGhostIdlePauseSeconds(90);
      await store.saveGhostGate(false);
      await store.saveM5ButtonControl(false);
      await store.saveVbtMetrics(false);
      await store.saveAdaptiveRest(false);
      await store.saveDiagnoseOverlay(true);
      await store.saveBlindMode(true);
      await store.saveCameraEnabled(true);
      await store.saveButtonHaptic(false);
      await store.saveButtonAudio(false);

      final snap = await store.loadAll();
      expect(snap.haptic, isFalse);
      expect(snap.audio, isTrue);
      expect(snap.restDurationSeconds, 60);
      expect(snap.ghostIdlePauseSeconds, 90);
      expect(snap.ghostGate, isFalse);
      expect(snap.m5ButtonControl, isFalse);
      expect(snap.vbtMetrics, isFalse);
      expect(snap.adaptiveRest, isFalse);
      expect(snap.diagnoseOverlay, isTrue);
      expect(snap.blindMode, isTrue);
      expect(snap.cameraEnabled, isTrue);
      expect(snap.buttonHaptic, isFalse);
      expect(snap.buttonAudio, isFalse);
    });
  });

  group('EngineNotifier prefs persistence', () {
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
      await b.reloadUserPrefsForTest();
      expect(b.autoArmAfterCalib, isFalse);
      b.dispose();
    });

    test('settings suite survives reload', () async {
      final fake = _FakeSecureStorage();
      final a = EngineNotifier.create(
        sensorProvider: MockSensorProvider(),
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
        userPrefs: UserPrefsStore(storage: fake),
      );

      await a.setFeedback(haptic: false, audio: true);
      await a.setRestDurationSeconds(60);
      await a.setM5ButtonControlEnabled(false);
      await a.setButtonFeedback(haptic: false, audio: false);
      await a.setAdaptiveRestEnabled(false);
      await a.setVbtMetricsEnabled(false);
      await a.setDiagnoseOverlayEnabled(true);
      await a.setGhostGateEnabled(false);
      await a.setGhostIdlePauseSeconds(30);
      await a.setCameraEnabled(true);
      await a.setBlindModeEnabled(true);
      a.dispose();

      final b = EngineNotifier.create(
        sensorProvider: MockSensorProvider(),
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
        userPrefs: UserPrefsStore(storage: fake),
      );
      await b.reloadUserPrefsForTest();

      expect(b.hapticEnabled, isTrue); // blind mode forces haptic on
      expect(b.audioEnabled, isTrue);
      expect(b.restDurationSeconds, 60);
      expect(b.m5ButtonControlEnabled, isFalse);
      expect(b.buttonHapticEnabled, isFalse);
      expect(b.buttonAudioEnabled, isFalse);
      expect(b.adaptiveRestEnabled, isFalse);
      expect(b.vbtEnabled, isFalse);
      expect(b.state.diagnoseOverlayEnabled, isTrue);
      expect(b.state.vbtMetricsEnabled, isFalse);
      expect(b.state.blindModeEnabled, isTrue);
      expect(b.state.cameraEnabled, isTrue);
      expect(b.engine.ghostGateEnabled, isFalse);
      expect(b.ghostIdlePauseSeconds, 30);
      b.dispose();
    });

    test('setCameraEnabled persist:false does not write storage', () async {
      final fake = _FakeSecureStorage();
      final n = EngineNotifier.create(
        sensorProvider: MockSensorProvider(),
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
        userPrefs: UserPrefsStore(storage: fake),
      );
      await n.setCameraEnabled(true, persist: false);
      expect(n.isCameraEnabled, isTrue);
      expect(fake.data.containsKey(UserPrefsStore.keyCameraEnabled), isFalse);

      await n.setCameraEnabled(true, persist: true);
      expect(fake.data[UserPrefsStore.keyCameraEnabled], '1');
      n.dispose();
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

    test('exercise targets persist across reload', () async {
      final fake = _FakeSecureStorage();
      final a = EngineNotifier.create(
        sensorProvider: MockSensorProvider(),
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
        userPrefs: UserPrefsStore(storage: fake),
      );
      await a.setExerciseTarget(sets: 5, reps: 8);
      expect(a.state.targetSets, 5);
      expect(a.state.targetReps, 8);
      a.dispose();

      final b = EngineNotifier.create(
        sensorProvider: MockSensorProvider(),
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
        userPrefs: UserPrefsStore(storage: fake),
      );
      await b.reloadUserPrefsForTest();
      expect(b.state.targetSets, 5);
      expect(b.state.targetReps, 8);
      expect(b.targets.of('bicep_curl')?.targetSets, 5);
      b.dispose();
    });

    test('clearExerciseTarget removes from storage', () async {
      final fake = _FakeSecureStorage();
      final store = UserPrefsStore(storage: fake);
      final a = EngineNotifier.create(
        sensorProvider: MockSensorProvider(),
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
        userPrefs: store,
      );
      await a.setExerciseTarget(sets: 3, reps: 10);
      await a.clearExerciseTarget();
      expect(a.state.targetSets, isNull);
      a.dispose();

      final loaded = await store.loadExerciseTargets();
      expect(loaded.containsKey('bicep_curl'), isFalse);
    });
  });

  group('ExerciseTargets JSON', () {
    test('mapFromJson skips invalid entries', () {
      final map = ExerciseTargets.mapFromJson({
        'bicep_curl': {'sets': 4, 'reps': 12},
        'bad': {'sets': 0, 'reps': 5},
        'also_bad': 'x',
      });
      expect(map.keys, ['bicep_curl']);
      expect(map['bicep_curl']!.targetReps, 12);
    });
  });
}

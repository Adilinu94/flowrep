import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowrep/data/security/calibration_store.dart';
import 'package:flowrep/domain/models/exercise_profile.dart';

/// In-memory Fake statt der echten (Platform-Channel-basierten)
/// FlutterSecureStorage - macht CalibrationStore ohne Geraet/Emulator
/// testbar. CalibrationStore nimmt die Storage-Instanz per Konstruktor
/// entgegen (Dependency Injection), extra Wiring ist nicht noetig.
class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};

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
      _data[key];

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
      _data.remove(key);
    } else {
      _data[key] = value;
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
    _data.remove(key);
  }
}

ExerciseProfile _sampleProfile(String exerciseId) => ExerciseProfile(
      exerciseId: exerciseId,
      rotationAxis: const [0.1, 0.9, 0.0],
      chosenSignal: ChosenSignal.gP,
      theta: 2.5,
      minRepIntervalSeconds: 0.8,
      medianTSeconds: 1.5,
      madTSeconds: 0.1,
      gyroBias: const [0.01, -0.02, 0.0],
      qualityScore: 0.9,
      calibratedAt: DateTime(2026, 7, 17),
    );

void main() {
  group('CalibrationStore v2 (ExerciseProfile)', () {
    test('loadProfile gibt null, wenn nichts gespeichert ist', () async {
      final store = CalibrationStore(storage: _FakeSecureStorage());
      final result =
          await store.loadProfile(exerciseId: 'bicep_curl', deviceId: 'dev1');
      expect(result, isNull);
    });

    test('saveProfile + loadProfile: Round-Trip liefert identische Werte',
        () async {
      final store = CalibrationStore(storage: _FakeSecureStorage());
      final profile = _sampleProfile('bicep_curl');
      await store.saveProfile(profile: profile);

      final loaded =
          await store.loadProfile(exerciseId: 'bicep_curl', deviceId: 'dev1');
      expect(loaded, isNotNull);
      expect(loaded!.exerciseId, 'bicep_curl');
      expect(loaded.theta, 2.5);
      expect(loaded.chosenSignal, ChosenSignal.gP);
      expect(loaded.rotationAxis, [0.1, 0.9, 0.0]);
      expect(loaded.needsRecalibration, isFalse);
    });

    test('Migration: v1-Legacy-Daten werden automatisch gewrapt', () async {
      final storage = _FakeSecureStorage();
      final store = CalibrationStore(storage: storage);
      // Altes v1-Format schreiben (wie es der bestehende Code in
      // home_screen.dart._saveCalibration() tut).
      await store.save(
        deviceId: 'dev1',
        peakThreshold: 1.8,
        minThresholdAboveBaseline: 0.3,
        baselineLevel: 0.1,
      );

      final loaded =
          await store.loadProfile(exerciseId: 'bicep_curl', deviceId: 'dev1');
      expect(loaded, isNotNull);
      expect(loaded!.theta, 1.8);
      expect(loaded.needsRecalibration, isTrue,
          reason: 'migrierte v1-Profile muessen zur Rekalibrierung '
              'auffordern (Konzept 2.0 §6)');
    });

    test('v2-Profil hat Vorrang vor v1-Legacy-Daten, falls beides existiert',
        () async {
      final storage = _FakeSecureStorage();
      final store = CalibrationStore(storage: storage);
      await store.save(
        deviceId: 'dev1',
        peakThreshold: 1.8,
        minThresholdAboveBaseline: 0.3,
        baselineLevel: 0.1,
      );
      await store.saveProfile(profile: _sampleProfile('bicep_curl'));

      final loaded =
          await store.loadProfile(exerciseId: 'bicep_curl', deviceId: 'dev1');
      expect(loaded!.theta, 2.5); // v2-Wert, nicht der v1-Wert 1.8
      expect(loaded.needsRecalibration, isFalse);
    });

    test('mehrere Uebungen werden unabhaengig voneinander gespeichert',
        () async {
      final store = CalibrationStore(storage: _FakeSecureStorage());
      await store.saveProfile(profile: _sampleProfile('bicep_curl'));
      await store.saveProfile(profile: _sampleProfile('squat'));

      final curl =
          await store.loadProfile(exerciseId: 'bicep_curl', deviceId: 'dev1');
      final squat =
          await store.loadProfile(exerciseId: 'squat', deviceId: 'dev1');
      expect(curl!.exerciseId, 'bicep_curl');
      expect(squat!.exerciseId, 'squat');
    });

    test('deleteAll entfernt v1- UND v2-Daten (DSGVO)', () async {
      final storage = _FakeSecureStorage();
      final store = CalibrationStore(storage: storage);
      await store.save(
        deviceId: 'dev1',
        peakThreshold: 1.8,
        minThresholdAboveBaseline: 0.3,
        baselineLevel: 0.1,
      );
      await store.saveProfile(profile: _sampleProfile('bicep_curl'));

      await store.deleteAll();

      final legacyGone = await store.load(deviceId: 'dev1');
      final v2Gone =
          await store.loadProfile(exerciseId: 'bicep_curl', deviceId: 'dev1');
      expect(legacyGone, isNull);
      expect(v2Gone, isNull);
    });
  });
}

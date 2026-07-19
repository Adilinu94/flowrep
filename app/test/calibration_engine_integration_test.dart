import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowrep/data/security/calibration_store.dart';
import 'package:flowrep/domain/models/exercise_profile.dart';
import 'package:flowrep/domain/workout_engine.dart';

/// Regressionstest fuer die Engine-Anbindung (2026-07-18): ein per
/// CalibrationStore gespeichertes ExerciseProfile muss sich nach dem Laden
/// tatsaechlich auf WorkoutEngine.peakThreshold auswirken - vorher war
/// die Kalibrierung ein Sackgassen-System (gespeichert, aber nie wieder
/// gelesen und angewendet), siehe STATUS_FORTSCHRITT.md.
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

void main() {
  test(
      'ein gespeichertes ExerciseProfile wirkt sich nach dem Laden auf '
      'WorkoutEngine.peakThreshold aus (Engine-Anbindung)', () async {
    final store = CalibrationStore(storage: _FakeSecureStorage());
    final profile = ExerciseProfile(
      exerciseId: 'bicep_curl',
      rotationAxis: const [0.0, 1.0, 0.0],
      chosenSignal: ChosenSignal.gP,
      theta: 2.42,
      minRepIntervalSeconds: 0.8,
      medianTSeconds: 1.5,
      madTSeconds: 0.1,
      gyroBias: const [0.0, 0.0, 0.0],
      qualityScore: 0.9,
      calibratedAt: DateTime(2026, 7, 18),
    );
    await store.saveProfile(profile: profile);

    // Simuliert exakt, was home_screen.dart._loadCalibration() jetzt tut.
    final loaded = await store.loadProfile(
      exerciseId: 'bicep_curl',
      deviceId: 'test-device',
    );
    expect(loaded, isNotNull);

    final engine = WorkoutEngine(exerciseId: 'bicep_curl');
    expect(engine.peakThreshold, isNot(loaded!.theta),
        reason: 'Vorbedingung: frischer Engine-Default darf nicht zufaellig '
            'mit dem Testwert uebereinstimmen');

    engine.applyCalibration(
      peakThreshold: loaded.theta,
      minThresholdAboveBaseline: 0.10,
    );

    expect(engine.peakThreshold, 2.42);
    expect(engine.hasValidCalibration, isTrue);
  });

  test('v1-Legacy-Kalibrierung (kein Wizard genutzt) wirkt sich weiterhin '
      'aus - Rueckwaertskompatibilitaet', () async {
    final store = CalibrationStore(storage: _FakeSecureStorage());
    await store.save(
      deviceId: 'test-device',
      peakThreshold: 1.55,
      minThresholdAboveBaseline: 0.12,
      baselineLevel: 0.05,
    );

    final loaded = await store.loadProfile(
      exerciseId: 'bicep_curl',
      deviceId: 'test-device',
    );
    expect(loaded, isNotNull);
    expect(loaded!.needsRecalibration, isTrue);

    final engine = WorkoutEngine(exerciseId: 'bicep_curl');
    engine.applyCalibration(
      peakThreshold: loaded.theta,
      minThresholdAboveBaseline: 0.10,
    );
    expect(engine.peakThreshold, 1.55);
  });
}

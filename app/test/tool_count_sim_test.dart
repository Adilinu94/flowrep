import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/models/exercise_profile.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/workout_engine.dart';

void main() {
  test('gP profile: curls count both signs; small wiggle does not', () {
    final engine = WorkoutEngine(
      exerciseId: 'bicep_curl',
      useSignedProjectionCounting: true,
    );
    engine.applyCalibration(
      peakThreshold: 87.2,
      minThresholdAboveBaseline: 0.10,
      rotationAxis: const [1.0, 0.0, 0.0],
      gyroBias: const [0.0, 0.0, 0.0],
      chosenSignal: ChosenSignal.gP,
      minRepIntervalSeconds: 0.8,
    );
    expect(engine.peakThreshold, greaterThan(100),
        reason: 'combined path must be inert under gP profile');

    var t = DateTime(2026, 1, 1);
    var lastReps = 0;
    engine.events.listen((e) => lastReps = e.repsInCurrentSet);

    void rest([int n = 30]) {
      for (var i = 0; i < n; i++) {
        engine.processSample(SensorSample(
          timestamp: t, ax: 0, ay: 1, az: 0, gx: 0, gy: 0, gz: 0,
        ));
        t = t.add(const Duration(milliseconds: 20));
      }
    }

    void curlGx(double peak) {
      const steps = 40;
      for (var i = 0; i < steps; i++) {
        final g = peak * sin(i / (steps - 1) * pi);
        engine.processSample(SensorSample(
          timestamp: t, ax: 0, ay: 1, az: 0, gx: g, gy: 0, gz: 0,
        ));
        t = t.add(const Duration(milliseconds: 20));
      }
      rest();
    }

    rest();
    curlGx(180); // + direction
    expect(lastReps, 1);
    curlGx(-180); // opposite sign — still a real curl on the axis
    expect(lastReps, 2,
        reason: '|gP| must count either polarity after profile calib');

    final after = lastReps;
    for (var i = 0; i < 80; i++) {
      final g = 18.0 * sin(i / 5);
      engine.processSample(SensorSample(
        timestamp: t,
        ax: 0.05 * sin(i / 3.0),
        ay: 1,
        az: 0.02,
        gx: g,
        gy: g * 0.4,
        gz: g * 0.2,
      ));
      t = t.add(const Duration(milliseconds: 20));
    }
    rest();
    expect(lastReps, after,
        reason: 'small wiggle under threshold must not count');

    engine.dispose();
  });

  test('autoEndSetEnabled false: stillness does not complete set', () {
    final engine = WorkoutEngine(
      exerciseId: 'bicep_curl',
      autoEndSetEnabled: false,
    );
    ExerciseSet? finished;
    engine.events.listen((e) {
      if (e.completedSet != null) finished = e.completedSet;
    });
    var t = DateTime(2026, 1, 1);
    // Calibrate with movement then rest far beyond pauseAfter.
    for (var i = 0; i < 40; i++) {
      final g = 3.0 * (i < 20 ? i / 20 : (40 - i) / 20);
      engine.processSample(SensorSample(
        timestamp: t, ax: 0, ay: g, az: 0, gx: 0, gy: 0, gz: 0,
      ));
      t = t.add(const Duration(milliseconds: 20));
    }
    for (var i = 0; i < 400; i++) {
      engine.processSample(SensorSample(
        timestamp: t, ax: 0, ay: 1, az: 0, gx: 0, gy: 0, gz: 0,
      ));
      t = t.add(const Duration(milliseconds: 20));
    }
    expect(finished, isNull,
        reason: 'with autoEndSetEnabled=false, set must stay open');
    engine.endSetManually();
    expect(finished, isNotNull);
    engine.dispose();
  });
}

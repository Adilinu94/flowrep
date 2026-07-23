import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/models/exercise_profile.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/workout_engine.dart';

/// Synthetic IMU sequences driving the **real** [WorkoutEngine] (no mocks).
void main() {
  WorkoutEngine profiledEngine() {
    final engine = WorkoutEngine(
      exerciseId: 'bicep_curl',
      useSignedProjectionCounting: true,
      autoEndSetEnabled: false,
    );
    // Matches post-calib hardware profile (see CALIB_SESSION_ANALYSIS).
    engine.applyCalibration(
      peakThreshold: 87.2,
      minThresholdAboveBaseline: 0.10,
      rotationAxis: const [1.0, 0.0, 0.0],
      gyroBias: const [0.0, 0.0, 0.0],
      chosenSignal: ChosenSignal.gP,
      minRepIntervalSeconds: 0.8,
    );
    return engine;
  }

  test('gP profile: curls count both signs; small wiggle does not', () {
    final engine = profiledEngine();
    expect(engine.peakThreshold, greaterThan(100),
        reason: 'combined path must be inert under gP profile');
    expect(engine.gpThreshold, greaterThanOrEqualTo(50.0));
    expect(engine.gpThreshold, closeTo(87.2 * 0.70, 0.5));

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

    void curlGx(double peak, {int steps = 40}) {
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
    // Low-amplitude multi-axis shake (under θ and/or peak gate).
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

  test('gP: brief vigorous flick does not count; sustained curl does', () {
    final engine = profiledEngine();
    var t = DateTime(2026, 1, 1);
    var lastReps = 0;
    engine.events.listen((e) => lastReps = e.repsInCurrentSet);

    void rest([int n = 40]) {
      for (var i = 0; i < n; i++) {
        engine.processSample(SensorSample(
          timestamp: t, ax: 0, ay: 1, az: 0, gx: 0, gy: 0, gz: 0,
        ));
        t = t.add(const Duration(milliseconds: 20));
      }
    }

    rest();
    // Short high spike (~120ms @ 50Hz) — duration gate must reject.
    for (var i = 0; i < 6; i++) {
      final g = 120.0 * sin(i / 5 * pi);
      engine.processSample(SensorSample(
        timestamp: t, ax: 0, ay: 1, az: 0, gx: g, gy: 0, gz: 0,
      ));
      t = t.add(const Duration(milliseconds: 20));
    }
    rest();
    expect(lastReps, 0, reason: 'brief flick must not count as a rep');

    // Medium amplitude sustained but below peak-over-θ (1.2×θ≈73 for θ≈61).
    for (var i = 0; i < 40; i++) {
      final g = 68.0 * sin(i / 39 * pi);
      engine.processSample(SensorSample(
        timestamp: t, ax: 0, ay: 1, az: 0, gx: g, gy: 0, gz: 0,
      ));
      t = t.add(const Duration(milliseconds: 20));
    }
    rest();
    expect(lastReps, 0,
        reason: 'threshold-graze without strong peak must not count');

    // Real curl: long + high peak.
    for (var i = 0; i < 40; i++) {
      final g = 160.0 * sin(i / 39 * pi);
      engine.processSample(SensorSample(
        timestamp: t, ax: 0, ay: 1, az: 0, gx: g, gy: 0, gz: 0,
      ));
      t = t.add(const Duration(milliseconds: 20));
    }
    rest();
    expect(lastReps, 1, reason: 'sustained high curl must count');

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
    // Manual end with zero reps yields no completedSet (idle only).
    // With movement that never committed reps, finished may stay null.
    // Product path with counted reps:
    engine.dispose();
  });

  test('manual endSet after gP reps emits completedSet with countedReps', () {
    final engine = profiledEngine();
    ExerciseSet? finished;
    var lastReps = 0;
    engine.events.listen((e) {
      lastReps = e.repsInCurrentSet;
      if (e.completedSet != null) finished = e.completedSet;
    });
    var t = DateTime(2026, 1, 1);

    void rest([int n = 30]) {
      for (var i = 0; i < n; i++) {
        engine.processSample(SensorSample(
          timestamp: t, ax: 0, ay: 1, az: 0, gx: 0, gy: 0, gz: 0,
        ));
        t = t.add(const Duration(milliseconds: 20));
      }
    }

    rest();
    for (var rep = 0; rep < 3; rep++) {
      for (var i = 0; i < 40; i++) {
        final g = 170.0 * sin(i / 39 * pi);
        engine.processSample(SensorSample(
          timestamp: t, ax: 0, ay: 1, az: 0, gx: g, gy: 0, gz: 0,
        ));
        t = t.add(const Duration(milliseconds: 20));
      }
      rest(50); // refractory gap
    }
    expect(lastReps, 3);
    expect(finished, isNull, reason: 'no auto-end while counting');

    engine.endSetManually();
    expect(finished, isNotNull);
    expect(finished!.countedReps, 3);
    expect(finished!.correctedReps, isNull);

    engine.dispose();
  });

  test('nudgeDirectionAwareThreshold raises θ after over-count', () {
    final engine = profiledEngine();
    final before = engine.gpThreshold!;
    engine.nudgeDirectionAwareThreshold(1.15);
    expect(engine.gpThreshold!, greaterThan(before));
    expect(engine.gpThreshold!, closeTo(before * 1.15, 0.01));
    engine.dispose();
  });
}

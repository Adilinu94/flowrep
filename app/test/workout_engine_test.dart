import 'dart:math';

import 'package:test/test.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/workout_engine.dart';

/// Generates a synthetic "bicep curl"-like acceleration profile: a quiet
/// baseline near zero plus `repCount` smooth sine-shaped excursions, each
/// rising to `peakHeight` and falling back to `baseline`. The quiet baseline
/// must sit clearly below the engine's falling-edge threshold so that each
/// rep is counted exactly once. This is deliberately simple synthetic data,
/// not real captured motion - it exists to validate the state machine's
/// logic (does N clean excursions produce N counted reps?), not to claim
/// real-world accuracy.
List<SensorSample> _generateSyntheticReps({
  required int repCount,
  double peakHeight = 1.8,
  double baseline = 0.0,
  int samplesPerRep = 30, // ~0.6s at 50Hz-equivalent 20ms steps
  int restSamplesBetween = 5,
}) {
  final samples = <SensorSample>[];
  var t = DateTime(2026, 1, 1);
  const step = Duration(milliseconds: 20);

  for (var rep = 0; rep < repCount; rep++) {
    for (var i = 0; i < samplesPerRep; i++) {
      final phase = (i / samplesPerRep) * 3.14159265;
      final magnitude = baseline + (peakHeight - baseline) * _sin(phase);
      samples.add(SensorSample(
        timestamp: t,
        ax: 0, ay: magnitude, az: 0,
        gx: 0, gy: 0, gz: 0,
      ));
      t = t.add(step);
    }
    for (var i = 0; i < restSamplesBetween; i++) {
      samples.add(SensorSample(timestamp: t, ax: 0, ay: baseline, az: 0, gx: 0, gy: 0, gz: 0));
      t = t.add(step);
    }
  }
  return samples;
}

double _sin(double x) {
  // Minimal Taylor-series sine to avoid importing dart:math just for tests;
  // accurate enough for 0..pi over a handful of terms.
  final x2 = x * x;
  return x * (1 - x2 / 6 * (1 - x2 / 20 * (1 - x2 / 42)));
}

void main() {
  group('WorkoutEngine', () {
    test('counts a clean series of repetitions without double-counting',
        () async {
      final engine = WorkoutEngine(exerciseId: 'bicep_curl');
      ExerciseSet? finishedSet;
      engine.events.listen((e) {
        if (e.completedSet != null) finishedSet = e.completedSet;
      });

      final samples = _generateSyntheticReps(repCount: 10);
      for (final s in samples) {
        engine.processSample(s);
      }

      // Force the pause timeout by feeding several seconds of stillness.
      // The quiet signal must sit below the falling-edge threshold so the
      // engine recognises the set has ended.
      var t = samples.last.timestamp;
      for (var i = 0; i < 250; i++) {
        t = t.add(const Duration(milliseconds: 20));
        engine.processSample(
          SensorSample(timestamp: t, ax: 0, ay: 0.0, az: 0, gx: 0, gy: 0, gz: 0),
        );
      }

      expect(finishedSet, isNotNull,
          reason: 'Expected the set to end after the pause timeout');
      // Allow +/-1 tolerance: the first 3 reps are also the calibration
      // window (see WorkoutEngine.calibrationReps), during which the
      // threshold itself is still being refined - exact 10/10 is not
      // guaranteed by design, see GYM_TRACKER_ARCHITEKTUR.md 5.1.2.
      expect(finishedSet!.countedReps, closeTo(10, 1));
      engine.dispose();
    });

    test('idle state transitions to calibrating on first movement, not '
        'before', () {
      final engine = WorkoutEngine(exerciseId: 'bicep_curl');
      expect(engine.state, WorkoutState.idle);

      // Small noise below the activation threshold must NOT trigger a
      // state change - otherwise sensor noise alone would start a "set".
      // Activation is baseline-relative (baselineLevel + (peakThreshold -
      // baselineLevel) * 0.5, see processSample()), not a flat multiple of
      // peakThreshold - that was the real HyperOS bug fixed 2026-07-12
      // (see DEBUGSESSION_2026-07-12.md). Default peakThreshold is 1.2.
      for (var i = 0; i < 20; i++) {
        engine.processSample(SensorSample(
          timestamp: DateTime.now(),
          ax: 0.01, ay: 0.3, az: 0.0, gx: 0, gy: 0, gz: 0,
        ));
      }
      expect(engine.state, WorkoutState.idle);
      engine.dispose();
    });

    test('does not count a rep on every sample while above threshold '
        '(regression test for the naive-pseudocode bug)', () {
      final engine = WorkoutEngine(exerciseId: 'bicep_curl');
      int lastRepsSeen = 0;
      var repCountChanges = 0;
      engine.events.listen((e) {
        if (e.repsInCurrentSet != lastRepsSeen) {
          repCountChanges++;
          lastRepsSeen = e.repsInCurrentSet;
        }
      });

      // Hold the signal continuously above threshold for 40 samples
      // (~0.8s) without ever falling back down - this must count as AT
      // MOST one rep-in-progress, never ~40.
      var t = DateTime(2026, 1, 1);
      for (var i = 0; i < 40; i++) {
        engine.processSample(SensorSample(
          timestamp: t, ax: 0, ay: 2.0, az: 0, gx: 0, gy: 0, gz: 0,
        ));
        t = t.add(const Duration(milliseconds: 20));
      }

      expect(repCountChanges, lessThanOrEqualTo(1),
          reason: 'A sustained excursion above threshold must not be '
              'counted repeatedly per sample.');
      engine.dispose();
    });

    test('endSetManually ends the set even before the pause timeout', () {
      final engine = WorkoutEngine(exerciseId: 'bicep_curl');
      ExerciseSet? finishedSet;
      engine.events.listen((e) {
        if (e.completedSet != null) finishedSet = e.completedSet;
      });

      final samples = _generateSyntheticReps(repCount: 3);
      for (final s in samples) {
        engine.processSample(s);
      }
      engine.endSetManually();

      expect(finishedSet, isNotNull);
      expect(finishedSet!.countedReps, greaterThan(0));
      engine.dispose();
    });

    test(
        'regression: counting must continue AFTER the calibration reps, not '
        'stop there (see workout_engine.dart class doc for the bug this '
        'guards against - found via tools/workout_engine_simulation.py '
        'before hardware arrived)', () {
      final engine = WorkoutEngine(exerciseId: 'bicep_curl');
      ExerciseSet? finishedSet;
      engine.events.listen((e) {
        if (e.completedSet != null) finishedSet = e.completedSet;
      });

      // Deliberately more reps than calibrationReps (default 3), well
      // beyond it, so a regression back to "stops counting after
      // calibration" would be obvious rather than hidden by a tolerance
      // band.
      final samples = _generateSyntheticReps(repCount: 12);
      for (final s in samples) {
        engine.processSample(s);
      }
      engine.endSetManually();

      expect(finishedSet, isNotNull);
      expect(finishedSet!.countedReps, greaterThan(6),
          reason: 'If this is <= calibrationReps (3), counting stopped '
              'right after calibration - that is the exact bug this test '
              'guards against.');
      engine.dispose();
    });

    test(
        'does not wildly overcount under noisy/shaky input (regression for '
        'the pre-lowpass-filter behaviour, which counted 18 for 10 actual '
        'reps under realistic sensor noise - see '
        'tools/workout_engine_simulation.py, make_noisy_calibration_reps)',
        () {
      final engine = WorkoutEngine(exerciseId: 'bicep_curl');
      ExerciseSet? finishedSet;
      engine.events.listen((e) {
        if (e.completedSet != null) finishedSet = e.completedSet;
      });

      final rng = Random(42);
      var t = DateTime(2026, 1, 1);
      const step = Duration(milliseconds: 20);
      const repCount = 10;
      const samplesPerRep = 30;

      for (var rep = 0; rep < repCount; rep++) {
        for (var i = 0; i < samplesPerRep; i++) {
          final phase = (i / samplesPerRep) * 3.14159265;
          final magnitude = 1.0 + 0.8 * _sin(phase);
          // Substantially more noise than the clean-signal tests, to
          // approximate a nervous/unpracticed first-time user.
          final noise = (rng.nextDouble() - 0.5) * 0.3;
          engine.processSample(SensorSample(
            timestamp: t,
            ax: 0, ay: magnitude + noise, az: 0,
            gx: 0, gy: 0, gz: 0,
          ));
          t = t.add(step);
        }
        for (var i = 0; i < 5; i++) {
          engine.processSample(SensorSample(
            timestamp: t, ax: 0, ay: 0.0, az: 0, gx: 0, gy: 0, gz: 0,
          ));
          t = t.add(step);
        }
      }
      engine.endSetManually();

      expect(finishedSet, isNotNull);
      // Wide but meaningful band: catches the 18-for-10 failure mode
      // without demanding hardware-validated precision from a synthetic
      // test.
      expect(finishedSet!.countedReps, inInclusiveRange(7, 14));
      engine.dispose();
    });
  });

  // Added 2026-07-12 (docs/ANALYSE_EXTERNE_KI_2026-07-12.md Punkt F): the
  // guided-calibration path (WorkoutState.guidedCalibration,
  // startGuidedCalibration()/_finishGuidedCalibration()) previously had NO
  // test coverage at all - every test above only exercises the older
  // auto-calibration-from-first-3-reps path. See also
  // tools/workout_engine_simulation.py run_guided_calibration_suite() for
  // the Python-side equivalent, including a documented open finding.
  group('WorkoutEngine.guidedCalibration', () {
    test('startGuidedCalibration transitions state to guidedCalibration',
        () {
      final engine = WorkoutEngine(exerciseId: 'bicep_curl');
      engine.startGuidedCalibration();
      expect(engine.state, WorkoutState.guidedCalibration);
      engine.dispose();
    });

    test(
        'a pure rest signal (no real excursions) never spuriously '
        'completes calibration', () {
      final engine = WorkoutEngine(exerciseId: 'bicep_curl');
      engine.startGuidedCalibration();

      var t = DateTime(2026, 1, 1);
      for (var i = 0; i < 500; i++) {
        engine.processSample(SensorSample(
          timestamp: t, ax: 0, ay: 1.0, az: 0, gx: 0, gy: 0, gz: 0,
        ));
        t = t.add(const Duration(milliseconds: 20));
      }

      expect(engine.state, WorkoutState.guidedCalibration,
          reason: 'Without any real excursions above the gyro-validated '
              'peak thresholds, calibration must not complete.');
      engine.dispose();
    });

    test('cancelCalibration resets to idle and discards recorded signals',
        () {
      final engine = WorkoutEngine(exerciseId: 'bicep_curl');
      engine.startGuidedCalibration();

      var t = DateTime(2026, 1, 1);
      for (var i = 0; i < 20; i++) {
        engine.processSample(SensorSample(
          timestamp: t, ax: 0, ay: 1.5, az: 0, gx: 0, gy: 80, gz: 0,
        ));
        t = t.add(const Duration(milliseconds: 20));
      }

      engine.cancelCalibration();
      expect(engine.state, WorkoutState.idle);
      engine.dispose();
    });

    test(
        'regression: guided calibration completes at the real ~15Hz app data '
        'rate despite the median-filter plateau at a clean rep\'s peak '
        '(median filter + strict ">" on both sides could not select any '
        'index inside the plateau - fixed 2026-07-12 by making '
        '_findPeaksWithIndices tie-tolerant, see its doc comment and '
        'tools/workout_engine_simulation.py run_guided_calibration_suite, '
        '0/30 before the fix vs 30/30 after)',
        () {
      final engine = WorkoutEngine(exerciseId: 'bicep_curl');
      engine.startGuidedCalibration();

      // ~15 Hz, matching the app's real observed polling rate rather than
      // the 50Hz used in the other synthetic tests in this file.
      var t = DateTime(2026, 1, 1);
      const step = Duration(milliseconds: 67);
      for (var rep = 0; rep < 10; rep++) {
        const steps = 18;
        for (var i = 0; i < steps; i++) {
          final phase = (i / steps) * 3.14159265;
          final accelMag = 1.0 + 0.9 * _sin(phase);
          final gyroMag = 120 * _sin(phase);
          engine.processSample(SensorSample(
            timestamp: t, ax: 0, ay: accelMag, az: 0, gx: 0, gy: gyroMag, gz: 0,
          ));
          t = t.add(step);
        }
        for (var i = 0; i < 5; i++) {
          engine.processSample(SensorSample(
            timestamp: t, ax: 0, ay: 1.0, az: 0, gx: 0, gy: 0, gz: 0,
          ));
          t = t.add(step);
        }
      }

      expect(engine.state, WorkoutState.idle,
          reason: 'Calibration should complete with the tie-tolerant peak '
              'detector; if this fails, the plateau fix may have '
              'regressed.');
      engine.dispose();
    });

    test(
        'regression (ADR-020): the guided-calibration threshold must NOT be '
        'silently overwritten by the old one-rep auto-calibration when the '
        'first real movement after calibration begins (see '
        "docs/Umbauplan Flowrep/02_ARCHITECTURE_DECISION_RECORDS.md, "
        'ADR-020 - without the hasValidCalibration check in the idle-state '
        'handler, the very next movement after _finishGuidedCalibration() '
        're-enters WorkoutState.calibrating and recomputes peakThreshold '
        'from just that one rep, discarding the carefully guided-'
        'calibrated value)', () {
      final engine = WorkoutEngine(exerciseId: 'bicep_curl');
      engine.startGuidedCalibration();

      var t = DateTime(2026, 1, 1);
      const step = Duration(milliseconds: 67); // ~15 Hz, real app data rate
      const steps = 18;

      void feedOneRep() {
        for (var i = 0; i < steps; i++) {
          final phase = (i / steps) * 3.14159265;
          final accelMag = 1.0 + 0.9 * _sin(phase);
          final gyroMag = 120 * _sin(phase);
          engine.processSample(SensorSample(
            timestamp: t, ax: 0, ay: accelMag, az: 0, gx: 0, gy: gyroMag, gz: 0,
          ));
          t = t.add(step);
        }
        for (var i = 0; i < 5; i++) {
          engine.processSample(SensorSample(
            timestamp: t, ax: 0, ay: 1.0, az: 0, gx: 0, gy: 0, gz: 0,
          ));
          t = t.add(step);
        }
      }

      for (var rep = 0; rep < 10; rep++) {
        feedOneRep();
      }

      expect(engine.state, WorkoutState.idle,
          reason: 'Guided calibration should have completed by now.');
      expect(engine.hasValidCalibration, isTrue,
          reason: '_finishGuidedCalibration() must set this flag.');
      final thresholdAfterCalibration = engine.peakThreshold;

      // Exactly ONE more realistic rep, as if the user immediately started
      // their real working set right after calibration - the scenario
      // ADR-020 diagnoses.
      feedOneRep();

      expect(engine.peakThreshold, equals(thresholdAfterCalibration),
          reason: 'ADR-020 regression: the guided-calibrated threshold '
              'must survive the first post-calibration rep unchanged. If '
              'this fails, the idle-state hasValidCalibration check has '
              'regressed and the old one-rep auto-calibration is silently '
              'overwriting it again.');
      engine.dispose();
    });
  });
}

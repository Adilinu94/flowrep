import 'package:test/test.dart';
import 'package:flowrep/domain/workout_engine.dart';

/// Generates a synthetic "bicep curl"-like acceleration profile: baseline
/// gravity (~1g on the Y axis) plus `repCount` smooth sine-shaped
/// excursions, each rising above and falling back below `peakHeight`.
/// This is deliberately simple synthetic data, not real captured motion -
/// it exists to validate the state machine's logic (does N clean
/// excursions produce N counted reps?), not to claim real-world accuracy.
List<SensorSample> _generateSyntheticReps({
  required int repCount,
  double peakHeight = 1.8,
  double baseline = 1.0,
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
      var t = samples.last.timestamp;
      for (var i = 0; i < 250; i++) {
        t = t.add(const Duration(milliseconds: 20));
        engine.processSample(
          SensorSample(timestamp: t, ax: 0, ay: 1.0, az: 0, gx: 0, gy: 0, gz: 0),
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
      for (var i = 0; i < 20; i++) {
        engine.processSample(SensorSample(
          timestamp: DateTime.now(),
          ax: 0.01, ay: 1.0, az: 0.0, gx: 0, gy: 0, gz: 0,
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
  });
}

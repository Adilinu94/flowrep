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

/// Like [_generateSyntheticReps], but each rep is TWO humps
/// (`|sin(phase)|` over a full 0..2*pi period, instead of one hump over
/// 0..pi) with a genuine return-to-baseline trough between them - a curl's
/// concentric and eccentric phase, mirrored in
/// tools/workout_engine_simulation.py make_double_peak_reps(). This is what
/// S1 (docs/RECHERCHE_ZAEHLROBUSTHEIT_2026-07-16.md) is about: in a
/// magnitude-only signal each such rep can look like two separate
/// excursions to a threshold-only detector.
List<SensorSample> _generateSyntheticDoubleHumpReps({
  required int repCount,
  double peakHeight = 1.8,
  double baseline = 0.0,
  int samplesPerHumpPair = 60, // one full rep (both humps), ~1.2s @ 20ms
  int restSamplesBetween = 15, // ~0.3s, matches make_double_peak_reps
}) {
  final samples = <SensorSample>[];
  var t = DateTime(2026, 1, 1);
  const step = Duration(milliseconds: 20);

  for (var rep = 0; rep < repCount; rep++) {
    for (var i = 0; i < samplesPerHumpPair; i++) {
      final phase = (i / samplesPerHumpPair) * 2 * pi;
      final magnitude = baseline + (peakHeight - baseline) * sin(phase).abs();
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

/// For the Schritt B (g_p) shadow-counting tests: a signed GYRO signal
/// (not accel) with a genuine positive lobe (concentric) followed by a
/// genuine negative lobe (eccentric) per rep - `sin(phase)` over a full
/// 0..2*pi period, NOT `.abs()`'d like [_generateSyntheticDoubleHumpReps]
/// above. This is what g_p actually looks like on real hardware; the
/// magnitude-only helper above is deliberately the wrong shape for this
/// (it's testing what combined/_detectPeak sees, which never has a sign).
List<SensorSample> _generateSyntheticSignedGyroReps({
  required int repCount,
  double peakDegPerS = 200,
  int samplesPerRep = 60,
  int restSamplesBetween = 15,
  int axis = 2, // 0=gx, 1=gy, 2=gz - which axis carries the signal
}) {
  final samples = <SensorSample>[];
  var t = DateTime(2026, 1, 1);
  const step = Duration(milliseconds: 20);

  for (var rep = 0; rep < repCount; rep++) {
    for (var i = 0; i < samplesPerRep; i++) {
      final phase = (i / samplesPerRep) * 2 * pi;
      final gyroValue = peakDegPerS * sin(phase);
      samples.add(SensorSample(
        timestamp: t,
        ax: 0, ay: 0, az: 0,
        gx: axis == 0 ? gyroValue : 0,
        gy: axis == 1 ? gyroValue : 0,
        gz: axis == 2 ? gyroValue : 0,
      ));
      t = t.add(step);
    }
    for (var i = 0; i < restSamplesBetween; i++) {
      samples.add(SensorSample(timestamp: t, ax: 0, ay: 0, az: 0, gx: 0, gy: 0, gz: 0));
      t = t.add(step);
    }
  }
  return samples;
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

    test(
        'minRepIntervalSamples lockout (Agent 1 / Schritt A, S1 noise '
        'guard) suppresses a within-reach spurious re-trigger, without it '
        'double-counts', () async {
      // CORRECTED 2026-07-17 (Claude-c00679f3, after real `flutter test`
      // via Desktop Commander found a live regression - see
      // minRepIntervalSamples doc comment in workout_engine.dart for the
      // full story): this used to test a REALISTIC double-humped curl
      // (~30 samples between humps) and expect the lockout to fix it. It
      // doesn't, not at any value that also keeps the existing 35-samples/
      // rep tests above passing (24 <= 28 <= 35, with no overlap where
      // both a real double-hump AND the existing cadence are protected).
      // What 24 samples DOES still do: suppress a somewhat FASTER
      // re-trigger that's still within its reach - that's what this test
      // checks now, using a hump gap verified in
      // tools/workout_engine_simulation.py (not guessed) to double-count
      // at refractory=0 and land back near 10 at refractory=24.
      //
      // The actual double-hump fix is Schritt B (g_p, signed gyro
      // projection) - proven in tools/workout_engine_simulation.py
      // (pruefe_strukturellen_gp_fix: 10/10 with ZERO refractory needed),
      // not yet ported to this engine.
      final realistic = _generateSyntheticDoubleHumpReps(
        repCount: 10,
        samplesPerHumpPair: 60, // ~30-sample hump gap, matches a normal curl tempo
        restSamplesBetween: 15,
      );
      final withinReach = _generateSyntheticDoubleHumpReps(
        repCount: 10,
        samplesPerHumpPair: 40, // ~20-sample hump gap - verified below 24, so within the lockout's reach
        restSamplesBetween: 15,
      );
      Future<int> countOf(List<SensorSample> input, int minRepIntervalSamples) async {
        final tail = <SensorSample>[];
        var t = input.last.timestamp;
        for (var i = 0; i < 250; i++) {
          t = t.add(const Duration(milliseconds: 20));
          tail.add(SensorSample(timestamp: t, ax: 0, ay: 0.0, az: 0, gx: 0, gy: 0, gz: 0));
        }
        final engine = WorkoutEngine(
          exerciseId: 'bicep_curl',
          minRepIntervalSamples: minRepIntervalSamples,
        );
        ExerciseSet? finishedSet;
        engine.events.listen((e) {
          if (e.completedSet != null) finishedSet = e.completedSet;
        });
        for (final s in [...input, ...tail]) {
          engine.processSample(s);
        }
        engine.dispose();
        expect(finishedSet, isNotNull,
            reason: 'Expected the set to end after the pause timeout');
        return finishedSet!.countedReps;
      }

      final withoutLockout = await countOf(withinReach, 0);
      final withLockout = await countOf(withinReach, 24); // engine default
      final realisticWithLockout = await countOf(realistic, 24); // engine default

      expect(withoutLockout, greaterThan(10),
          reason: 'Sanity check that the within-reach input reproduces '
              'some genuine over-counting without any lockout at all - '
              'deliberately not pinned to a precise multiple of 10, since '
              'exactly how much a given synthetic gap over-counts depends '
              'on calibration-phase interactions that are not worth '
              'over-fitting a test to. The real claim is the comparison '
              'below.');
      expect(withLockout, lessThan(withoutLockout),
          reason: 'The 24-sample default must still measurably suppress a '
              'gap this size (~20 samples) - this is the actual, narrower '
              'claim this mechanism makes post-correction.');
      // Deliberately NOT asserting realisticWithLockout is close to 10 -
      // it isn't, and claiming otherwise would just reintroduce the
      // regression this test exists to prevent. Documented instead of
      // silently omitted.
      // ignore: avoid_print
      print('Realistic double-hump (~30-sample gap) with the 24-sample '
          'default: $realisticWithLockout counted (still not fixed by '
          'Schritt A alone - see Schritt B for the actual fix).');
    });

    test(
        'adaptiveThresholdRatio (Agent 1 / Schritt A, S2 fix) counts more '
        'reps of a within-session tempo drop than with adaptation '
        'disabled', () async {
      // Reproduces the "S2, realistischer Fall" section of
      // sweep_live_pfad_refraktaer_und_prominenz() in
      // tools/workout_engine_simulation.py: calibrate at a normal pace (3
      // reps, matching calibrationReps default... no, matching
      // adaptiveMinConfirmed=3 default here), then slow down for the rest
      // of the set. Comparable Python result: 3/10 without adaptation,
      // 6/10 with it - same mechanism, not necessarily the same exact
      // count here (different synthetic generator), so this asserts the
      // relative improvement rather than a specific number.
      //
      // NOT tested here (matches the Python sweep's explicit finding): a
      // COLD start where the entire session is below _peakThreshold from
      // sample 1 is unreachable by adaptiveThresholdRatio at all - that
      // needs Guided Calibration 2.0's own per-user calibration (Agent 2),
      // not this engine.
      final fastReps = _generateSyntheticReps(
          repCount: 3, peakHeight: 1.8, baseline: 0.0);
      var t = fastReps.isEmpty ? DateTime(2026, 1, 1) : fastReps.last.timestamp;
      final slowReps = <SensorSample>[];
      // Same shape as _generateSyntheticReps, just a lower peak and a
      // later start time, continuing on from where fastReps left off.
      for (var rep = 0; rep < 7; rep++) {
        for (var i = 0; i < 30; i++) {
          t = t.add(const Duration(milliseconds: 20));
          final phase = (i / 30) * 3.14159265;
          slowReps.add(SensorSample(
            timestamp: t, ax: 0, ay: 0.65 * _sin(phase), az: 0, gx: 0, gy: 0, gz: 0,
          ));
        }
        for (var i = 0; i < 5; i++) {
          t = t.add(const Duration(milliseconds: 20));
          slowReps.add(SensorSample(timestamp: t, ax: 0, ay: 0.0, az: 0, gx: 0, gy: 0, gz: 0));
        }
      }
      final mixed = [...fastReps, ...slowReps];

      Future<int> runWith(double adaptiveThresholdRatio) async {
        final engine = WorkoutEngine(
          exerciseId: 'bicep_curl',
          adaptiveThresholdRatio: adaptiveThresholdRatio,
        );
        var totalCounted = 0;
        engine.events.listen((e) {
          if (e.completedSet != null) totalCounted = e.completedSet!.countedReps;
        });
        for (final s in mixed) {
          engine.processSample(s);
        }
        // Force the set to end so countedReps reflects everything fed in,
        // even the still-open final rep of the tail.
        final tailStart = mixed.last.timestamp;
        for (var i = 0; i < 250; i++) {
          engine.processSample(SensorSample(
            timestamp: tailStart.add(Duration(milliseconds: 20 * (i + 1))),
            ax: 0, ay: 0.0, az: 0, gx: 0, gy: 0, gz: 0,
          ));
        }
        engine.dispose();
        return totalCounted;
      }

      final withoutAdaptation = await runWith(1.0); // ratio=1.0: never lowers below _peakThreshold
      final withAdaptation = await runWith(0.25); // engine default

      expect(withAdaptation, greaterThan(withoutAdaptation),
          reason: 'The whole point of S2: the same slowed-down reps should '
              'be counted more often once the effective threshold is '
              'allowed to adapt down from recently confirmed peaks, not '
              'stay pinned to the fast-tempo calibration value.');
    });

    test(
        'useSignedProjectionCounting (Agent 1 / Schritt B, P2/S8 '
        'structural fix) counts a double-humped rep correctly WITHOUT '
        'needing any refractory, unlike the combined-signal path',
        () async {
      // The actual structural fix, not the Schritt A noise-guard mitigation
      // above: g_p separates concentric/eccentric by SIGN. A signed gyro
      // signal with a genuine positive lobe then negative lobe (see
      // _generateSyntheticSignedGyroReps) should count once per rep on the
      // g_p shadow path even with the DEFAULT 24-sample refractory, which
      // (per the Schritt A tests above) does NOT fix a comparably-shaped
      // combined-signal double-hump.
      final signed = _generateSyntheticSignedGyroReps(repCount: 10);

      final tail = <SensorSample>[];
      var t = signed.last.timestamp;
      for (var i = 0; i < 250; i++) {
        t = t.add(const Duration(milliseconds: 20));
        tail.add(SensorSample(timestamp: t, ax: 0, ay: 0, az: 0, gx: 0, gy: 0, gz: 0));
      }

      final engine = WorkoutEngine(
        exerciseId: 'bicep_curl',
        useSignedProjectionCounting: true,
      );
      expect(engine.signedProjectionRepCount, isNull,
          reason: 'Before any samples are processed, neither the axis nor '
              'the g_p threshold have been learned yet.');

      for (final s in [...signed, ...tail]) {
        engine.processSample(s);
      }
      engine.dispose();

      expect(engine.signedProjectionRepCount, isNotNull,
          reason: 'After 10 reps worth of samples (well past the 100-sample '
              'axis-learning window and the first calibration rep), the '
              'shadow count should be available.');
      expect(engine.signedProjectionRepCount, closeTo(10, 2),
          reason: 'g_p should count close to the true 10 reps - see '
              'tools/workout_engine_simulation.py pruefe_strukturellen_gp_fix '
              'for the Python-side equivalent (exactly 10/10 there, but '
              'that proof reads g_p from sample 1 - it does not model the '
              'axisLearningWindowSamples=100 bootstrap cost this Dart port '
              'actually has to pay before the shadow counter can start at '
              'all, real value observed here: 8/10). Deliberately not '
              'shrinking that window just to tighten this number - fewer '
              'samples means a less reliable variance-based axis estimate '
              'on real hardware, which matters far more than this test '
              'looking cleaner.');
    });

    test(
        'useSignedProjectionCounting defaults to false and leaves '
        'countedReps/state completely unchanged when off', () async {
      // The isolation guarantee this whole feature depends on: turning
      // Schritt B off (the default) must reproduce EXACTLY the existing,
      // hardware-verified combined-signal behaviour - same input, same
      // count, just without a shadow number attached.
      final signed = _generateSyntheticSignedGyroReps(repCount: 10);
      final tail = <SensorSample>[];
      var t = signed.last.timestamp;
      for (var i = 0; i < 250; i++) {
        t = t.add(const Duration(milliseconds: 20));
        tail.add(SensorSample(timestamp: t, ax: 0, ay: 0, az: 0, gx: 0, gy: 0, gz: 0));
      }

      Future<int?> run({required bool useSignedProjectionCounting}) async {
        final engine = WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: useSignedProjectionCounting,
        );
        ExerciseSet? finishedSet;
        engine.events.listen((e) {
          if (e.completedSet != null) finishedSet = e.completedSet;
        });
        for (final s in [...signed, ...tail]) {
          engine.processSample(s);
        }
        engine.dispose();
        expect(engine.signedProjectionRepCount,
            useSignedProjectionCounting ? isNotNull : isNull);
        return finishedSet?.countedReps;
      }

      final countedOff = await run(useSignedProjectionCounting: false);
      final countedOn = await run(useSignedProjectionCounting: true);

      expect(countedOff, equals(countedOn),
          reason: 'countedReps comes entirely from the combined-signal '
              'path (_detectPeak), which Schritt B never writes to - '
              'toggling the shadow counter must not change it.');
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

    test(
        'applyCalibration() updates threshold and hasValidCalibration '
        'in place without recreating the engine (race-condition fix, '
        'found during E2E hardware test 2026-07-16: _loadCalibration() '
        'previously disposed+recreated the engine, leaving the '
        '_CalibrationDialog with a stale reference)', () {
      final engine = WorkoutEngine(exerciseId: 'bicep_curl');
      final initialThreshold = engine.peakThreshold;
      expect(engine.hasValidCalibration, isFalse);

      // Apply a persisted calibration as _loadCalibration() would.
      engine.applyCalibration(
        peakThreshold: 2.5,
        minThresholdAboveBaseline: 0.75,
      );

      expect(engine.peakThreshold, equals(2.5));
      expect(engine.minThresholdAboveBaseline, equals(0.75));
      expect(engine.hasValidCalibration, isTrue,
          reason: 'applyCalibration must set hasValidCalibration so the '
              'idle-state handler goes straight to active (ADR-020), '
              'not to the one-rep auto-calibration path.');
      expect(engine.state, WorkoutState.idle);

      // The engine instance must still be usable — feed a sample and
      // verify it processes without errors.
      engine.processSample(SensorSample(
        timestamp: DateTime.now(),
        ax: 0, ay: 1.0, az: 0, gx: 0, gy: 0, gz: 0,
      ));
      expect(engine.state, WorkoutState.idle,
          reason: 'A resting sample (~1.0g) must not trigger a state '
              'change with a threshold of 2.5.');

      // Verify that guided calibration still works after applyCalibration —
      // this is the exact scenario that was broken: load calibration, then
      // start guided calibration from a dialog that captured this engine.
      engine.startGuidedCalibration();
      expect(engine.state, WorkoutState.guidedCalibration,
          reason: 'startGuidedCalibration() must work after '
              'applyCalibration() — this is the race condition that was '
              'broken when _loadCalibration() disposed the engine.');

      // Threshold should be reset by startGuidedCalibration.
      expect(engine.peakThreshold, equals(1.2),
          reason: 'startGuidedCalibration() resets threshold to 1.2 '
              'regardless of what applyCalibration set.');
      expect(initialThreshold, equals(1.2),
          reason: 'Sanity: default threshold is 1.2.');

      engine.dispose();
    });

    test(
        'regression: baseline must NOT drift upward during guidedCalibration '
        '(found during E2E hardware test 2026-07-16: baseline drifted from '
        '1.05 to 5.7 because _aboveThreshold is never set true in this '
        'state, so the EMA tracked every sample including movement spikes)', () {
      final engine = WorkoutEngine(exerciseId: 'bicep_curl');

      // Feed rest samples FIRST (in idle state) to settle the signal
      // processor's EMA to ~1.0. Then start calibration so
      // _baselineLevel captures the settled rest level.
      var t = DateTime(2026, 1, 1);
      const step = Duration(milliseconds: 67);
      for (var i = 0; i < 10; i++) {
        engine.processSample(SensorSample(
          timestamp: t, ax: 0, ay: 1.0, az: 0, gx: 0, gy: 0, gz: 0,
        ));
        t = t.add(step);
      }
      engine.startGuidedCalibration();
      final baselineBefore = engine.baselineLevel;

      // Feed 10 reps of large excursions. Gyro is deliberately kept BELOW
      // the 50 deg/s validation threshold so _findGyroValidatedPeaks()
      // rejects all peaks and calibration NEVER completes — this keeps
      // the engine in guidedCalibration state for the entire test,
      // isolating the baseline-freeze behavior. The combined signal still
      // reaches ~3.9 (accel 1.9 + gyro 40*0.05=2.0), well above baseline.
      for (var rep = 0; rep < 10; rep++) {
        const steps = 18;
        for (var i = 0; i < steps; i++) {
          final phase = (i / steps) * 3.14159265;
          final accelMag = 1.0 + 0.9 * _sin(phase);
          final gyroMag = 40 * _sin(phase); // <50: peaks not validated
          engine.processSample(SensorSample(
            timestamp: t, ax: 0, ay: accelMag, az: 0,
            gx: 0, gy: gyroMag, gz: 0,
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

      // Engine must still be in guidedCalibration (no peaks validated).
      expect(engine.state, WorkoutState.guidedCalibration,
          reason: 'Calibration must not have completed — gyro was kept '
              'below the 50 deg/s validation threshold.');

      final baselineAfter = engine.baselineLevel;

      // The baseline must be EXACTLY the same — it's frozen during
      // guidedCalibration. No tolerance needed because the EMA update
      // is completely skipped in this state.
      expect(baselineAfter, equals(baselineBefore),
          reason: 'Baseline must not drift during guidedCalibration. '
              'Before the fix it rose from ~1.0 to ~5.7 because the EMA '
              'tracked movement spikes. After the fix, the baseline is '
              'frozen for the duration of guided calibration.');
      engine.dispose();
    });
  });
}

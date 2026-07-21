import 'package:flutter_test/flutter_test.dart';

import 'package:flowrep/domain/signal_processor.dart';
import 'package:flowrep/domain/workout_engine.dart';

SensorSample _sample({
  DateTime? t,
  double gx = 0,
  double gy = 0,
  double gz = 0,
  double ax = 0,
  double ay = 0,
  double az = 0,
}) =>
    SensorSample(
      timestamp: t ?? DateTime(2026, 1, 1),
      ax: ax, ay: ay, az: az,
      gx: gx, gy: gy, gz: gz,
    );

void main() {
  group('SignalProcessor.process (existing combined-signal path)', () {
    test('is completely unaffected by the g_p learning/query calls - '
        'Schritt B is additive, not a modification of the existing path',
        () {
      final withGp = SignalProcessor();
      final withoutGp = SignalProcessor();
      final samples = List.generate(
        150,
        (i) => _sample(gx: 5.0 + i * 0.1, gy: 1.0, gz: -2.0, ay: 0.5),
      );

      final resultsWithGp = <double>[];
      for (final s in samples) {
        withGp.observeForAxisLearning(s);
        withGp.signedGyroProjection(s);
        resultsWithGp.add(withGp.process(s));
      }
      final resultsWithoutGp = samples.map(withoutGp.process).toList();

      expect(resultsWithGp, equals(resultsWithoutGp));
    });
  });

  group('SignalProcessor Schritt B (g_p) additions', () {
    test('signedGyroProjection returns null before enough samples have '
        'been observed', () {
      final sp = SignalProcessor(axisLearningWindowSamples: 10);
      for (var i = 0; i < 9; i++) {
        sp.observeForAxisLearning(_sample(gx: 5, gy: 1, gz: 1));
      }
      expect(sp.isSignedProjectionReady, isFalse);
      expect(sp.signedGyroProjection(_sample(gx: 5, gy: 1, gz: 1)), isNull);
    });

    test('picks the axis with the most variance during the learning '
        'window, not the largest raw value', () {
      final sp = SignalProcessor(axisLearningWindowSamples: 60);
      // gx: large but CONSTANT (zero variance) - a naive "biggest value"
      // heuristic would wrongly pick this.
      // gy: smaller but genuinely oscillating (the real signal of interest).
      for (var i = 0; i < 60; i++) {
        sp.observeForAxisLearning(_sample(
          gx: 100.0,
          gy: 10.0 * (i.isEven ? 1 : -1),
          gz: 0.5,
        ));
      }
      expect(sp.isSignedProjectionReady, isTrue);
      // Confirm it's gy, not gx: a sample with gy=+50 (clearly off the
      // oscillation pattern above) should project to a large value if gy
      // was chosen, or to ~0 (relative to the learned gx bias of 100) if
      // gx was wrongly chosen instead.
      final probe = sp.signedGyroProjection(_sample(gx: 100.0, gy: 50.0, gz: 0.5));
      expect(probe, isNotNull);
      expect(probe!.abs(), greaterThan(20),
          reason: 'Expected the projection to reflect gy (the '
              'high-variance axis), not gx (high-value but constant).');
    });

    test('subtracts the learned bias, not just the raw axis value', () {
      final sp = SignalProcessor(axisLearningWindowSamples: 50);
      // gz oscillates AROUND a bias of +20, not around zero.
      for (var i = 0; i < 50; i++) {
        sp.observeForAxisLearning(
            _sample(gx: 0, gy: 0, gz: 20.0 + (i.isEven ? 5 : -5)));
      }
      expect(sp.isSignedProjectionReady, isTrue);
      // At exactly the learned bias (20), the projection should be ~0.
      final atBias = sp.signedGyroProjection(_sample(gz: 20.0));
      expect(atBias, isNotNull);
      expect(atBias!.abs(), lessThan(0.5));
    });
  });

  group('SignalProcessor.setKnownAxis (Punkt 1, arbitrary-direction axis)', () {
    test('is ready immediately, without any observeForAxisLearning calls', () {
      final sp = SignalProcessor();
      expect(sp.isSignedProjectionReady, isFalse);
      sp.setKnownAxis([1.0, 0.0, 0.0], [0.0, 0.0, 0.0]);
      expect(sp.isSignedProjectionReady, isTrue);
    });

    test('projects onto a true arbitrary (non-cardinal) unit vector, not '
        'just one raw axis component', () {
      final sp = SignalProcessor();
      // 3-4-... a simple non-cardinal unit vector: (0.6, 0.8, 0.0).
      sp.setKnownAxis([0.6, 0.8, 0.0], [0.0, 0.0, 0.0]);
      // Pure gx=10 alone should NOT give the full 10 - only its 0.6
      // component. A single-cardinal-axis implementation (picking
      // whichever raw component is largest) would instead return exactly
      // 10 or 0 here, not 6.
      final projected = sp.signedGyroProjection(_sample(gx: 10.0, gy: 0.0));
      expect(projected, isNotNull);
      expect(projected!, closeTo(6.0, 1e-9));
    });

    test('subtracts the provided gyro bias per-axis, matching the '
        'learned-axis behaviour', () {
      final sp = SignalProcessor();
      sp.setKnownAxis([1.0, 0.0, 0.0], [5.0, 0.0, 0.0]);
      final atBias = sp.signedGyroProjection(_sample(gx: 5.0));
      expect(atBias, isNotNull);
      expect(atBias!.abs(), lessThan(1e-9));
    });

    test('overrides an in-progress runtime learning window rather than '
        'being overridden by it', () {
      final sp = SignalProcessor(axisLearningWindowSamples: 100);
      for (var i = 0; i < 50; i++) {
        sp.observeForAxisLearning(_sample(gx: 5, gy: 1, gz: 1));
      }
      expect(sp.isSignedProjectionReady, isFalse);
      sp.setKnownAxis([0.0, 1.0, 0.0], [0.0, 0.0, 0.0]);
      expect(sp.isSignedProjectionReady, isTrue);
      // Further observeForAxisLearning calls must now be no-ops (the
      // known axis must not get silently overwritten once the runtime
      // window happens to fill up afterwards).
      for (var i = 0; i < 100; i++) {
        sp.observeForAxisLearning(_sample(gx: 5, gy: 1, gz: 1));
      }
      final projected = sp.signedGyroProjection(_sample(gx: 999.0, gy: 7.0));
      expect(projected, isNotNull);
      expect(projected!, closeTo(7.0, 1e-9),
          reason: 'Expected the known y-axis to still be in effect, not '
              'overwritten by the runtime heuristic.');
    });
  });
}

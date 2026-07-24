import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/metrics/slow_rep_shadow.dart';
import 'package:flowrep/domain/models/exercise_profile.dart';
import 'package:flowrep/domain/workout_engine.dart';

void main() {
  group('SlowRepShadow pure', () {
    test('flags near-miss under product peak gate', () {
      expect(
        SlowRepShadow.shouldFlag(
          productAccepted: false,
          peak: 90,
          threshold: 100,
          samplesAbove: 12,
        ),
        isTrue,
      );
    });

    test('rejects wiggle (too short / too weak)', () {
      expect(
        SlowRepShadow.shouldFlag(
          productAccepted: false,
          peak: 90,
          threshold: 100,
          samplesAbove: 3,
        ),
        isFalse,
      );
      expect(
        SlowRepShadow.shouldFlag(
          productAccepted: false,
          peak: 50,
          threshold: 100,
          samplesAbove: 20,
        ),
        isFalse,
      );
    });

    test('never flags when product accepted', () {
      expect(
        SlowRepShadow.shouldFlag(
          productAccepted: true,
          peak: 90,
          threshold: 100,
          samplesAbove: 20,
        ),
        isFalse,
      );
    });
  });

  group('WorkoutEngine slow-rep shadow integration', () {
    late WorkoutEngine engine;

    /// θ_applied = max(50, 100×0.70) = 70.
    /// Product peak ≥ 1.2×70 = 84; shadow ≥ 0.85×70 ≈ 59.5; min samples product 15 / shadow 10.
    setUp(() {
      engine = WorkoutEngine(
        exerciseId: 'bicep_curl',
        useSignedProjectionCounting: true,
        autoEndSetEnabled: false,
      );
      engine.ghostGateEnabled = false;
      engine.applyCalibration(
        peakThreshold: 100,
        minThresholdAboveBaseline: 0.1,
        rotationAxis: const [0.0, 0.0, 1.0],
        gyroBias: const [0.0, 0.0, 0.0],
        chosenSignal: ChosenSignal.gP,
        minRepIntervalSeconds: 0.3,
      );
    });

    SensorSample sample(double gz, {required int ms}) {
      return SensorSample(
        timestamp: DateTime.utc(2026, 7, 24).add(Duration(milliseconds: ms)),
        ax: 0,
        ay: 0,
        az: 1,
        gx: 0,
        gy: 0,
        gz: gz,
      );
    }

    test('slow hump under 1.2θ does not live-count but shadows', () {
      expect(engine.gpThreshold, closeTo(70.0, 0.1));
      var t = 0;
      for (var i = 0; i < 5; i++) {
        engine.processSample(sample(0, ms: t));
        t += 20;
      }
      // Peak 75: > θ 70 (enters excursion), < 84 product peak gate, > 59.5 shadow.
      for (var i = 0; i < 20; i++) {
        engine.processSample(sample(75, ms: t));
        t += 20;
      }
      for (var i = 0; i < 5; i++) {
        engine.processSample(sample(0, ms: t));
        t += 20;
      }

      expect(engine.repsInCurrentSetCount, 0,
          reason: 'live product must not count under-peak slow curl');
      expect(engine.slowRepShadowCount, greaterThanOrEqualTo(1),
          reason: 'searchback shadow should see the near-miss');
    });

    test('strong product rep does not inflate slow shadow', () {
      var t = 0;
      for (var i = 0; i < 5; i++) {
        engine.processSample(sample(0, ms: t));
        t += 20;
      }
      for (var i = 0; i < 20; i++) {
        engine.processSample(sample(150, ms: t));
        t += 20;
      }
      for (var i = 0; i < 5; i++) {
        engine.processSample(sample(0, ms: t));
        t += 20;
      }

      expect(engine.repsInCurrentSetCount, 1);
      expect(engine.slowRepShadowCount, 0);
    });
  });
}

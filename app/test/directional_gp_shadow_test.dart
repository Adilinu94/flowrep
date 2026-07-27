import 'dart:math';

import 'package:flowrep/domain/metrics/directional_gp_shadow.dart';
import 'package:flowrep/domain/models/exercise_profile.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:test/test.dart';

void main() {
  void feed(DirectionalGpShadow shadow, double value, int samples) {
    for (var i = 0; i < samples; i++) {
      shadow.processSample(value);
    }
  }

  void feedBipolarRep(DirectionalGpShadow shadow, {int samples = 20}) {
    feed(shadow, 0, 5);
    feed(shadow, 150, samples);
    feed(shadow, 0, 3);
    feed(shadow, -150, samples);
    feed(shadow, 0, 12);
  }

  group('DirectionalGpShadow', () {
    test('counts one bipolar repetition once instead of twice', () {
      final shadow = DirectionalGpShadow(threshold: 70);

      feedBipolarRep(shadow);

      expect(shadow.shadowRepCount, 1);
      expect(shadow.mountMismatchSuspected, isFalse);
    });

    test('counts repeated double-bump movements one per full cycle', () {
      final shadow = DirectionalGpShadow(threshold: 70);

      for (var i = 0; i < 10; i++) {
        feedBipolarRep(shadow);
      }

      expect(shadow.shadowRepCount, 10);
      expect(shadow.mountMismatchSuspected, isFalse);
    });

    test('rejects short and weak wiggles', () {
      final shadow = DirectionalGpShadow(threshold: 70);

      feed(shadow, 150, 8);
      feed(shadow, 0, 10);
      feed(shadow, 75, 20);
      feed(shadow, 0, 10);

      expect(shadow.shadowRepCount, 0);
    });

    test('counts slow repetitions when their direction and ROM qualify', () {
      final shadow = DirectionalGpShadow(threshold: 70);

      for (var i = 0; i < 5; i++) {
        feedBipolarRep(shadow, samples: 45);
      }

      expect(shadow.shadowRepCount, 5);
    });

    test('does not treat the normal return as a mount mismatch', () {
      final shadow = DirectionalGpShadow(threshold: 70);

      for (var i = 0; i < 3; i++) {
        feedBipolarRep(shadow);
      }

      expect(shadow.unpairedOppositeCycles, 0);
      expect(shadow.mountMismatchSuspected, isFalse);
    });

    test('flags repeated qualifying opposite-only movements', () {
      final shadow = DirectionalGpShadow(threshold: 70);

      for (var i = 0; i < 2; i++) {
        feed(shadow, -150, 20);
        feed(shadow, 0, 12);
      }

      expect(shadow.shadowRepCount, 0);
      expect(shadow.mountMismatchSuspected, isTrue);
    });

    test('reset clears both counter and mismatch evidence', () {
      final shadow = DirectionalGpShadow(threshold: 70);
      feed(shadow, -150, 20);
      feed(shadow, 0, 12);
      feed(shadow, -150, 20);
      feed(shadow, 0, 12);
      expect(shadow.mountMismatchSuspected, isTrue);

      shadow.reset();

      expect(shadow.shadowRepCount, 0);
      expect(shadow.unpairedOppositeCycles, 0);
      expect(shadow.mountMismatchSuspected, isFalse);
    });
  });

  test('gP profile runs the directional counter as shadow only', () {
    final engine = WorkoutEngine(
      exerciseId: 'bicep_curl',
      autoEndSetEnabled: false,
    )..ghostGateEnabled = false;
    engine.applyCalibration(
      peakThreshold: 100,
      minThresholdAboveBaseline: 0.1,
      rotationAxis: const [0, 0, 1],
      gyroBias: const [0, 0, 0],
      chosenSignal: ChosenSignal.gP,
    );

    var timestamp = DateTime.utc(2026, 7, 27);
    void feedEngine(double gz, int samples) {
      for (var i = 0; i < samples; i++) {
        engine.processSample(
          SensorSample(
            timestamp: timestamp,
            ax: 0,
            ay: 0,
            az: 1,
            gx: 0,
            gy: 0,
            gz: gz,
          ),
        );
        timestamp = timestamp.add(const Duration(milliseconds: 20));
      }
    }

    for (var rep = 0; rep < 10; rep++) {
      for (var i = 0; i < 60; i++) {
        feedEngine(200 * sin((i / 60) * 2 * pi), 1);
      }
      feedEngine(0, 15);
    }

    expect(engine.directionalGpShadowRepCount, 10);
    expect(engine.gpMountMismatchSuspected, isFalse);
    engine.dispose();
  });
}

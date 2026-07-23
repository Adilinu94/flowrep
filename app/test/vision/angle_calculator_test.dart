import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/vision/angle_calculator.dart';
import 'package:flowrep/domain/vision/vision_config.dart';

void main() {
  group('VisionConfig (CV-01)', () {
    test('defaults: disabled, bicep-curl thresholds', () {
      const c = VisionConfig();
      expect(c.enabled, isFalse);
      expect(c.angleDownThreshold, 160.0);
      expect(c.angleUpThreshold, 90.0);
      expect(c.minLandmarkConfidence, 0.5);
      expect(c.minRepIntervalSeconds, 0.5);
      expect(c.maxRepDurationSeconds, 5.0);
    });

    test('copyWith and equality', () {
      const base = VisionConfig();
      final on = base.copyWith(enabled: true, cameraLens: 'front');
      expect(on.enabled, isTrue);
      expect(on.cameraLens, 'front');
      expect(on.angleDownThreshold, base.angleDownThreshold);
      expect(base, const VisionConfig());
      expect(on, isNot(equals(base)));
    });

    test('presets', () {
      expect(VisionConfig.disabled.enabled, isFalse);
      expect(VisionConfig.bicepCurl.enabled, isTrue);
    });
  });

  group('AngleCalculator (CV-02 pure math)', () {
    test('right angle at origin: 90 degrees', () {
      // A=(0,1), B=(0,0), C=(1,0) → 90°
      final angle = AngleCalculator.calculateAngle(
        a: const LandmarkPoint(x: 0, y: 1),
        b: const LandmarkPoint(x: 0, y: 0),
        c: const LandmarkPoint(x: 1, y: 0),
      );
      expect(angle, closeTo(90.0, 0.01));
    });

    test('straight arm (extended) ≈ 180 degrees', () {
      // A=(-1,0), B=(0,0), C=(1,0) → 180°
      final angle = AngleCalculator.calculateAngle(
        a: const LandmarkPoint(x: -1, y: 0),
        b: const LandmarkPoint(x: 0, y: 0),
        c: const LandmarkPoint(x: 1, y: 0),
      );
      expect(angle, closeTo(180.0, 0.01));
    });

    test('acute contracted curl ≈ 45 degrees', () {
      // Vectors BA and BC at 45°
      // B at origin, A along y, C at 45° in Q1
      final angle = AngleCalculator.calculateAngle(
        a: const LandmarkPoint(x: 0, y: 1),
        b: const LandmarkPoint(x: 0, y: 0),
        c: const LandmarkPoint(x: 1, y: 1),
      );
      expect(angle, closeTo(45.0, 0.01));
    });

    test('degenerate zero-length vector returns 0', () {
      final angle = AngleCalculator.calculateAngle(
        a: const LandmarkPoint(x: 0, y: 0),
        b: const LandmarkPoint(x: 0, y: 0),
        c: const LandmarkPoint(x: 1, y: 0),
      );
      expect(angle, 0.0);
    });

    test('allConfident respects minConfidence', () {
      expect(
        AngleCalculator.allConfident(
          a: const LandmarkPoint(x: 0, y: 0, confidence: 0.9),
          b: const LandmarkPoint(x: 1, y: 0, confidence: 0.9),
          c: const LandmarkPoint(x: 1, y: 1, confidence: 0.9),
        ),
        isTrue,
      );
      expect(
        AngleCalculator.allConfident(
          a: const LandmarkPoint(x: 0, y: 0, confidence: 0.4),
          b: const LandmarkPoint(x: 1, y: 0, confidence: 0.9),
          c: const LandmarkPoint(x: 1, y: 1, confidence: 0.9),
          minConfidence: 0.5,
        ),
        isFalse,
      );
    });

    test('elbowAngleDegrees right arm from landmark list', () {
      // Build minimal list with indices 0..16
      final landmarks = List.generate(
        17,
        (i) => const LandmarkPoint(x: 0, y: 0, confidence: 0.1),
      );
      // Right shoulder, elbow, wrist: extended arm
      landmarks[PoseLandmarkIndex.rightShoulder] =
          const LandmarkPoint(x: 0, y: 1, confidence: 0.9);
      landmarks[PoseLandmarkIndex.rightElbow] =
          const LandmarkPoint(x: 0, y: 0, confidence: 0.9);
      landmarks[PoseLandmarkIndex.rightWrist] =
          const LandmarkPoint(x: 0, y: -1, confidence: 0.9);

      final angle = AngleCalculator.elbowAngleDegrees(
        landmarks: landmarks,
        rightArm: true,
      );
      expect(angle, isNotNull);
      expect(angle!, closeTo(180.0, 0.01));
    });

    test('elbowAngleDegrees returns null when confidence low', () {
      final landmarks = List.generate(
        17,
        (i) => const LandmarkPoint(x: 0, y: 0, confidence: 0.1),
      );
      expect(
        AngleCalculator.elbowAngleDegrees(
          landmarks: landmarks,
          rightArm: false,
        ),
        isNull,
      );
    });

    test('elbowAngleDegrees returns null when list too short', () {
      expect(
        AngleCalculator.elbowAngleDegrees(
          landmarks: const [LandmarkPoint(x: 0, y: 0)],
          rightArm: true,
        ),
        isNull,
      );
    });
  });

  group('CV architecture invariants', () {
    test('default VisionConfig keeps camera off (IMU authoritative)', () {
      // Shipped default must not auto-enable camera.
      expect(const VisionConfig().enabled, isFalse);
    });
  });
}

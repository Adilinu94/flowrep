import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/vision/pose_rep_counter.dart';
import 'package:flowrep/domain/vision/vision_config.dart';

void main() {
  group('PoseRepCounter (CV-03)', () {
    late PoseRepCounter counter;

    setUp(() {
      counter = PoseRepCounter(
        config: const VisionConfig(
          angleDownThreshold: 160,
          angleUpThreshold: 90,
          minRepIntervalSeconds: 0.5,
          maxRepDurationSeconds: 5.0,
        ),
      );
    });

    test('starts waiting; needs arm down first', () {
      final r = counter.processAngle(elbowAngleDegrees: 45, timestampMs: 0);
      expect(r.repCounted, isFalse);
      expect(counter.state, PoseRepState.waiting);
    });

    test('full curl down→up→down counts one rep', () {
      // Extended
      var r = counter.processAngle(elbowAngleDegrees: 170, timestampMs: 0);
      expect(counter.state, PoseRepState.armDown);
      expect(r.repCounted, isFalse);

      // Contracted
      r = counter.processAngle(elbowAngleDegrees: 50, timestampMs: 800);
      expect(counter.state, PoseRepState.armUp);
      expect(r.repCounted, isFalse);

      // Extended again → rep
      r = counter.processAngle(elbowAngleDegrees: 170, timestampMs: 1600);
      expect(r.repCounted, isTrue);
      expect(r.repNumber, 1);
      expect(counter.repCount, 1);
      expect(counter.state, PoseRepState.armDown);
    });

    test('hysteresis: mid angles do not flip state', () {
      counter.processAngle(elbowAngleDegrees: 170, timestampMs: 0);
      expect(counter.state, PoseRepState.armDown);
      // Between thresholds
      counter.processAngle(elbowAngleDegrees: 120, timestampMs: 100);
      expect(counter.state, PoseRepState.armDown);
    });

    test('rejects too-fast second rep', () {
      // First complete rep
      counter.processAngle(elbowAngleDegrees: 170, timestampMs: 0);
      counter.processAngle(elbowAngleDegrees: 40, timestampMs: 500);
      final first =
          counter.processAngle(elbowAngleDegrees: 170, timestampMs: 1000);
      expect(first.repCounted, isTrue);

      // Second cycle too soon after last rep
      counter.processAngle(elbowAngleDegrees: 40, timestampMs: 1100);
      final second =
          counter.processAngle(elbowAngleDegrees: 170, timestampMs: 1200);
      expect(second.repCounted, isFalse);
      expect(second.rejectionReason, contains('Zu schnell'));
      expect(counter.repCount, 1);
      expect(counter.framesRejectedTooFast, greaterThan(0));
    });

    test('rejects too-slow rep duration', () {
      counter.processAngle(elbowAngleDegrees: 170, timestampMs: 0);
      counter.processAngle(elbowAngleDegrees: 40, timestampMs: 100);
      // Stay up for > maxRepDuration then go down
      final r = counter.processAngle(
        elbowAngleDegrees: 170,
        timestampMs: 100 + 6000, // 6s > 5s max
      );
      expect(r.repCounted, isFalse);
      expect(r.rejectionReason, contains('Zu langsam'));
      expect(counter.repCount, 0);
      expect(counter.framesRejectedTooSlow, 1);
    });

    test('counts multiple valid reps', () {
      var t = 0;
      for (var i = 0; i < 3; i++) {
        counter.processAngle(elbowAngleDegrees: 170, timestampMs: t);
        t += 700;
        counter.processAngle(elbowAngleDegrees: 40, timestampMs: t);
        t += 700;
        final r =
            counter.processAngle(elbowAngleDegrees: 170, timestampMs: t);
        expect(r.repCounted, isTrue, reason: 'rep ${i + 1}');
        t += 700;
      }
      expect(counter.repCount, 3);
    });

    test('processNoPose increments counter without state change', () {
      counter.processAngle(elbowAngleDegrees: 170, timestampMs: 0);
      expect(counter.state, PoseRepState.armDown);
      counter.processNoPose();
      expect(counter.framesWithoutPose, 1);
      expect(counter.state, PoseRepState.armDown);
    });

    test('reset clears all state', () {
      counter.processAngle(elbowAngleDegrees: 170, timestampMs: 0);
      counter.processAngle(elbowAngleDegrees: 40, timestampMs: 500);
      counter.processAngle(elbowAngleDegrees: 170, timestampMs: 1200);
      expect(counter.repCount, 1);
      counter.reset();
      expect(counter.repCount, 0);
      expect(counter.state, PoseRepState.waiting);
      expect(counter.totalFramesProcessed, 0);
    });
  });
}

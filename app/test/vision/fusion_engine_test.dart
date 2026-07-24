import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/repositories/i_workout_repository.dart';
import 'package:flowrep/domain/vision/fusion_engine.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:flowrep/presentation/providers/engine_provider.dart';

class _NoopRepo implements IWorkoutRepository {
  @override
  Future<void> saveCorrection(CorrectionEvent event) async {}

  @override
  Future<void> saveSession(WorkoutSession session) async {}

  @override
  Future<List<WorkoutSession>> getHistory() async => const [];

  @override
  Future<void> deleteAllUserData() async {}
}

void main() {
  group('FusionEngine (CV-04)', () {
    late FusionEngine fusion;

    setUp(() {
      fusion = FusionEngine(
        config: const FusionConfig(
          fusionWindowMs: 500,
          allowCameraOnly: false,
          minCameraConfidence: 0.5,
        ),
      );
    });

    test('both sources within window → count with both', () {
      fusion.onImuRep(timestampMs: 1000);
      fusion.onCameraRep(timestampMs: 1100, confidence: 0.9);
      final r = fusion.getDecision(currentTimestampMs: 1200);
      expect(r.shouldCount, isTrue);
      expect(r.source, RepSource.both);
      expect(r.confidence, 1.0);
      expect(fusion.fusedReps, 1);
      expect(fusion.totalImuReps, 1);
      expect(fusion.totalCameraReps, 1);
    });

    test('IMU only → count (authoritative)', () {
      fusion.onImuRep(timestampMs: 1000);
      final r = fusion.getDecision(currentTimestampMs: 1200);
      expect(r.shouldCount, isTrue);
      expect(r.source, RepSource.imuOnly);
      expect(fusion.imuOnlyReps, 1);
    });

    test('camera only without allowCameraOnly → reject', () {
      fusion.onCameraRep(timestampMs: 1000, confidence: 0.9);
      final r = fusion.getDecision(currentTimestampMs: 1100);
      expect(r.shouldCount, isFalse);
      expect(r.source, RepSource.cameraOnly);
      expect(fusion.rejectedCameraReps, 1);
    });

    test('camera only with allowCameraOnly → count', () {
      fusion = FusionEngine(
        config: const FusionConfig(allowCameraOnly: true),
      );
      fusion.onCameraRep(timestampMs: 1000, confidence: 0.9);
      final r = fusion.getDecision(currentTimestampMs: 1100);
      expect(r.shouldCount, isTrue);
      expect(r.source, RepSource.cameraOnly);
      expect(fusion.cameraOnlyReps, 1);
    });

    test('low camera confidence not treated as recent camera', () {
      fusion.onImuRep(timestampMs: 1000);
      fusion.onCameraRep(timestampMs: 1050, confidence: 0.2);
      final r = fusion.getDecision(currentTimestampMs: 1100);
      // hasRecentCamera requires confidence only for "both" branch;
      // low confidence means cameraConfident false → falls to IMU only
      // if hasRecentCamera is true but cameraConfident false...
      // Looking at logic: hasRecentCamera is true even with low conf.
      // Fall 1 needs cameraConfident. Fall 2 needs !hasRecentCamera.
      // Fall 3 needs !hasRecentImu. So we get Fall 4 none.
      // That might be a doc bug - for V1 IMU should still count.
      // Our implementation matches the doc literally; document via expect.
      // After re-read: Fall 2 is hasRecentImu && !hasRecentCamera.
      // If camera event exists but low conf, hasRecentCamera is still true
      // so we don't hit Fall 2. Fall 1 fails cameraConfident. Fall 3 needs
      // !hasRecentImu. → Fall 4. This is a gap: IMU event is left uncleared.
      // Fix in engine: treat unconfident camera as "no camera opinion".
      expect(r.shouldCount, isTrue); // after engine fix
      expect(r.source, RepSource.imuOnly);
    });

    test('stale events outside window → no count', () {
      fusion.onImuRep(timestampMs: 1000);
      final r = fusion.getDecision(currentTimestampMs: 2000);
      expect(r.shouldCount, isFalse);
      expect(r.confidence, 0.0);
    });

    test('reset clears stats and pending events', () {
      fusion.onImuRep(timestampMs: 1);
      fusion.onCameraRep(timestampMs: 2, confidence: 1);
      fusion.getDecision(currentTimestampMs: 100);
      fusion.reset();
      expect(fusion.totalImuReps, 0);
      expect(fusion.fusedReps, 0);
      expect(
        fusion.getDecision(currentTimestampMs: 200).shouldCount,
        isFalse,
      );
    });

    test('agreementLabel and ratio for product badge', () {
      expect(fusion.agreementRatio, isNull);
      expect(fusion.agreementLabel, 'Pose bereit');
      expect(fusion.imuDecidedReps, 0);

      // 2 both + 1 imuOnly → Pose bestätigt 2/3
      fusion.onImuRep(timestampMs: 1000);
      fusion.onCameraRep(timestampMs: 1050, confidence: 0.9);
      fusion.getDecision(currentTimestampMs: 1100);

      fusion.onImuRep(timestampMs: 2000);
      fusion.onCameraRep(timestampMs: 2050, confidence: 0.9);
      fusion.getDecision(currentTimestampMs: 2100);

      fusion.onImuRep(timestampMs: 3000);
      fusion.getDecision(currentTimestampMs: 3100);

      expect(fusion.fusedReps, 2);
      expect(fusion.imuOnlyReps, 1);
      expect(fusion.imuDecidedReps, 3);
      expect(fusion.agreementRatio, closeTo(2 / 3, 1e-9));
      expect(fusion.agreementLabel, 'Pose bestätigt 2/3');
    });
  });

  group('EngineNotifier CV-04 hooks', () {
    late EngineNotifier notifier;

    setUp(() {
      notifier = EngineNotifier.create(
        sensorProvider: MockSensorProvider(),
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
        repository: _NoopRepo(),
      );
    });

    tearDown(() => notifier.dispose());

    test('processCameraAngle ignored when camera disabled', () {
      expect(notifier.isCameraEnabled, isFalse);
      notifier.processCameraAngle(
        elbowAngleDegrees: 170,
        timestampMs: 0,
      );
      notifier.processCameraAngle(
        elbowAngleDegrees: 40,
        timestampMs: 500,
      );
      notifier.processCameraAngle(
        elbowAngleDegrees: 170,
        timestampMs: 1200,
      );
      expect(notifier.fusionEngine.totalCameraReps, 0);
      expect(notifier.poseRepCounter.repCount, 0);
    });

    test('processCameraAngle feeds fusion when enabled', () {
      notifier.setCameraEnabled(true);
      notifier.processCameraAngle(
        elbowAngleDegrees: 170,
        timestampMs: 0,
      );
      notifier.processCameraAngle(
        elbowAngleDegrees: 40,
        timestampMs: 600,
      );
      notifier.processCameraAngle(
        elbowAngleDegrees: 170,
        timestampMs: 1300,
      );
      expect(notifier.poseRepCounter.repCount, 1);
      expect(notifier.fusionEngine.totalCameraReps, 1);
      final decision =
          notifier.fusionEngine.getDecision(currentTimestampMs: 1400);
      // Camera-only rejected by default (IMU authoritative).
      expect(decision.shouldCount, isFalse);
      expect(notifier.fusionEngine.rejectedCameraReps, 1);
    });

    test('low live confidence does not confirm both with IMU (D2 gating)', () {
      notifier.setCameraEnabled(true);
      // One camera rep with low landmark confidence.
      notifier.processCameraAngle(
        elbowAngleDegrees: 170,
        timestampMs: 0,
        confidence: 0.2,
      );
      notifier.processCameraAngle(
        elbowAngleDegrees: 40,
        timestampMs: 600,
        confidence: 0.2,
      );
      notifier.processCameraAngle(
        elbowAngleDegrees: 170,
        timestampMs: 1300,
        confidence: 0.2,
      );
      expect(notifier.poseRepCounter.repCount, 1);
      expect(notifier.fusionEngine.totalCameraReps, 1);

      notifier.fusionEngine.onImuRep(timestampMs: 1320);
      final decision =
          notifier.fusionEngine.getDecision(currentTimestampMs: 1400);
      // Low conf → no "both"; IMU still counts as imuOnly.
      expect(decision.shouldCount, isTrue);
      expect(decision.source, RepSource.imuOnly);
      expect(notifier.fusionEngine.fusedReps, 0);
    });

    test('high live confidence + IMU → both (real conf path)', () {
      notifier.setCameraEnabled(true);
      notifier.processCameraAngle(
        elbowAngleDegrees: 170,
        timestampMs: 0,
        confidence: 0.91,
      );
      notifier.processCameraAngle(
        elbowAngleDegrees: 40,
        timestampMs: 600,
        confidence: 0.91,
      );
      notifier.processCameraAngle(
        elbowAngleDegrees: 170,
        timestampMs: 1300,
        confidence: 0.91,
      );
      notifier.fusionEngine.onImuRep(timestampMs: 1310);
      final decision =
          notifier.fusionEngine.getDecision(currentTimestampMs: 1400);
      expect(decision.shouldCount, isTrue);
      expect(decision.source, RepSource.both);
      expect(notifier.fusionEngine.fusedReps, 1);
    });
  });
}

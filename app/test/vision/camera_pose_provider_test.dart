import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/camera_pose_provider.dart';
import 'package:flowrep/domain/vision/tracking_quality.dart';
import 'package:flowrep/domain/vision/vision_config.dart';
import 'package:flowrep/presentation/providers/vision_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PoseFrameMapper (CV-02 pure path)', () {
    test('elbowAngle from synthetic landmarks (right arm extended)', () {
      final landmarks = List.generate(
        17,
        (_) => const FlowPoseLandmark(x: 0, y: 0, confidence: 0.1),
      );
      // Indices match PoseLandmarkIndex (11/12 shoulder, 13/14 elbow, 15/16 wrist)
      landmarks[12] = const FlowPoseLandmark(x: 0, y: 1, confidence: 0.9);
      landmarks[14] = const FlowPoseLandmark(x: 0, y: 0, confidence: 0.9);
      landmarks[16] = const FlowPoseLandmark(x: 0, y: -1, confidence: 0.9);

      final frame = PoseFrame(
        timestampMs: 1000,
        landmarks: landmarks,
        processingTimeMs: 3,
      );
      final angle = PoseFrameMapper.elbowAngle(frame, rightArm: true);
      expect(angle, isNotNull);
      expect(angle!, closeTo(180.0, 0.5));
    });

    test('elbowAngle returns null when confidence low', () {
      final landmarks = List.generate(
        17,
        (_) => const FlowPoseLandmark(x: 0, y: 0, confidence: 0.1),
      );
      final frame = PoseFrame(
        timestampMs: 1,
        landmarks: landmarks,
        processingTimeMs: 1,
      );
      expect(PoseFrameMapper.elbowAngle(frame, rightArm: false), isNull);
    });

    test('armConfidence averages real shoulder/elbow/wrist visibility', () {
      final landmarks = List.generate(
        17,
        (_) => const FlowPoseLandmark(x: 0, y: 0, confidence: 0.1),
      );
      landmarks[12] = const FlowPoseLandmark(x: 0, y: 1, confidence: 0.9);
      landmarks[14] = const FlowPoseLandmark(x: 0, y: 0, confidence: 0.6);
      landmarks[16] = const FlowPoseLandmark(x: 0, y: -1, confidence: 0.3);

      final frame = PoseFrame(
        timestampMs: 10,
        landmarks: landmarks,
        processingTimeMs: 1,
      );
      final conf = PoseFrameMapper.armConfidence(frame, rightArm: true);
      expect(conf, isNotNull);
      expect(conf!, closeTo((0.9 + 0.6 + 0.3) / 3.0, 1e-9));
    });

    test('primaryElbow returns angle with real confidence (not 0.8 placeholder)',
        () {
      final landmarks = List.generate(
        17,
        (_) => const FlowPoseLandmark(x: 0, y: 0, confidence: 0.1),
      );
      landmarks[12] = const FlowPoseLandmark(x: 0, y: 1, confidence: 0.72);
      landmarks[14] = const FlowPoseLandmark(x: 0, y: 0, confidence: 0.72);
      landmarks[16] = const FlowPoseLandmark(x: 0, y: -1, confidence: 0.72);

      final frame = PoseFrame(
        timestampMs: 20,
        landmarks: landmarks,
        processingTimeMs: 2,
      );
      final primary = PoseFrameMapper.primaryElbow(frame);
      expect(primary, isNotNull);
      expect(primary!.angle, closeTo(180.0, 0.5));
      expect(primary.confidence, closeTo(0.72, 1e-9));
      expect(primary.confidence, isNot(closeTo(0.8, 0.001)));
      expect(primary.rightArm, isTrue);
    });

    test('primaryElbow null when all landmarks low confidence', () {
      final landmarks = List.generate(
        17,
        (_) => const FlowPoseLandmark(x: 0, y: 0, confidence: 0.1),
      );
      final frame = PoseFrame(
        timestampMs: 21,
        landmarks: landmarks,
        processingTimeMs: 1,
      );
      expect(PoseFrameMapper.primaryElbow(frame), isNull);
    });
  });

  group('CameraPoseProvider lifecycle (CV-02)', () {
    setUp(() {
      CameraPoseProvider.debugSkipPlatform = true;
    });

    tearDown(() {
      CameraPoseProvider.debugSkipPlatform = false;
    });

    test('startDetection without init sets error', () async {
      final p = CameraPoseProvider();
      await p.startDetection();
      expect(p.isDetecting, isFalse);
      expect(p.error, contains('nicht initialisiert'));
      p.dispose();
    });

    test('initializeCamera + startDetection in debug mode', () async {
      final p = CameraPoseProvider(
        config: const VisionConfig(enabled: true),
      );
      await p.initializeCamera();
      expect(p.isInitialized, isTrue);
      expect(p.error, isNull);

      await p.startDetection();
      expect(p.isDetecting, isTrue);

      await p.stopDetection();
      expect(p.isDetecting, isFalse);
      p.dispose();
    });

    test('switchCameraLens toggles front/back in debug mode', () async {
      final p = CameraPoseProvider(
        config: const VisionConfig(enabled: true, cameraLens: 'back'),
      );
      await p.initializeCamera();
      expect(p.activeLens, 'back');
      await p.switchCameraLens();
      expect(p.activeLens, 'front');
      await p.switchCameraLens();
      expect(p.activeLens, 'back');
      p.dispose();
    });

    test('updateConfig notifies and stores', () {
      final p = CameraPoseProvider();
      var notified = 0;
      p.addListener(() => notified++);
      p.updateConfig(const VisionConfig(enabled: true, cameraLens: 'front'));
      expect(p.config.enabled, isTrue);
      expect(p.config.cameraLens, 'front');
      expect(notified, greaterThan(0));
      p.dispose();
    });

    test('debugEmitFrame delivers on poseFrames stream', () async {
      final p = CameraPoseProvider();
      final frames = <PoseFrame>[];
      final sub = p.poseFrames.listen(frames.add);

      p.debugEmitFrame(
        const PoseFrame(
          timestampMs: 42,
          landmarks: [FlowPoseLandmark(x: 0.1, y: 0.2, confidence: 0.9)],
          processingTimeMs: 5,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(frames, hasLength(1));
      expect(frames.single.timestampMs, 42);

      await sub.cancel();
      p.dispose();
    });

    test('debugEmitNoPose delivers empty frame for E3/E4 lost path', () async {
      final p = CameraPoseProvider();
      final frames = <PoseFrame>[];
      final sub = p.poseFrames.listen(frames.add);

      p.debugEmitNoPose(timestampMs: 99);
      await Future<void>.delayed(Duration.zero);
      expect(frames, hasLength(1));
      expect(frames.single.hasPose, isFalse);
      expect(frames.single.landmarks, isEmpty);
      expect(frames.single.timestampMs, 99);

      // Session-side quality: null conf after empty frame → lost after streak.
      final q = TrackingQualityTracker(
        emaAlpha: 1.0,
        framesToTrack: 1,
        framesToLose: 2,
      );
      q.update(0.9);
      expect(q.state, TrackingQuality.tracking);
      // Simulate N empty stream frames (what session does with conf=null).
      for (var i = 0; i < 3; i++) {
        q.update(frames.single.hasPose
            ? PoseFrameMapper.armConfidence(
                frames.single,
                rightArm: true,
              )
            : null);
      }
      expect(q.state, TrackingQuality.lost);

      await sub.cancel();
      p.dispose();
    });

    test('PoseFrame.noPose is the empty live-frame contract', () {
      final empty = PoseFrame.noPose(timestampMs: 1);
      expect(empty.hasPose, isFalse);
      expect(PoseFrameMapper.primaryElbow(empty), isNull);
    });

    test('dispose is safe after detect cycle', () async {
      final p = CameraPoseProvider();
      await p.initializeCamera();
      await p.startDetection();
      await p.stopDetection();
      expect(() => p.dispose(), returnsNormally);
    });

    test('empty camera list sets error without crash (CV-06 soft-fail)',
        () async {
      CameraPoseProvider.debugSkipPlatform = false;
      CameraPoseProvider.debugAvailableCameras =
          () async => <CameraDescription>[];
      final p = CameraPoseProvider();
      await p.initializeCamera();
      expect(p.isInitialized, isFalse);
      expect(p.error, contains('Keine Kamera'));
      p.dispose();
      CameraPoseProvider.debugAvailableCameras = null;
      CameraPoseProvider.debugSkipPlatform = true;
    });
  });

  group('visionProvider Riverpod (CV-02)', () {
    test('creates CameraPoseProvider with enabled config', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final vision = container.read(visionProvider);
      expect(vision, isA<CameraPoseProvider>());
      expect(vision.config.enabled, isTrue);
      expect(vision.config.cameraLens, 'back');
    });

    test('visionConfigProvider defaults camera disabled', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cfg = container.read(visionConfigProvider);
      expect(cfg.enabled, isFalse);
    });
  });

  group('CV-02 structural deps', () {
    test('pubspec has camera and flutter_pose_detection', () {
      final pub = File('pubspec.yaml').readAsStringSync();
      expect(pub.contains('camera:'), isTrue);
      expect(pub.contains('flutter_pose_detection:'), isTrue);
    });

    test('camera_pose_provider and vision_provider exist', () {
      expect(
        File('lib/data/providers/camera_pose_provider.dart').existsSync(),
        isTrue,
      );
      expect(
        File('lib/presentation/providers/vision_provider.dart').existsSync(),
        isTrue,
      );
    });
  });
}

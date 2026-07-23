import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/camera_pose_provider.dart';
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

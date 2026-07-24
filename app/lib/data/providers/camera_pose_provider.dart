/// Optional camera + pose detection provider (CV-02).
///
/// Responsibilities:
/// 1. Initialize camera stream
/// 2. Feed frames to [NpuPoseDetector] when available
/// 3. Emit [PoseFrame] events for angle/rep logic
/// 4. Release resources on dispose
///
/// OPTIONAL: FlowRep works fully without this (IMU-only).
library;

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart' as fpd;

import '../../domain/vision/angle_calculator.dart';
import '../../domain/vision/vision_config.dart';

/// Detected pose frame with MediaPipe-style landmarks (33 points).
///
/// Empty [landmarks] means **no person detected** this frame (still emitted so
/// UI tracking quality / framed guide can react — CV-07 E3/E4).
class PoseFrame {
  final int timestampMs;
  final List<FlowPoseLandmark> landmarks;
  final double processingTimeMs;
  final double? fps;

  const PoseFrame({
    required this.timestampMs,
    required this.landmarks,
    required this.processingTimeMs,
    this.fps,
  });

  /// True when at least one landmark is present (person detected).
  bool get hasPose => landmarks.isNotEmpty;

  /// Explicit no-person frame for stream continuity (E3/E4).
  factory PoseFrame.noPose({
    required int timestampMs,
    double processingTimeMs = 0,
    double? fps,
  }) {
    return PoseFrame(
      timestampMs: timestampMs,
      landmarks: const [],
      processingTimeMs: processingTimeMs,
      fps: fps,
    );
  }
}

/// App-level landmark (avoids clashing with package [fpd.PoseLandmark]).
class FlowPoseLandmark {
  final double x;
  final double y;
  final double z;
  final double confidence;

  const FlowPoseLandmark({
    required this.x,
    required this.y,
    this.z = 0.0,
    required this.confidence,
  });

  LandmarkPoint toLandmarkPoint() =>
      LandmarkPoint(x: x, y: y, confidence: confidence);
}

/// Maps package pose results into FlowRep [PoseFrame] models (testable pure path).
class PoseFrameMapper {
  /// Convert a package [fpd.Pose] into ordered landmark list (33).
  static List<FlowPoseLandmark> fromPackagePose(fpd.Pose pose) {
    return pose.landmarks
        .map(
          (l) => FlowPoseLandmark(
            x: l.x,
            y: l.y,
            z: l.z,
            confidence: l.visibility,
          ),
        )
        .toList(growable: false);
  }

  /// Build [PoseFrame] from [fpd.PoseResult]; returns null if no poses.
  static PoseFrame? fromPoseResult(
    fpd.PoseResult result, {
    int? timestampMs,
    double? fps,
  }) {
    if (!result.hasPoses || result.firstPose == null) return null;
    return PoseFrame(
      timestampMs: timestampMs ?? result.timestamp.millisecondsSinceEpoch,
      landmarks: fromPackagePose(result.firstPose!),
      processingTimeMs: result.processingTimeMs.toDouble(),
      fps: fps,
    );
  }

  /// Always returns a frame — empty landmarks when no person (live stream path).
  static PoseFrame fromPoseResultOrEmpty(
    fpd.PoseResult result, {
    int? timestampMs,
    double? fps,
  }) {
    final mapped = fromPoseResult(
      result,
      timestampMs: timestampMs,
      fps: fps,
    );
    if (mapped != null) return mapped;
    return PoseFrame.noPose(
      timestampMs: timestampMs ?? result.timestamp.millisecondsSinceEpoch,
      processingTimeMs: result.processingTimeMs.toDouble(),
      fps: fps,
    );
  }

  /// Elbow angle helper for right or left arm from a [PoseFrame].
  static double? elbowAngle(
    PoseFrame frame, {
    required bool rightArm,
    double minConfidence = 0.5,
  }) {
    final points =
        frame.landmarks.map((l) => l.toLandmarkPoint()).toList(growable: false);
    return AngleCalculator.elbowAngleDegrees(
      landmarks: points,
      rightArm: rightArm,
      minConfidence: minConfidence,
    );
  }

  /// Mean landmark confidence for the shoulder–elbow–wrist chain.
  ///
  /// Uses MediaPipe visibility already mapped into [FlowPoseLandmark.confidence]
  /// by [fromPackagePose]. Returns null if the arm indices are missing.
  /// Live camera path must pass this into fusion — never a fixed placeholder.
  static double? armConfidence(
    PoseFrame frame, {
    required bool rightArm,
  }) {
    final shoulderIdx =
        rightArm ? PoseLandmarkIndex.rightShoulder : PoseLandmarkIndex.leftShoulder;
    final elbowIdx =
        rightArm ? PoseLandmarkIndex.rightElbow : PoseLandmarkIndex.leftElbow;
    final wristIdx =
        rightArm ? PoseLandmarkIndex.rightWrist : PoseLandmarkIndex.leftWrist;
    final maxIdx =
        [shoulderIdx, elbowIdx, wristIdx].reduce((a, b) => a > b ? a : b);
    if (frame.landmarks.length <= maxIdx) return null;

    final s = frame.landmarks[shoulderIdx].confidence;
    final e = frame.landmarks[elbowIdx].confidence;
    final w = frame.landmarks[wristIdx].confidence;
    return (s + e + w) / 3.0;
  }

  /// Prefer right arm when both have angles; returns angle + confidence pair.
  ///
  /// Confidence is the mean of the used arm's landmark visibilities (real
  /// pose scores), not a hardcoded default.
  static ({double angle, double confidence, bool rightArm})? primaryElbow(
    PoseFrame frame, {
    double minConfidence = 0.5,
  }) {
    final rightAngle = elbowAngle(
      frame,
      rightArm: true,
      minConfidence: minConfidence,
    );
    if (rightAngle != null) {
      final conf = armConfidence(frame, rightArm: true);
      if (conf != null) {
        return (angle: rightAngle, confidence: conf, rightArm: true);
      }
    }
    final leftAngle = elbowAngle(
      frame,
      rightArm: false,
      minConfidence: minConfidence,
    );
    if (leftAngle != null) {
      final conf = armConfidence(frame, rightArm: false);
      if (conf != null) {
        return (angle: leftAngle, confidence: conf, rightArm: false);
      }
    }
    return null;
  }
}

/// Manages camera and optional live pose detection.
class CameraPoseProvider extends ChangeNotifier {
  CameraController? _cameraController;
  fpd.NpuPoseDetector? _poseDetector;
  StreamSubscription<CameraImage>? _imageSub; // not used; stream via controller
  bool _isInitialized = false;
  bool _isDetecting = false;
  bool _detectorReady = false;
  bool _processingFrame = false;
  String? _error;
  String? _accelerationMode;

  final StreamController<PoseFrame> _poseFrameController =
      StreamController<PoseFrame>.broadcast();

  VisionConfig _config;

  /// When true, skip real camera/platform calls (unit tests).
  @visibleForTesting
  static bool debugSkipPlatform = false;

  /// Optional override for [availableCameras] (tests / injection).
  @visibleForTesting
  static Future<List<CameraDescription>> Function()? debugAvailableCameras;

  CameraPoseProvider({VisionConfig config = const VisionConfig()})
      : _config = config;

  bool get isInitialized => _isInitialized;
  bool get isDetecting => _isDetecting;
  bool get isDetectorReady => _detectorReady;
  String? get error => _error;
  String? get accelerationMode => _accelerationMode;
  Stream<PoseFrame> get poseFrames => _poseFrameController.stream;
  CameraController? get cameraController => _cameraController;
  VisionConfig get config => _config;

  /// Current lens preference: `'front'` or `'back'`.
  String get activeLens => _config.cameraLens;

  /// Whether a camera with the opposite lens exists on this device.
  Future<bool> canSwitchLens() async {
    if (debugSkipPlatform) return true;
    try {
      final cameras = debugAvailableCameras != null
          ? await debugAvailableCameras!()
          : await availableCameras();
      final hasFront =
          cameras.any((c) => c.lensDirection == CameraLensDirection.front);
      final hasBack =
          cameras.any((c) => c.lensDirection == CameraLensDirection.back);
      return hasFront && hasBack;
    } catch (_) {
      return false;
    }
  }

  /// Toggle front ↔ back camera. Restarts image stream if detection was active.
  Future<void> switchCameraLens() async {
    final next = _config.cameraLens == 'front' ? 'back' : 'front';
    await setCameraLens(next);
  }

  /// Open a specific lens (`'front'` / `'back'`). Soft-fails if missing.
  Future<void> setCameraLens(String lens) async {
    final want = lens == 'front' ? 'front' : 'back';
    if (_config.cameraLens == want && _isInitialized) {
      return;
    }
    final wasDetecting = _isDetecting;
    if (wasDetecting) {
      await stopDetection();
    }
    await _disposeControllerOnly();
    _config = _config.copyWith(cameraLens: want);
    await initializeCamera(lens: want);
    if (wasDetecting && _isInitialized) {
      await startDetection();
    }
    notifyListeners();
  }

  Future<void> _disposeControllerOnly() async {
    if (_cameraController != null &&
        _cameraController!.value.isStreamingImages) {
      try {
        await _cameraController!.stopImageStream();
      } catch (_) {}
    }
    await _cameraController?.dispose();
    _cameraController = null;
    _isInitialized = false;
  }

  /// Initialize the camera (must run before [startDetection]).
  Future<void> initializeCamera({String? lens}) async {
    if (_isInitialized) return;

    if (debugSkipPlatform) {
      _isInitialized = true;
      _error = null;
      if (lens != null) {
        _config = _config.copyWith(cameraLens: lens);
      }
      notifyListeners();
      return;
    }

    try {
      final cameras = debugAvailableCameras != null
          ? await debugAvailableCameras!()
          : await availableCameras();
      if (cameras.isEmpty) {
        _error = 'Keine Kamera verfügbar.';
        notifyListeners();
        return;
      }

      final preferred = lens ?? _config.cameraLens;
      final lensDirection = preferred == 'front'
          ? CameraLensDirection.front
          : CameraLensDirection.back;

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == lensDirection,
        orElse: () => cameras.first,
      );

      // Reflect actual lens if preferred was unavailable.
      final actualLens =
          camera.lensDirection == CameraLensDirection.front ? 'front' : 'back';
      _config = _config.copyWith(cameraLens: actualLens);

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      _isInitialized = true;
      _error = null;
      notifyListeners();
      debugPrint(
        '[CameraPose] Kamera initialisiert: ${camera.name} ($actualLens)',
      );
    } catch (e) {
      _error = 'Kamera-Fehler: $e';
      _isInitialized = false;
      notifyListeners();
      debugPrint('[CameraPose] Fehler: $e');
    }
  }

  /// Start pose detection on the camera stream when the detector is available.
  Future<void> startDetection() async {
    if (!_isInitialized) {
      _error = 'Kamera nicht initialisiert. Erst initializeCamera() aufrufen.';
      notifyListeners();
      return;
    }
    if (_isDetecting) return;

    _isDetecting = true;
    _error = null;
    notifyListeners();

    if (debugSkipPlatform) {
      debugPrint('[CameraPose] Detection gestartet (debugSkipPlatform).');
      return;
    }

    await _ensureDetector();
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _error = 'Kamera-Controller nicht bereit.';
      _isDetecting = false;
      notifyListeners();
      return;
    }

    if (_detectorReady && _poseDetector != null) {
      try {
        await _cameraController!.startImageStream(_onCameraImage);
        debugPrint('[CameraPose] Image-Stream + Pose Detector aktiv.');
      } catch (e) {
        _error = 'Image-Stream Fehler: $e';
        debugPrint('[CameraPose] $e');
      }
    } else {
      // Preview-only: camera may work without native pose on this platform.
      debugPrint(
        '[CameraPose] Detection ohne Pose-Detector '
        '(Preview-only / Desktop).',
      );
    }
    notifyListeners();
  }

  Future<void> _ensureDetector() async {
    if (_poseDetector != null && _detectorReady) return;
    try {
      _poseDetector = fpd.NpuPoseDetector(
        config: fpd.PoseDetectorConfig.realtime(),
      );
      final mode = await _poseDetector!.initialize();
      _accelerationMode = mode.name;
      _detectorReady = true;
      debugPrint('[CameraPose] Pose Detector aktiv (Modus: ${mode.name})');
    } catch (e) {
      _detectorReady = false;
      _accelerationMode = null;
      // Soft-fail: app still works with camera preview / IMU.
      debugPrint('[CameraPose] Pose Detector nicht verfügbar: $e');
    }
  }

  Future<void> _onCameraImage(CameraImage image) async {
    if (!_isDetecting || _processingFrame || _poseDetector == null) return;
    _processingFrame = true;
    try {
      final planes = image.planes
          .map(
            (p) => <String, dynamic>{
              'bytes': p.bytes,
              'bytesPerRow': p.bytesPerRow,
              'bytesPerPixel': p.bytesPerPixel,
            },
          )
          .toList(growable: false);

      final result = await _poseDetector!.processFrame(
        planes: planes,
        width: image.width,
        height: image.height,
        format: 'yuv420',
        rotation: 0,
      );

      // Always emit: empty landmarks when no person so E3/E4 can leave Tracking.
      final frame = PoseFrameMapper.fromPoseResultOrEmpty(result);
      if (!_poseFrameController.isClosed) {
        _poseFrameController.add(frame);
      }
    } catch (e) {
      // Drop frame errors — do not tear down the stream.
      debugPrint('[CameraPose] Frame-Fehler: $e');
    } finally {
      _processingFrame = false;
    }
  }

  /// Stop pose detection (keeps camera initialized for preview).
  Future<void> stopDetection() async {
    if (!_isDetecting) return;
    _isDetecting = false;
    if (!debugSkipPlatform &&
        _cameraController != null &&
        _cameraController!.value.isStreamingImages) {
      try {
        await _cameraController!.stopImageStream();
      } catch (_) {}
    }
    try {
      await _poseDetector?.stopCameraDetection();
    } catch (_) {}
    notifyListeners();
    debugPrint('[CameraPose] Detection gestoppt.');
  }

  void updateConfig(VisionConfig newConfig) {
    _config = newConfig;
    notifyListeners();
  }

  /// Emit a synthetic frame (unit tests / mock path).
  @visibleForTesting
  void debugEmitFrame(PoseFrame frame) {
    if (!_poseFrameController.isClosed) {
      _poseFrameController.add(frame);
    }
  }

  /// Emit an empty no-person frame (unit tests for E3/E4 lost path).
  @visibleForTesting
  void debugEmitNoPose({int timestampMs = 0}) {
    debugEmitFrame(PoseFrame.noPose(timestampMs: timestampMs));
  }

  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isDetecting = false;
    if (_cameraController != null &&
        _cameraController!.value.isStreamingImages) {
      // fire-and-forget stop; dispose will release controller
      unawaited(_cameraController!.stopImageStream().catchError((_) {}));
    }
    _cameraController?.dispose();
    _cameraController = null;
    _poseDetector?.dispose();
    _poseDetector = null;
    _isInitialized = false;
    _detectorReady = false;
    _imageSub?.cancel();
    if (!_poseFrameController.isClosed) {
      _poseFrameController.close();
    }
    super.dispose();
  }
}

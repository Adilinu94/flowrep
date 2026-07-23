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

  /// Initialize the camera (must run before [startDetection]).
  Future<void> initializeCamera({String? lens}) async {
    if (_isInitialized) return;

    if (debugSkipPlatform) {
      _isInitialized = true;
      _error = null;
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

      final lensDirection = (lens ?? _config.cameraLens) == 'front'
          ? CameraLensDirection.front
          : CameraLensDirection.back;

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == lensDirection,
        orElse: () => cameras.first,
      );

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
      debugPrint('[CameraPose] Kamera initialisiert: ${camera.name}');
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

      final frame = PoseFrameMapper.fromPoseResult(result);
      if (frame != null && !_poseFrameController.isClosed) {
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

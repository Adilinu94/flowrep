import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/camera_pose_provider.dart';
import '../../data/repositories/landmark_session_recorder.dart';
import '../../domain/vision/fusion_pulse.dart';
import '../../domain/vision/pose_skeleton.dart';
import '../../domain/vision/tracking_quality.dart';
import '../../domain/vision/vision_config.dart';
import '../../domain/vision/vision_focus.dart';
import '../providers/engine_provider.dart';
import '../providers/vision_provider.dart';
import '../widgets/camera_preview_overlay.dart';
import '../widgets/fusion_status_badge.dart';

/// Optional camera session: preview + skeleton + pose angles → fusion stats.
/// IMU counting remains authoritative on the home screen.
class CameraSessionScreen extends ConsumerStatefulWidget {
  const CameraSessionScreen({super.key});

  @override
  ConsumerState<CameraSessionScreen> createState() =>
      _CameraSessionScreenState();
}

class _CameraSessionScreenState extends ConsumerState<CameraSessionScreen> {
  StreamSubscription<PoseFrame>? _poseSub;
  double? _lastElbowAngle;
  String? _lastDiagnostic;
  bool _starting = false;
  bool _switchingLens = false;
  bool _canSwitchLens = false;

  PoseFrame? _lastFrame;
  bool _highlightRight = true;
  AngleFormColor? _formColor;
  final TrackingQualityTracker _quality = TrackingQualityTracker();
  final FusionPulseController _pulse = FusionPulseController();
  SkeletonDrawMode _drawMode = SkeletonDrawMode.upper;
  bool _showSkeleton = true;
  bool _recordLandmarks = false;
  LandmarkSessionRecorder? _recorder;
  String? _recorderPath;

  @override
  void dispose() {
    _poseSub?.cancel();
    _recorder?.close();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    final cam = ref.read(visionProvider);
    final engine = ref.read(engineProvider.notifier);
    try {
      engine.setCameraEnabled(true);
      await cam.initializeCamera();
      await cam.startDetection();
      await _poseSub?.cancel();
      _quality.reset();
      _pulse.reset();
      await _setupRecorder(cam.config);
      _poseSub = cam.poseFrames.listen(_onPoseFrame);
      final canSwitch = await cam.canSwitchLens();
      if (mounted) setState(() => _canSwitchLens = canSwitch);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _toggleLens() async {
    if (_switchingLens || _starting) return;
    setState(() => _switchingLens = true);
    final cam = ref.read(visionProvider);
    try {
      await cam.switchCameraLens();
      // Re-attach pose listener (stream controller is the same).
      await _poseSub?.cancel();
      _poseSub = cam.poseFrames.listen(_onPoseFrame);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              cam.activeLens == 'front'
                  ? 'Frontkamera aktiv (gespiegelt)'
                  : 'Rückkamera aktiv',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _switchingLens = false);
    }
  }

  /// Opens a **file** sink under app documents when recording is on (E9).
  Future<void> _setupRecorder(VisionConfig config) async {
    _recorder?.close();
    _recorder = null;
    _recorderPath = null;
    if (!(_recordLandmarks || config.recordLandmarks)) return;
    try {
      final file = await LandmarkFilePaths.createSessionFile();
      final sink = FileLandmarkSink(file);
      _recorder = LandmarkSessionRecorder(
        sink: sink,
        enabled: true,
        minIntervalMs: 100,
      );
      _recorderPath = file.path;
    } catch (e) {
      // Soft-fail: keep session usable without disk log.
      debugPrint('[CameraSession] Landmark file sink failed: $e');
    }
  }

  Future<void> _stop() async {
    final cam = ref.read(visionProvider);
    final engine = ref.read(engineProvider.notifier);
    await _poseSub?.cancel();
    _poseSub = null;
    await cam.stopDetection();
    engine.setCameraEnabled(false);
    _recorder?.close();
    if (mounted) {
      setState(() {
        _lastFrame = null;
        _lastElbowAngle = null;
        _formColor = null;
        _quality.reset();
        _pulse.reset();
      });
    }
  }

  void _onPoseFrame(PoseFrame frame) {
    final engine = ref.read(engineProvider.notifier);
    final cam = ref.read(visionProvider);
    final cfg = cam.config;

    // Empty landmarks = person left frame (always emitted by CameraPoseProvider).
    final primary = frame.hasPose
        ? PoseFrameMapper.primaryElbow(
            frame,
            minConfidence: cfg.minLandmarkConfidence,
          )
        : null;

    final double? conf = primary?.confidence;
    if (primary != null) {
      engine.processCameraAngle(
        elbowAngleDegrees: primary.angle,
        timestampMs: frame.timestampMs,
        confidence: primary.confidence,
      );
    }

    // null conf drives E5 hysteresis → Lost → E4 framed guide.
    _quality.update(conf);
    final decision = engine.fusionEngine.getDecision(
      currentTimestampMs: frame.timestampMs + 1,
    );
    _pulse.onFrame(
      nowMs: frame.timestampMs,
      lastDecision: decision,
      fusedReps: engine.fusionEngine.fusedReps,
    );

    AngleFormColor? form;
    var highlightRight = _highlightRight;
    if (primary != null) {
      form = AngleFormClassifier.classify(
        angleDegrees: primary.angle,
        confidence: primary.confidence,
        angleUpThreshold: cfg.angleUpThreshold,
        angleDownThreshold: cfg.angleDownThreshold,
        minConfidence: cfg.minLandmarkConfidence,
      );
      if (cfg.highlightArm == ArmSide.auto) {
        highlightRight = primary.rightArm;
      } else {
        highlightRight = cfg.highlightArm == ArmSide.right;
      }
    } else {
      form = null;
    }

    if (frame.hasPose) {
      _recorder?.maybeRecord(
        timestampMs: frame.timestampMs,
        meanConfidence: conf ?? 0.0,
        landmarks: frame.landmarks,
      );
    }

    if (!mounted) return;
    setState(() {
      // Empty landmarks → painter skips skeleton; guide uses trackingQuality.
      _lastFrame = frame.hasPose ? frame : null;
      _highlightRight = highlightRight;
      _formColor = form;
      _lastElbowAngle = primary?.angle;
      _lastDiagnostic = frame.hasPose
          ? decision.diagnostic
          : 'Person nicht erkannt';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cam = ref.watch(visionProvider);
    final engine = ref.watch(engineProvider.notifier);
    final fusion = engine.fusionEngine;
    final pose = engine.poseRepCounter;
    final cfg = cam.config;
    final mirror = cfg.mirrorPreview ||
        cam.cameraController?.description.lensDirection.name == 'front';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kamera-Validierung'),
        actions: [
          if (cam.isDetecting && _canSwitchLens)
            IconButton(
              tooltip: cam.activeLens == 'front'
                  ? 'Zur Rückkamera'
                  : 'Zur Frontkamera',
              icon: _switchingLens
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      cam.activeLens == 'front'
                          ? Icons.camera_rear
                          : Icons.camera_front,
                    ),
              onPressed: _switchingLens ? null : _toggleLens,
            ),
          if (cam.isDetecting)
            IconButton(
              tooltip: 'Skelett an/aus',
              icon: Icon(
                _showSkeleton ? Icons.accessibility_new : Icons.accessibility,
              ),
              onPressed: () => setState(() => _showSkeleton = !_showSkeleton),
            ),
          if (cam.isDetecting)
            IconButton(
              tooltip: 'Stoppen',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: _stop,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Optional — Zählen läuft weiter über den Sensor (IMU). '
            'Die Kamera zeigt Pose/Skelett und kann Form bestätigen; '
            'sie ersetzt die IMU-Zählung nicht. '
            'Umschalten Front/Rück: Kamera-Symbol oben.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (cam.isDetecting) ...[
            const SizedBox(height: 4),
            Text(
              'Aktiv: ${cam.activeLens == 'front' ? 'Frontkamera' : 'Rückkamera'}'
              '${mirror ? ' (Spiegel)' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          CameraPreviewOverlay(
            controller: cam.cameraController,
            isDetecting: cam.isDetecting,
            error: cam.error,
            onStart: _starting ? null : _start,
            onStop: _stop,
            landmarks: _lastFrame?.landmarks,
            showSkeleton: _showSkeleton && cfg.showSkeletonOverlay,
            mirrorX: mirror,
            drawMode: _drawMode,
            highlightRightArm: _highlightRight,
            minConfidence: cfg.minLandmarkConfidence,
            primaryJointForm: _formColor,
            trackingQuality: _quality.state,
            pulseScale: _pulse.pulseScale,
            focus: cfg.visionFocus,
            showFramedGuide: true,
          ),
          if (_starting) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 8),
          Text('Skelett-Modus', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SegmentedButton<SkeletonDrawMode>(
            segments: const [
              ButtonSegment(
                value: SkeletonDrawMode.full,
                label: Text('Full'),
              ),
              ButtonSegment(
                value: SkeletonDrawMode.upper,
                label: Text('Upper'),
              ),
              ButtonSegment(
                value: SkeletonDrawMode.armOnly,
                label: Text('Arm'),
              ),
            ],
            selected: {_drawMode},
            onSelectionChanged: (s) => setState(() => _drawMode = s.first),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Landmark-Log (Debug, lokal)'),
              subtitle: Text(
                _recorder == null
                    ? 'Aus'
                    : 'Frames: ${_recorder!.framesWritten}',
              ),
              value: _recordLandmarks,
              onChanged: (v) async {
                setState(() => _recordLandmarks = v);
                await _setupRecorder(cfg.copyWith(recordLandmarks: v));
                if (mounted) setState(() {});
              },
            ),
            if (_recorderPath != null)
              Text(
                'Log: $_recorderPath',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
          const SizedBox(height: 12),
          FusionStatusBadge(
            cameraEnabled: engine.isCameraEnabled,
            imuOnlyReps: fusion.imuOnlyReps,
            cameraOnlyReps: fusion.cameraOnlyReps,
            fusedReps: fusion.fusedReps,
            poseReps: pose.repCount,
            lastElbowAngle: _lastElbowAngle,
            diagnostic: _lastDiagnostic ?? cam.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Pose-Reps (Kamera-SM): ${pose.repCount}\n'
            'Fusion both/imu/cam: '
            '${fusion.fusedReps}/${fusion.imuOnlyReps}/'
            '${fusion.cameraOnlyReps}\n'
            'Tracking: ${_quality.state.name} '
            '(conf=${_quality.smoothedConfidence.toStringAsFixed(2)})\n'
            'Detector: ${cam.isDetectorReady ? (cam.accelerationMode ?? "ok") : "n/a"}'
            '${_pulse.pulseScale > 1.0 ? "\nPulse: active" : ""}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

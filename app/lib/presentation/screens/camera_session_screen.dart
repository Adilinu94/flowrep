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

  PoseFrame? _lastFrame;
  bool _highlightRight = true;
  AngleFormColor? _formColor;
  final TrackingQualityTracker _quality = TrackingQualityTracker();
  final FusionPulseController _pulse = FusionPulseController();
  SkeletonDrawMode _drawMode = SkeletonDrawMode.upper;
  bool _showSkeleton = true;
  bool _recordLandmarks = false;
  LandmarkSessionRecorder? _recorder;
  MemoryLandmarkSink? _debugSink;

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
      _setupRecorder(cam.config);
      _poseSub = cam.poseFrames.listen(_onPoseFrame);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _setupRecorder(VisionConfig config) {
    _recorder?.close();
    _recorder = null;
    _debugSink = null;
    if (_recordLandmarks || config.recordLandmarks) {
      _debugSink = MemoryLandmarkSink();
      _recorder = LandmarkSessionRecorder(
        sink: _debugSink!,
        enabled: true,
        minIntervalMs: 100,
      );
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
    final primary = PoseFrameMapper.primaryElbow(
      frame,
      minConfidence: cfg.minLandmarkConfidence,
    );

    double? conf;
    if (primary != null) {
      conf = primary.confidence;
      engine.processCameraAngle(
        elbowAngleDegrees: primary.angle,
        timestampMs: frame.timestampMs,
        confidence: primary.confidence,
      );
    } else {
      conf = null;
    }

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
    bool highlightRight = _highlightRight;
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
    }

    _recorder?.maybeRecord(
      timestampMs: frame.timestampMs,
      meanConfidence: conf ?? 0.0,
      landmarks: frame.landmarks,
    );

    if (!mounted) return;
    setState(() {
      _lastFrame = frame;
      _highlightRight = highlightRight;
      _formColor = form;
      _lastElbowAngle = primary?.angle;
      _lastDiagnostic = decision.diagnostic;
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
            'Validierung — Zählen über Sensor (IMU). '
            'Kamera bestätigt Form und liefert Skelett-Overlay.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
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
              onChanged: (v) {
                setState(() {
                  _recordLandmarks = v;
                  _setupRecorder(cfg.copyWith(recordLandmarks: v));
                });
              },
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/camera_pose_provider.dart';
import '../providers/engine_provider.dart';
import '../providers/vision_provider.dart';
import '../widgets/camera_preview_overlay.dart';
import '../widgets/fusion_status_badge.dart';

/// Optional camera session: preview + pose angles → fusion stats.
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

  @override
  void dispose() {
    _poseSub?.cancel();
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
      _poseSub = cam.poseFrames.listen(_onPoseFrame);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    final cam = ref.read(visionProvider);
    final engine = ref.read(engineProvider.notifier);
    await _poseSub?.cancel();
    _poseSub = null;
    await cam.stopDetection();
    engine.setCameraEnabled(false);
    if (mounted) setState(() {});
  }

  void _onPoseFrame(PoseFrame frame) {
    final engine = ref.read(engineProvider.notifier);
    final angle = PoseFrameMapper.elbowAngle(frame, rightArm: true) ??
        PoseFrameMapper.elbowAngle(frame, rightArm: false);
    if (angle == null) return;

    engine.processCameraAngle(
      elbowAngleDegrees: angle,
      timestampMs: frame.timestampMs,
      confidence: 0.8,
    );
    final decision = engine.fusionEngine.getDecision(
      currentTimestampMs: frame.timestampMs + 1,
    );
    if (!mounted) return;
    setState(() {
      _lastElbowAngle = angle;
      _lastDiagnostic = decision.diagnostic;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cam = ref.watch(visionProvider);
    final engine = ref.watch(engineProvider.notifier);
    final fusion = engine.fusionEngine;
    final pose = engine.poseRepCounter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kamera-Validierung'),
        actions: [
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
            'Optionaler Validator. Wiederholungen zählt weiterhin die IMU '
            'auf dem Startbildschirm. Kamera bestätigt / verwirft für Stats.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          CameraPreviewOverlay(
            controller: cam.cameraController,
            isDetecting: cam.isDetecting,
            error: cam.error,
            onStart: _starting ? null : _start,
            onStop: _stop,
          ),
          if (_starting) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
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
            'Detector: ${cam.isDetectorReady ? (cam.accelerationMode ?? "ok") : "n/a"}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

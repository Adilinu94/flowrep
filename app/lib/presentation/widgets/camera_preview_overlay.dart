import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../data/providers/camera_pose_provider.dart';
import '../../domain/vision/pose_skeleton.dart';
import '../../domain/vision/tracking_quality.dart';
import '../../domain/vision/vision_focus.dart';
import 'framed_guide_overlay.dart';
import 'skeleton_painter.dart';

/// Live camera preview with optional skeleton / guide (CV-07).
class CameraPreviewOverlay extends StatelessWidget {
  final CameraController? controller;
  final bool isDetecting;
  final String? error;
  final VoidCallback? onStart;
  final VoidCallback? onStop;

  /// Latest pose landmarks (normalized 0..1).
  final List<FlowPoseLandmark>? landmarks;

  final bool showSkeleton;
  final bool mirrorX;
  final SkeletonDrawMode drawMode;
  final bool highlightRightArm;
  final double minConfidence;
  final AngleFormColor? primaryJointForm;
  final TrackingQuality trackingQuality;
  final double pulseScale;
  final VisionFocus focus;
  final bool showFramedGuide;

  const CameraPreviewOverlay({
    super.key,
    required this.controller,
    this.isDetecting = false,
    this.error,
    this.onStart,
    this.onStop,
    this.landmarks,
    this.showSkeleton = true,
    this.mirrorX = false,
    this.drawMode = SkeletonDrawMode.upper,
    this.highlightRightArm = true,
    this.minConfidence = 0.5,
    this.primaryJointForm,
    this.trackingQuality = TrackingQuality.lost,
    this.pulseScale = 1.0,
    this.focus = VisionFocus.bicepCurl,
    this.showFramedGuide = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = controller != null && controller!.value.isInitialized;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: ready ? controller!.value.aspectRatio : 4 / 3,
            child: ready
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(controller!),
                      if (showSkeleton &&
                          landmarks != null &&
                          landmarks!.isNotEmpty)
                        CustomPaint(
                          painter: SkeletonPainter(
                            landmarks: landmarks,
                            minConfidence: minConfidence,
                            drawMode: drawMode,
                            highlightRightArm: highlightRightArm,
                            mirrorX: mirrorX,
                            primaryJointForm: primaryJointForm,
                            pulseScale: pulseScale,
                            focus: focus,
                          ),
                        ),
                      if (isDetecting &&
                          showFramedGuide &&
                          trackingQuality == TrackingQuality.lost)
                        const FramedGuideOverlay(visible: true),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _TrackingBadge(quality: trackingQuality),
                      ),
                    ],
                  )
                : ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Center(
                      child: Text(
                        error ?? 'Kamera nicht aktiv',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isDetecting ? 'Pose-Erkennung läuft' : 'Pose pausiert',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (!isDetecting && onStart != null)
                  FilledButton.tonal(
                    onPressed: onStart,
                    child: const Text('Start'),
                  ),
                if (isDetecting && onStop != null)
                  FilledButton.tonal(
                    onPressed: onStop,
                    child: const Text('Stop'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingBadge extends StatelessWidget {
  final TrackingQuality quality;

  const _TrackingBadge({required this.quality});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (quality) {
      TrackingQuality.tracking => ('Tracking', Colors.green.shade700),
      TrackingQuality.partial => ('Teilweise', Colors.orange.shade800),
      TrackingQuality.lost => ('Verloren', Colors.red.shade700),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

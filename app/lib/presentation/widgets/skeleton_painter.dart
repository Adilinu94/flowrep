/// CustomPainter for MediaPipe-style skeleton overlay (CV-07 B, E1/E2/E6).
library;

import 'package:flutter/material.dart';

import '../../data/providers/camera_pose_provider.dart';
import '../../domain/vision/angle_calculator.dart';
import '../../domain/vision/pose_skeleton.dart';
import '../../domain/vision/vision_focus.dart';

/// Paints pose bones + joints over a camera preview of the same size.
class SkeletonPainter extends CustomPainter {
  final List<FlowPoseLandmark>? landmarks;
  final double minConfidence;
  final SkeletonDrawMode drawMode;
  final bool highlightRightArm;
  final bool mirrorX;
  final AngleFormColor? primaryJointForm;
  final VisionFocus focus;
  final double pulseScale;
  final Color boneColor;
  final Color jointColor;
  final Color dimColor;
  final Color goodColor;
  final Color warningColor;
  final Color poorColor;

  const SkeletonPainter({
    required this.landmarks,
    this.minConfidence = 0.5,
    this.drawMode = SkeletonDrawMode.upper,
    this.highlightRightArm = true,
    this.mirrorX = false,
    this.primaryJointForm,
    this.focus = VisionFocus.bicepCurl,
    this.pulseScale = 1.0,
    this.boneColor = const Color(0xFF4CAF50),
    this.jointColor = const Color(0xFFFFEB3B),
    this.dimColor = const Color(0x66FFFFFF),
    this.goodColor = const Color(0xFF4CAF50),
    this.warningColor = const Color(0xFFFFC107),
    this.poorColor = const Color(0xFFF44336),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final lms = landmarks;
    if (lms == null || lms.isEmpty) return;

    final bones = PoseSkeleton.bonesFor(
      drawMode,
      activeRight: highlightRightArm,
    );
    final highlight = PoseSkeleton.highlightJoints(
      rightArm: highlightRightArm,
      focus: focus,
    );
    final primaryElbowIdx = highlightRightArm
        ? PoseLandmarkIndex.rightElbow
        : PoseLandmarkIndex.leftElbow;

    final bonePaintFull = Paint()
      ..color = boneColor
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final bonePaintDim = Paint()
      ..color = dimColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final bone in bones) {
      final a = _point(lms, bone.$1, size);
      final b = _point(lms, bone.$2, size);
      if (a == null || b == null) continue;
      final hi = highlight.contains(bone.$1) && highlight.contains(bone.$2);
      canvas.drawLine(a, b, hi ? bonePaintFull : bonePaintDim);
    }

    final joints = PoseSkeleton.jointIndices(bones);
    for (final idx in joints) {
      final p = _point(lms, idx, size);
      if (p == null) continue;
      final hi = highlight.contains(idx);
      var color = hi ? jointColor : dimColor;
      var radius = hi ? 5.0 : 3.5;

      if (idx == primaryElbowIdx && primaryJointForm != null) {
        color = switch (primaryJointForm!) {
          AngleFormColor.good => goodColor,
          AngleFormColor.warning => warningColor,
          AngleFormColor.poor => poorColor,
        };
        radius = 6.0 * pulseScale;
      } else if (hi && pulseScale > 1.0 && idx == primaryElbowIdx) {
        radius = 5.0 * pulseScale;
      }

      canvas.drawCircle(
        p,
        radius,
        Paint()..color = color,
      );
      if (hi) {
        canvas.drawCircle(
          p,
          radius,
          Paint()
            ..color = Colors.black54
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
  }

  Offset? _point(List<FlowPoseLandmark> lms, int idx, Size size) {
    if (idx < 0 || idx >= lms.length) return null;
    final lm = lms[idx];
    if (!PoseSkeleton.visibleEnough(lm.confidence, minConfidence)) {
      return null;
    }
    return PoseSkeleton.toCanvasOffset(
      x: lm.x,
      y: lm.y,
      canvas: size,
      mirrorX: mirrorX,
    );
  }

  @override
  bool shouldRepaint(covariant SkeletonPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks ||
        oldDelegate.minConfidence != minConfidence ||
        oldDelegate.drawMode != drawMode ||
        oldDelegate.highlightRightArm != highlightRightArm ||
        oldDelegate.mirrorX != mirrorX ||
        oldDelegate.primaryJointForm != primaryJointForm ||
        oldDelegate.pulseScale != pulseScale;
  }
}

/// MediaPipe-style pose skeleton topology for overlay (CV-07 Phase A).
///
/// Pure Dart — no Flutter. Used by [SkeletonPainter] and unit tests.
library;

import 'dart:ui' show Offset, Size;

import 'angle_calculator.dart';
import 'vision_focus.dart';

/// How many bones to draw (E6).
enum SkeletonDrawMode {
  /// Torso + arms + legs (no face).
  full,

  /// Shoulders, elbows, wrists, hips (default for curl).
  upper,

  /// Only active arm chain (+ optional opposite shoulder for context).
  armOnly,
}

/// Undirected bone as landmark index pair (MediaPipe 0..32).
typedef SkeletonBone = (int a, int b);

/// Topology + coordinate mapping for pose skeleton overlay.
abstract final class PoseSkeleton {
  PoseSkeleton._();

  static const int landmarkCount = 33;

  // --- MediaPipe extra indices (beyond PoseLandmarkIndex arms) ---
  static const int leftHip = 23;
  static const int rightHip = 24;
  static const int leftKnee = 25;
  static const int rightKnee = 26;
  static const int leftAnkle = 27;
  static const int rightAnkle = 28;

  /// Upper-body bones (E6 upper).
  static const List<SkeletonBone> upperBones = [
    (PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.rightShoulder),
    (PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.leftElbow),
    (PoseLandmarkIndex.leftElbow, PoseLandmarkIndex.leftWrist),
    (PoseLandmarkIndex.rightShoulder, PoseLandmarkIndex.rightElbow),
    (PoseLandmarkIndex.rightElbow, PoseLandmarkIndex.rightWrist),
    (PoseLandmarkIndex.leftShoulder, leftHip),
    (PoseLandmarkIndex.rightShoulder, rightHip),
    (leftHip, rightHip),
  ];

  /// Leg bones (with upper = full).
  static const List<SkeletonBone> legBones = [
    (leftHip, leftKnee),
    (leftKnee, leftAnkle),
    (rightHip, rightKnee),
    (rightKnee, rightAnkle),
  ];

  /// Full body without face.
  static List<SkeletonBone> get fullBones => [...upperBones, ...legBones];

  /// Bones for [mode]; [activeRight] only used for [SkeletonDrawMode.armOnly].
  static List<SkeletonBone> bonesFor(
    SkeletonDrawMode mode, {
    bool? activeRight,
  }) {
    switch (mode) {
      case SkeletonDrawMode.full:
        return fullBones;
      case SkeletonDrawMode.upper:
        return upperBones;
      case SkeletonDrawMode.armOnly:
        final right = activeRight ?? true;
        if (right) {
          return const [
            (PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.rightShoulder),
            (PoseLandmarkIndex.rightShoulder, PoseLandmarkIndex.rightElbow),
            (PoseLandmarkIndex.rightElbow, PoseLandmarkIndex.rightWrist),
          ];
        }
        return const [
          (PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.rightShoulder),
          (PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.leftElbow),
          (PoseLandmarkIndex.leftElbow, PoseLandmarkIndex.leftWrist),
        ];
    }
  }

  /// All unique landmark indices referenced by [bones].
  static Set<int> jointIndices(List<SkeletonBone> bones) {
    final out = <int>{};
    for (final b in bones) {
      out.add(b.$1);
      out.add(b.$2);
    }
    return out;
  }

  /// True when confidence meets threshold.
  static bool visibleEnough(double confidence, double minConfidence) =>
      confidence >= minConfidence;

  /// Map normalized landmark (0..1) to canvas pixels.
  ///
  /// [mirrorX] flips horizontally (front camera selfie view).
  static Offset toCanvasOffset({
    required double x,
    required double y,
    required Size canvas,
    bool mirrorX = false,
  }) {
    final nx = mirrorX ? (1.0 - x) : x;
    return Offset(nx * canvas.width, y * canvas.height);
  }

  /// Whether every bone endpoint index is in 0..32.
  static bool allBoneIndicesValid(List<SkeletonBone> bones) {
    for (final b in bones) {
      if (b.$1 < 0 || b.$1 >= landmarkCount) return false;
      if (b.$2 < 0 || b.$2 >= landmarkCount) return false;
    }
    return true;
  }

  /// Indices that belong to the active arm highlight chain (E1).
  static Set<int> highlightJoints({
    required bool rightArm,
    VisionFocus focus = VisionFocus.bicepCurl,
  }) {
    return focus.armChain(rightArm: rightArm).toSet();
  }

  /// Bones fully on the highlighted arm chain (both ends in highlight set).
  static List<SkeletonBone> highlightBones({
    required bool rightArm,
    VisionFocus focus = VisionFocus.bicepCurl,
  }) {
    final joints = highlightJoints(rightArm: rightArm, focus: focus);
    final chain = focus.armChain(rightArm: rightArm);
    final bones = <SkeletonBone>[];
    for (var i = 0; i < chain.length - 1; i++) {
      bones.add((chain[i], chain[i + 1]));
    }
    // keep only if both ends highlighted (always true for chain)
    return bones.where((b) => joints.contains(b.$1) && joints.contains(b.$2)).toList();
  }
}

/// Form-color class for primary joint (E2) — pure, no Flutter Color.
enum AngleFormColor {
  /// Angle in productive curl ROM band.
  good,

  /// Near thresholds / ambiguous.
  warning,

  /// Low confidence or clearly incomplete ROM cue.
  poor,
}

/// Maps elbow (or primary) angle + confidence to form color (E2).
abstract final class AngleFormClassifier {
  AngleFormClassifier._();

  /// [angleUpThreshold] contracted (~90), [angleDownThreshold] extended (~160).
  ///
  /// good: between up and down (full ROM path)
  /// warning: outside but within 25° of band
  /// poor: far outside or confidence low
  static AngleFormColor classify({
    required double? angleDegrees,
    required double confidence,
    required double angleUpThreshold,
    required double angleDownThreshold,
    double minConfidence = 0.5,
    double outerMarginDegrees = 25.0,
  }) {
    if (angleDegrees == null || confidence < minConfidence) {
      return AngleFormColor.poor;
    }
    final lo = angleUpThreshold < angleDownThreshold
        ? angleUpThreshold
        : angleDownThreshold;
    final hi = angleUpThreshold < angleDownThreshold
        ? angleDownThreshold
        : angleUpThreshold;
    if (angleDegrees >= lo && angleDegrees <= hi) {
      return AngleFormColor.good;
    }
    if (angleDegrees >= lo - outerMarginDegrees &&
        angleDegrees <= hi + outerMarginDegrees) {
      return AngleFormColor.warning;
    }
    return AngleFormColor.poor;
  }
}

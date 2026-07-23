/// Joint-angle calculation from pose landmarks (CV-02).
///
/// Angle at B from points A → B → C:
///   BA = A - B, BC = C - B
///   angle = arccos( (BA · BC) / (|BA| * |BC|) )
///
/// Pure Dart — no Flutter/camera dependency. IMU pipeline unchanged.
library;

import 'dart:math';

/// A 2D landmark with optional confidence.
class LandmarkPoint {
  final double x;
  final double y;
  final double confidence;

  const LandmarkPoint({
    required this.x,
    required this.y,
    this.confidence = 1.0,
  });
}

/// MediaPipe Pose landmark indices used for bicep-curl elbow angle.
abstract final class PoseLandmarkIndex {
  static const int leftShoulder = 11;
  static const int rightShoulder = 12;
  static const int leftElbow = 13;
  static const int rightElbow = 14;
  static const int leftWrist = 15;
  static const int rightWrist = 16;
}

/// Computes joint angles from three landmark points.
class AngleCalculator {
  AngleCalculator._();

  /// Angle at [b] in degrees (0–180).
  ///
  /// Bicep curl: a=shoulder, b=elbow, c=wrist.
  /// ~170° extended (down), ~45° contracted (up).
  static double calculateAngle({
    required LandmarkPoint a,
    required LandmarkPoint b,
    required LandmarkPoint c,
  }) {
    final baX = a.x - b.x;
    final baY = a.y - b.y;
    final bcX = c.x - b.x;
    final bcY = c.y - b.y;

    final dotProduct = baX * bcX + baY * bcY;
    final magnitudeBA = sqrt(baX * baX + baY * baY);
    final magnitudeBC = sqrt(bcX * bcX + bcY * bcY);

    if (magnitudeBA < 1e-10 || magnitudeBC < 1e-10) {
      return 0.0;
    }

    var cosAngle = dotProduct / (magnitudeBA * magnitudeBC);
    cosAngle = cosAngle.clamp(-1.0, 1.0);

    final angleRadians = acos(cosAngle);
    return angleRadians * 180.0 / pi;
  }

  /// True when all three points meet [minConfidence].
  static bool allConfident({
    required LandmarkPoint a,
    required LandmarkPoint b,
    required LandmarkPoint c,
    double minConfidence = 0.5,
  }) {
    return a.confidence >= minConfidence &&
        b.confidence >= minConfidence &&
        c.confidence >= minConfidence;
  }

  /// Elbow angle for left or right arm from a full landmark list.
  ///
  /// [landmarks] must be indexable MediaPipe-style (at least 17 points).
  /// Returns null if indices missing or confidence too low.
  static double? elbowAngleDegrees({
    required List<LandmarkPoint> landmarks,
    required bool rightArm,
    double minConfidence = 0.5,
  }) {
    final shoulderIdx =
        rightArm ? PoseLandmarkIndex.rightShoulder : PoseLandmarkIndex.leftShoulder;
    final elbowIdx =
        rightArm ? PoseLandmarkIndex.rightElbow : PoseLandmarkIndex.leftElbow;
    final wristIdx =
        rightArm ? PoseLandmarkIndex.rightWrist : PoseLandmarkIndex.leftWrist;

    final maxIdx = [shoulderIdx, elbowIdx, wristIdx].reduce((a, b) => a > b ? a : b);
    if (landmarks.length <= maxIdx) return null;

    final a = landmarks[shoulderIdx];
    final b = landmarks[elbowIdx];
    final c = landmarks[wristIdx];

    if (!allConfident(a: a, b: b, c: c, minConfidence: minConfidence)) {
      return null;
    }
    return calculateAngle(a: a, b: b, c: c);
  }
}

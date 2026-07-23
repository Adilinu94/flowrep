/// Configuration for the Computer-Vision pipeline (CV-01 / CV-02 / CV-07).
///
/// All thresholds for pose estimation and angle-based rep counting.
/// Camera is OPTIONAL — IMU remains authoritative.
library;

import 'pose_skeleton.dart';
import 'vision_focus.dart';

/// Configuration for pose estimation and rep recognition.
class VisionConfig {
  /// Minimum landmark confidence (0.0–1.0). Below = not detected.
  final double minLandmarkConfidence;

  /// Elbow angle for "down" (extended) in degrees.
  final double angleDownThreshold;

  /// Elbow angle for "up" (contracted) in degrees.
  final double angleUpThreshold;

  /// Minimum time between two reps (seconds) — anti-double-count.
  final double minRepIntervalSeconds;

  /// Maximum duration of one full rep (seconds).
  final double maxRepDurationSeconds;

  /// Whether the camera pipeline is active.
  final bool enabled;

  /// Whether the skeleton overlay is shown.
  final bool showSkeletonOverlay;

  /// Camera lens: `'back'` or `'front'`.
  final String cameraLens;

  /// Skeleton draw density (E6). Default upper for curl.
  final SkeletonDrawMode skeletonDrawMode;

  /// Preferred arm for highlight; auto uses best confidence (E1).
  final ArmSide highlightArm;

  /// Opt-in local landmark CSV/JSONL recording (E9). Default off.
  final bool recordLandmarks;

  /// Exercise id for [VisionFocus.forExercise] (E10).
  final String exerciseId;

  const VisionConfig({
    this.minLandmarkConfidence = 0.5,
    this.angleDownThreshold = 160.0,
    this.angleUpThreshold = 90.0,
    this.minRepIntervalSeconds = 0.5,
    this.maxRepDurationSeconds = 5.0,
    this.enabled = false,
    this.showSkeletonOverlay = true,
    this.cameraLens = 'back',
    this.skeletonDrawMode = SkeletonDrawMode.upper,
    this.highlightArm = ArmSide.auto,
    this.recordLandmarks = false,
    this.exerciseId = kDefaultVisionExerciseId,
  });

  /// Default disabled config (IMU-only path).
  static const VisionConfig disabled = VisionConfig(enabled: false);

  /// Default enabled config for bicep-curl validation.
  static const VisionConfig bicepCurl = VisionConfig(enabled: true);

  VisionFocus get visionFocus => VisionFocus.forExercise(exerciseId);

  bool get mirrorPreview => cameraLens == 'front';

  VisionConfig copyWith({
    double? minLandmarkConfidence,
    double? angleDownThreshold,
    double? angleUpThreshold,
    double? minRepIntervalSeconds,
    double? maxRepDurationSeconds,
    bool? enabled,
    bool? showSkeletonOverlay,
    String? cameraLens,
    SkeletonDrawMode? skeletonDrawMode,
    ArmSide? highlightArm,
    bool? recordLandmarks,
    String? exerciseId,
  }) {
    return VisionConfig(
      minLandmarkConfidence:
          minLandmarkConfidence ?? this.minLandmarkConfidence,
      angleDownThreshold: angleDownThreshold ?? this.angleDownThreshold,
      angleUpThreshold: angleUpThreshold ?? this.angleUpThreshold,
      minRepIntervalSeconds:
          minRepIntervalSeconds ?? this.minRepIntervalSeconds,
      maxRepDurationSeconds:
          maxRepDurationSeconds ?? this.maxRepDurationSeconds,
      enabled: enabled ?? this.enabled,
      showSkeletonOverlay: showSkeletonOverlay ?? this.showSkeletonOverlay,
      cameraLens: cameraLens ?? this.cameraLens,
      skeletonDrawMode: skeletonDrawMode ?? this.skeletonDrawMode,
      highlightArm: highlightArm ?? this.highlightArm,
      recordLandmarks: recordLandmarks ?? this.recordLandmarks,
      exerciseId: exerciseId ?? this.exerciseId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VisionConfig &&
          minLandmarkConfidence == other.minLandmarkConfidence &&
          angleDownThreshold == other.angleDownThreshold &&
          angleUpThreshold == other.angleUpThreshold &&
          minRepIntervalSeconds == other.minRepIntervalSeconds &&
          maxRepDurationSeconds == other.maxRepDurationSeconds &&
          enabled == other.enabled &&
          showSkeletonOverlay == other.showSkeletonOverlay &&
          cameraLens == other.cameraLens &&
          skeletonDrawMode == other.skeletonDrawMode &&
          highlightArm == other.highlightArm &&
          recordLandmarks == other.recordLandmarks &&
          exerciseId == other.exerciseId;

  @override
  int get hashCode => Object.hash(
        minLandmarkConfidence,
        angleDownThreshold,
        angleUpThreshold,
        minRepIntervalSeconds,
        maxRepDurationSeconds,
        enabled,
        showSkeletonOverlay,
        cameraLens,
        skeletonDrawMode,
        highlightArm,
        recordLandmarks,
        exerciseId,
      );
}

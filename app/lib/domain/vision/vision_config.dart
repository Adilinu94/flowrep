/// Configuration for the Computer-Vision pipeline (CV-01 / CV-02).
///
/// All thresholds for pose estimation and angle-based rep counting.
/// Camera is OPTIONAL — IMU remains authoritative.
library;

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

  const VisionConfig({
    this.minLandmarkConfidence = 0.5,
    this.angleDownThreshold = 160.0,
    this.angleUpThreshold = 90.0,
    this.minRepIntervalSeconds = 0.5,
    this.maxRepDurationSeconds = 5.0,
    this.enabled = false,
    this.showSkeletonOverlay = true,
    this.cameraLens = 'back',
  });

  /// Default disabled config (IMU-only path).
  static const VisionConfig disabled = VisionConfig(enabled: false);

  /// Default enabled config for bicep-curl validation.
  static const VisionConfig bicepCurl = VisionConfig(enabled: true);

  VisionConfig copyWith({
    double? minLandmarkConfidence,
    double? angleDownThreshold,
    double? angleUpThreshold,
    double? minRepIntervalSeconds,
    double? maxRepDurationSeconds,
    bool? enabled,
    bool? showSkeletonOverlay,
    String? cameraLens,
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
          cameraLens == other.cameraLens;

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
      );
}

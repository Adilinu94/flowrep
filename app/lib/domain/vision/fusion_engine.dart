/// Fusion of IMU and camera rep detection (CV-04).
///
/// - IMU pipeline remains AUTHORITATIVE
/// - Camera is VALIDATOR / optional camera-only mode
/// - Does not modify workout_engine / exercise_engine
library;

/// Source of a fused rep decision.
enum RepSource {
  imuOnly,
  cameraOnly,
  both,
}

/// Outcome of a fusion decision.
class FusionResult {
  final bool shouldCount;
  final RepSource source;
  final double confidence;
  final String diagnostic;

  const FusionResult({
    required this.shouldCount,
    required this.source,
    required this.confidence,
    required this.diagnostic,
  });
}

/// Fusion timing / policy configuration.
class FusionConfig {
  /// Max age of a source event to be considered "recent" (ms).
  final int fusionWindowMs;

  /// When true, camera-only reps may count (camera-only mode).
  final bool allowCameraOnly;

  /// Minimum camera confidence to use a camera event.
  final double minCameraConfidence;

  const FusionConfig({
    this.fusionWindowMs = 500,
    this.allowCameraOnly = false,
    this.minCameraConfidence = 0.5,
  });
}

/// Combines IMU and camera rep events into ensemble decisions.
class FusionEngine {
  final FusionConfig _config;

  int? _lastImuRepTimestamp;
  int? _lastCameraRepTimestamp;
  double _lastCameraConfidence = 0.0;

  int _totalImuReps = 0;
  int _totalCameraReps = 0;
  int _fusedReps = 0;
  int _imuOnlyReps = 0;
  int _cameraOnlyReps = 0;
  int _rejectedCameraReps = 0;

  FusionEngine({FusionConfig config = const FusionConfig()})
      : _config = config;

  FusionConfig get config => _config;
  int get totalImuReps => _totalImuReps;
  int get totalCameraReps => _totalCameraReps;
  int get fusedReps => _fusedReps;
  int get imuOnlyReps => _imuOnlyReps;
  int get cameraOnlyReps => _cameraOnlyReps;
  int get rejectedCameraReps => _rejectedCameraReps;

  /// IMU-side decisions so far (`both` + `imuOnly`). Camera-only does not count.
  int get imuDecidedReps => _fusedReps + _imuOnlyReps;

  /// Share of IMU reps that pose also confirmed in the fusion window.
  /// Null when no IMU decision yet.
  double? get agreementRatio {
    final d = imuDecidedReps;
    if (d == 0) return null;
    return _fusedReps / d;
  }

  /// Product copy: „Pose bestätigt 7/10“ (fused / IMU-decided).
  String get agreementLabel {
    final d = imuDecidedReps;
    if (d == 0) return 'Pose bereit';
    return 'Pose bestätigt $_fusedReps/$d';
  }

  void onImuRep({required int timestampMs}) {
    _totalImuReps++;
    _lastImuRepTimestamp = timestampMs;
  }

  void onCameraRep({required int timestampMs, required double confidence}) {
    _totalCameraReps++;
    _lastCameraRepTimestamp = timestampMs;
    _lastCameraConfidence = confidence;
  }

  /// Decide based on recent events within [fusionWindowMs].
  FusionResult getDecision({required int currentTimestampMs}) {
    final hasRecentImu = _lastImuRepTimestamp != null &&
        (currentTimestampMs - _lastImuRepTimestamp!) < _config.fusionWindowMs;

    final cameraInWindow = _lastCameraRepTimestamp != null &&
        (currentTimestampMs - _lastCameraRepTimestamp!) <
            _config.fusionWindowMs;

    final cameraConfident =
        _lastCameraConfidence >= _config.minCameraConfidence;

    // Low-confidence camera = "no opinion" (occlusion / noise), not a veto.
    final hasRecentCamera = cameraInWindow && cameraConfident;

    if (hasRecentImu && hasRecentCamera) {
      _fusedReps++;
      _lastImuRepTimestamp = null;
      _lastCameraRepTimestamp = null;
      return const FusionResult(
        shouldCount: true,
        source: RepSource.both,
        confidence: 1.0,
        diagnostic: 'IMU + Kamera einig → Rep bestätigt',
      );
    }

    if (hasRecentImu && !hasRecentCamera) {
      _imuOnlyReps++;
      _lastImuRepTimestamp = null;
      // Drop weak camera noise so it does not stick around.
      if (cameraInWindow && !cameraConfident) {
        _lastCameraRepTimestamp = null;
      }
      return const FusionResult(
        shouldCount: true,
        source: RepSource.imuOnly,
        confidence: 0.7,
        diagnostic: 'Nur IMU → Rep gezählt (Kamera evtl. Okklusion)',
      );
    }

    if (!hasRecentImu && hasRecentCamera) {
      if (_config.allowCameraOnly) {
        _cameraOnlyReps++;
        _lastCameraRepTimestamp = null;
        return const FusionResult(
          shouldCount: true,
          source: RepSource.cameraOnly,
          confidence: 0.5,
          diagnostic: 'Nur Kamera → Rep gezählt (Camera-Only-Modus)',
        );
      }
      _rejectedCameraReps++;
      _lastCameraRepTimestamp = null;
      return const FusionResult(
        shouldCount: false,
        source: RepSource.cameraOnly,
        confidence: 0.3,
        diagnostic: 'Nur Kamera → Verworfen (IMU nötig)',
      );
    }

    return const FusionResult(
      shouldCount: false,
      source: RepSource.imuOnly,
      confidence: 0.0,
      diagnostic: 'Keine aktuelle Rep-Erkennung',
    );
  }

  void reset() {
    _lastImuRepTimestamp = null;
    _lastCameraRepTimestamp = null;
    _lastCameraConfidence = 0.0;
    _totalImuReps = 0;
    _totalCameraReps = 0;
    _fusedReps = 0;
    _imuOnlyReps = 0;
    _cameraOnlyReps = 0;
    _rejectedCameraReps = 0;
  }
}

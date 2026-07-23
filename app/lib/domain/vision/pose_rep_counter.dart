/// Angle-based rep counter for pose estimation (CV-03).
///
/// Hysteresis state machine:
///   DOWN (angle > angleDown) → UP (angle < angleUp) → REP on return DOWN
///
/// Independent of the IMU pipeline. Can run alone (camera-only) or as
/// validator for IMU (fusion, CV-04). Does not modify workout_engine.
library;

import 'vision_config.dart';

/// States of pose rep detection.
enum PoseRepState {
  /// Waiting for first valid "down" pose.
  waiting,

  /// Arm extended (down). Waiting for contraction.
  armDown,

  /// Arm contracted (up). Waiting for extension → counts a rep.
  armUp,
}

/// Result of processing one pose frame / angle sample.
class PoseRepResult {
  final bool repCounted;
  final int repNumber;
  final double? currentAngle;
  final PoseRepState state;
  final String? rejectionReason;

  const PoseRepResult({
    required this.repCounted,
    required this.repNumber,
    this.currentAngle,
    required this.state,
    this.rejectionReason,
  });

  static const PoseRepResult noPose = PoseRepResult(
    repCounted: false,
    repNumber: 0,
    currentAngle: null,
    state: PoseRepState.waiting,
    rejectionReason: 'Keine Pose erkannt',
  );
}

/// Counts bicep-curl reps from elbow angle samples.
class PoseRepCounter {
  final VisionConfig _config;

  PoseRepState _state = PoseRepState.waiting;
  int _repCount = 0;
  int _lastRepTimestampMs = 0;
  int _repStartTimestampMs = 0;

  int _totalFramesProcessed = 0;
  int _framesWithoutPose = 0;
  int _framesRejectedTooFast = 0;
  int _framesRejectedTooSlow = 0;

  PoseRepCounter({VisionConfig config = const VisionConfig()})
      : _config = config;

  int get repCount => _repCount;
  PoseRepState get state => _state;
  int get totalFramesProcessed => _totalFramesProcessed;
  int get framesWithoutPose => _framesWithoutPose;
  int get framesRejectedTooFast => _framesRejectedTooFast;
  int get framesRejectedTooSlow => _framesRejectedTooSlow;

  /// Process one elbow angle (degrees). Returns whether a rep was counted.
  PoseRepResult processAngle({
    required double elbowAngleDegrees,
    required int timestampMs,
  }) {
    _totalFramesProcessed++;

    final timeSinceLastRep = _lastRepTimestampMs > 0
        ? (timestampMs - _lastRepTimestampMs) / 1000.0
        : double.infinity;

    switch (_state) {
      case PoseRepState.waiting:
        if (elbowAngleDegrees > _config.angleDownThreshold) {
          _state = PoseRepState.armDown;
        }
        return PoseRepResult(
          repCounted: false,
          repNumber: _repCount,
          currentAngle: elbowAngleDegrees,
          state: _state,
        );

      case PoseRepState.armDown:
        if (elbowAngleDegrees < _config.angleUpThreshold) {
          _state = PoseRepState.armUp;
          _repStartTimestampMs = timestampMs;
        }
        return PoseRepResult(
          repCounted: false,
          repNumber: _repCount,
          currentAngle: elbowAngleDegrees,
          state: _state,
        );

      case PoseRepState.armUp:
        if (elbowAngleDegrees > _config.angleDownThreshold) {
          final repDuration =
              (timestampMs - _repStartTimestampMs) / 1000.0;

          if (timeSinceLastRep < _config.minRepIntervalSeconds) {
            _framesRejectedTooFast++;
            _state = PoseRepState.armDown;
            return PoseRepResult(
              repCounted: false,
              repNumber: _repCount,
              currentAngle: elbowAngleDegrees,
              state: _state,
              rejectionReason:
                  'Zu schnell (${timeSinceLastRep.toStringAsFixed(2)}s < '
                  '${_config.minRepIntervalSeconds}s)',
            );
          }

          if (repDuration > _config.maxRepDurationSeconds) {
            _framesRejectedTooSlow++;
            _state = PoseRepState.armDown;
            return PoseRepResult(
              repCounted: false,
              repNumber: _repCount,
              currentAngle: elbowAngleDegrees,
              state: _state,
              rejectionReason:
                  'Zu langsam (${repDuration.toStringAsFixed(2)}s > '
                  '${_config.maxRepDurationSeconds}s)',
            );
          }

          _repCount++;
          _lastRepTimestampMs = timestampMs;
          _state = PoseRepState.armDown;

          return PoseRepResult(
            repCounted: true,
            repNumber: _repCount,
            currentAngle: elbowAngleDegrees,
            state: _state,
          );
        }
        return PoseRepResult(
          repCounted: false,
          repNumber: _repCount,
          currentAngle: elbowAngleDegrees,
          state: _state,
        );
    }
  }

  /// Signal missing pose (occlusion). Does not reset state.
  void processNoPose() {
    _framesWithoutPose++;
  }

  /// Reset for a new session / exercise change.
  void reset() {
    _state = PoseRepState.waiting;
    _repCount = 0;
    _lastRepTimestampMs = 0;
    _repStartTimestampMs = 0;
    _totalFramesProcessed = 0;
    _framesWithoutPose = 0;
    _framesRejectedTooFast = 0;
    _framesRejectedTooSlow = 0;
  }
}

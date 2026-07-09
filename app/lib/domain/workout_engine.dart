import 'dart:async';
import 'dart:math';

import '../models/workout_models.dart';

enum WorkoutState { idle, calibrating, active, paused }

class SensorSample {
  final DateTime timestamp;
  final double ax, ay, az; // g
  final double gx, gy, gz; // degrees/second

  const SensorSample({
    required this.timestamp,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  double get accelMagnitude => sqrt(ax * ax + ay * ay + az * az);
  double get gyroMagnitude => sqrt(gx * gx + gy * gy + gz * gz);
}

class WorkoutEngineEvent {
  final WorkoutState state;
  final int repsInCurrentSet;
  final ExerciseSet? completedSet;

  const WorkoutEngineEvent({
    required this.state,
    required this.repsInCurrentSet,
    this.completedSet,
  });
}

/// Adaptive, per-exercise-calibrated peak counting.
///
/// See GYM_TRACKER_ARCHITEKTUR.md Abschnitt 5.1.2 for the design rationale:
/// a relative, per-exercise threshold (not a single global fixed value)
/// is what the RecoFit-paper analysis and the reviewed reference repos
/// suggest performs best. This class also fixes a bug present in the
/// architecture document's illustrative pseudocode: that version counted
/// a rep on every sample above threshold, which would massively overcount.
/// Here a rep is counted exactly once, on the falling edge, using a small
/// hysteresis band to avoid noise re-triggering right at the boundary.
class WorkoutEngine {
  WorkoutEngine({
    required this.exerciseId,
    this.gyroWeight = 0.05,
    this.envelopeDecayRate = 0.95,
    this.pauseAfter = const Duration(seconds: 4),
    this.calibrationReps = 3,
    this.fallingEdgeRatio = 0.7,
  });

  final String exerciseId;
  final double gyroWeight;
  final double envelopeDecayRate;
  final Duration pauseAfter;
  final int calibrationReps;

  /// Falling-edge trigger = peakThreshold * fallingEdgeRatio. Must be < 1.0
  /// to create a hysteresis band; otherwise sensor noise right at the
  /// threshold can trigger multiple false rising/falling transitions for
  /// a single real rep.
  final double fallingEdgeRatio;

  final _controller = StreamController<WorkoutEngineEvent>.broadcast();
  Stream<WorkoutEngineEvent> get events => _controller.stream;

  WorkoutState _state = WorkoutState.idle;
  WorkoutState get state => _state;

  double _peakThreshold = 1.3; // g, conservative default until calibrated
  double get peakThreshold => _peakThreshold;

  double _runningEnvelope = 0.0;
  bool _aboveThreshold = false;
  double _currentExcursionPeak = 0.0;
  DateTime? _lastMovementAt;

  final List<Rep> _repsInSet = [];
  int _setCounter = 0;

  void processSample(SensorSample s) {
    final combinedSignal = s.accelMagnitude + (s.gyroMagnitude * gyroWeight);
    _runningEnvelope = max(combinedSignal, _runningEnvelope * envelopeDecayRate);

    switch (_state) {
      case WorkoutState.idle:
        if (combinedSignal > _peakThreshold * 0.5) {
          // First real movement IS the first set - no separate, empty
          // calibration step. See ADR-003 / "Magic Moment" principle.
          _state = WorkoutState.calibrating;
          _lastMovementAt = s.timestamp;
          _emitStateEvent();
        }
        break;

      case WorkoutState.calibrating:
        _detectPeak(s, combinedSignal);
        if (_repsInSet.length >= calibrationReps) {
          _peakThreshold = _runningEnvelope * 0.6;
          _state = WorkoutState.active;
          _emitStateEvent();
        }
        break;

      case WorkoutState.active:
        _detectPeak(s, combinedSignal);
        if (_lastMovementAt != null &&
            s.timestamp.difference(_lastMovementAt!) > pauseAfter) {
          _endSet();
        }
        break;

      case WorkoutState.paused:
        if (combinedSignal > _peakThreshold * 0.5) {
          _state = WorkoutState.active;
          _lastMovementAt = s.timestamp;
          _emitStateEvent();
        }
        break;
    }
  }

  void _detectPeak(SensorSample s, double combinedSignal) {
    if (!_aboveThreshold && combinedSignal > _peakThreshold) {
      _aboveThreshold = true;
      _currentExcursionPeak = combinedSignal;
      _lastMovementAt = s.timestamp;
      return;
    }

    if (_aboveThreshold) {
      _currentExcursionPeak = max(_currentExcursionPeak, combinedSignal);
      _lastMovementAt = s.timestamp;

      if (combinedSignal < _peakThreshold * fallingEdgeRatio) {
        _aboveThreshold = false;
        _repsInSet.add(
          Rep(timestamp: s.timestamp, peakMagnitude: _currentExcursionPeak),
        );
        _emitStateEvent();
      }
    }
  }

  void _endSet() {
    if (_repsInSet.isEmpty) {
      _state = WorkoutState.idle;
      _emitStateEvent();
      return;
    }
    _setCounter++;
    final completedSet = ExerciseSet(
      id: 'set_${DateTime.now().microsecondsSinceEpoch}_$_setCounter',
      exerciseId: exerciseId,
      countedReps: _repsInSet.length,
      endedAt: DateTime.now(),
      reps: List.of(_repsInSet),
    );
    _repsInSet.clear();
    _state = WorkoutState.paused;
    _controller.add(WorkoutEngineEvent(
      state: _state,
      repsInCurrentSet: 0,
      completedSet: completedSet,
    ));
  }

  void _emitStateEvent() {
    _controller.add(WorkoutEngineEvent(
      state: _state,
      repsInCurrentSet: _repsInSet.length,
    ));
  }

  /// Ends the current set manually (user-triggered "Satz beenden"), rather
  /// than waiting for the pauseAfter timeout.
  void endSetManually() => _endSet();

  void dispose() => _controller.close();
}

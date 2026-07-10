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
///
/// IMPORTANT - calibration formula fixed after Python simulation testing
/// (tools/workout_engine_simulation.py, run before hardware arrived): the
/// first version of this class computed the post-calibration threshold as
/// `_runningEnvelope * 0.6` at the moment the 3rd calibration rep
/// completed. Since the envelope decays during the rest between reps,
/// by that moment it had already decayed back down close to resting
/// baseline - producing a threshold BELOW resting baseline, which meant
/// the "above threshold" state never cleared again and the engine
/// silently stopped counting after exactly `calibrationReps` reps, every
/// single time, for every session. This was caught by simulation, not by
/// reasoning about the pseudocode - see the simulation script for the
/// reproduction. The fix: track a separate slow-moving baseline estimate,
/// and calibrate the threshold from the actual recorded peak magnitudes of
/// the calibration reps (anchored against that baseline), not from the
/// instantaneous envelope value at an arbitrary later moment.
///
/// FOLLOW-UP ROBUSTNESS PASS (same simulation script, extended suite): a
/// noisy-calibration scenario (nervous/unpracticed first-time user) showed
/// significant overcounting (18 vs 10 expected) without any signal
/// filtering, and a single outlier calibration rep (e.g. device bumped)
/// could skew a mean-based threshold. Both addressed here: a causal EMA
/// low-pass filter (`lowPassAlpha`) now runs before any threshold logic,
/// and calibration uses the median of recorded peaks instead of the mean.
/// Both parameter choices are simulation-tuned starting points, not
/// validated against real hardware yet.
class WorkoutEngine {
  WorkoutEngine({
    required this.exerciseId,
    this.gyroWeight = 0.05,
    this.envelopeDecayRate = 0.95,
    this.pauseAfter = const Duration(seconds: 4),
    this.calibrationReps = 3,
    this.fallingEdgeRatio = 0.7,
    this.baselineEmaAlpha = 0.01,
    this.minThresholdAboveBaseline = 0.10,
    this.lowPassAlpha = 0.6,
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

  /// How quickly the resting-baseline estimate adapts. Small on purpose -
  /// it should track "what does quiet look like" over seconds, not react
  /// to every sample.
  final double baselineEmaAlpha;

  /// Safety floor: the calibrated threshold is never allowed to sit closer
  /// than this to the resting baseline, regardless of what the calibration
  /// reps looked like. Without this, if a user's very first movements are
  /// themselves small/marginal, the engine calibrates to accept that
  /// marginal signal as "normal" from then on. This floor is a starting
  /// point, not yet validated against real hardware - see
  /// 09_TESTPROTOKOLL_TEMPLATE.md for where that validation belongs.
  final double minThresholdAboveBaseline;

  /// Streaming (causal) EMA low-pass filter strength applied to the
  /// combined signal before any threshold logic, 0 < alpha <= 1 (higher =
  /// less smoothing/lag, closer to raw signal). Added + tuned via
  /// tools/workout_engine_simulation.py after a robustness test showed the
  /// unfiltered engine overcounted (18 vs 10 expected) under realistic
  /// sensor/motion noise during calibration. 0.6 was chosen as a balance:
  /// it fixed the noisy-calibration case without materially breaking fast
  /// or variable-tempo reps in the same test suite - it is a starting
  /// point for the real Milestone-2 hardware test to refine, not a final
  /// tuned value.
  final double lowPassAlpha;

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
  double? _filteredSignal;

  /// Slow-moving estimate of the resting ("quiet") signal level. Only
  /// updated from samples that are NOT part of an above-threshold
  /// excursion, so a long set does not slowly drag the baseline upward.
  double? _baselineLevel;
  double get baselineLevel => _baselineLevel ?? 1.0;

  final List<Rep> _repsInSet = [];
  int _setCounter = 0;

  void processSample(SensorSample s) {
    final rawCombined = s.accelMagnitude + (s.gyroMagnitude * gyroWeight);

    _filteredSignal = _filteredSignal == null
        ? rawCombined
        : _filteredSignal! * (1 - lowPassAlpha) + rawCombined * lowPassAlpha;
    final combinedSignal = _filteredSignal!;

    _runningEnvelope = max(combinedSignal, _runningEnvelope * envelopeDecayRate);

    if (_baselineLevel == null) {
      _baselineLevel = combinedSignal;
    } else if (!_aboveThreshold) {
      _baselineLevel = _baselineLevel! * (1 - baselineEmaAlpha) +
          combinedSignal * baselineEmaAlpha;
    }

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
          // Median rather than mean: robust against a single outlier
          // calibration rep (e.g. the device getting bumped) skewing the
          // threshold - confirmed via the outlier-calibration robustness
          // test in tools/workout_engine_simulation.py.
          final sortedPeaks = _repsInSet.map((r) => r.peakMagnitude).toList()
            ..sort();
          final mid = sortedPeaks.length ~/ 2;
          final medianPeak = sortedPeaks.length.isOdd
              ? sortedPeaks[mid]
              : (sortedPeaks[mid - 1] + sortedPeaks[mid]) / 2;
          final calibrated =
              baselineLevel + (medianPeak - baselineLevel) * 0.5;
          _peakThreshold =
              max(calibrated, baselineLevel + minThresholdAboveBaseline);
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

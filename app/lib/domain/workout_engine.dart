import 'dart:async';
import 'dart:math';

import 'package:flowrep/data/logger.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/signal_processor.dart';

enum WorkoutState { idle, calibrating, active, paused, guidedCalibration, connectionLost }

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
  final double? calibrationProgress; // 0.0–1.0 during guidedCalibration
  final double? calibratedThreshold; // result after calibration completes

  const WorkoutEngineEvent({
    required this.state,
    required this.repsInCurrentSet,
    this.completedSet,
    this.calibrationProgress,
    this.calibratedThreshold,
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
    SignalProcessor? signalProcessor,
    this.envelopeDecayRate = 0.95,
    this.pauseAfter = const Duration(seconds: 4),
    this.calibrationReps = 1,
    this.minRepIntervalSamples = 40,
    this.fallingDebounce = 4,
    this.prominenceRatio = 0.30,
    this.adaptiveThresholdRatio = 0.25,
    this.adaptiveMinConfirmed = 3,
    this.adaptiveWindow = 5,
    this.fallingEdgeRatio = 0.7,
    this.baselineEmaAlpha = 0.01,
    this.minThresholdAboveBaseline = 0.10,
    this.hasValidCalibration = false,
    double gyroWeight = 0.05,
    double lowPassAlpha = 0.6,
    this.initialPeakThreshold,
  }) : _signalProcessor = signalProcessor ??
            SignalProcessor(gyroWeight: gyroWeight, lowPassAlpha: lowPassAlpha),
       _peakThreshold = initialPeakThreshold ?? 1.2;

  /// Optional pre-calibrated threshold loaded from persistent storage.
  /// If null, the engine starts with the default 1.5g.
  final double? initialPeakThreshold;
  final String exerciseId;
  final SignalProcessor _signalProcessor;
  final double envelopeDecayRate;
  final Duration pauseAfter;
  final int calibrationReps;

  // Agent 1 / Schritt A (docs/Umbauplan Flowrep/agenten-baupläne/
  // AGENT_1_SIGNAL_PIPELINE.md, RECHERCHE_ZAEHLROBUSTHEIT_2026-07-16.md
  // S1/S2), superseding the earlier Duration-based minRepInterval patch
  // (Claude-c00679f3, commit a5e8aee): all values below are 1:1 ported
  // from WorkoutEngineSim in tools/workout_engine_simulation.py, derived
  // there via sweep_live_pfad_refraktaer_und_prominenz() against 5
  // personas (clean/double_bump/weak/slow/inconsistent), not guessed -
  // re-run that function to reproduce or re-derive them.

  /// S1 fix: minimum number of SAMPLES (not real time) after a COUNTED rep
  /// before a new rising edge in [_detectPeak] is accepted at all. Counted
  /// in samples rather than Duration because S3 (docs/RECHERCHE_ZAEHLROBUSTHEIT)
  /// means real elapsed time doesn't yet mean what it appears to - the
  /// firmware sends bursts of 4 without honest per-sample pacing. Sample
  /// count stays meaningful regardless of how that pacing behaves; once
  /// Schritt C (Agent 4's protocol + honest timestamps) lands, this should
  /// convert to a real-time duration.
  ///
  /// Without this, a single curl - which in the magnitude signal
  /// (`accelMagnitude + gyroMagnitude*gyroWeight`) almost always produces
  /// two humps, concentric and eccentric - gets counted twice (reproduced
  /// in tools/workout_engine_simulation.py: 20 counted for 10 expected).
  ///
  /// 40 samples (800ms @ 50Hz) is the smallest sweep candidate that fixed
  /// the double-peak scenario (20 -> exactly 10, no residual) without
  /// disturbing clean/inconsistent - see the Python sweep's "Sperrzeit-
  /// Sweep" section for the full candidate table.
  final int minRepIntervalSamples;

  /// S1, secondary fix: the falling threshold must be undershot for this
  /// many CONSECUTIVE samples before an excursion is allowed to close.
  /// Value adopted UNCHANGED from zaehle_edge() in workout_engine_simulation.py
  /// (Agent 2's / Paket 1's already-tuned reference primitive, not
  /// reinvented here) - without it, a single noise dip on the long falling
  /// edge of a slow rep closes the excursion early, and a second, spurious
  /// detection follows once the lockout above expires. Confirmed against
  /// all 5 personas in the Python sweep with no regression.
  final int fallingDebounce;

  /// S1/S8 mitigation: an excursion only counts as a rep if
  /// `(peak - precedingValley) >= prominenceRatio * (peakThreshold - baselineLevel)`.
  /// Expressed as a ratio of the existing baseline-relative excursion
  /// (consistent with [fallingEdgeRatio], not an independent magic number).
  /// Guards against [adaptiveThresholdRatio] below picking up noise once
  /// it lowers the effective threshold.
  final double prominenceRatio;

  /// S2 fix: the effective threshold used by [_detectPeak] is
  /// `max(minFloor, min(_peakThreshold, adaptiveThresholdRatio * median(last
  /// adaptiveWindow CONFIRMED rep peaks)))`, active only once at least
  /// [adaptiveMinConfirmed] reps have been confirmed in the current engine
  /// lifetime (before that there is nothing to adapt from - the effective
  /// threshold stays [_peakThreshold]). `minFloor` is
  /// `baselineLevel + max(0.10, 0.15 * (_peakThreshold - baselineLevel))` -
  /// without it, a low enough ratio can push the effective threshold below
  /// baseline noise, and the excursion detector gets stuck permanently
  /// "above threshold" (found via regression against the Python port's
  /// existing "Sehr langsame Reps" scenario: 8/8 became 3/8 before this
  /// floor was added back).
  ///
  /// This fixes WITHIN-SESSION tempo drift (same person calibrates at a
  /// normal pace, later slows down): confirmed via simulation at 3/10 ->
  /// 6/10 for a calibrate-fast-then-go-slow scenario. It does NOT fix a
  /// cold start where an entire session's signal stays below
  /// `_peakThreshold` from the first sample (a structurally different
  /// person/tempo than whoever calibrated) - that is 0/10, unreachable by
  /// any live-path tuning, and is what Guided Calibration 2.0's own
  /// per-user known-count calibration (Paket 1/2, Agent 2) is for instead.
  final double adaptiveThresholdRatio;
  final int adaptiveMinConfirmed;
  final int adaptiveWindow;

  /// Rolling record of CONFIRMED rep peak magnitudes, most recent last,
  /// used by [adaptiveThresholdRatio]. Not reset in [_endSet] for the same
  /// reason [_lastCountedRepSample] isn't (see below) - tempo drift can
  /// span a pause/resume within one session.
  final List<double> _confirmedPeaks = [];

  /// Sample index (from [diagEngineSampleCount], already incremented on
  /// every [processSample] call) of the last rep actually added to
  /// [_repsInSet]. Null until the first rep of the current engine lifetime
  /// is counted, which means [minRepIntervalSamples] cannot protect that
  /// very first rep's own second hump - the residual gap this leaves is
  /// exactly the same bootstrap case documented for [_confirmedPeaks].
  /// Intentionally not reset in [_endSet]: rep cadence for the same
  /// exercise/session is not expected to reset between sets, and keeping
  /// it lets the lockout stay effective across a paused-then-resumed set
  /// instead of re-exposing the bootstrap gap on every set.
  int? _lastCountedRepSample;

  /// Falling-debounce counter for the CURRENT excursion, see [fallingDebounce].
  int _fallingDebounceCount = 0;

  /// Minimum combined-signal value seen since the excursion before last
  /// closed - the "preceding valley" for [prominenceRatio].
  double _preMin = double.infinity;

  /// Falling threshold for the CURRENT excursion, frozen at the moment it
  /// starts from whatever effective threshold triggered it (which may be
  /// lower than [_peakThreshold] if [adaptiveThresholdRatio] is active) -
  /// NOT recomputed from the static [_peakThreshold]. Without freezing this
  /// per-excursion, an excursion triggered only because of a lowered
  /// effective threshold could never fall back below a falling threshold
  /// computed from the higher, static one, and would never close (found
  /// and fixed during the Python-side reference implementation, see
  /// sweep output "S2, realistischer Fall").
  double? _excursionFallingThreshold;

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
  ///
  /// NOT final: the guided calibration mode updates this after learning
  /// the user's typical rep excursion. See _finishGuidedCalibration().
  // ignore: prefer_final_fields
  double minThresholdAboveBaseline;

  /// True once a valid calibration is in place - either a completed guided
  /// calibration, or a persisted calibration loaded from storage at engine
  /// construction. Gates the idle state's transition below: without this
  /// check, ANY movement out of idle re-triggers the one-rep
  /// auto-calibration path (calibrationReps, defaulting to 1) and silently
  /// overwrites the carefully-calibrated guided-calibration threshold on
  /// the very next rep, no matter how good that threshold already was.
  /// See docs/Umbauplan Flowrep/02_ARCHITECTURE_DECISION_RECORDS.md, ADR-020.
  // ignore: prefer_final_fields
  bool hasValidCalibration;

  /// True for a brief window right after guided calibration finishes.
  /// Calibration completes as soon as the Nth peak is CONFIRMED (one
  /// sample past the actual maximum, per _findPeaksWithIndices), not once
  /// the signal has returned to rest - the remaining tail of that last rep
  /// is often still elevated. Without this gate, that still-elevated tail
  /// immediately re-crosses the idle activation threshold and triggers a
  /// spurious extra transition before the user has genuinely stopped
  /// moving (found via real `flutter test` execution, not simulation -
  /// neither this session's nor an earlier session's Python/Dart
  /// reconstruction caught it; see Änderungsprotokoll in
  /// docs/Umbauplan Flowrep/STATUS_FORTSCHRITT.md for how this surfaced).
  /// Cleared as soon as one sample is seen back at/below a settled level.
  // ignore: prefer_final_fields
  bool _awaitingSettleAfterCalibration = false;

  // Synchronous delivery is intentional: it lets tests observe state
  // changes immediately after calling processSample(), without needing
  // async pumps. UI listeners (setState) are safe because processSample
  // is never invoked inside another setState cycle in this app.
  final _controller = StreamController<WorkoutEngineEvent>.broadcast(sync: true);
  Stream<WorkoutEngineEvent> get events => _controller.stream;

  WorkoutState _state = WorkoutState.idle;
  WorkoutState get state => _state;

  // Real-hardware tuning (2026-07-12): lowered from 1.5 to 1.2 because
  // the raw accel magnitude peaks at ~1.227 on actual bicep curls (Serial
  // data from M5StickC Plus2). With gyro contribution (gyroMag*0.05),
  // even slow curls with low rotation easily cross 1.2. At 1.5, curls
  // with <50 deg/s gyro were missed entirely.
  double _peakThreshold = 1.2; // g, lowered for real-hardware sensitivity
  double get peakThreshold => _peakThreshold;

  double _runningEnvelope = 0.0;
  bool _aboveThreshold = false;
  double _currentExcursionPeak = 0.0;
  DateTime? _lastMovementAt;

  /// Slow-moving estimate of the resting ("quiet") signal level. Only
  /// updated from samples that are NOT part of an above-threshold
  /// excursion, so a long set does not slowly drag the baseline upward.
  double? _baselineLevel;
  double get baselineLevel => _baselineLevel ?? 1.0;

  final List<Rep> _repsInSet = [];
  int _setCounter = 0;
  int _diagEngineSampleCount = 0;  // diagnostics: samples received by engine

  /// Public: how many samples the engine has received since last reset.
  int get diagEngineSampleCount => _diagEngineSampleCount;

  // ---- Guided calibration mode ----
  final List<double> _calibrationSignals = [];
  final List<double> _calibrationGyroSignals = [];
  static const _minPeakHeight = 1.2;  // restored from 1.05 (diagnosis): must be above noise floor
  static const _minPeakDistanceSamples = 12; // restored from 8: prevents double-counting within one curl
  static const _calibrationPercentile = 0.3;
  static const int calibrationTargetReps = 10;
  static const _minGyroPeakDegPerS = 50.0; // restored from 10.0: requires real rotation, not wrist twitch
  // Diagnostics: track max values seen during calibration
  double _diagMaxAccel = 0;
  double _diagMaxGyro = 0;
  int _finalCalibrationSignalCount = 0;  // snapshot before clear

  /// Public diagnostic accessors for CALIB log capture on UI.
  double get diagMaxAccel => _diagMaxAccel;
  double get diagMaxGyro => _diagMaxGyro;
  int get calibrationSignalCount => _calibrationSignals.length;
  int get finalCalibrationSignalCount => _finalCalibrationSignalCount;

  void processSample(SensorSample s) {
    _diagEngineSampleCount++;

    final combinedSignal = _signalProcessor.process(s);

    // DIAGNOSTIC: log every 50th sample, plus during calibrating every 10th
    final bool shouldLog = _diagEngineSampleCount % 50 == 0 ||
        (_state == WorkoutState.calibrating && _diagEngineSampleCount % 10 == 0);
    if (shouldLog) {
      AppLogger.d('ENGINE #$_diagEngineSampleCount '
          'state=${_state.name} '
          'combined=${combinedSignal.toStringAsFixed(3)} '
          'accelMag=${s.accelMagnitude.toStringAsFixed(3)} '
          'gyroMag=${s.gyroMagnitude.toStringAsFixed(1)} '
          'threshold=$_peakThreshold baseline=${baselineLevel.toStringAsFixed(3)} '
          'above=$_aboveThreshold');
    }

    _runningEnvelope = max(combinedSignal, _runningEnvelope * envelopeDecayRate);

    if (_baselineLevel == null) {
      _baselineLevel = combinedSignal;
    } else if (!_aboveThreshold &&
        _state != WorkoutState.guidedCalibration) {
      // Don't adapt baseline during guided calibration. The calibration
      // reps produce large excursions that would drag the EMA upward
      // (observed: 1.05 → 5.7 during the 2026-07-16 E2E test). The
      // baseline was already set by startGuidedCalibration() from the
      // settled rest signal after the 3s+5s rest/countdown phase, so
      // it is the correct reference point for the entire calibration.
      _baselineLevel = _baselineLevel! * (1 - baselineEmaAlpha) +
          combinedSignal * baselineEmaAlpha;
    }

    switch (_state) {
      case WorkoutState.idle:
        if (_awaitingSettleAfterCalibration) {
          // Don't evaluate movement at all until the tail of the last
          // calibration rep has genuinely settled back down - see field
          // doc comment above.
          final settleLine = baselineLevel + minThresholdAboveBaseline;
          if (combinedSignal <= settleLine) {
            _awaitingSettleAfterCalibration = false;
          }
          break;
        }
        // Baseline-relative: gravity (~1.0g) alone must not trigger
        // calibrating. The signal must rise meaningfully above the
        // resting baseline before we treat it as movement.
        if (combinedSignal >
            baselineLevel + (_peakThreshold - baselineLevel) * 0.5) {
          if (hasValidCalibration) {
            // ADR-020 fix: a valid calibration (guided, or loaded from
            // persistence) already exists - go straight to active
            // tracking, same as the paused state below. Without this
            // branch, the one-rep auto-calibration path in the `else`
            // fires unconditionally and overwrites this threshold after
            // just one rep - see ADR-020 for the full diagnosis.
            _state = WorkoutState.active;
            _repsInSet.clear();
          } else {
            // First real movement IS the first set - no separate, empty
            // calibration step. See ADR-003 / "Magic Moment" principle.
            // Reserved exclusively for users who have never calibrated.
            _state = WorkoutState.calibrating;
          }
          _lastMovementAt = s.timestamp;
          _emitStateEvent();
          // BUGFIX: the triggering sample MUST also be processed by
          // _detectPeak. Without this, the first high signal that
          // transitions out of idle is lost, and if the signal drops
          // before the next sample, no rep is ever counted.
          _detectPeak(s, combinedSignal);
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
        // Baseline-relative: same reasoning as idle — gravity alone
        // must not re-trigger the active state during a pause.
        if (combinedSignal >
            baselineLevel + (_peakThreshold - baselineLevel) * 0.5) {
          _state = WorkoutState.active;
          _lastMovementAt = s.timestamp;
          _emitStateEvent();
        }
        break;

      case WorkoutState.guidedCalibration:
        _calibrationSignals.add(combinedSignal);
        _calibrationGyroSignals.add(s.gyroMagnitude);
        // Track max values for diagnosis.
        if (s.accelMagnitude > _diagMaxAccel) _diagMaxAccel = s.accelMagnitude;
        if (s.gyroMagnitude > _diagMaxGyro) _diagMaxGyro = s.gyroMagnitude;
        final currentPeaks = _findGyroValidatedPeaks();
        if (currentPeaks.length != _lastCalibrationPeakCount) {
          _lastCalibrationPeakCount = currentPeaks.length;
          AppLogger.i('CALIB peaks=$_lastCalibrationPeakCount '
              'maxAccel=${_diagMaxAccel.toStringAsFixed(3)} '
              'maxGyro=${_diagMaxGyro.toStringAsFixed(1)} '
              'signals=${_calibrationSignals.length}');
          final progress =
              (currentPeaks.length / calibrationTargetReps).clamp(0.0, 1.0);
          _controller.add(WorkoutEngineEvent(
            state: _state,
            repsInCurrentSet: currentPeaks.length,
            calibrationProgress: progress,
          ));
        }
        if (currentPeaks.length >= calibrationTargetReps) {
          _finishGuidedCalibration();
        }
        break;

      case WorkoutState.connectionLost:
        // Ignore samples until explicit reset via handleReconnect().
        break;
    }
  }

  void _detectPeak(SensorSample s, double combinedSignal) {
    // S2: effective threshold, only ever LOWER than _peakThreshold, only
    // once enough reps are confirmed (bootstrap: nothing to adapt from
    // before that - see _confirmedPeaks doc comment).
    var effectiveThreshold = _peakThreshold;
    if (_confirmedPeaks.length >= adaptiveMinConfirmed) {
      final window = _confirmedPeaks.sublist(
        max(0, _confirmedPeaks.length - adaptiveWindow),
      )..sort();
      final mid = window.length ~/ 2;
      final medianPeak = window.length.isOdd
          ? window[mid]
          : (window[mid - 1] + window[mid]) / 2;
      effectiveThreshold = min(_peakThreshold, adaptiveThresholdRatio * medianPeak);
      // Floor: see _confirmedPeaks doc comment for the regression this
      // prevents (effective threshold sinking below baseline noise).
      final calibratedExcursion = _peakThreshold - baselineLevel;
      final floor = baselineLevel + max(0.10, 0.15 * calibratedExcursion);
      effectiveThreshold = max(effectiveThreshold, floor);
    }

    // S1: a rising edge during the lockout window (in SAMPLES, not real
    // time - see minRepIntervalSamples doc comment) after the last COUNTED
    // rep is ignored entirely, never sets _aboveThreshold, rather than
    // being allowed to become its own excursion and only being discarded
    // later.
    final inRefractory = _lastCountedRepSample != null &&
        (diagEngineSampleCount - _lastCountedRepSample!) < minRepIntervalSamples;

    if (!_aboveThreshold) {
      _preMin = min(_preMin, combinedSignal);
      if (combinedSignal > effectiveThreshold && !inRefractory) {
        _aboveThreshold = true;
        _currentExcursionPeak = combinedSignal;
        _lastMovementAt = s.timestamp;
        _fallingDebounceCount = 0;
        // Falling threshold for THIS excursion, frozen from the
        // effectiveThreshold that triggered it - see
        // _excursionFallingThreshold doc comment for why this must not be
        // recomputed from the static _peakThreshold later.
        _excursionFallingThreshold = baselineLevel +
            (effectiveThreshold - baselineLevel) * fallingEdgeRatio;
      }
      return;
    }

    _currentExcursionPeak = max(_currentExcursionPeak, combinedSignal);
    _lastMovementAt = s.timestamp;

    if (combinedSignal < _excursionFallingThreshold!) {
      _fallingDebounceCount++;
    } else {
      _fallingDebounceCount = 0;
    }

    if (_fallingDebounceCount >= fallingDebounce) {
      _aboveThreshold = false;
      _fallingDebounceCount = 0;

      final prominence = prominenceRatio * (_peakThreshold - baselineLevel);
      if (prominence > 0.0 && (_currentExcursionPeak - _preMin) < prominence) {
        // Too shallow relative to the preceding valley - likely noise, not
        // a rep. Deliberately NOT resetting _preMin to combinedSignal
        // here: it only updates on the next non-excursion sample (above),
        // otherwise a just-rejected shallow excursion would itself become
        // the new valley for the next check.
        return;
      }

      _repsInSet.add(
        Rep(timestamp: s.timestamp, peakMagnitude: _currentExcursionPeak),
      );
      _confirmedPeaks.add(_currentExcursionPeak);
      _lastCountedRepSample = diagEngineSampleCount;
      _preMin = combinedSignal;
      _emitStateEvent();
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

  // ---- Guided calibration mode ----

  /// Starts a guided calibration recording. The engine records all
  /// [combinedSignal] values and runs event-based peak detection: as soon
  /// as [calibrationTargetReps] distinct peaks are found, calibration
  /// finishes. Live feedback is emitted via [WorkoutEngineEvent].
  ///
  /// See docs/CALIBRATION_MODE_CONCEPT.md for the design rationale.
  void startGuidedCalibration() {
    _calibrationSignals.clear();
    _calibrationGyroSignals.clear();
    _baselineLevel = _signalProcessor.lastFiltered;
    _peakThreshold = 1.2;  // matches default, lowered for real hardware
    _aboveThreshold = false;
    _currentExcursionPeak = 0.0;
    _repsInSet.clear();
    _lastCountedRepSample = null;
    _confirmedPeaks.clear();
    _fallingDebounceCount = 0;
    _preMin = double.infinity;
    _excursionFallingThreshold = null;
    _lastCalibrationPeakCount = 0;
    _diagMaxAccel = 0;
    _diagMaxGyro = 0;
    _state = WorkoutState.guidedCalibration;
    _emitStateEvent();
  }

  int get calibrationPeaksFound => _calibrationPeaksFound;
  int _calibrationPeaksFound = 0;
  int _lastCalibrationPeakCount = 0;  // throttle: only emit when count changes

  void _finishGuidedCalibration() {
    final peaks = _findGyroValidatedPeaks();
    _calibrationPeaksFound = peaks.length;
    _finalCalibrationSignalCount = _calibrationSignals.length;  // snapshot before clear

    final double newThreshold;
    if (peaks.length >= 5) {
      peaks.sort();
      final index = (peaks.length * _calibrationPercentile).round();
      newThreshold = peaks[index.clamp(0, peaks.length - 1)];
    } else {
      newThreshold = _peakThreshold;
    }

    _peakThreshold = newThreshold;
    final excursion = _peakThreshold - baselineLevel;
    minThresholdAboveBaseline = (excursion * 0.5).clamp(0.10, 2.0);
    hasValidCalibration = true; // ADR-020: guided calibration just completed
    _awaitingSettleAfterCalibration = true; // settle-gate, see field doc comment

    _calibrationSignals.clear();
    _calibrationGyroSignals.clear();
    _state = WorkoutState.idle;
    _controller.add(WorkoutEngineEvent(
      state: _state,
      repsInCurrentSet: 0,
      calibrationProgress: 1.0,
      calibratedThreshold: newThreshold,
    ));
  }

  /// 5-sample median filter: for each sample, takes the median of a
  /// 5-sample window centered on that sample. At edges, the window is
  /// clamped. O(n*window) = O(5n).
  List<double> _medianFilter(List<double> signal, int window) {
    final result = <double>[];
    final half = window ~/ 2;
    for (var i = 0; i < signal.length; i++) {
      final start = (i - half).clamp(0, signal.length - 1);
      final end = (i + half + 1).clamp(0, signal.length);
      final window_ = signal.sublist(start, end)..sort();
      result.add(window_[window_.length ~/ 2]);
    }
    return result;
  }

  /// Cancels an ongoing guided calibration, resetting the engine to idle
  /// and discarding any recorded signals. Safe to call at any time.
  void cancelCalibration() {
    _calibrationSignals.clear();
    _calibrationGyroSignals.clear();
    _state = WorkoutState.idle;
    _emitStateEvent();
  }

  /// Peak detector with gyro validation. Finds peaks in the accel signal
  /// (via [_findPeaks]) and cross-references each peak against the gyro
  /// magnitude at the same index. Only peaks where gyro >= [_minGyroPeakDegPerS]
  /// are kept. This eliminates false positives from lifting/shaking the
  /// device without actual rotation (Architecture Review §2.3).
  List<double> _findGyroValidatedPeaks() {
    if (_calibrationSignals.length < 5 || _calibrationGyroSignals.length < 5) {
      return [];
    }
    // Get accel peak indices with magnitudes.
    final accelPeaks = _findPeaksWithIndices(_calibrationSignals);
    // Validate: gyro must also show rotation at the same time.
    final validated = <double>[];
    for (final (idx, mag) in accelPeaks) {
      if (idx < _calibrationGyroSignals.length &&
          _calibrationGyroSignals[idx] >= _minGyroPeakDegPerS) {
        validated.add(mag);
      }
    }
    return validated;
  }

  /// Like [_findPeaks] but returns (index, magnitude) pairs so gyro
  /// validation can cross-reference peak positions.
  ///
  /// Tie-tolerant on purpose (`>=` on the left, `>` on the right): a plain
  /// `smoothed[i] > both neighbours` check cannot select ANY index inside a
  /// flat plateau, and the 5-sample median filter reliably produces exactly
  /// such a plateau at the top of a clean, controlled rep - confirmed via
  /// tools/workout_engine_simulation.py run_guided_calibration_suite() at
  /// the real ~14-20Hz app data rate: 0/30 calibrations completed with the
  /// strict version, 30/30 with this tie-tolerant version. Fixed
  /// 2026-07-12, see docs/ANALYSE_EXTERNE_KI_2026-07-12.md Punkt F. Picks
  /// the FIRST sample of a plateau as the peak index.
  List<(int, double)> _findPeaksWithIndices(List<double> signal) {
    if (signal.length < 5) return [];
    final smoothed = _medianFilter(signal, 5);
    final maxima = <int>[];
    for (var i = 1; i < smoothed.length - 1; i++) {
      if (smoothed[i] >= smoothed[i - 1] && smoothed[i] > smoothed[i + 1]) {
        maxima.add(i);
      }
    }
    final peaks = <(int, double)>[];
    int? lastPeakIndex;
    for (final idx in maxima) {
      if (smoothed[idx] < _minPeakHeight) continue;
      if (lastPeakIndex != null &&
          (idx - lastPeakIndex) < _minPeakDistanceSamples) {
        if (smoothed[idx] > peaks.last.$2) {
          peaks.last = (idx, smoothed[idx]);
          lastPeakIndex = idx;
        }
        continue;
      }
      peaks.add((idx, smoothed[idx]));
      lastPeakIndex = idx;
    }
    return peaks;
  }

  void dispose() => _controller.close();

  /// Call when the BLE connection is lost mid-workout. Saves the current
  /// set as aborted and transitions to [WorkoutState.connectionLost].
  /// Safe to call from any state (no-op if already idle/disconnected).
  void handleDisconnect() {
    if (_state == WorkoutState.idle ||
        _state == WorkoutState.paused ||
        _state == WorkoutState.connectionLost) {
      return;
    }
    // Save whatever reps were counted as an aborted set.
    if (_repsInSet.isNotEmpty) {
      _setCounter++;
      final abortedSet = ExerciseSet(
        id: 'set_${DateTime.now().microsecondsSinceEpoch}_$_setCounter',
        exerciseId: exerciseId,
        countedReps: _repsInSet.length,
        endedAt: DateTime.now(),
        reps: List.of(_repsInSet),
      );
      _repsInSet.clear();
      _controller.add(WorkoutEngineEvent(
        state: WorkoutState.connectionLost,
        repsInCurrentSet: 0,
        completedSet: abortedSet,
      ));
      _state = WorkoutState.connectionLost;
      return;
    }
    _state = WorkoutState.connectionLost;
    _emitStateEvent();
  }

  /// Call when the BLE connection is re-established. Resets the engine
  /// to idle, discarding old baseline and filter state.
  void handleReconnect() {
    _signalProcessor.reset();
    _baselineLevel = null;
    _runningEnvelope = 0.0;
    _aboveThreshold = false;
    _currentExcursionPeak = 0.0;
    _lastMovementAt = null;
    _lastCountedRepSample = null;
    _confirmedPeaks.clear();
    _fallingDebounceCount = 0;
    _preMin = double.infinity;
    _excursionFallingThreshold = null;
    _repsInSet.clear();
    _state = WorkoutState.idle;
    _emitStateEvent();
  }

  /// Applies persisted calibration parameters to this engine instance,
  /// updating the threshold and related fields in place — WITHOUT
  /// recreating the engine.
  ///
  /// This method exists to fix a race condition (found during the E2E
  /// hardware test on 2026-07-16) where [_HomeScreenState._loadCalibration]
  /// previously disposed the old engine and created a new one. Any code
  /// that had captured a reference to the old engine (notably the
  /// [_CalibrationDialog], which receives the engine as a constructor
  /// parameter) would then call [startGuidedCalibration] on a disposed
  /// engine — the call silently did nothing, and the live engine never
  /// entered guidedCalibration state.
  ///
  /// By applying calibration in-place, the engine reference stays stable
  /// for the lifetime of the [_HomeScreenState], and all listeners
  /// (samples, events, dialog) always talk to the same instance.
  void applyCalibration({
    required double peakThreshold,
    required double minThresholdAboveBaseline,
    bool markValid = true,
  }) {
    _peakThreshold = peakThreshold;
    this.minThresholdAboveBaseline = minThresholdAboveBaseline;
    if (markValid) {
      hasValidCalibration = true;
    }
    // Reset transient state so the engine starts fresh with the new
    // threshold, mirroring what a freshly-constructed engine would have.
    _aboveThreshold = false;
    _currentExcursionPeak = 0.0;
    _repsInSet.clear();
    _runningEnvelope = 0.0;
    _lastMovementAt = null;
    _lastCountedRepSample = null;
    _confirmedPeaks.clear();
    _fallingDebounceCount = 0;
    _preMin = double.infinity;
    _excursionFallingThreshold = null;
    // Don't reset _baselineLevel — let the EMA adapt naturally from
    // whatever the current signal level is. A null baseline (fresh
    // engine) would re-initialise on the next sample; keeping the
    // existing value avoids a brief window of wrong threshold logic.
    if (_state != WorkoutState.guidedCalibration) {
      _state = WorkoutState.idle;
    }
  }
}

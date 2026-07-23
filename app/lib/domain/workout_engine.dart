import 'dart:async';
import 'dart:math';

import 'package:flowrep/data/logger.dart';
import 'package:flowrep/domain/config/engine_constants.dart';
import 'package:flowrep/domain/models/exercise_profile.dart' show ChosenSignal;
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/signal_processor.dart';
import 'package:flowrep/domain/exercise_engine.dart' as pipeline;
import 'package:flowrep/domain/state/workout_state_machine.dart';

// Kanonischer WorkoutState lebt in state/workout_state_machine.dart.
// Re-Export für Abwärtskompatibilität (alle bestehenden Imports weiter gültig).
export 'state/workout_state_machine.dart' show WorkoutState;

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
  // === NEUE PIPELINE (KRITISCHER SCHRITT 3: Facade-Pattern) ===
  // Feature-Flag: solang false, läuft der Legacy-Pfad unverändert weiter.
  // Aktivierung erst, wenn die neue Pipeline gegen reale Daten validiert ist.
  // ignore: prefer_final_fields
  bool _useNewPipeline = false;

  /// Shadow-Mode: Beide Pfade laufen parallel, Legacy bleibt autoritativ.
  ///
  /// Aktivierung: [enableShadowMode] = true. Die neue Pipeline läuft still
  /// mit; Rep-Unterschiede werden geloggt (AppLogger). Dient als Gate vor
  /// der endgültigen Aktivierung (_useNewPipeline = true).
  ///
  /// Checklist vor Pipeline-Aktivierung:
  /// 1. Shadow-Mode mit echten CSV/Hardware-Sätzen: Rep-Diff = 0
  /// 2. Gleiche Events/States (idle/active/pause/set-end)
  /// 3. Template aus ExerciseProfile tatsächlich in ExerciseEngine.setTemplate
  /// 4. Dann: _useNewPipeline = true, Legacy schrumpfen
  // ignore: prefer_final_fields
  bool _shadowMode = false;
  int _shadowRepCount = 0;
  int _legacyRepCount = 0;

  /// Die neue ExerciseEngine-Pipeline (SignalChain → RepCounter → StateMachine).
  /// Wird lazy initialisiert, sobald rotationAxis/gyroBias verfügbar sind.
  pipeline.ExerciseEngine? _exerciseEngine;

  /// Initialisiert die neue Pipeline mit Kalibrierungsdaten.
  /// Wird aus [applyCalibration] aufgerufen, wenn rotationAxis/gyroBias vorhanden.
  void _initNewPipeline(List<double> rotationAxis, List<double> gyroBias) {
    _exerciseEngine?.dispose();
    _exerciseEngine = pipeline.ExerciseEngine(
      config: pipeline.ExerciseEngineConfig(
        rotationAxis: rotationAxis,
        gyroBias: gyroBias,
        hasValidCalibration: hasValidCalibration,
      ),
    );
  }

  WorkoutEngine({
    required this.exerciseId,
    SignalProcessor? signalProcessor,
    this.envelopeDecayRate = 0.95,
    this.pauseAfter = const Duration(seconds: 4),
    this.calibrationReps = 1,
    this.minRepIntervalSamples = 24,
    this.fallingDebounce = 4,
    this.prominenceRatio = 0.30,
    this.adaptiveThresholdRatio = 0.25,
    this.adaptiveMinConfirmed = 3,
    this.adaptiveWindow = 5,
    this.fallingEdgeRatio = 0.7,
    this.baselineEmaAlpha = 0.01,
    this.minThresholdAboveBaseline = 0.10,
    this.hasValidCalibration = false,
    this.useSignedProjectionCounting = false,
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

  /// S1, noise guard - NOT a double_bump fix, see below: minimum number of
  /// SAMPLES (not real time) after a COUNTED rep before a new rising edge
  /// in [_detectPeak] is accepted at all. Counted in samples rather than
  /// Duration because S3 (docs/RECHERCHE_ZAEHLROBUSTHEIT) means real
  /// elapsed time doesn't yet mean what it appears to - the firmware sends
  /// bursts of 4 without honest per-sample pacing. Sample count stays
  /// meaningful regardless of how that pacing behaves; once Schritt C
  /// (Agent 4's protocol + honest timestamps) lands, this should convert
  /// to a real-time duration.
  ///
  /// CORRECTED 2026-07-17 (Claude-c00679f3, after real `flutter test` via
  /// Desktop Commander found a live regression): the first version of this
  /// used 40 samples, the smallest value that fully solved the double-hump
  /// scenario (20 counted -> 10) in isolation. That BROKE three existing
  /// tests in workout_engine_test.dart, which rely on a 35-samples/rep
  /// cadence (_generateSyntheticReps, samplesPerRep=30+rest=5) that
  /// predates this change - 40 > 35 meant every second legitimate rep fell
  /// inside the lockout and got silently dropped (10/10 counted -> 5/10).
  /// Re-swept in tools/workout_engine_simulation.py with that cadence as a
  /// hard constraint: the largest safe value is 28 samples, and at NO
  /// value <= 28 does the double-hump case improve at all - its own
  /// hump-to-hump gap is itself bigger than 28 samples, so a single fixed
  /// sample-count refractory cannot satisfy both constraints simultaneously.
  ///
  /// 24 samples (a small margin below the 28-sample safe ceiling) is kept
  /// as a defense-in-depth guard against very tight, clearly-spurious
  /// re-triggers (sensor noise, not a real second hump), NOT as the S1 fix
  /// - that is what Schritt B (g_p, signed gyro projection) is for,
  /// verified in tools/workout_engine_simulation.py to fix the double-hump
  /// case with ZERO refractory needed at all, since it separates
  /// concentric/eccentric by sign rather than by timing. Schritt B is not
  /// yet ported to this engine (see commit history / STATUS_FORTSCHRITT.md).
  // ignore: prefer_final_fields
  int minRepIntervalSamples;

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

  // --- Schritt B (P2, S8) shadow-counting state - only touched when
  // useSignedProjectionCounting is true. Entirely separate from the
  // combined-signal fields above; does not read or write any of them. ---
  double? _gpThreshold; // set once, from the same calibration rep(s) as _peakThreshold
  int _gpDirection = 1; // +1 or -1: which sign of g_p corresponds to a rep's primary excursion
  double _gpPeakDuringCalibrationAbs = 0.0; // |g_p| high-water mark while calibrating
  int _gpSignAtPeakDuringCalibration = 1;
  bool _gpAboveThreshold = false;
  int _gpRepCount = 0;

  /// Rep count from the Schritt B signed-gyro-projection shadow path, or
  /// null if [useSignedProjectionCounting] is false or the axis/threshold
  /// haven't been learned yet (see [SignalProcessor.isSignedProjectionReady]
  /// and [_gpThreshold]). See [useSignedProjectionCounting] doc comment for
  /// what this is and isn't yet.
  int? get signedProjectionRepCount =>
      useSignedProjectionCounting && _gpThreshold != null ? _gpRepCount : null;

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

  /// Agent 1 / Schritt B (P2, S8, docs/RECHERCHE_ZAEHLROBUSTHEIT_2026-07-16.md,
  /// tools/workout_engine_simulation.py pruefe_strukturellen_gp_fix): when
  /// true, the engine ALSO runs a parallel, signed-gyro-projection-based
  /// rep count (see [signedProjectionRepCount]) alongside the existing
  /// combined-magnitude [_detectPeak] path, which remains completely
  /// unaffected and is still what [ExerciseSet.countedReps] reports.
  ///
  /// Deliberately a SHADOW counter, not a replacement, for now: g_p fixes
  /// the double-hump case structurally in simulation (10/10 with zero
  /// refractory, vs. combined's ~19-20/10 under the same condition - see
  /// the Python proof), but this Dart port has not been run against real
  /// hardware, unlike the combined-signal path (verified 2026-07-18,
  /// commit accf44d). Flip this on to compare the two counts against a
  /// real workout before considering a switch of which one actually gates
  /// [ExerciseSet.countedReps].
  final bool useSignedProjectionCounting;

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

  // 2026-07-20 bugfix: the idle-wake gate below used to derive its
  // margin straight from _peakThreshold - fine as long as _peakThreshold
  // stayed in combinedSignal's own units, which stopped being true the
  // moment applyCalibration started accepting a gP-scale threshold
  // (rotationAxis/gyroBias, Punkt 1). combinedSignal realistically sits
  // in the 1-10 range; a gP-scale theta can be 100+ (degrees/second) -
  // (combinedSignal > baseline + (peakThreshold-baseline)*0.5) then
  // becomes nearly impossible to satisfy, and the engine never leaves
  // idle at all. Verified: a wizard run that happens to choose gP as
  // chosenSignal would have made live counting appear completely dead,
  // not just inaccurate - countedReps stuck at 0 regardless of what the
  // user does. Kept separate from _peakThreshold on purpose rather than
  // trying to rescale it: this gate only ever needs to answer "is
  // anything significant happening at all", never precise per-signal
  // accuracy - that's _detectPeak/_detectPeakSigned's job downstream.
  double _wakeThreshold = 1.2;

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
    if (_useNewPipeline && _exerciseEngine != null) {
      _processSampleNewPipeline(s);
      return;
    }
    _processSampleLegacy(s);

    // Shadow-Mode: neue Pipeline parallel laufen lassen (nur Logging)
    if (_shadowMode && _exerciseEngine != null) {
      _processShadowSample(s);
    }
  }

  /// Shadow-Vergleich: führt die neue Pipeline still aus und loggt Diffs.
  void _processShadowSample(SensorSample s) {
    final result = _exerciseEngine!.processSample(
      timestampMs: s.timestamp.millisecondsSinceEpoch,
      gx: s.gx,
      gy: s.gy,
      gz: s.gz,
    );
    if (result.repResult.repCounted) {
      _shadowRepCount++;
      if (_shadowRepCount != _legacyRepCount) {
        AppLogger.w('SHADOW-DIFF: legacy=$_legacyRepCount '
            'new=$_shadowRepCount (Δ=${_shadowRepCount - _legacyRepCount})');
      }
    }
  }

  /// Aktiviert den Shadow-Mode (beide Pfade parallel, Legacy autoritativ).
  void enableShadowMode() {
    _shadowMode = true;
    _shadowRepCount = 0;
    _legacyRepCount = 0;
    AppLogger.i('Shadow-Mode aktiviert: neue Pipeline läuft parallel.');
  }

  /// Deaktiviert den Shadow-Mode.
  void disableShadowMode() {
    _shadowMode = false;
    AppLogger.i('Shadow-Mode deaktiviert. '
        'Legacy=$_legacyRepCount, New=$_shadowRepCount');
  }

  /// Shadow-Statistik (für Diagnose/UI).
  ({int legacyReps, int newReps, int diff}) get shadowStats => (
    legacyReps: _legacyRepCount,
    newReps: _shadowRepCount,
    diff: _shadowRepCount - _legacyRepCount,
  );

  /// NEUER PFAD (KRITISCHER SCHRITT 3): delegiert an ExerciseEngine.
  /// Öffentliche API bleibt identisch — gleiche Events, gleiche Zustände.
  void _processSampleNewPipeline(SensorSample s) {
    _diagEngineSampleCount++;

    final result = _exerciseEngine!.processSample(
      timestampMs: s.timestamp.millisecondsSinceEpoch,
      gx: s.gx,
      gy: s.gy,
      gz: s.gz,
    );

    if (result.repResult.repCounted) {
      _repsInSet.add(Rep(
        timestamp: s.timestamp,
        peakMagnitude: result.repResult.qualityScore ?? 0.0,
      ));
      _lastMovementAt = s.timestamp;
      _emitStateEvent();
    }

    // Pause-Timeout prüfen (Satz beenden nach Inaktivität)
    if (_state == WorkoutState.active &&
        _lastMovementAt != null &&
        s.timestamp.difference(_lastMovementAt!) > pauseAfter) {
      _endSet();
    }
  }

  void _processSampleLegacy(SensorSample s) {
    _diagEngineSampleCount++;

    final combinedSignal = _signalProcessor.process(s);

    // Schritt B shadow path: opt-in via the constructor flag, OR mandatory
    // because a real profile chose gP as the primary signal
    // (applyCalibration) - either way, computed unconditionally alongside
    // (never instead of) the combined-signal path above.
    double? gp;
    if (useSignedProjectionCounting || _primarySignal == ChosenSignal.gP) {
      _signalProcessor.observeForAxisLearning(s);
      gp = _signalProcessor.signedGyroProjection(s);
    }
    if (gp != null && _gpThreshold == null) {
      // Self-contained g_p auto-calibration, decoupled on purpose from the
      // combined-signal auto-calibration below: axis learning takes
      // axisLearningWindowSamples (~100, ~2s) to complete, which can
      // easily be LONGER than a single calibrationReps=1 rep - if this
      // instead tried to read gp only during WorkoutState.calibrating (the
      // first version of this code did exactly that), it would frequently
      // still be null by the time that state's calibration completes, and
      // _gpThreshold would silently never get set at all (found via real
      // flutter test, not simulation - the Python proof always calibrated
      // g_p directly from a single already-defined rep, so it never hit
      // this ordering issue). So instead: track the largest |g_p| seen at
      // all, on any sample, since the axis became known, and finalise a
      // threshold the first time that peak has clearly come back down -
      // i.e. this rep, whichever one it turns out to be, is treated as
      // g_p's own one-rep calibration, independently of which sample
      // index the COMBINED signal happened to finish its own calibration
      // on.
      final absGp = gp.abs();
      if (absGp > _gpPeakDuringCalibrationAbs) {
        _gpPeakDuringCalibrationAbs = absGp;
        _gpSignAtPeakDuringCalibration = gp >= 0 ? 1 : -1;
      }
      const minGpPeakForCalibration = 20.0; // deg/s - a real curl, not noise
      if (_gpPeakDuringCalibrationAbs > minGpPeakForCalibration &&
          absGp < _gpPeakDuringCalibrationAbs * 0.3) {
        _gpThreshold = _gpPeakDuringCalibrationAbs * 0.5;
        _gpDirection = _gpSignAtPeakDuringCalibration;
      }
    }

    // DIAGNOSTIC: log every 50th sample, plus during calibrating every 10th
    final bool shouldLog = _diagEngineSampleCount % 50 == 0 ||
        (_state == WorkoutState.calibrating && _diagEngineSampleCount % 10 == 0);
    if (shouldLog) {
      final effThresh = _primarySignal == ChosenSignal.gP
          ? _gpThreshold
          : _primarySignal == ChosenSignal.gyroMag
              ? _gyroMagThreshold
              : _peakThreshold;
      AppLogger.d('ENGINE #$_diagEngineSampleCount '
          'state=${_state.name} '
          'combined=${combinedSignal.toStringAsFixed(3)} '
          'accelMag=${s.accelMagnitude.toStringAsFixed(3)} '
          'gyroMag=${s.gyroMagnitude.toStringAsFixed(1)} '
          'gp=${gp?.toStringAsFixed(1) ?? "n/a"} '
          'threshold=${effThresh ?? _peakThreshold} '
          'sig=${_primarySignal?.name ?? "combined"} '
          'gpT=${_gpThreshold?.toStringAsFixed(1)} '
          'gmT=${_gyroMagThreshold?.toStringAsFixed(1)} '
          'reps=$_legacyRepCount gpReps=$_gpRepCount '
          'baseline=${baselineLevel.toStringAsFixed(3)} '
          'above=$_aboveThreshold');
    }

    _runningEnvelope = max(combinedSignal, _runningEnvelope * envelopeDecayRate);

    if (_baselineLevel == null) {
      _baselineLevel = combinedSignal;
    } else if (!_aboveThreshold &&
        _state != WorkoutState.guidedCalibration &&
        _state != WorkoutState.paused &&
        _state != WorkoutState.connectionLost) {
      // P0.5 Baseline-Gate: freeze in guidedCalibration / paused /
      // connectionLost. In active, only update at true rest
      // (|gyro| < kGyroRestThresholdDegPerSec) so everyday motion cannot
      // drift the baseline upward (Adi-Bug).
      final atRest =
          s.gyroMagnitude < kGyroRestThresholdDegPerSec;
      if (_state != WorkoutState.active || atRest) {
        _baselineLevel = _baselineLevel! * (1 - baselineEmaAlpha) +
            combinedSignal * baselineEmaAlpha;
      }
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
        // resting baseline before we treat it as movement. Uses
        // _wakeThreshold, NOT _peakThreshold - see that field's doc
        // comment for why using _peakThreshold directly here was a bug.
        if (combinedSignal >
            baselineLevel + (_wakeThreshold - baselineLevel) * 0.5) {
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
          // peak detectors. Without this, the first high signal that
          // transitions out of idle is lost, and if the signal drops
          // before the next sample, no rep is ever counted.
          _detectPeak(s, combinedSignal);
          if (gp != null && _gpThreshold != null) {
            _detectPeakSigned(gp, s.timestamp);
          }
          if (_gyroMagThreshold != null) {
            final gm = _signalProcessor.biasCorrectedGyroMagnitude(s);
            if (gm != null) _detectPeakGyroMag(s, gm);
          }
        }
        break;

      case WorkoutState.calibrating:
        _detectPeak(s, combinedSignal);
        if (gp != null && _gpThreshold != null) {
          _detectPeakSigned(gp, s.timestamp);
        }
        if (_gyroMagThreshold != null) {
          final gm = _signalProcessor.biasCorrectedGyroMagnitude(s);
          if (gm != null) _detectPeakGyroMag(s, gm);
        }
        if (_confirmedPeaks.length >= calibrationReps) {
          // Median rather than mean: robust against a single outlier
          // calibration rep (e.g. the device getting bumped) skewing the
          // threshold - confirmed via the outlier-calibration robustness
          // test in tools/workout_engine_simulation.py.
          final sortedPeaks = List<double>.from(_confirmedPeaks)..sort();
          final mid = sortedPeaks.length ~/ 2;
          final medianPeak = sortedPeaks.length.isOdd
              ? sortedPeaks[mid]
              : (sortedPeaks[mid - 1] + sortedPeaks[mid]) / 2;
          final calibrated =
              baselineLevel + (medianPeak - baselineLevel) * 0.5;
          _peakThreshold =
              max(calibrated, baselineLevel + minThresholdAboveBaseline);
          // Same _wakeThreshold bugfix as applyCalibration/
          // _finishGuidedCalibration - this auto-calibration path is
          // combined-signal-scale only, same as those.
          _wakeThreshold = _peakThreshold;
          // Schritt B's own g_p threshold is calibrated independently, see
          // the self-contained tracking near the top of this method - not
          // tied to this specific state-completion moment (it used to be;
          // see that comment for why that ordering was wrong).
          _state = WorkoutState.active;
          _emitStateEvent();
        }
        break;

      case WorkoutState.active:
        _detectPeak(s, combinedSignal);
        if (gp != null && _gpThreshold != null) {
          _detectPeakSigned(gp, s.timestamp);
        }
        if (_gyroMagThreshold != null) {
          final gm = _signalProcessor.biasCorrectedGyroMagnitude(s);
          if (gm != null) _detectPeakGyroMag(s, gm);
        }
        if (_lastMovementAt != null &&
            s.timestamp.difference(_lastMovementAt!) > pauseAfter) {
          _endSet();
        }
        break;

      case WorkoutState.paused:
        // Baseline-relative: same reasoning as idle — gravity alone
        // must not re-trigger the active state during a pause. Uses
        // _wakeThreshold, same bugfix as the idle case above.
        if (combinedSignal >
            baselineLevel + (_wakeThreshold - baselineLevel) * 0.5) {
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

      case WorkoutState.resting:
        // Neuer Pipeline-State (Satzpause). Im Legacy-Pfad nicht verwendet,
        // da _endSet() direkt zu idle zurückkehrt.
        break;
    }
  }

  void _detectPeak(SensorSample s, double combinedSignal) {
    // S2: effective threshold, only ever LOWER than _peakThreshold, only
    // once enough reps are confirmed (bootstrap: nothing to adapt from
    // before that - see _confirmedPeaks doc comment).
    var effectiveThreshold = _peakThreshold;
    if (_adaptiveThresholdEnabled && _confirmedPeaks.length >= adaptiveMinConfirmed) {
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

      final prominence = _prominenceOverride ??
          prominenceRatio * (_peakThreshold - baselineLevel);
      if (prominence > 0.0 && (_currentExcursionPeak - _preMin) < prominence) {
        // Too shallow relative to the preceding valley - likely noise, not
        // a rep. Deliberately NOT resetting _preMin to combinedSignal
        // here: it only updates on the next non-excursion sample (above),
        // otherwise a just-rejected shallow excursion would itself become
        // the new valley for the next check.
        return;
      }

      // 2026-07-19 (real-hardware complaint, Adi verbatim: "wenn ich den
      // M5 nur bewege oder etwas drehe werden reps gezaehlt" - RIGOROUSLY
      // reproduced, not just anecdotal: a synthetic sweep of 360 bursts
      // of arbitrary, non-repeating-axis motion at 150-190 deg/s - the
      // exact range seen in real hardware logs - produced a false rep on
      // EVERY SINGLE burst via this combined/magnitude-only path, because
      // it has no notion of direction, only "was something above
      // threshold". Once g_p (signed, direction-aware) has a learned
      // threshold, it becomes authoritative for _repsInSet/countedReps
      // instead - see [_gpIsAuthoritative] - and this combined-signal
      // path continues running (needed as the bootstrap source before
      // g_p is ready, and as the sole path when the feature is off) but
      // stops writing to _repsInSet once g_p has taken over, so the two
      // paths can never double-count the same physical rep.
      if (_combinedCountsReps) {
        _commitRep(
          timestamp: s.timestamp,
          peakMagnitude: _currentExcursionPeak,
        );
      }
      _confirmedPeaks.add(_currentExcursionPeak);
      _preMin = combinedSignal;
    }
  }

  /// True once the signed g_p path has a learned threshold AND the
  /// feature is enabled - from that point on it, not the combined-signal
  /// path above, is the source of truth for _repsInSet/countedReps (see
  /// bugfix comment in [_detectPeak] and [_detectPeakSigned] for why).
  // --- Threshold routing (2026-07-20 follow-up to Punkt 1's axis wiring
  // above): Punkt 1 deliberately left _gpThreshold coming from live
  // auto-calibration even when a profile's chosenSignal says gP - "a
  // separate, larger decision" per its own commit message. This is that
  // decision: chosenSignal/minRepIntervalSeconds/prominenceMin from
  // ExerciseProfile, routed to the field whose UNITS actually match. ---

  /// Which signal a real profile chose (`ExerciseProfile.chosenSignal` via
  /// [applyCalibration]) - null (the default) means no profile has set
  /// this, i.e. [_gpIsAuthoritative] alone (self-calibrated, live
  /// auto-calibration threshold) still governs whether g_p or combined
  /// counts, unchanged from before this addition.
  ChosenSignal? _primarySignal;

  /// Absolute prominence (not a ratio) from a real profile's
  /// `prominenceMin`, used instead of [prominenceRatio]'s computation when
  /// present - see [applyCalibration].
  double? _prominenceOverride;

  double? _gyroMagThreshold;
  bool _gyroMagAboveThreshold = false;
  int _gyroMagRepCount = 0;
  /// When true, gyroMag peaks write to [_repsInSet] (ChosenSignal.gyroMag).
  bool _gyroMagCountsReps = false;

  /// When true, gP peak detection uses |g_p| (sign-agnostic). Profile gP
  /// enables this so a flipped mount / axis sign still counts curls;
  /// [minRepIntervalSamples] suppresses the opposite-phase double-hump.
  bool _gpUseAbsProjection = false;

  bool get _gyroMagIsAuthoritative =>
      _gyroMagCountsReps && _gyroMagThreshold != null;
  int? get gyroMagRepCount => _gyroMagThreshold != null ? _gyroMagRepCount : null;

  /// S2's adaptive threshold ([adaptiveThresholdRatio]) is a stopgap for
  /// the FRAGILE single-rep auto-calibration (`calibrationReps`, default
  /// 1) - it exists to cope with a threshold that was never properly
  /// tuned. A real profile from Guided Calibration 2.0's Known-Count
  /// process is already properly tuned against verified repetitions;
  /// letting the adaptive mechanism keep eroding THAT threshold based on
  /// whatever movement happens to get confirmed next has no equivalent
  /// upside. Defaults to true (unchanged behaviour for a profile-less
  /// engine); [applyCalibration] sets this false whenever it's called
  /// with a non-null `chosenSignal`.
  bool _adaptiveThresholdEnabled = true;

  bool get _gpIsAuthoritative =>
      (useSignedProjectionCounting || _primarySignal == ChosenSignal.gP) &&
      _gpThreshold != null;

  /// Combined-magnitude path only counts when neither direction-aware path
  /// owns the rep. Profile gP/gyroMag also raise [_peakThreshold] to a
  /// sentinel so a missing gate cannot fall back to ultra-sensitive 1.2g.
  bool get _combinedCountsReps =>
      !_gpIsAuthoritative && !_gyroMagIsAuthoritative;

  /// Schritt B (P2, S8) shadow counting: rising/falling edge on the SIGNED
  /// g_p signal instead of _peakThreshold-gated combined magnitude. No
  /// refractory, no debounce, no prominence - proven in
  /// tools/workout_engine_simulation.py (pruefe_strukturellen_gp_fix) not
  /// to need any of that, because the opposite-signed lobe (the OTHER
  /// half of the same rep, e.g. the eccentric phase) never crosses a
  /// same-signed threshold in the first place. Callers pass the raw
  /// signed [gp] value; normalisation by [_gpDirection] (which sign is
  /// "the primary excursion direction", learned during calibration - see
  /// [_gpSignAtPeakDuringCalibration]) happens inside this method.
  ///
  /// 2026-07-19: promoted from a pure shadow counter (_gpRepCount only)
  /// to the actual countedReps source once ready (_gpIsAuthoritative) -
  /// see [_detectPeak] bugfix comment for the real-hardware false-positive
  /// finding this fixes. _gpRepCount itself is kept exactly as before
  /// (always increments here, whether authoritative yet or not) so it
  /// keeps working as a diagnostic/shadow value regardless.
  void _detectPeakSigned(double gp, DateTime timestamp) {
    final threshold = _gpThreshold!;
    // Profile path: |g_p| (tilt/sign tolerant). Self-calib path: signed
    // with learned direction (structural double-hump fix).
    final value = _gpUseAbsProjection ? gp.abs() : gp * _gpDirection;
    if (!_gpAboveThreshold && value > threshold) {
      _gpAboveThreshold = true;
      _lastMovementAt = timestamp;
    } else if (_gpAboveThreshold && value < threshold * 0.3) {
      _gpAboveThreshold = false;
      _gpRepCount++;
      if (_gpIsAuthoritative) {
        _commitRep(timestamp: timestamp, peakMagnitude: gp.abs());
      }
    }
  }

  /// Shared rep commit with sample-based refractory (minRepIntervalSamples).
  void _commitRep({required DateTime timestamp, required double peakMagnitude}) {
    final inRefractory = _lastCountedRepSample != null &&
        (diagEngineSampleCount - _lastCountedRepSample!) < minRepIntervalSamples;
    if (inRefractory) return;
    _repsInSet.add(Rep(timestamp: timestamp, peakMagnitude: peakMagnitude));
    _legacyRepCount++;
    _lastCountedRepSample = diagEngineSampleCount;
    _lastMovementAt = timestamp;
    _emitStateEvent();
  }

  /// `ChosenSignal.gyroMag` counterpart to [_detectPeakSigned]: same
  /// simple rising/falling edge, on bias-corrected gyro MAGNITUDE
  /// ([SignalProcessor.biasCorrectedGyroMagnitude]) instead of a signed
  /// projection - always non-negative, so there is no sign/direction
  /// concept here at all. Only ever reached when a real profile
  /// explicitly chose this signal ([_gyroMagThreshold] is null otherwise -
  /// no self-calibrating fallback exists for it, unlike g_p's
  /// live-auto-calibration path).
  void _detectPeakGyroMag(SensorSample s, double gyroMag) {
    final threshold = _gyroMagThreshold!;
    if (!_gyroMagAboveThreshold && gyroMag > threshold) {
      _gyroMagAboveThreshold = true;
      _lastMovementAt = s.timestamp;
    } else if (_gyroMagAboveThreshold && gyroMag < threshold * 0.3) {
      _gyroMagAboveThreshold = false;
      _gyroMagRepCount++;
      if (_gyroMagIsAuthoritative) {
        _commitRep(timestamp: s.timestamp, peakMagnitude: gyroMag);
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
    _wakeThreshold = 1.2;  // same bugfix as applyCalibration - see doc comment
    _aboveThreshold = false;
    _currentExcursionPeak = 0.0;
    _repsInSet.clear();
    _lastCountedRepSample = null;
    _confirmedPeaks.clear();
    _fallingDebounceCount = 0;
    _preMin = double.infinity;
    // Schritt B: NOT re-calibrated by guided calibration (that's a
    // separate path, _findGyroValidatedPeaks, not _detectPeak) - reset to
    // "not yet calibrated" rather than carry over a threshold from a
    // possibly-stale earlier auto-calibration.
    _gpThreshold = null;
    _gpDirection = 1;
    _gpPeakDuringCalibrationAbs = 0.0;
    _gpAboveThreshold = false;
    _gpRepCount = 0;
    _gyroMagThreshold = null;
    _gyroMagAboveThreshold = false;
    _gyroMagRepCount = 0;
    _gyroMagCountsReps = false;
    _gpUseAbsProjection = false;
    _primarySignal = null;
    _prominenceOverride = null;
    _adaptiveThresholdEnabled = true;
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
    // Bugfix, same as applyCalibration: guided calibration is entirely
    // combined-signal-scale (no rotationAxis/gyroBias concept exists on
    // this path at all), so _wakeThreshold must track the freshly
    // learned threshold here exactly like _peakThreshold does - or the
    // idle/paused wake gate keeps using startGuidedCalibration()'s stale
    // 1.2 default instead of what was just calibrated.
    _wakeThreshold = newThreshold;
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

  void dispose() {
    _exerciseEngine?.dispose();
    _controller.close();
  }

  /// User-initiated pause/stop of counting. Clears in-progress set reps
  /// and returns to [WorkoutState.idle] without aborting as a completed set.
  /// Calibration profile and thresholds are preserved.
  void pause() {
    if (_state == WorkoutState.idle || _state == WorkoutState.paused) {
      return;
    }
    _repsInSet.clear();
    _aboveThreshold = false;
    _currentExcursionPeak = 0.0;
    _gpAboveThreshold = false;
    _gyroMagAboveThreshold = false;
    _fallingDebounceCount = 0;
    _excursionFallingThreshold = null;
    _state = WorkoutState.idle;
    _emitStateEvent();
  }

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
    if (_primarySignal == null) {
      // Self-calibrated placeholder path only - a real profile's
      // threshold survives a reconnect for the same reason its axis now
      // does (SignalProcessor.reset() doc comment): it came from a real
      // calibration, not from watching live samples in THIS session.
      _gpThreshold = null;
      _gpDirection = 1;
      _gpPeakDuringCalibrationAbs = 0.0;
      _gyroMagThreshold = null;
    }
    _gpAboveThreshold = false;
    _gpRepCount = 0;
    _gyroMagAboveThreshold = false;
    _gyroMagRepCount = 0;
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
  /// [chosenSignal]/[minRepIntervalSeconds]/[prominenceMin] mirror
  /// `ExerciseProfile`'s fields of the same name (2026-07-20, follow-up to
  /// [rotationAxis]/[gyroBias] above - see the field doc comments on
  /// [_primarySignal] for why this was left separate). Optional; omitting
  /// them behaves exactly as before - [chosenSignal] null means combined,
  /// same as every call site before this existed.
  void applyCalibration({
    required double peakThreshold,
    required double minThresholdAboveBaseline,
    bool markValid = true,
    List<double>? rotationAxis,
    List<double>? gyroBias,
    ChosenSignal? chosenSignal,
    double? minRepIntervalSeconds,
    double? prominenceMin,
    List<double>? repTemplate,
    double? templateCorrThreshold,
  }) {
    // peakThreshold's UNIT depends on chosenSignal (ExerciseProfile.theta:
    // unit follows the chosen signal) - route it to whichever field
    // actually matches those units, not always _peakThreshold (merge of
    // two independent 2026-07-21 bugfixes: chosenSignal-based routing
    // here, _wakeThreshold separation below). _wakeThreshold (idle/paused
    // wake-gate, always combined-signal scale - see its doc comment) is
    // only updated when peakThreshold itself is on that same scale, i.e.
    // chosenSignal is combined or unset; a gP-/gyroMag-scale threshold
    // there would reproduce exactly the "engine stuck in idle forever"
    // bug _wakeThreshold was split out to fix, just via a more precise
    // trigger (chosenSignal) than the original rotationAxis/gyroBias
    // proxy.
    // Hardware 2026-07-23: gP profile left combined _peakThreshold at the
    // default 1.2. If gP ever failed to be authoritative, ANY wiggle
    // counted while real curls (off-axis projection) did not. For
    // direction-aware profiles we (1) lower the applied °/s threshold for
    // form variance, (2) park combined at a sentinel, (3) enable gyroMag
    // backup for gP so slight mount tilt still counts full curls.
    const combinedSentinel = 999.0;
    const wakeCombined = 1.5;
    switch (chosenSignal) {
      case ChosenSignal.gP:
        // 0.55×theta: form/mount variance on device (2026-07-23 hardware).
        // Combined stays at a sentinel so wiggle can never fall back to the
        // ultra-sensitive default 1.2 combined threshold.
        // |g_p| is sign-agnostic (mount flip); min refractory ≥0.7s so the
        // opposite-phase hump of one curl is not double-counted.
        _gpThreshold = max(25.0, peakThreshold * 0.55);
        _gpDirection = 1;
        _gpUseAbsProjection = true;
        _gyroMagCountsReps = false;
        _peakThreshold = combinedSentinel;
        _wakeThreshold = wakeCombined;
      case ChosenSignal.gyroMag:
        _gyroMagThreshold = max(25.0, peakThreshold * 0.55);
        _gyroMagCountsReps = true;
        _gpUseAbsProjection = false;
        _peakThreshold = combinedSentinel;
        _wakeThreshold = wakeCombined;
      case ChosenSignal.combined:
        _peakThreshold = peakThreshold;
        _wakeThreshold = peakThreshold;
        _gyroMagCountsReps = false;
        _gpUseAbsProjection = false;
      case null:
        _peakThreshold = peakThreshold;
        _gyroMagCountsReps = false;
        _gpUseAbsProjection = false;
        // Only update _wakeThreshold when the threshold is on combined-
        // signal scale. If rotationAxis/gyroBias are provided without an
        // explicit chosenSignal, the threshold is gP-scale (deg/s) and
        // must NOT feed into the combined-scale wake gate.
        if (rotationAxis == null || gyroBias == null) {
          _wakeThreshold = peakThreshold;
        }
    }
    this.minThresholdAboveBaseline = minThresholdAboveBaseline;
    _primarySignal = chosenSignal;
    if (chosenSignal != null) {
      // A real, Known-Count-tuned profile - see _adaptiveThresholdEnabled
      // doc comment for why this turns S2's runtime adaptation off.
      _adaptiveThresholdEnabled = false;
    }
    if (minRepIntervalSeconds != null) {
      // Samples, not seconds - same S3 reason minRepIntervalSamples itself
      // is in samples. 1000/20 because per-SAMPLE pacing is honestly 20ms
      // since docs/01_protocol.yaml v2 (Agent 4), independent of the
      // ~11.8Hz BATCH arrival rate that number could be confused with.
      minRepIntervalSamples = (minRepIntervalSeconds * 1000 / 20).round();
    }
    // |g_p| mode needs enough refractory to collapse opposite-phase humps
    // of one curl into a single count (after optional profile override).
    if (_gpUseAbsProjection) {
      minRepIntervalSamples =
          max(minRepIntervalSamples, (0.7 * 1000 / 20).round());
    }
    if (prominenceMin != null) {
      _prominenceOverride = prominenceMin;
    }
    if (markValid) {
      hasValidCalibration = true;
    }
    // Punkt 1 (STATUS_FORTSCHRITT.md 2026-07-19/20): adopt a wizard-
    // calibrated rotation axis (ExerciseProfile.rotationAxis, PCA/Jacobi
    // eigenvalue decomposition over real known-count reps) instead of
    // leaving g_p to SignalProcessor's own cruder runtime variance
    // heuristic (a single cardinal x/y/z axis - see
    // tools/workout_engine_simulation.py
    // pruefe_pca_achse_vs_laufzeit_heuristik for how much signal that can
    // lose on a realistically tilted mounting axis). Optional and
    // additive - omitting these two parameters leaves every existing
    // caller's behaviour, and every existing test, completely unchanged.
    // Deliberately not gated on _gpThreshold here: SignalProcessor.
    // setKnownAxis only changes what the axis IS, not whether g_p is
    // authoritative yet (still calibrationReps/_gpIsAuthoritative's job).
    if (rotationAxis != null && gyroBias != null) {
      _signalProcessor.setKnownAxis(rotationAxis, gyroBias);
      // KRITISCHER SCHRITT 3: Neue Pipeline initialisieren (Feature-Flag
      // bleibt vorerst false — Aktivierung nach Validierung gegen reale Daten).
      _initNewPipeline(rotationAxis, gyroBias);
      // Template end-to-end: ExerciseProfile → ExerciseEngine
      if (repTemplate != null && repTemplate.isNotEmpty) {
        _exerciseEngine!.setTemplate(repTemplate);
      }
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
    _gpAboveThreshold = false;
    _gpRepCount = 0;
    _gyroMagAboveThreshold = false;
    _gyroMagRepCount = 0;
    // NOT resetting _gpThreshold/_gpDirection here: guided calibration
    // (this method) doesn't produce a g_p calibration at all (see
    // startGuidedCalibration doc comment above) - if one exists, it came
    // from an earlier auto-calibration in this same session and stays
    // valid; if none exists, this is a no-op either way.
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

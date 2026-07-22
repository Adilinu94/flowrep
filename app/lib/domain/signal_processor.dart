import 'dart:math';

import 'package:flowrep/domain/workout_engine.dart';

/// Pure signal processing: takes raw [SensorSample] objects, applies
/// EMA low-pass filtering and combined-signal computation, and returns
/// cleaned output. No state machine logic — that belongs in [WorkoutEngine].
///
/// Extracted per ADR-013 (Architecture Review 2026-07-12 §6.1).
class SignalProcessor {
  SignalProcessor({
    this.gyroWeight = 0.05,
    this.lowPassAlpha = 0.6,
    this.axisLearningWindowSamples = 100,
  });

  /// Weight of gyroscope magnitude in the combined signal.
  /// Higher = more gyro influence.
  final double gyroWeight;

  /// EMA low-pass filter coefficient, 0 < alpha <= 1.
  /// Higher = less smoothing, closer to raw signal.
  final double lowPassAlpha;

  double? _filteredSignal;

  /// The most recent filtered value, or 0.0 if no samples processed yet.
  double get lastFiltered => _filteredSignal ?? 0.0;

  /// Process a raw sensor sample and return the filtered combined signal.
  ///
  /// The combined signal is `accelMagnitude + gyroMagnitude * gyroWeight`,
  /// passed through a causal EMA low-pass filter.
  double process(SensorSample s) {
    final raw = s.accelMagnitude + (s.gyroMagnitude * gyroWeight);
    _filteredSignal = _filteredSignal == null
        ? raw
        : _filteredSignal! * (1 - lowPassAlpha) + raw * lowPassAlpha;
    return _filteredSignal!;
  }

  // --- Schritt B (P2, S8, docs/RECHERCHE_ZAEHLROBUSTHEIT_2026-07-16.md,
  // tools/workout_engine_simulation.py pruefe_strukturellen_gp_fix) ---
  //
  // Signed gyro projection onto a learned dominant axis, as an OPT-IN
  // addition alongside the existing combined-magnitude signal above -
  // [process]/[lastFiltered] are completely unaffected by any of this.
  // Proven in Python to fix the double-hump case (S1/S8) STRUCTURALLY,
  // with zero refractory needed, because it separates concentric/
  // eccentric by sign rather than by timing (unlike combined, which is
  // a pure magnitude and sees two same-signed humps per rep either way).
  //
  // Axis choice: by default the dominant-VARIANCE gyro axis over the first
  // [axisLearningWindowSamples] - a single cardinal axis (x, y, or z), not
  // a true 3D direction. This is deliberately the same placeholder
  // heuristic used in the Python proof (cos=0.976 to the true axis
  // there). [setKnownAxis] below lets a caller override this with a real
  // arbitrary-direction axis (e.g. ExerciseProfile.rotationAxis, learned
  // via PCA/Jacobi eigenvalue decomposition over real known-count reps in
  // the guided calibration wizard - Agent 2's CalibrationController
  // territory, not reimplemented here) - see
  // tools/workout_engine_simulation.py pruefe_pca_achse_vs_laufzeit_heuristik
  // for how much signal the cardinal-only approximation can lose on a
  // realistically tilted mounting axis (~25% in that example).

  /// Number of samples to learn the dominant axis + gyro bias from before
  /// [isSignedProjectionReady] becomes true. 100 @ 50Hz ~= 2s, matching
  /// the window used in the Python proof. Irrelevant once [setKnownAxis]
  /// has been called - there is nothing left to learn.
  final int axisLearningWindowSamples;

  final List<List<double>> _gyroLearningWindow = [];
  List<double>? _gyroBias;
  List<double>? _dominantAxis; // unit vector [x, y, z]

  /// True once a dominant axis is known, either learned via
  /// [observeForAxisLearning] or provided directly via [setKnownAxis].
  bool get isSignedProjectionReady => _dominantAxis != null;

  /// Feed a raw sample toward learning the dominant gyro axis + bias.
  /// Safe to call on every sample regardless of state; becomes a no-op
  /// once learning has completed OR [setKnownAxis] has already been
  /// called. Deliberately does NOT touch [process]/[_filteredSignal] -
  /// this is entirely separate bookkeeping.
  void observeForAxisLearning(SensorSample s) {
    if (_dominantAxis != null) return;
    _gyroLearningWindow.add([s.gx, s.gy, s.gz]);
    if (_gyroLearningWindow.length < axisLearningWindowSamples) return;

    final n = _gyroLearningWindow.length;
    final sums = [0.0, 0.0, 0.0];
    for (final v in _gyroLearningWindow) {
      sums[0] += v[0];
      sums[1] += v[1];
      sums[2] += v[2];
    }
    final means = [sums[0] / n, sums[1] / n, sums[2] / n];

    final variances = [0.0, 0.0, 0.0];
    for (final v in _gyroLearningWindow) {
      for (var axis = 0; axis < 3; axis++) {
        final d = v[axis] - means[axis];
        variances[axis] += d * d;
      }
    }
    var bestAxis = 0;
    for (var axis = 1; axis < 3; axis++) {
      if (variances[axis] > variances[bestAxis]) bestAxis = axis;
    }

    _gyroBias = means;
    _dominantAxis = List.generate(3, (i) => i == bestAxis ? 1.0 : 0.0);
    _gyroLearningWindow.clear(); // no longer needed once learned
  }

  /// Adopt an already-known rotation axis + gyro bias instead of learning
  /// one at runtime via [observeForAxisLearning] - e.g. from a wizard-
  /// calibrated ExerciseProfile. Unlike the runtime heuristic (always one
  /// of the 3 cardinal axes), [axis] can be any direction; it is expected
  /// to already be a unit vector (as ExerciseProfile.rotationAxis is) -
  /// not renormalized here. Makes [isSignedProjectionReady] true
  /// immediately, skipping the ~2s runtime learning window entirely.
  bool _axisIsKnown = false;

  /// Unlike a self-learned axis, a known one (from a real calibration
  /// profile, not live-session observation) SURVIVES [reset] - see its
  /// doc comment for why a reconnect has no reason to discard it.
  void setKnownAxis(List<double> axis, List<double> gyroBias) {
    _dominantAxis = List.of(axis);
    _gyroBias = List.of(gyroBias);
    _gyroLearningWindow.clear();
    _axisIsKnown = true;
  }

  /// Signed projection of the (bias-corrected) gyro vector onto the
  /// learned dominant axis: `(gyro - bias) . axis`. Deliberately NOT
  /// smoothed (unlike [process]'s combined signal) - matches
  /// tools/workout_engine_simulation.py's `kandidaten_signale` exactly,
  /// where this was proven against the double-hump case. Returns null
  /// until [isSignedProjectionReady].
  double? signedGyroProjection(SensorSample s) {
    final axis = _dominantAxis;
    final bias = _gyroBias;
    if (axis == null || bias == null) return null;
    return (s.gx - bias[0]) * axis[0] +
        (s.gy - bias[1]) * axis[1] +
        (s.gz - bias[2]) * axis[2];
  }

  /// Bias-corrected gyro magnitude - `ChosenSignal.gyroMag` in
  /// `ExerciseProfile`, distinct from [SensorSample.gyroMagnitude] (which
  /// is NOT bias-corrected) and from [signedGyroProjection] (which is
  /// signed and axis-projected, not a magnitude). Returns null until
  /// [isSignedProjectionReady] (same bias source as the projection above).
  double? biasCorrectedGyroMagnitude(SensorSample s) {
    final bias = _gyroBias;
    if (bias == null) return null;
    final dx = s.gx - bias[0];
    final dy = s.gy - bias[1];
    final dz = s.gz - bias[2];
    return sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// Reset internal filter state. Call on engine reconnect or new session.
  ///
  /// Deliberately does NOT clear a known axis/bias ([setKnownAxis],
  /// `_axisIsKnown`) - that came from a real calibration profile, not from
  /// watching live samples in THIS session, so a reconnect (still the
  /// same calibration, same exercise) has no reason to throw it away and
  /// force ~100 samples of placeholder relearning before g_p works again.
  /// Only the placeholder, self-learned case ([observeForAxisLearning])
  /// resets - which is exactly what a reconnect SHOULD invalidate, since
  /// it was learned from THIS session's movement. Found and fixed
  /// 2026-07-20: before this, a reconnect silently discarded a
  /// wizard-calibrated axis too, with no test catching it because no
  /// existing test called setKnownAxis() then reset() then asserted on
  /// the axis surviving.
  void reset() {
    _filteredSignal = null;
    _gyroLearningWindow.clear();
    if (!_axisIsKnown) {
      _gyroBias = null;
      _dominantAxis = null;
    }
  }
}

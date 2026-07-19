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
  // Axis choice: the dominant-VARIANCE gyro axis over the first
  // [axisLearningWindowSamples], not a PCA/calibration-derived axis -
  // that is Agent 2's CalibrationController territory
  // (AGENT_2_CALIBRATION_CONTROLLER.md), not reimplemented here. This is
  // deliberately the same placeholder heuristic used in the Python proof
  // (cos=0.976 to the true axis there), not a claim of being the final,
  // best axis-selection method.

  /// Number of samples to learn the dominant axis + gyro bias from before
  /// [isSignedProjectionReady] becomes true. 100 @ 50Hz ~= 2s, matching
  /// the window used in the Python proof.
  final int axisLearningWindowSamples;

  final List<List<double>> _gyroLearningWindow = [];
  List<double>? _gyroBias;
  int? _dominantAxisIndex; // 0=x, 1=y, 2=z

  /// True once enough samples have been observed via
  /// [observeForAxisLearning] to compute [signedGyroProjection].
  bool get isSignedProjectionReady => _dominantAxisIndex != null;

  /// Feed a raw sample toward learning the dominant gyro axis + bias.
  /// Safe to call on every sample regardless of state; becomes a no-op
  /// once learning has completed. Deliberately does NOT touch [process]/
  /// [_filteredSignal] - this is entirely separate bookkeeping.
  void observeForAxisLearning(SensorSample s) {
    if (_dominantAxisIndex != null) return;
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
    _dominantAxisIndex = bestAxis;
    _gyroLearningWindow.clear(); // no longer needed once learned
  }

  /// Signed projection of the (bias-corrected) gyro vector onto the
  /// learned dominant axis: `(gyro - bias) . axis`. Deliberately NOT
  /// smoothed (unlike [process]'s combined signal) - matches
  /// tools/workout_engine_simulation.py's `kandidaten_signale` exactly,
  /// where this was proven against the double-hump case. Returns null
  /// until [isSignedProjectionReady].
  double? signedGyroProjection(SensorSample s) {
    final axis = _dominantAxisIndex;
    final bias = _gyroBias;
    if (axis == null || bias == null) return null;
    final raw = axis == 0
        ? s.gx
        : axis == 1
            ? s.gy
            : s.gz;
    return raw - bias[axis];
  }

  /// Reset internal filter state. Call on engine reconnect or new session.
  void reset() {
    _filteredSignal = null;
    _gyroLearningWindow.clear();
    _gyroBias = null;
    _dominantAxisIndex = null;
  }
}

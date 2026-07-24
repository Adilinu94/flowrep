import '../models/workout_models.dart';

/// VBT-style helpers over gP / envelope peaks already stored on [Rep].
///
/// Values are **relative angular-velocity proxies** (°/s scale of the signal),
/// never linear m/s. See Doc 15 FR-A1.
class VelocityMetrics {
  VelocityMetrics._();

  /// Peak velocity of a single rep (= stored [Rep.peakMagnitude]).
  static double peakOf(Rep rep) => rep.peakMagnitude;

  /// Mean peak across reps in a set (null if empty).
  static double? meanPeak(List<Rep> reps) {
    if (reps.isEmpty) return null;
    var sum = 0.0;
    for (final r in reps) {
      sum += r.peakMagnitude;
    }
    return sum / reps.length;
  }

  /// Velocity loss % vs first rep: `(peak[0] - peak[i]) / peak[0] * 100`.
  /// Positive = slowing down. Null if fewer than 2 reps or first peak ≤ 0.
  static double? velocityLossPct(List<Rep> reps, {int? atIndex}) {
    if (reps.length < 2) return null;
    final first = reps.first.peakMagnitude;
    if (first <= 0 || !first.isFinite) return null;
    final idx = atIndex ?? reps.length - 1;
    if (idx < 0 || idx >= reps.length) return null;
    final peak = reps[idx].peakMagnitude;
    return (first - peak) / first * 100.0;
  }

  /// Set-level loss: first vs last rep.
  static double? setVelocityLossPct(List<Rep> reps) =>
      velocityLossPct(reps, atIndex: reps.length - 1);

  /// Adaptive rest seconds from base duration and optional velocity loss.
  /// User can always override in settings; this only suggests a start value.
  static int adaptiveRestSeconds({
    required int baseSeconds,
    double? velocityLossPct,
  }) {
    if (baseSeconds < 1) return baseSeconds;
    final loss = velocityLossPct;
    if (loss == null || !loss.isFinite) return baseSeconds;
    if (loss >= 20) {
      return (baseSeconds * 1.25).round().clamp(baseSeconds, baseSeconds * 2);
    }
    if (loss <= 5) {
      return (baseSeconds * 0.85).round().clamp(30, baseSeconds);
    }
    return baseSeconds;
  }
}

/// Shadow-only slow-rep searchback (Audit C-06).
///
/// When the product gP path rejects an excursion for being slightly under
/// peak/duration gates, a relaxed "searchback" criterion can still flag it
/// as a likely missed slow rep — for diagnostics only, never live counts.
library;

/// Pure decision helper — no side effects.
class SlowRepShadow {
  SlowRepShadow._();

  /// Product peak gate is 1.2×θ; searchback accepts down to this fraction of θ.
  static const double peakRatioOfTheta = 0.85;

  /// Product needs ≥15 samples; searchback allows slightly shorter slow curls.
  static const int minSamplesAbove = 10;

  /// Whether this failed product excursion would count as a shadow slow-rep.
  ///
  /// [productAccepted] true → never shadow (already counted or would count).
  static bool shouldFlag({
    required bool productAccepted,
    required double peak,
    required double threshold,
    required int samplesAbove,
    double peakRatio = peakRatioOfTheta,
    int minSamples = minSamplesAbove,
  }) {
    if (productAccepted) return false;
    if (!threshold.isFinite || threshold <= 0) return false;
    if (!peak.isFinite || peak <= 0) return false;
    if (samplesAbove < minSamples) return false;
    return peak >= threshold * peakRatio;
  }
}

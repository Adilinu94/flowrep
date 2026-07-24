/// Detects likely strap/axis misplacement: arm moves, but gP energy is weak
/// relative to calibrated θ (Audit C-07).
///
/// Pure Dart — UI shows re-calib hint; does not alter counts.
library;

class PlacementEnergyMonitor {
  PlacementEnergyMonitor({
    this.windowSize = 50,
    /// |accel|−1g mean above this → "moving".
    this.motionAccelDeltaMin = 0.12,
    /// Mean |gP| must stay below this fraction of θ while moving.
    this.weakGpFractionOfTheta = 0.25,
    this.windowsToWarn = 4,
    this.windowsToClear = 2,
  });

  final int windowSize;
  final double motionAccelDeltaMin;
  final double weakGpFractionOfTheta;
  final int windowsToWarn;
  final int windowsToClear;

  final List<double> _accelDelta = <double>[];
  final List<double> _gpAbs = <double>[];
  int _weakStreak = 0;
  int _okStreak = 0;
  bool _warn = false;

  bool get shouldWarn => _warn;

  String get message =>
      'Bewegung erkannt, aber wenig Signal auf der gelernten Achse. '
      'Sensorlage prüfen und ggf. neu kalibrieren.';

  void reset() {
    _accelDelta.clear();
    _gpAbs.clear();
    _weakStreak = 0;
    _okStreak = 0;
    _warn = false;
  }

  /// [theta] in °/s (gP scale). If null, monitor is idle.
  void push({
    required double accelMagnitude,
    required double? gpAbs,
    required double? theta,
  }) {
    if (theta == null || theta <= 0) return;
    if (gpAbs == null || !gpAbs.isFinite) return;
    if (!accelMagnitude.isFinite) return;

    _accelDelta.add((accelMagnitude - 1.0).abs());
    _gpAbs.add(gpAbs.abs());
    if (_accelDelta.length < windowSize) return;

    final aMean = _mean(_accelDelta);
    final gMean = _mean(_gpAbs);
    _accelDelta.clear();
    _gpAbs.clear();

    final moving = aMean >= motionAccelDeltaMin;
    final weak = gMean < theta * weakGpFractionOfTheta;

    if (moving && weak) {
      _weakStreak++;
      _okStreak = 0;
      if (_weakStreak >= windowsToWarn) {
        _warn = true;
      }
    } else {
      _okStreak++;
      _weakStreak = 0;
      if (_okStreak >= windowsToClear) {
        _warn = false;
      }
    }
  }

  static double _mean(List<double> xs) {
    var s = 0.0;
    for (final x in xs) {
      s += x;
    }
    return s / xs.length;
  }
}

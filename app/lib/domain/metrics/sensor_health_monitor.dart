/// Detects unhealthy IMU rest (e.g. stuck gyro bias ~80°/s) without
/// changing the counting algorithm (Audit C-03 / COUNT_ZERO_ANALYSIS).
///
/// Pure Dart — feed samples; query [isUnhealthy] / [message].
library;

import 'dart:math';

/// Rest-window gyro anomaly detector.
///
/// Healthy M5 rest is typically |gyro| ≪ 15°/s. Session evidence showed
/// stuck rest ~86°/s with flat accel → zero gP edges. This monitor flags
/// that class of failure for UI banners (does not block samples).
class SensorHealthMonitor {
  SensorHealthMonitor({
    this.windowSize = 50, // ~1 s @ 50 Hz
    this.restAccelSigmaMax = 0.08,
    this.restAccelMeanMin = 0.85,
    this.restAccelMeanMax = 1.20,
    /// Mean |gyro| (°/s) while “at rest” above this → unhealthy.
    this.unhealthyRestGyroMean = 40.0,
    this.windowsToFlag = 3,
    this.windowsToClear = 2,
  });

  final int windowSize;
  final double restAccelSigmaMax;
  final double restAccelMeanMin;
  final double restAccelMeanMax;
  final double unhealthyRestGyroMean;
  final int windowsToFlag;
  final int windowsToClear;

  final List<double> _gyro = <double>[];
  final List<double> _accel = <double>[];
  int _badStreak = 0;
  int _goodStreak = 0;
  bool _unhealthy = false;
  double _lastRestGyroMean = 0.0;

  bool get isUnhealthy => _unhealthy;
  double get lastRestGyroMean => _lastRestGyroMean;

  String? get message {
    if (!_unhealthy) return null;
    return 'Sensor unruhig (Gyro-Ruhe ≈ ${_lastRestGyroMean.toStringAsFixed(0)}°/s). '
        'M5 neu starten, verbinden und kurz neu kalibrieren.';
  }

  void reset() {
    _gyro.clear();
    _accel.clear();
    _badStreak = 0;
    _goodStreak = 0;
    _unhealthy = false;
    _lastRestGyroMean = 0.0;
  }

  /// Push one IMU sample (gyro magnitude °/s, accel magnitude g).
  void push({required double gyroMagnitude, required double accelMagnitude}) {
    if (!gyroMagnitude.isFinite || !accelMagnitude.isFinite) return;
    _gyro.add(gyroMagnitude.abs());
    _accel.add(accelMagnitude);
    if (_gyro.length < windowSize) return;

    final gMean = _mean(_gyro);
    final aMean = _mean(_accel);
    final aSigma = _sigma(_accel, aMean);
    _gyro.clear();
    _accel.clear();

    final atRest = aSigma <= restAccelSigmaMax &&
        aMean >= restAccelMeanMin &&
        aMean <= restAccelMeanMax;

    if (!atRest) {
      // Motion windows do not clear the flag by themselves.
      return;
    }

    _lastRestGyroMean = gMean;
    final bad = gMean >= unhealthyRestGyroMean;
    if (bad) {
      _badStreak++;
      _goodStreak = 0;
      if (_badStreak >= windowsToFlag) {
        _unhealthy = true;
      }
    } else {
      _goodStreak++;
      _badStreak = 0;
      if (_goodStreak >= windowsToClear) {
        _unhealthy = false;
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

  static double _sigma(List<double> xs, double mean) {
    var s = 0.0;
    for (final x in xs) {
      final d = x - mean;
      s += d * d;
    }
    return sqrt(s / xs.length);
  }
}

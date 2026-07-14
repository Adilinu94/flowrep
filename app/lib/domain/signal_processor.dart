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

  /// Reset internal filter state. Call on engine reconnect or new session.
  void reset() {
    _filteredSignal = null;
  }
}

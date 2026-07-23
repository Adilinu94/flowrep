/// UI-only fusion rep pulse state (CV-07 E7).
///
/// Does not affect counting — session screen reads [pulseScale] for painter.
library;

import 'fusion_engine.dart';

/// Tracks a short pulse when fusion reports a confirmed multi-source rep.
class FusionPulseController {
  final int pulseDurationMs;
  final double peakScale;

  double _pulseScale = 1.0;
  int? _pulseUntilMs;
  int _lastFusedCount = 0;
  int _lastBothTrigger = 0;

  FusionPulseController({
    this.pulseDurationMs = 350,
    this.peakScale = 1.8,
  });

  double get pulseScale => _pulseScale;

  /// Call each UI tick / pose frame with current time and fusion snapshot.
  void onFrame({
    required int nowMs,
    required FusionResult? lastDecision,
    required int fusedReps,
  }) {
    // Expire pulse
    if (_pulseUntilMs != null && nowMs >= _pulseUntilMs!) {
      _pulseScale = 1.0;
      _pulseUntilMs = null;
    }

    // New fused rep counter increase
    if (fusedReps > _lastFusedCount) {
      _lastFusedCount = fusedReps;
      _trigger(nowMs);
      return;
    }
    _lastFusedCount = fusedReps;

    // Or decision says both sources agreed and should count
    if (lastDecision != null &&
        lastDecision.shouldCount &&
        lastDecision.source == RepSource.both) {
      // debounce same decision window
      if (nowMs - _lastBothTrigger > pulseDurationMs) {
        _lastBothTrigger = nowMs;
        _trigger(nowMs);
      }
    }
  }

  void _trigger(int nowMs) {
    _pulseScale = peakScale;
    _pulseUntilMs = nowMs + pulseDurationMs;
  }

  void reset() {
    _pulseScale = 1.0;
    _pulseUntilMs = null;
    _lastFusedCount = 0;
    _lastBothTrigger = 0;
  }

  /// Test helper: force pulse without fusion.
  void debugTrigger(int nowMs) => _trigger(nowMs);
}

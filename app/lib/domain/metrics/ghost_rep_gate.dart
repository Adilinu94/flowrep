import 'dart:math';

/// Detects "device laid down / non-periodic noise" and pauses counting.
///
/// Complements existing gP amplitude/duration gates (Doc 15 FR-B6).
/// Pure Dart — feed envelope (or |gP|) samples; query [allowCounting].
///
/// Evaluation runs once per filled window (not every sample) so short
/// rests between curls do not immediately freeze counting.
class GhostRepGate {
  GhostRepGate({
    this.windowSize = 50, // ~1 s @ 50 Hz when product path ~50 Hz gP samples
    // |gP| °/s scale (product path only).
    this.idleVarianceMax = 40.0,
    this.idleMeanMax = 18.0,
    this.activeMeanMin = 35.0,
    /// Default ~45 s — short rests between curls must NOT freeze counting.
    /// Configurable via [setIdlePauseSeconds] / Settings.
    this.minIdleWindowsToPause = 45,
    this.minActiveWindowsToResume = 2,
  });

  final int windowSize;
  final double idleVarianceMax;
  final double idleMeanMax;
  final double activeMeanMin;
  /// Number of consecutive idle windows (~1 s each) before pause.
  int minIdleWindowsToPause;
  final int minActiveWindowsToResume;

  /// Configure idle duration before ghost-pause. `0` or negative = never auto-pause.
  void setIdlePauseSeconds(int seconds) {
    if (seconds <= 0) {
      minIdleWindowsToPause = 1 << 30; // effectively never
      return;
    }
    // One evaluation window ≈ 1 s at windowSize samples @ ~50 Hz product path.
    minIdleWindowsToPause = seconds.clamp(5, 600);
  }

  final List<double> _buf = <double>[];
  int _idleStreak = 0;
  int _activeStreak = 0;
  bool _paused = false;

  bool get isPaused => _paused;

  /// Reset when starting a new counting session.
  void reset() {
    _buf.clear();
    _idleStreak = 0;
    _activeStreak = 0;
    _paused = false;
  }

  /// Push one envelope / |gP| sample. Updates pause state once per window.
  void push(double magnitude) {
    if (!magnitude.isFinite) return;
    _buf.add(magnitude.abs());
    if (_buf.length < windowSize) return;

    // Evaluate on a full window, then clear for the next window.
    final mean = _mean(_buf);
    final variance = _variance(_buf, mean);
    _buf.clear();

    final idle = mean < idleMeanMax && variance < idleVarianceMax;
    final active = mean >= activeMeanMin;

    if (idle) {
      _idleStreak++;
      _activeStreak = 0;
      if (_idleStreak >= minIdleWindowsToPause) {
        _paused = true;
      }
    } else if (active) {
      _activeStreak++;
      _idleStreak = 0;
      if (_activeStreak >= minActiveWindowsToResume) {
        _paused = false;
      }
    } else {
      _idleStreak = max(0, _idleStreak - 1);
      _activeStreak = max(0, _activeStreak - 1);
    }
  }

  /// Whether a rep commit is allowed right now.
  bool get allowCounting => !_paused;

  static double _mean(List<double> xs) {
    var s = 0.0;
    for (final x in xs) {
      s += x;
    }
    return s / xs.length;
  }

  static double _variance(List<double> xs, double mean) {
    var s = 0.0;
    for (final x in xs) {
      final d = x - mean;
      s += d * d;
    }
    return s / xs.length;
  }
}

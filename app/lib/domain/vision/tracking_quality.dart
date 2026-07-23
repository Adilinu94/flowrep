/// Tracking quality states + confidence hysteresis (CV-07 E3 / E5).
///
/// Pure Dart — used by camera session HUD and tests.
library;

/// Coarse pose tracking state for badge UI (E3).
enum TrackingQuality {
  /// Arm chain confidence solid.
  tracking,

  /// Partial visibility / borderline.
  partial,

  /// No usable pose / person not in frame.
  lost,
}

/// Smooths confidence and applies enter/exit frame counts (E5).
class TrackingQualityTracker {
  final double minTracking;
  final double minPartial;
  final double emaAlpha;
  final int framesToTrack;
  final int framesToLose;

  double _smoothed = 0.0;
  bool _hasSample = false;
  TrackingQuality _state = TrackingQuality.lost;
  int _goodStreak = 0;
  int _badStreak = 0;

  TrackingQualityTracker({
    this.minTracking = 0.5,
    this.minPartial = 0.25,
    this.emaAlpha = 0.35,
    this.framesToTrack = 2,
    this.framesToLose = 3,
  });

  TrackingQuality get state => _state;
  double get smoothedConfidence => _smoothed;
  bool get hasSample => _hasSample;

  /// Feed one frame confidence; null = no pose this frame.
  TrackingQuality update(double? rawConfidence) {
    final raw = rawConfidence ?? 0.0;
    if (!_hasSample) {
      _smoothed = raw;
      _hasSample = true;
    } else {
      _smoothed = emaAlpha * raw + (1.0 - emaAlpha) * _smoothed;
    }

    final instant = _classify(_smoothed);

    if (instant == TrackingQuality.tracking) {
      _goodStreak++;
      _badStreak = 0;
    } else if (instant == TrackingQuality.lost) {
      _badStreak++;
      _goodStreak = 0;
    } else {
      // partial: slow decay of both streaks
      _goodStreak = 0;
      _badStreak = 0;
      if (_state == TrackingQuality.tracking) {
        // stay tracking until lose streak via lost
        return _state;
      }
      _state = TrackingQuality.partial;
      return _state;
    }

    if (_goodStreak >= framesToTrack) {
      _state = TrackingQuality.tracking;
    } else if (_badStreak >= framesToLose) {
      _state = TrackingQuality.lost;
    } else if (_state == TrackingQuality.lost &&
        instant == TrackingQuality.partial) {
      _state = TrackingQuality.partial;
    } else if (_state == TrackingQuality.tracking &&
        instant == TrackingQuality.partial) {
      // keep tracking until enough lost frames
    } else if (_state == TrackingQuality.lost && _goodStreak > 0) {
      _state = TrackingQuality.partial;
    }

    return _state;
  }

  void reset() {
    _smoothed = 0.0;
    _hasSample = false;
    _state = TrackingQuality.lost;
    _goodStreak = 0;
    _badStreak = 0;
  }

  TrackingQuality _classify(double c) {
    if (c >= minTracking) return TrackingQuality.tracking;
    if (c >= minPartial) return TrackingQuality.partial;
    return TrackingQuality.lost;
  }
}

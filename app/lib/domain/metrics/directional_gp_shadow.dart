import '../detection/template_matcher.dart';

/// Shadow-only directional counter for a calibrated gP profile.
///
/// The product counter currently uses |gP| for tolerance against a changed
/// mount. That can fold the concentric and eccentric parts of one movement
/// onto the same side of the threshold. This observer keeps their sign and
/// requires a primary movement followed by a return or settled rest before
/// it can arm again. It never changes the product counter.
///
/// A repeated, qualifying movement in only the opposite direction is kept as
/// a recalibration signal. A normal return after a primary movement is not
/// evidence: it is consumed by the phase machine while awaiting that return.
class DirectionalGpShadow {
  DirectionalGpShadow({
    required this.threshold,
    this.direction = 1,
    List<double>? repTemplate,
    double templateCorrThreshold = 0.65,
    this.oppositeCyclesToSuspect = 2,
  }) : _templateMatcher = TemplateMatcher(threshold: templateCorrThreshold) {
    if (repTemplate != null && repTemplate.isNotEmpty) {
      _templateMatcher.setTemplate(repTemplate);
    }
  }

  /// Same gP threshold that the product path uses, in degrees per second.
  final double threshold;

  /// Sign of the calibrated primary movement.
  final int direction;

  /// Number of unpaired opposite-direction cycles needed before a mounting
  /// mismatch becomes suspicious. This is diagnostic only in the shadow
  /// phase.
  final int oppositeCyclesToSuspect;

  static const int _minSamplesAbove = 15;
  static const double _peakOverThreshold = 1.2;
  static const double _rearmRatio = 0.3;
  static const int _minSettleSamples = 10;
  static const int _maxAwaitReturnSamples = 250;

  final TemplateMatcher _templateMatcher;
  final List<double> _cycleWindow = <double>[];

  _DirectionalGpPhase _phase = _DirectionalGpPhase.ready;
  int _samplesAbove = 0;
  double _peak = 0.0;
  int _settleSamples = 0;
  int _samplesAwaitingReturn = 0;
  bool _sawReturn = false;

  int _shadowRepCount = 0;
  int _unpairedOppositeCycles = 0;
  bool _mountMismatchSuspected = false;
  double? _lastTemplateCorrelation;

  int get shadowRepCount => _shadowRepCount;
  int get unpairedOppositeCycles => _unpairedOppositeCycles;
  bool get mountMismatchSuspected => _mountMismatchSuspected;
  double? get lastTemplateCorrelation => _lastTemplateCorrelation;

  /// Processes a signed gyro projection before the product path applies abs().
  void processSample(double gp) {
    if (!gp.isFinite || threshold <= 0 || !threshold.isFinite) return;

    final value = gp * direction;
    switch (_phase) {
      case _DirectionalGpPhase.ready:
        if (value > threshold) {
          _startPrimary(value);
        } else if (value < -threshold) {
          _startOpposite(value);
        }
        return;

      case _DirectionalGpPhase.primary:
        _cycleWindow.add(value);
        if (value > threshold) {
          _samplesAbove++;
          if (value > _peak) _peak = value;
        } else if (value < threshold * _rearmRatio) {
          _finishPrimary();
        }
        return;

      case _DirectionalGpPhase.awaitingReturn:
        _cycleWindow.add(value);
        _samplesAwaitingReturn++;
        if (value < -threshold * _rearmRatio) {
          _sawReturn = true;
          _settleSamples = 0;
        } else if (value.abs() < threshold * _rearmRatio) {
          _settleSamples++;
        } else {
          _settleSamples = 0;
        }

        final returnedToRest =
            _sawReturn && value.abs() < threshold * _rearmRatio;
        if (returnedToRest ||
            _settleSamples >= _minSettleSamples ||
            _samplesAwaitingReturn >= _maxAwaitReturnSamples) {
          _finishCycle();
        }
        return;

      case _DirectionalGpPhase.opposite:
        if (value < -threshold) {
          _samplesAbove++;
          if (value < _peak) _peak = value;
        } else if (value > -threshold * _rearmRatio) {
          _finishOpposite();
        }
        return;
    }
  }

  void _startPrimary(double value) {
    _phase = _DirectionalGpPhase.primary;
    _samplesAbove = 1;
    _peak = value;
    _cycleWindow
      ..clear()
      ..add(value);
  }

  void _finishPrimary() {
    final qualifies = _samplesAbove >= _minSamplesAbove &&
        _peak >= threshold * _peakOverThreshold;
    _samplesAbove = 0;
    _peak = 0.0;

    if (!qualifies) {
      _cycleWindow.clear();
      _phase = _DirectionalGpPhase.ready;
      return;
    }

    _shadowRepCount++;
    // A primary movement proves the calibrated direction is currently seen.
    // Its normal return must not accumulate as a mounting mismatch.
    _unpairedOppositeCycles = 0;
    _phase = _DirectionalGpPhase.awaitingReturn;
    _samplesAwaitingReturn = 0;
    _settleSamples = 0;
    _sawReturn = false;
  }

  void _finishCycle() {
    final match = _templateMatcher.match(_cycleWindow);
    _lastTemplateCorrelation = match.noTemplate ? null : match.correlation;
    _cycleWindow.clear();
    _phase = _DirectionalGpPhase.ready;
    _samplesAwaitingReturn = 0;
    _settleSamples = 0;
    _sawReturn = false;
  }

  void _startOpposite(double value) {
    _phase = _DirectionalGpPhase.opposite;
    _samplesAbove = 1;
    _peak = value;
  }

  void _finishOpposite() {
    final qualifies = _samplesAbove >= _minSamplesAbove &&
        -_peak >= threshold * _peakOverThreshold;
    _samplesAbove = 0;
    _peak = 0.0;
    _phase = _DirectionalGpPhase.ready;
    if (!qualifies) return;

    _unpairedOppositeCycles++;
    if (_unpairedOppositeCycles >= oppositeCyclesToSuspect) {
      _mountMismatchSuspected = true;
    }
  }

  void reset() {
    _phase = _DirectionalGpPhase.ready;
    _cycleWindow.clear();
    _samplesAbove = 0;
    _peak = 0.0;
    _settleSamples = 0;
    _samplesAwaitingReturn = 0;
    _sawReturn = false;
    _shadowRepCount = 0;
    _unpairedOppositeCycles = 0;
    _mountMismatchSuspected = false;
    _lastTemplateCorrelation = null;
  }
}

enum _DirectionalGpPhase { ready, primary, awaitingReturn, opposite }

/// Exponentiell geglätteter Absolutwert-Detektor (Envelope Detector).
///
/// Wandelt ein vorzeichenbehaftetes Signal (g_p) in eine nicht-negative
/// Hüllkurve um. Die Hüllkurve zeigt die "Bewegungsintensität" an:
///   envelope ≈ 0 → Ruhe
///   envelope > 0 → Bewegung (unabhängig von der Richtung)
///
/// Wird vom PeakDetector als Eingabesignal verwendet.
library;

/// Exponentiell geglättete Hüllkurve eines Signals.
///
/// Formel: env = alpha * |x| + (1 - alpha) * env_prev
/// wobei alpha = 1 - exp(-2π * cutoffHz / sampleRateHz)
class EnvelopeDetector {
  final double _alpha;
  double _envelope = 0.0;
  int _sampleCount = 0;

  /// Erstellt den Envelope-Detektor.
  ///
  /// [cutoffHz]: Cutoff-Frequenz der Glättung (Standard: 3.0 Hz).
  ///   Höher = schnellere Reaktion, mehr Rauschen.
  ///   Niedriger = stärkere Glättung, mehr Verzögerung.
  /// [sampleRateHz]: Abtastrate (Standard: 50.0 Hz).
  EnvelopeDetector({
    double cutoffHz = 3.0,
    double sampleRateHz = 50.0,
  }) : _alpha = _computeAlpha(cutoffHz, sampleRateHz);

  /// Verarbeitet EIN Sample.
  ///
  /// [value]: Eingangswert (z.B. gefiltertes g_p-Signal).
  /// Rückgabe: nicht-negative Hüllkurve (≥ 0).
  double process(double value) {
    if (value.isNaN) return _envelope;

    final absValue = value.abs();
    _envelope = _alpha * absValue + (1.0 - _alpha) * _envelope;
    _sampleCount++;
    return _envelope;
  }

  /// Setzt die Hüllkurve auf 0 zurück.
  ///
  /// Aufrufen bei: neue Session, Reconnect, Übungswechsel.
  void reset() {
    _envelope = 0.0;
    _sampleCount = 0;
  }

  /// Aktueller Hüllkurvenwert (≥ 0).
  double get value => _envelope;

  /// Anzahl verarbeiteter Samples seit letztem Reset.
  int get sampleCount => _sampleCount;

  /// true, wenn die Hüllkurve eingeschwungen ist (sampleCount > 10).
  bool get isSettled => _sampleCount > 10;

  /// Berechnet Alpha aus Cutoff und Abtastrate.
  static double _computeAlpha(double cutoffHz, double sampleRateHz) {
    final tau = 1.0 / (2.0 * 3.141592653589793 * cutoffHz);
    final te = 1.0 / sampleRateHz;
    return te / (tau + te);
  }
}

/// Kausaler Butterworth-Bandpassfilter 4. Ordnung.
///
/// Entfernt Frequenzen unterhalb 0.1 Hz (Drift, Gravitation)
/// und oberhalb 5.0 Hz (Handzittern, Stöße).
///
/// Implementierung als kaskadierte Biquad-Sektionen (Direct Form II Transposed)
/// für numerische Stabilität bei 50 Hz Abtastrate.
///
/// Koeffizienten generiert von: tools/compute_butterworth_coeffs.py
/// NICHT manuell ändern!
library;

/// Interne Biquad-Sektion (2. Ordnung, Direct Form II Transposed).
class _BiquadSection {
  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  double _z1 = 0.0;
  double _z2 = 0.0;

  _BiquadSection({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });

  /// Verarbeitet EIN Sample. Direct Form II Transposed.
  ///
  /// Formeln:
  ///   y  = b0 * x + z1
  ///   z1 = b1 * x - a1 * y + z2
  ///   z2 = b2 * x - a2 * y
  double process(double x) {
    final y = b0 * x + _z1;
    _z1 = b1 * x - a1 * y + _z2;
    _z2 = b2 * x - a2 * y;
    return y;
  }

  void reset() {
    _z1 = 0.0;
    _z2 = 0.0;
  }
}

/// Butterworth-Bandpassfilter für IMU-Signalverarbeitung.
///
/// Standardparameter: 0.1–5.0 Hz bei 50 Hz Abtastrate, 4. Ordnung.
/// Koeffizienten sind VORBERECHNET und gelten NUR für fs=50 Hz.
class ButterworthBandpass {
  // === KOEFFIZIENTEN (scipy.signal.butter, order=4, band=[0.1, 5.0], fs=50) ===
  // Sektion 1 (Lowpass-Anteil):
  static const double _b0_s1 = 4.503322126154910e-03;
  static const double _b1_s1 = 9.006644252309820e-03;
  static const double _b2_s1 = 4.503322126154910e-03;
  static const double _a1_s1 = -1.075862874825275e+00;
  static const double _a2_s1 = 3.114599233477081e-01;

  // Sektion 2 (Lowpass-Anteil):
  static const double _b0_s2 = 1.000000000000000e+00;
  static const double _b1_s2 = 2.000000000000000e+00;
  static const double _b2_s2 = 1.000000000000000e+00;
  static const double _a1_s2 = -1.333002028842331e+00;
  static const double _a2_s2 = 6.439576709734650e-01;

  // Sektion 3 (Highpass-Anteil):
  static const double _b0_s3 = 1.000000000000000e+00;
  static const double _b1_s3 = -2.000000000000000e+00;
  static const double _b2_s3 = 1.000000000000000e+00;
  static const double _a1_s3 = -1.976249408404586e+00;
  static const double _a2_s3 = 9.764163461850986e-01;

  // Sektion 4 (Highpass-Anteil):
  static const double _b0_s4 = 1.000000000000000e+00;
  static const double _b1_s4 = -2.000000000000000e+00;
  static const double _b2_s4 = 1.000000000000000e+00;
  static const double _a1_s4 = -1.990534735931486e+00;
  static const double _a2_s4 = 9.906935960361350e-01;

  final List<_BiquadSection> _sections;
  int _sampleCount = 0;

  /// Erstellt den Bandpassfilter.
  ///
  /// Koeffizienten sind fest für fs=50 Hz, fc_low=0.1 Hz, fc_high=5.0 Hz.
  ButterworthBandpass()
      : _sections = [
          _BiquadSection(b0: _b0_s1, b1: _b1_s1, b2: _b2_s1, a1: _a1_s1, a2: _a2_s1),
          _BiquadSection(b0: _b0_s2, b1: _b1_s2, b2: _b2_s2, a1: _a1_s2, a2: _a2_s2),
          _BiquadSection(b0: _b0_s3, b1: _b1_s3, b2: _b2_s3, a1: _a1_s3, a2: _a2_s3),
          _BiquadSection(b0: _b0_s4, b1: _b1_s4, b2: _b2_s4, a1: _a1_s4, a2: _a2_s4),
        ];

  /// Verarbeitet EIN Sample durch alle 4 Sektionen.
  ///
  /// NaN-Schutz: Bei NaN-Eingabe wird 0.0 zurückgegeben.
  /// Infinity-Schutz: Bei ±Infinity wird auf ±1e6 geclipped.
  double process(double input) {
    if (input.isNaN) return 0.0;
    if (input.isInfinite) {
      input = input > 0 ? 1e6 : -1e6;
    }

    var x = input;
    for (final section in _sections) {
      x = section.process(x);
    }

    _sampleCount++;
    return x;
  }

  /// Setzt alle internen Zustände zurück.
  ///
  /// Aufrufen bei: neue Session, Reconnect, Übungswechsel, nach Kalibrierung.
  void reset() {
    for (final section in _sections) {
      section.reset();
    }
    _sampleCount = 0;
  }

  /// Anzahl der seit dem letzten [reset] verarbeiteten Samples.
  int get sampleCount => _sampleCount;

  /// true, wenn der Filter eingeschwungen ist (sampleCount > 16).
  ///
  /// Vor dem Einschwingen (320ms bei 50 Hz) sind die Ausgabewerte
  /// unzuverlässig und sollten NICHT für Peak-Detection verwendet werden.
  bool get isSettled => _sampleCount > 16;
}

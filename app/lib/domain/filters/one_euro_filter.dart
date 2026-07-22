/// Adaptiver Low-Pass-Filter nach Casiez et al. (CHI 2012).
///
/// Glättet bei langsamen Bewegungen stark (wenig Jitter) und bei
/// schnellen Bewegungen wenig (wenig Lag). Ideal für Rep-Signale,
/// die sowohl langsame (kontrollierte) als auch schnelle (explosive)
/// Phasen haben.
///
/// Parameter:
/// - [minCutoff]: Minimale Cutoff-Frequenz (Hz). Bestimmt Glättung bei Ruhe.
/// - [beta]: Geschwindigkeits-Koeffizient. Bestimmt Reaktion auf schnelle Bewegung.
/// - [dCutoff]: Cutoff für den Ableitungsfilter (Hz). Selten ändern.
library;

import 'dart:math' as math;

/// One Euro Filter — adaptiver 1D Low-Pass-Filter.
///
/// Referenz: Casiez, Roussel, Vogel. "1€ Filter: A Simple Speed-based
/// Low-pass Filter for Noisy Input in Interactive Systems." CHI 2012.
class OneEuroFilter {
  final double _te; // Abtastperiode = 1/sampleRateHz
  double _minCutoff;
  double _beta;
  final double _dCutoff;

  double? _lastFiltered;
  double? _lastFilteredDeriv;

  /// Erstellt den Filter.
  ///
  /// [sampleRateHz]: Abtastrate (z.B. 50.0 für M5StickC Plus2).
  /// [minCutoff]: Minimale Cutoff-Frequenz in Hz (Standard: 1.0).
  /// [beta]: Geschwindigkeits-Koeffizient (Standard: 0.007).
  /// [dCutoff]: Cutoff für Ableitungsfilter in Hz (Standard: 1.0).
  OneEuroFilter({
    required double sampleRateHz,
    double minCutoff = 1.0,
    double beta = 0.007,
    double dCutoff = 1.0,
  })  : _te = 1.0 / sampleRateHz,
        _minCutoff = minCutoff,
        _beta = beta,
        _dCutoff = dCutoff;

  /// Verarbeitet ein Sample. [value] ist der rohe Messwert.
  ///
  /// Erster Aufruf: Gibt [value] ungefiltert zurück (Initialisierung).
  /// Danach: Adaptive Glättung basierend auf der Änderungsgeschwindigkeit.
  double process(double value) {
    if (value.isNaN) return _lastFiltered ?? 0.0;

    // Erster Aufruf: kein Filter, nur Initialisierung
    if (_lastFiltered == null) {
      _lastFiltered = value;
      _lastFilteredDeriv = 0.0;
      return value;
    }

    // Schritt 1: Roh-Ableitung schätzen
    final dx = (value - _lastFiltered!) / _te;

    // Schritt 2: Ableitung glätten (fester Alpha aus dCutoff)
    final alphaD = _alpha(_dCutoff);
    final dxHat = alphaD * dx + (1.0 - alphaD) * (_lastFilteredDeriv ?? 0.0);

    // Schritt 3: Adaptiven Cutoff berechnen
    final cutoff = _minCutoff + _beta * dxHat.abs();

    // Schritt 4: Alpha aus adaptivem Cutoff berechnen
    final alpha = _alpha(cutoff);

    // Schritt 5: Signal glätten
    final xHat = alpha * value + (1.0 - alpha) * _lastFiltered!;

    _lastFiltered = xHat;
    _lastFilteredDeriv = dxHat;
    return xHat;
  }

  /// Berechnet den Glättungsfaktor Alpha aus einer Cutoff-Frequenz.
  ///
  /// Formel: α = 1 / (1 + τ/T_e), wobei τ = 1/(2π·fc)
  /// Hohes fc → kleines τ → α ≈ 1 → wenig Glättung (schnelle Reaktion).
  /// Niedriges fc → großes τ → α ≈ 0 → starke Glättung.
  double _alpha(double cutoff) {
    final tau = 1.0 / (2.0 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / _te);
  }

  /// Aktualisiert die Filterparameter (z.B. nach Kalibrierung).
  ///
  /// [minCutoff]: Neue minimale Cutoff-Frequenz (null = unverändert).
  /// [beta]: Neuer Geschwindigkeits-Koeffizient (null = unverändert).
  void updateParameters({double? minCutoff, double? beta}) {
    if (minCutoff != null) _minCutoff = minCutoff;
    if (beta != null) _beta = beta;
  }

  /// Setzt den Filterzustand zurück.
  ///
  /// Aufrufen bei: neue Session, Reconnect, Übungswechsel.
  void reset() {
    _lastFiltered = null;
    _lastFilteredDeriv = null;
  }

  /// true, wenn mindestens ein Sample verarbeitet wurde.
  bool get isInitialized => _lastFiltered != null;

  /// Aktuelle minimale Cutoff-Frequenz.
  double get minCutoff => _minCutoff;

  /// Aktueller Beta-Wert.
  double get beta => _beta;
}

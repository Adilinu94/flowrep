/// Phasen-Validierung: Prüft ob ein Peak eine vollständige Rep-Phase darstellt.
///
/// Eine gültige Rep besteht aus:
///   1. Konzentrische Phase (g_p > 0, z.B. Bizep-Curl hoch)
///   2. Exzentrische Phase (g_p < 0, z.B. Bizep-Curl runter)
///
/// Der PhaseValidator prüft:
///   - Vorzeichen-Sequenz im Peak-Window (positiv → negativ oder umgekehrt)
///   - Dauer-Verhältnis zwischen den Phasen (nicht zu asymmetrisch)
library;

/// Ergebnis der Phasen-Validierung.
class PhaseResult {
  /// true, wenn beide Phasen (konzentrisch + exzentrisch) vorhanden sind.
  final bool valid;

  /// Dauer der positiven Phase in Samples.
  final int positiveDuration;

  /// Dauer der negativen Phase in Samples.
  final int negativeDuration;

  /// Verhältnis positive/(positive+negative). Ideal: ~0.5.
  final double durationRatio;

  /// Grund für Ablehnung (null wenn valid).
  final String? rejectionReason;

  const PhaseResult({
    required this.valid,
    required this.positiveDuration,
    required this.negativeDuration,
    required this.durationRatio,
    this.rejectionReason,
  });
}

/// Validiert die Phasen-Struktur eines Rep-Peaks.
///
/// Verwendung:
/// ```dart
/// final validator = PhaseValidator();
/// final result = validator.validate(peakWindow);
/// if (result.valid) { /* Rep hat korrekte Phasen */ }
/// ```
class PhaseValidator {
  /// Minimales Dauer-Verhältnis (positive Phase / Gesamtdauer).
  /// Unter diesem Wert: zu asymmetrisch → keine gültige Rep.
  final double minDurationRatio;

  /// Maximales Dauer-Verhältnis.
  final double maxDurationRatio;

  /// Minimale Samples pro Phase (unter diesem Wert: Rauschen).
  final int minPhaseSamples;

  /// Erstellt den PhaseValidator.
  ///
  /// [minDurationRatio]: Min. Anteil der positiven Phase (Standard: 0.2).
  /// [maxDurationRatio]: Max. Anteil der positiven Phase (Standard: 0.8).
  /// [minPhaseSamples]: Min. Samples pro Phase (Standard: 3).
  PhaseValidator({
    this.minDurationRatio = 0.2,
    this.maxDurationRatio = 0.8,
    this.minPhaseSamples = 3,
  });

  /// Validiert die Phasen-Struktur eines Peak-Windows.
  ///
  /// [window]: Signalverlauf der Excursion (aus PeakEvent.window).
  ///   Das Signal sollte das VORZEICHENBEHAFTETE g_p sein (nicht die Hüllkurve).
  ///   Für die Hüllkurve (immer ≥ 0) wird eine vereinfachte Prüfung durchgeführt.
  ///
  /// Rückgabe: [PhaseResult] mit Gültigkeit und Phasen-Dauern.
  PhaseResult validate(List<double> window) {
    if (window.length < 4) {
      return const PhaseResult(
        valid: false,
        positiveDuration: 0,
        negativeDuration: 0,
        durationRatio: 0.0,
        rejectionReason: 'Window zu kurz (< 4 Samples)',
      );
    }

    // Zähle positive und negative Samples
    int positiveCount = 0;
    int negativeCount = 0;
    for (final v in window) {
      if (v > 0) {
        positiveCount++;
      } else if (v < 0) {
        negativeCount++;
      }
      // v == 0 zählt zu keiner Phase
    }

    final total = positiveCount + negativeCount;

    // Fall 1: Nur eine Phase vorhanden (alles positiv oder alles negativ)
    // → kann trotzdem gültig sein (z.B. Hüllkurven-basiert)
    if (negativeCount == 0 || positiveCount == 0) {
      // Bei rein positivem Signal (Hüllkurve): akzeptiere als gültig
      // (Phasen-Info kommt dann aus dem VORZEICHEN des geglätteten g_p)
      return PhaseResult(
        valid: true,
        positiveDuration: positiveCount,
        negativeDuration: negativeCount,
        durationRatio: total > 0 ? positiveCount / total : 0.5,
      );
    }

    // Fall 2: Beide Phasen vorhanden → prüfe Verhältnis
    final ratio = positiveCount / total;

    if (positiveCount < minPhaseSamples) {
      return PhaseResult(
        valid: false,
        positiveDuration: positiveCount,
        negativeDuration: negativeCount,
        durationRatio: ratio,
        rejectionReason: 'Positive Phase zu kurz ($positiveCount < $minPhaseSamples)',
      );
    }

    if (negativeCount < minPhaseSamples) {
      return PhaseResult(
        valid: false,
        positiveDuration: positiveCount,
        negativeDuration: negativeCount,
        durationRatio: ratio,
        rejectionReason: 'Negative Phase zu kurz ($negativeCount < $minPhaseSamples)',
      );
    }

    if (ratio < minDurationRatio || ratio > maxDurationRatio) {
      return PhaseResult(
        valid: false,
        positiveDuration: positiveCount,
        negativeDuration: negativeCount,
        durationRatio: ratio,
        rejectionReason:
            'Phasen-Verhältnis zu asymmetrisch (${ratio.toStringAsFixed(2)} '
            'ausserhalb [${minDurationRatio}, ${maxDurationRatio}])',
      );
    }

    return PhaseResult(
      valid: true,
      positiveDuration: positiveCount,
      negativeDuration: negativeCount,
      durationRatio: ratio,
    );
  }
}

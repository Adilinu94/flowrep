/// Qualitätsbewertung einer erkannten Rep.
///
/// Bewertet eine Rep nach 4 Kriterien (gewichtete Summe):
///   1. Template-Korrelation (40%): NCC-Wert aus TemplateMatcher
///   2. ROM / Prominenz (25%): Verhältnis zur erwarteten Prominenz
///   3. Tempo (20%): Dauer im erwarteten Bereich
///   4. Symmetrie (15%): Phasen-Verhältnis nahe 0.5
///
/// Ergebnis: Score ∈ [0, 1]. Rep wird gezählt wenn Score >= minScore.
library;

/// Ergebnis der Qualitätsbewertung.
class QualityResult {
  /// Gesamt-Score ∈ [0, 1].
  final double score;

  /// true, wenn Score >= minScore (Rep wird gezählt).
  final bool accepted;

  /// Einzel-Scores für Diagnose.
  final double correlationScore;
  final double romScore;
  final double tempoScore;
  final double symmetryScore;

  const QualityResult({
    required this.score,
    required this.accepted,
    required this.correlationScore,
    required this.romScore,
    required this.tempoScore,
    required this.symmetryScore,
  });

  @override
  String toString() =>
      'QualityResult(score=${score.toStringAsFixed(3)}, accepted=$accepted, '
      'corr=${correlationScore.toStringAsFixed(2)}, rom=${romScore.toStringAsFixed(2)}, '
      'tempo=${tempoScore.toStringAsFixed(2)}, sym=${symmetryScore.toStringAsFixed(2)})';
}

/// Bewertet die Qualität einer erkannten Rep.
class QualityScorer {
  /// Gewicht für Template-Korrelation.
  final double weightCorrelation;

  /// Gewicht für ROM/Prominenz.
  final double weightRom;

  /// Gewicht für Tempo.
  final double weightTempo;

  /// Gewicht für Symmetrie.
  final double weightSymmetry;

  /// Minimale Score für Akzeptanz.
  final double minScore;

  /// Erwartete Prominenz (aus Profil/Kalibrierung).
  double _expectedProminence;

  /// Erwartete Rep-Dauer in Samples (aus Profil).
  double _expectedDurationSamples;

  /// Erstellt den QualityScorer.
  ///
  /// [expectedProminence]: Erwartete Peak-Prominenz (aus Kalibrierung).
  /// [expectedDurationSamples]: Erwartete Rep-Dauer in Samples (z.B. 50 = 1s bei 50Hz).
  /// [minScore]: Minimale Score für Akzeptanz (Standard: 0.4).
  QualityScorer({
    double expectedProminence = 50.0,
    double expectedDurationSamples = 50.0,
    this.weightCorrelation = 0.40,
    this.weightRom = 0.25,
    this.weightTempo = 0.20,
    this.weightSymmetry = 0.15,
    this.minScore = 0.4,
  })  : _expectedProminence = expectedProminence,
        _expectedDurationSamples = expectedDurationSamples;

  /// Bewertet eine Rep.
  ///
  /// [correlation]: NCC-Wert aus TemplateMatcher ∈ [-1, 1].
  /// [prominence]: Gemessene Prominenz des Peaks.
  /// [durationSamples]: Dauer der Excursion in Samples.
  /// [durationRatio]: Phasen-Verhältnis (positive/total) ∈ [0, 1].
  QualityResult score({
    required double correlation,
    required double prominence,
    required int durationSamples,
    required double durationRatio,
  }) {
    // 1. Korrelations-Score: NCC ∈ [-1,1] → [0,1]
    final corrScore = ((correlation + 1.0) / 2.0).clamp(0.0, 1.0);

    // 2. ROM-Score: Verhältnis zur erwarteten Prominenz
    //    Ideal: prominence ≈ expected → Score = 1.0
    //    Abweichung wird linear bestraft
    final romRatio = _expectedProminence > 0
        ? prominence / _expectedProminence
        : 1.0;
    final romScore = (1.0 - (romRatio - 1.0).abs()).clamp(0.0, 1.0);

    // 3. Tempo-Score: Dauer im erwarteten Bereich
    //    Ideal: duration ≈ expected → Score = 1.0
    final tempoRatio = _expectedDurationSamples > 0
        ? durationSamples / _expectedDurationSamples
        : 1.0;
    final tempoScore = (1.0 - (tempoRatio - 1.0).abs()).clamp(0.0, 1.0);

    // 4. Symmetrie-Score: durationRatio nahe 0.5 ist ideal
    final symmetryScore = (1.0 - (durationRatio - 0.5).abs() * 2.0).clamp(0.0, 1.0);

    // Gewichtete Summe
    final total = weightCorrelation * corrScore +
        weightRom * romScore +
        weightTempo * tempoScore +
        weightSymmetry * symmetryScore;

    return QualityResult(
      score: total,
      accepted: total >= minScore,
      correlationScore: corrScore,
      romScore: romScore,
      tempoScore: tempoScore,
      symmetryScore: symmetryScore,
    );
  }

  /// Aktualisiert erwartete Werte (nach Kalibrierung/Online-Adaptation).
  void updateExpectations({
    double? expectedProminence,
    double? expectedDurationSamples,
  }) {
    if (expectedProminence != null) _expectedProminence = expectedProminence;
    if (expectedDurationSamples != null) {
      _expectedDurationSamples = expectedDurationSamples;
    }
  }

  /// Aktuelle erwartete Prominenz.
  double get expectedProminence => _expectedProminence;

  /// Aktuelle erwartete Dauer in Samples.
  double get expectedDurationSamples => _expectedDurationSamples;
}

/// Eine gezählte Rep mit Qualitätsmetriken.
///
/// Wird vom RepCounter erzeugt und an die WorkoutEngine weitergereicht.
/// Enthält alle Informationen für UI-Anzeige und Statistik.
library;

/// Qualitätslevel einer Rep (für UI-Farbcodierung).
enum QualityLevel {
  /// Hervorragend (Score >= 85).
  excellent,

  /// Gut (Score >= 70).
  good,

  /// Akzeptabel (Score >= 50).
  fair,

  /// Schlecht (Score < 50).
  poor,
}

/// Ereignis: Eine Rep wurde gezählt.
class RepEvent {
  /// Laufende Rep-Nummer in der aktuellen Session.
  final int repNumber;

  /// Qualitäts-Score ∈ [0, 1].
  final double qualityScore;

  /// NCC-Korrelation mit Template (null wenn kein Template).
  final double? correlation;

  /// Prominenz des Peaks (Amplitude der Excursion).
  final double prominence;

  /// Dauer der Rep in Samples.
  final int durationSamples;

  /// Dauer der Rep in Sekunden (bei 50 Hz: durationSamples / 50).
  double get durationSeconds => durationSamples / 50.0;

  /// Zeitstempel der Rep (Millisekunden seit Epoch).
  final int timestampMs;

  /// Phasen-Verhältnis (positive/total) ∈ [0, 1].
  final double durationRatio;

  /// true, wenn die Rep gezählt wurde (vs. verworfen).
  final bool counted;

  /// Grund für Ablehnung (null wenn gezählt).
  final String? rejectionReason;

  const RepEvent({
    required this.repNumber,
    required this.qualityScore,
    this.correlation,
    required this.prominence,
    required this.durationSamples,
    required this.timestampMs,
    required this.durationRatio,
    this.counted = true,
    this.rejectionReason,
  });

  /// Qualitätslevel basierend auf Score.
  QualityLevel get qualityLevel {
    if (qualityScore >= 0.85) return QualityLevel.excellent;
    if (qualityScore >= 0.70) return QualityLevel.good;
    if (qualityScore >= 0.50) return QualityLevel.fair;
    return QualityLevel.poor;
  }

  /// Erstellt ein RepEvent für eine verworfene Rep.
  factory RepEvent.rejected({
    required int repNumber,
    required String reason,
    required int timestampMs,
  }) {
    return RepEvent(
      repNumber: repNumber,
      qualityScore: 0.0,
      prominence: 0.0,
      durationSamples: 0,
      timestampMs: timestampMs,
      durationRatio: 0.0,
      counted: false,
      rejectionReason: reason,
    );
  }

  @override
  String toString() =>
      'RepEvent(#$repNumber, score=${qualityScore.toStringAsFixed(2)}, '
      'prom=${prominence.toStringAsFixed(1)}, dur=$durationSamples, '
      'level=$qualityLevel${counted ? '' : ', REJECTED: $rejectionReason'})';
}

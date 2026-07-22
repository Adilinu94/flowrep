/// Ein verarbeitetes Frame nach Durchlauf der SignalChain.
///
/// Enthält alle Zwischenwerte, die von nachgelagerten Komponenten
/// (PeakDetector, TemplateMatcher, PhaseValidator) benötigt werden.
library;

/// Ergebnis der Signalverarbeitung für ein einzelnes IMU-Sample.
class ProcessedFrame {
  /// Zeitstempel in Millisekunden (vom BLE-Paket übernommen).
  final int timestampMs;

  /// Rohe g_p-Projektion (bias-korrigiert, vor Filterung).
  final double rawGp;

  /// g_p nach Butterworth-Bandpass (0.3–5 Hz).
  final double filteredGp;

  /// g_p nach One-Euro-Glättung (adaptiv).
  final double smoothedGp;

  /// Hüllkurve (exponentiell geglätteter Absolutwert von filteredGp).
  final double envelope;

  /// true, wenn alle Filter eingeschwungen sind.
  /// Vor dem Einschwingen sollten keine Peaks detektiert werden.
  final bool isSettled;

  const ProcessedFrame({
    required this.timestampMs,
    required this.rawGp,
    required this.filteredGp,
    required this.smoothedGp,
    required this.envelope,
    required this.isSettled,
  });

  @override
  String toString() =>
      'ProcessedFrame(t=$timestampMs, rawGp=${rawGp.toStringAsFixed(2)}, '
      'filtered=${filteredGp.toStringAsFixed(2)}, '
      'smoothed=${smoothedGp.toStringAsFixed(2)}, '
      'env=${envelope.toStringAsFixed(2)}, settled=$isSettled)';
}

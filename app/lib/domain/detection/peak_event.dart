/// Ein erkannter Peak im geglätteten g_p-Signal.
///
/// Wird vom PeakDetector erzeugt und an TemplateMatcher/PhaseValidator
/// weitergereicht.
library;

/// Ereignis: Ein Peak wurde im Signal bestätigt.
class PeakEvent {
  /// Globaler Sample-Index zum Zeitpunkt der Peak-Bestätigung.
  final int sampleIndex;

  /// Zeitstempel des Frames, das die Falling-Edge-Bestätigung auslöste.
  final int timestampMs;

  /// Maximalwert der Excursion (Peak-Amplitude im geglätteten Signal).
  final double peakValue;

  /// Minimum VOR der Excursion (für Prominenz-Berechnung).
  final double precedingValley;

  /// Prominenz = peakValue - precedingValley.
  final double prominence;

  /// Anzahl Samples in der Excursion (Rising bis Falling bestätigt).
  final int durationSamples;

  /// Roh-Signalverlauf der Excursion (für TemplateMatcher).
  final List<double> window;

  const PeakEvent({
    required this.sampleIndex,
    required this.timestampMs,
    required this.peakValue,
    required this.precedingValley,
    required this.prominence,
    required this.durationSamples,
    required this.window,
  });

  @override
  String toString() =>
      'PeakEvent(idx=$sampleIndex, t=$timestampMs, peak=${peakValue.toStringAsFixed(2)}, '
      'valley=${precedingValley.toStringAsFixed(2)}, prom=${prominence.toStringAsFixed(2)}, '
      'dur=$durationSamples)';
}

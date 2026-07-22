/// Online-Adaptation: Aktualisiert laufende Statistiken pro bestätigter Rep.
///
/// Nach jeder gezählten Rep werden die erwarteten Werte (Dauer, Prominenz,
/// Intervall) mittels EMA aktualisiert. Dies ermöglicht eine Anpassung an
/// Ermüdung oder veränderte Bewegungsausführung während des Trainings.
///
/// Die Adaptation startet erst nach [minRepsForAdaptation] Reps, um
/// Ausreißer am Anfang zu ignorieren.
library;

/// Adaptive Statistiken für die Rep-Erkennung.
///
/// Verwendung:
/// ```dart
/// final adapter = OnlineAdapter(emaAlpha: 0.1);
/// adapter.onRepConfirmed(durationSamples: 50, prominence: 100);
/// if (adapter.isAdaptive) {
///   print('Erwartete Dauer: ${adapter.adaptiveDurationSamples}');
/// }
/// ```
class OnlineAdapter {
  /// EMA-Glättungsfaktor (0.1 = langsame Anpassung).
  final double emaAlpha;

  /// Minimale Reps bevor Adaptation startet.
  final int minRepsForAdaptation;

  /// Maximale Fenstergröße für Statistik-Tracking.
  final int maxWindowSize;

  // Adaptive Werte
  double _adaptiveDurationSamples;
  double _adaptiveProminence;
  double _adaptiveIntervalMs;

  // Tracking
  int _repCount = 0;
  int? _lastRepTimestampMs;
  final List<double> _recentDurations = [];
  final List<double> _recentProminences = [];
  final List<double> _recentIntervals = [];

  /// Erstellt den OnlineAdapter.
  ///
  /// [emaAlpha]: Glättungsfaktor für EMA (Standard: 0.1).
  /// [minRepsForAdaptation]: Min. Reps vor Adaptation (Standard: 3).
  /// [maxWindowSize]: Max. Fenster für Statistik (Standard: 10).
  /// [initialDurationSamples]: Initiale erwartete Dauer (Standard: 50).
  /// [initialProminence]: Initiale erwartete Prominenz (Standard: 100).
  /// [initialIntervalMs]: Initiales erwartetes Intervall (Standard: 2000).
  OnlineAdapter({
    this.emaAlpha = 0.1,
    this.minRepsForAdaptation = 3,
    this.maxWindowSize = 10,
    double initialDurationSamples = 50.0,
    double initialProminence = 100.0,
    double initialIntervalMs = 2000.0,
  })  : _adaptiveDurationSamples = initialDurationSamples,
        _adaptiveProminence = initialProminence,
        _adaptiveIntervalMs = initialIntervalMs;

  /// Wird aufgerufen, wenn eine Rep bestätigt wurde.
  ///
  /// [durationSamples]: Dauer der Rep in Samples.
  /// [prominence]: Prominenz des Peaks.
  /// [timestampMs]: Zeitstempel der Rep (für Intervall-Berechnung).
  void onRepConfirmed({
    required int durationSamples,
    required double prominence,
    int? timestampMs,
  }) {
    _repCount++;

    // Intervall berechnen (Zeit seit letzter Rep)
    if (timestampMs != null && _lastRepTimestampMs != null) {
      final interval = (timestampMs - _lastRepTimestampMs!).toDouble();
      if (interval > 0 && interval < 30000) {
        // Max 30s Intervall (sonst Ausreißer)
        _recentIntervals.add(interval);
        if (_recentIntervals.length > maxWindowSize) {
          _recentIntervals.removeAt(0);
        }
      }
    }
    _lastRepTimestampMs = timestampMs;

    // Dauer und Prominenz tracken
    _recentDurations.add(durationSamples.toDouble());
    _recentProminences.add(prominence);

    if (_recentDurations.length > maxWindowSize) {
      _recentDurations.removeAt(0);
      _recentProminences.removeAt(0);
    }

    // Adaptation erst nach minRepsForAdaptation Reps
    if (_repCount >= minRepsForAdaptation) {
      _updateAdaptiveValues();
    }
  }

  /// Aktualisiert die adaptiven Werte mittels EMA.
  void _updateAdaptiveValues() {
    if (_recentDurations.isEmpty) return;

    // Mittelwerte berechnen
    final avgDuration =
        _recentDurations.reduce((a, b) => a + b) / _recentDurations.length;
    final avgProminence =
        _recentProminences.reduce((a, b) => a + b) / _recentProminences.length;

    // EMA-Update
    _adaptiveDurationSamples =
        emaAlpha * avgDuration + (1 - emaAlpha) * _adaptiveDurationSamples;
    _adaptiveProminence =
        emaAlpha * avgProminence + (1 - emaAlpha) * _adaptiveProminence;

    if (_recentIntervals.isNotEmpty) {
      final avgInterval =
          _recentIntervals.reduce((a, b) => a + b) / _recentIntervals.length;
      _adaptiveIntervalMs =
          emaAlpha * avgInterval + (1 - emaAlpha) * _adaptiveIntervalMs;
    }
  }

  /// Adaptive erwartete Dauer in Samples.
  double get adaptiveDurationSamples => _adaptiveDurationSamples;

  /// Adaptive erwartete Prominenz.
  double get adaptiveProminence => _adaptiveProminence;

  /// Adaptive erwartetes Intervall in Millisekunden.
  double get adaptiveIntervalMs => _adaptiveIntervalMs;

  /// true, wenn genügend Reps für Adaptation vorhanden sind.
  bool get isAdaptive => _repCount >= minRepsForAdaptation;

  /// Anzahl bestätigter Reps.
  int get repCount => _repCount;

  /// Setzt alle adaptiven Werte zurück.
  ///
  /// Aufrufen bei: neue Session, Übungswechsel.
  void reset() {
    _repCount = 0;
    _lastRepTimestampMs = null;
    _recentDurations.clear();
    _recentProminences.clear();
    _recentIntervals.clear();
    // Adaptive Werte werden NICHT zurückgesetzt (aus Profil laden)
  }

  /// Setzt adaptive Werte manuell (z.B. aus Profil).
  void setExpectations({
    double? durationSamples,
    double? prominence,
    double? intervalMs,
  }) {
    if (durationSamples != null) _adaptiveDurationSamples = durationSamples;
    if (prominence != null) _adaptiveProminence = prominence;
    if (intervalMs != null) _adaptiveIntervalMs = intervalMs;
  }
}

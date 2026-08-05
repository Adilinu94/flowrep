/// RepCounter: Orchestrator der Rep-Erkennungspipeline.
///
/// Verbindet PeakDetector → TemplateMatcher → PhaseValidator → QualityScorer
/// zu einer vollständigen Rep-Erkennung.
///
/// Datenfluss pro Frame:
///   ProcessedFrame → PeakDetector.process()
///     → PeakEvent? → TemplateMatcher.match()
///       → MatchResult → PhaseValidator.validate()
///         → PhaseResult → QualityScorer.score()
///           → QualityResult → Rep gezählt oder verworfen
///
/// Der RepCounter ist ZUSTANDSBEHAFTET — reset() bei Session-Wechsel.
library;

import '../models/processed_frame.dart';
import 'peak_detector.dart';
import 'peak_event.dart';
import 'template_matcher.dart';
import 'phase_validator.dart';
import 'quality_scorer.dart';

/// Ergebnis der Rep-Erkennung für ein einzelnes Frame.
class RepResult {
  /// true, wenn in diesem Frame eine Rep gezählt wurde.
  final bool repCounted;

  /// Laufende Rep-Nummer (nur gültig wenn repCounted = true).
  final int repNumber;

  /// Qualitäts-Score der gezählten Rep (null wenn nicht gezählt).
  final double? qualityScore;

  /// NCC-Korrelation der gezählten Rep (null wenn nicht gezählt).
  final double? correlation;

  /// Diagnose: Warum wurde die Rep verworfen? (null wenn gezählt).
  final String? rejectionReason;

  /// Fenster-Länge (Samples), auf der validiert/gewertet wurde (null wenn
  /// nicht gezählt). Kann größer sein als PeakDetectors eigene, trunkierte
  /// Fensterlänge (siehe PHASE_VALIDATOR_FIX_AUDIT_2026-08-05.md, Befund A/B) -
  /// Konsumenten sollten dieses Feld statt peakDetector.lastPeakDurationSamples
  /// verwenden.
  final int? durationSamples;

  /// Prominenz des zugrundeliegenden Peaks (null wenn nicht gezählt). Wird
  /// hier gespiegelt, damit Konsumenten nicht auf peakDetector.lastPeak*
  /// zurückgreifen müssen, das bei Kollisionen bereits den nächsten Peak
  /// zeigen kann (Befund B).
  final double? prominence;

  const RepResult({
    required this.repCounted,
    required this.repNumber,
    this.qualityScore,
    this.correlation,
    this.rejectionReason,
    this.durationSamples,
    this.prominence,
  });

  /// Konstante für "keine Rep in diesem Frame".
  static const RepResult none = RepResult(repCounted: false, repNumber: 0);
}

/// Orchestrator der vollständigen Rep-Erkennungspipeline.
///
/// Verwendung:
/// ```dart
/// final counter = RepCounter(
///   peakDetector: PeakDetector(sampleRateHz: 50.0),
///   templateMatcher: TemplateMatcher(),
///   phaseValidator: PhaseValidator(),
///   qualityScorer: QualityScorer(),
/// );
///
/// // Pro Frame:
/// final result = counter.process(frame);
/// if (result.repCounted) {
///   print('Rep ${result.repNumber} gezählt!');
/// }
/// ```
class RepCounter {
  final PeakDetector peakDetector;
  final TemplateMatcher templateMatcher;
  final PhaseValidator phaseValidator;
  final QualityScorer qualityScorer;

  int _repCount = 0;
  final List<double> _recentDurations = []; // Für Online-Adaptation
  final List<double> _recentProminences = []; // Für Online-Adaptation

  // === Ausstehende Phasen-Fenster-Erweiterung ===
  //
  // PhaseValidator braucht beide Halbwellen (konzentrisch + exzentrisch) fuer
  // ein belastbares Verhaeltnis. Das PeakDetector-Fenster endet aber kurz
  // nach der Falling-Edge-Bestaetigung (Debounce) und enthaelt fast nur die
  // positive Halbwelle. Fuer Peaks mit negativem Signalanteil wird die
  // Zaehl-Entscheidung deshalb zurueckgestellt: das Fenster wird Frame fuer
  // Frame weitergefuehrt, bis die exzentrische Halbwelle abgeschlossen ist
  // (Signal faellt unter das Fenster-Startminimum und kehrt danach auf >= 0
  // zurueck) oder ein Sicherheits-Limit erreicht ist. Reine Huellkurven-Peaks
  // (kein negativer Anteil) durchlaufen denselben Mechanismus, sind aber
  // sofort "vollstaendig" - Timing dafuer bleibt unveraendert.
  // Die Peak-ERKENNUNG selbst (PeakDetector) ist davon unberuehrt.
  PeakEvent? _pendingPeak;
  List<double>? _pendingWindow;
  double? _pendingStartMin;
  bool _pendingWentBelowStartMin = false;
  int _pendingExtraSamples = 0;
  static const int _maxExtraPhaseSamples = 120;

  /// Erstellt den RepCounter.
  ///
  /// Alle Komponenten werden injiziert (Dependency Injection für Testbarkeit).
  RepCounter({
    required this.peakDetector,
    required this.templateMatcher,
    required this.phaseValidator,
    required this.qualityScorer,
  });

  /// Verarbeitet EIN Frame durch die gesamte Pipeline.
  ///
  /// [frame]: Verarbeitetes Frame aus der SignalChain.
  /// Rückgabe: [RepResult] mit Zähl-Entscheidung.
  RepResult process(ProcessedFrame frame) {
    // Schritt 1: Peak-Detection (unveraendert - Fenster-Erweiterung aendert
    // nichts an Erkennung/Refractory/Timing des PeakDetectors selbst).
    final peak = peakDetector.process(frame);

    if (peak != null) {
      // Falls noch ein aelteres Fenster offen ist (sehr kurzer Abstand
      // zwischen zwei Peaks): mit seinem bisherigen Stand abschliessen,
      // bevor der neue Peak uebernommen wird. Damit geht keine Entscheidung
      // verloren, sie kann sich aber um einen Frame verschieben.
      RepResult? finishedOld;
      if (_pendingPeak != null) {
        finishedOld = _finalizePending();
      }
      _startPending(peak);
      if (finishedOld != null) return finishedOld;
      if (_pendingComplete()) return _finalizePending();
      return RepResult.none;
    }

    if (_pendingPeak == null) return RepResult.none;

    // Schritt 0: ausstehendes Fenster um dieses Sample weiterfuehren.
    final value = frame.smoothedGp;
    _pendingWindow!.add(value);
    _pendingExtraSamples++;
    if (value < _pendingStartMin!) _pendingWentBelowStartMin = true;

    if (_pendingComplete()) return _finalizePending();
    return RepResult.none;
  }

  /// Beginnt die Fenster-Erweiterung fuer einen frisch erkannten Peak.
  void _startPending(PeakEvent peak) {
    _pendingPeak = peak;
    _pendingWindow = List<double>.from(peak.window);
    _pendingStartMin = peak.window.reduce((a, b) => a < b ? a : b);
    _pendingWentBelowStartMin = false;
    _pendingExtraSamples = 0;
  }

  /// true, wenn das ausstehende Fenster bereit zur Validierung ist:
  /// entweder rein positiv (Huellkurve, nichts zu erweitern), oder die
  /// exzentrische Halbwelle wurde durchlaufen (unter Startminimum gefallen
  /// und wieder auf >= 0 zurueckgekehrt), oder das Sicherheits-Limit ist
  /// erreicht (verhindert endloses Warten bei Rauschen/atypischen Signalen).
  bool _pendingComplete() {
    final window = _pendingWindow!;
    final hasNegative = window.any((v) => v < 0);
    if (!hasNegative) return true;
    return (_pendingWentBelowStartMin && window.last >= 0) ||
        _pendingExtraSamples >= _maxExtraPhaseSamples;
  }

  /// Schliesst das ausstehende Fenster ab und fuehrt Template-Matching,
  /// Phasen-Validierung und Qualitaetsbewertung darauf aus.
  RepResult _finalizePending() {
    final peak = _pendingPeak!;
    final window = _pendingWindow!;
    _pendingPeak = null;
    _pendingWindow = null;
    return _decide(peak, window);
  }

  /// Schritte 2-4 der Pipeline (Template/Phase/Qualitaet) auf einem
  /// (moeglicherweise erweiterten) Fenster.
  RepResult _decide(PeakEvent peak, List<double> window) {
    // Schritt 2: Template-Matching
    final matchResult = templateMatcher.match(window);
    if (!matchResult.accepted && !matchResult.noTemplate) {
      return RepResult(
        repCounted: false,
        repNumber: _repCount,
        rejectionReason: 'Template-Match abgelehnt (NCC=${matchResult.correlation.toStringAsFixed(3)})',
      );
    }

    // Schritt 3: Phasen-Validierung
    final phaseResult = phaseValidator.validate(window);
    if (!phaseResult.valid) {
      return RepResult(
        repCounted: false,
        repNumber: _repCount,
        rejectionReason: 'Phasen-Validierung fehlgeschlagen: ${phaseResult.rejectionReason}',
      );
    }

    // Schritt 4: Qualitätsbewertung (durationSamples aus dem tatsaechlich
    // validierten Fenster, konsistent mit dem, was PhaseValidator gesehen hat)
    final qualityResult = qualityScorer.score(
      correlation: matchResult.noTemplate ? 1.0 : matchResult.correlation,
      prominence: peak.prominence,
      durationSamples: window.length,
      durationRatio: phaseResult.durationRatio,
    );

    if (!qualityResult.accepted) {
      return RepResult(
        repCounted: false,
        repNumber: _repCount,
        rejectionReason: 'Qualität zu niedrig (score=${qualityResult.score.toStringAsFixed(3)})',
      );
    }

    // === REP GEZÄHLT ===
    _repCount++;
    _trackForAdaptation(prominence: peak.prominence, durationSamples: window.length);

    return RepResult(
      repCounted: true,
      repNumber: _repCount,
      qualityScore: qualityResult.score,
      correlation: matchResult.noTemplate ? null : matchResult.correlation,
      durationSamples: window.length,
      prominence: peak.prominence,
    );
  }

  /// Trackt Dauer und Prominenz für Online-Adaptation.
  void _trackForAdaptation({required double prominence, required int durationSamples}) {
    _recentDurations.add(durationSamples.toDouble());
    _recentProminences.add(prominence);

    // Begrenze auf letzte 10 Reps
    if (_recentDurations.length > 10) {
      _recentDurations.removeAt(0);
      _recentProminences.removeAt(0);
    }

    // Online-Adaptation: aktualisiere erwartete Werte (EMA)
    if (_recentDurations.length >= 3) {
      final avgDuration =
          _recentDurations.reduce((a, b) => a + b) / _recentDurations.length;
      final avgProminence =
          _recentProminences.reduce((a, b) => a + b) / _recentProminences.length;

      qualityScorer.updateExpectations(
        expectedDurationSamples: avgDuration,
        expectedProminence: avgProminence,
      );
    }
  }

  /// Aktuelle Rep-Anzahl.
  int get repCount => _repCount;

  /// Setzt den Zähler und alle internen Zustände zurück.
  ///
  /// Aufrufen bei: neue Session, Übungswechsel.
  void reset() {
    _repCount = 0;
    _recentDurations.clear();
    _recentProminences.clear();
    _pendingPeak = null;
    _pendingWindow = null;
    _pendingStartMin = null;
    _pendingWentBelowStartMin = false;
    _pendingExtraSamples = 0;
    peakDetector.reset();
  }

  /// Setzt das Rep-Template (nach Template-Extraktion aus Kalibrierung).
  void setTemplate(List<double> template) {
    templateMatcher.setTemplate(template);
  }

  /// true, wenn ein Template gesetzt ist.
  bool get hasTemplate => templateMatcher.hasTemplate;
}

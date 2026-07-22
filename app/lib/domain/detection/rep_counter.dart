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

  const RepResult({
    required this.repCounted,
    required this.repNumber,
    this.qualityScore,
    this.correlation,
    this.rejectionReason,
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
    // Schritt 1: Peak-Detection
    final peak = peakDetector.process(frame);
    if (peak == null) return RepResult.none;

    // Schritt 2: Template-Matching
    final matchResult = templateMatcher.match(peak.window);
    if (!matchResult.accepted && !matchResult.noTemplate) {
      return RepResult(
        repCounted: false,
        repNumber: _repCount,
        rejectionReason: 'Template-Match abgelehnt (NCC=${matchResult.correlation.toStringAsFixed(3)})',
      );
    }

    // Schritt 3: Phasen-Validierung
    final phaseResult = phaseValidator.validate(peak.window);
    if (!phaseResult.valid) {
      return RepResult(
        repCounted: false,
        repNumber: _repCount,
        rejectionReason: 'Phasen-Validierung fehlgeschlagen: ${phaseResult.rejectionReason}',
      );
    }

    // Schritt 4: Qualitätsbewertung
    final qualityResult = qualityScorer.score(
      correlation: matchResult.noTemplate ? 1.0 : matchResult.correlation,
      prominence: peak.prominence,
      durationSamples: peak.durationSamples,
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
    _trackForAdaptation(peak);

    return RepResult(
      repCounted: true,
      repNumber: _repCount,
      qualityScore: qualityResult.score,
      correlation: matchResult.noTemplate ? null : matchResult.correlation,
    );
  }

  /// Trackt Dauer und Prominenz für Online-Adaptation.
  void _trackForAdaptation(PeakEvent peak) {
    _recentDurations.add(peak.durationSamples.toDouble());
    _recentProminences.add(peak.prominence);

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
    peakDetector.reset();
  }

  /// Setzt das Rep-Template (nach Template-Extraktion aus Kalibrierung).
  void setTemplate(List<double> template) {
    templateMatcher.setTemplate(template);
  }

  /// true, wenn ein Template gesetzt ist.
  bool get hasTemplate => templateMatcher.hasTemplate;
}

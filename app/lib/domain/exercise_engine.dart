/// ExerciseEngine: Neuer Orchestrator der vollständigen Rep-Erkennung.
///
/// Verbindet alle Phase-1/2/3-Komponenten zu einer kohärenten Pipeline:
///   SignalChain → RepCounter → WorkoutStateMachine → OnlineAdapter
///
/// Datenfluss pro BLE-Paket:
///   (gx, gy, gz, timestampMs)
///     → SignalChain.process() → ProcessedFrame
///       → RepCounter.process() → RepResult
///         → WorkoutStateMachine.handleEvent()
///           → OnlineAdapter.onRepConfirmed()
///             → RepEvent (Stream)
///
/// Der ExerciseEngine ist ZUSTANDSBEHAFTET — reset() bei Session-Wechsel.
///
/// Strangler-Pattern: Der alte WorkoutEngine bleibt vorerst API-stabil,
/// delegiert aber intern an ExerciseEngine (Phase 3, Schritt 2B.3).
library;

import 'dart:async';

import 'filters/signal_chain.dart';
import 'models/processed_frame.dart';
import 'detection/peak_detector.dart';
import 'detection/template_matcher.dart';
import 'detection/phase_validator.dart';
import 'detection/quality_scorer.dart';
import 'detection/rep_counter.dart';
import 'detection/rep_event.dart';
import 'detection/online_adapter.dart';
import 'state/workout_state_machine.dart';

/// Konfiguration für den ExerciseEngine.
class ExerciseEngineConfig {
  /// Abtastrate in Hz.
  final double sampleRateHz;

  /// Rotationsachse (Einheitsvektor, aus Kalibrierung).
  final List<double> rotationAxis;

  /// Gyro-Bias [bx, by, bz] in °/s.
  final List<double> gyroBias;

  /// One-Euro min. Cutoff (Hz).
  final double oneEuroMinCutoff;

  /// One-Euro Beta.
  final double oneEuroBeta;

  /// Hüllkurven-Cutoff (Hz).
  final double envelopeCutoffHz;

  /// PeakDetector Schwellen-Faktor.
  final double thresholdFactor;

  /// TemplateMatcher NCC-Schwelle.
  final double templateThreshold;

  /// QualityScorer min. Score.
  final double minQualityScore;

  /// Erwartete Prominenz (aus Profil).
  final double expectedProminence;

  /// Erwartete Rep-Dauer in Samples.
  final double expectedDurationSamples;

  /// true, wenn gültige Kalibrierung vorhanden.
  final bool hasValidCalibration;

  const ExerciseEngineConfig({
    this.sampleRateHz = 50.0,
    required this.rotationAxis,
    required this.gyroBias,
    this.oneEuroMinCutoff = 1.0,
    this.oneEuroBeta = 0.007,
    this.envelopeCutoffHz = 3.0,
    this.thresholdFactor = 0.25,
    this.templateThreshold = 0.7,
    this.minQualityScore = 0.4,
    this.expectedProminence = 50.0,
    this.expectedDurationSamples = 50.0,
    this.hasValidCalibration = false,
  });
}

/// Ergebnis der Frame-Verarbeitung (für UI/Diagnose).
class EngineFrameResult {
  /// Das verarbeitete Frame (null wenn nicht eingeschwungen).
  final ProcessedFrame? frame;

  /// Rep-Ergebnis (nur wenn Frame verarbeitet wurde).
  final RepResult repResult;

  /// Aktuellen Zustand der State Machine.
  final WorkoutState state;

  const EngineFrameResult({
    this.frame,
    required this.repResult,
    required this.state,
  });
}

/// Neuer Orchestrator der Rep-Erkennungspipeline.
///
/// Verwendung:
/// ```dart
/// final engine = ExerciseEngine(config: ExerciseEngineConfig(
///   rotationAxis: [0.1, 0.9, 0.2],
///   gyroBias: [0.5, -0.3, 0.1],
/// ));
///
/// engine.repEvents.listen((event) {
///   print('Rep ${event.repNumber}: Score=${event.qualityScore}');
/// });
///
/// // Pro BLE-Paket:
/// engine.processSample(timestampMs: 1234, gx: 10.0, gy: 20.0, gz: 5.0);
/// ```
class ExerciseEngine {
  // === KOMPONENTEN ===
  final SignalChain _signalChain;
  final RepCounter _repCounter;
  final WorkoutStateMachine _stateMachine;
  final OnlineAdapter _onlineAdapter;

  // === STREAM ===
  final StreamController<RepEvent> _repEventController =
      StreamController<RepEvent>.broadcast();

  // === KONFIGURATION ===
  final ExerciseEngineConfig config;

  // === DIAGNOSE ===
  int _framesProcessed = 0;
  int _framesRejected = 0;

  /// Erstellt den ExerciseEngine mit allen Komponenten.
  ///
  /// [config]: Konfiguration (Achse, Bias, Parameter).
  ExerciseEngine({required this.config})
      : _signalChain = SignalChain(
          rotationAxis: config.rotationAxis,
          gyroBias: config.gyroBias,
          sampleRateHz: config.sampleRateHz,
          oneEuroMinCutoff: config.oneEuroMinCutoff,
          oneEuroBeta: config.oneEuroBeta,
          envelopeCutoffHz: config.envelopeCutoffHz,
        ),
        _repCounter = RepCounter(
          peakDetector: PeakDetector(
            sampleRateHz: config.sampleRateHz,
            thresholdFactor: config.thresholdFactor,
          ),
          templateMatcher: TemplateMatcher(
            threshold: config.templateThreshold,
          ),
          phaseValidator: PhaseValidator(),
          qualityScorer: QualityScorer(
            expectedProminence: config.expectedProminence,
            expectedDurationSamples: config.expectedDurationSamples,
            minScore: config.minQualityScore,
          ),
        ),
        _stateMachine = WorkoutStateMachine(
          hasValidCalibration: config.hasValidCalibration,
        ),
        _onlineAdapter = OnlineAdapter(
          initialDurationSamples: config.expectedDurationSamples,
          initialProminence: config.expectedProminence,
        );

  /// Stream von RepEvents (gezählte und verworfene Reps).
  Stream<RepEvent> get repEvents => _repEventController.stream;

  /// Aktueller Zustand der Workout-State-Machine.
  WorkoutState get currentState => _stateMachine.currentState;

  /// Anzahl gezählter Reps.
  int get repCount => _repCounter.repCount;

  /// true, wenn die SignalChain eingeschwungen ist.
  bool get isSettled => _signalChain.isSettled;

  /// true, wenn ein Template gesetzt ist.
  bool get hasTemplate => _repCounter.hasTemplate;

  /// Anzahl verarbeiteter Frames.
  int get framesProcessed => _framesProcessed;

  /// Anzahl verworfener Frames (nicht eingeschwungen).
  int get framesRejected => _framesRejected;

  /// Verarbeitet ein rohes Gyro-Sample durch die gesamte Pipeline.
  ///
  /// [timestampMs]: Zeitstempel in Millisekunden.
  /// [gx], [gy], [gz]: Roh-Gyrowerte in °/s.
  ///
  /// Rückgabe: [EngineFrameResult] mit Diagnose-Informationen.
  EngineFrameResult processSample({
    required int timestampMs,
    required double gx,
    required double gy,
    required double gz,
  }) {
    // Schritt 1: Signalverarbeitung
    final frame = _signalChain.process(timestampMs, gx, gy, gz);

    // Vor Einschwingen: keine Peak-Detection
    if (!frame.isSettled) {
      _framesRejected++;
      return EngineFrameResult(
        frame: frame,
        repResult: RepResult.none,
        state: _stateMachine.currentState,
      );
    }

    _framesProcessed++;

    // Schritt 2: Rep-Erkennung
    final repResult = _repCounter.process(frame);

    // Schritt 3: State Machine + Online-Adaptation
    if (repResult.repCounted) {
      _onRepCounted(repResult, frame);
    }

    return EngineFrameResult(
      frame: frame,
      repResult: repResult,
      state: _stateMachine.currentState,
    );
  }

  /// Interne Verarbeitung einer gezählten Rep.
  void _onRepCounted(RepResult result, ProcessedFrame frame) {
    // State Machine: Rep gezählt
    _stateMachine.handleEvent(
      RepCounted(repNumber: result.repNumber),
    );

    // Online-Adaptation
    _onlineAdapter.onRepConfirmed(
      durationSamples: _repCounter.peakDetector.lastPeakDurationSamples,
      prominence: _repCounter.peakDetector.lastPeakProminence,
      timestampMs: frame.timestampMs,
    );

    // Adaptive Werte an QualityScorer weitergeben
    if (_onlineAdapter.isAdaptive) {
      _repCounter.qualityScorer.updateExpectations(
        expectedDurationSamples: _onlineAdapter.adaptiveDurationSamples,
        expectedProminence: _onlineAdapter.adaptiveProminence,
      );
    }

    // RepEvent erzeugen und emitten
    final repEvent = RepEvent(
      repNumber: result.repNumber,
      qualityScore: result.qualityScore ?? 0.0,
      correlation: result.correlation,
      prominence: _repCounter.peakDetector.lastPeakProminence,
      durationSamples: _repCounter.peakDetector.lastPeakDurationSamples,
      timestampMs: frame.timestampMs,
      durationRatio: 0.5, // Wird aus PhaseValidator übernommen
    );

    _repEventController.add(repEvent);
  }

  /// Signalisiert Bewegungserkennung (für State-Machine-Übergang idle → active/calibrating).
  void signalMovementDetected() {
    _stateMachine.handleEvent(
      MovementDetected(hasValidCalibration: config.hasValidCalibration),
    );
  }

  /// Signalisiert Kalibrierung abgeschlossen.
  void signalCalibrationComplete({required double threshold}) {
    _stateMachine.handleEvent(
      CalibrationComplete(threshold: threshold),
    );
  }

  /// Benutzer pausiert.
  void pause() {
    _stateMachine.handleEvent(UserPaused());
  }

  /// Benutzer setzt fort.
  void resume() {
    _stateMachine.handleEvent(UserResumed());
  }

  /// BLE-Verbindung verloren.
  void signalConnectionLost() {
    _stateMachine.handleEvent(ConnectionLostEvent());
  }

  /// BLE-Verbindung wiederhergestellt.
  void signalConnectionRestored() {
    _stateMachine.handleEvent(ConnectionRestored());
  }

  /// Setzt das Rep-Template.
  void setTemplate(List<double> template) {
    _repCounter.setTemplate(template);
  }

  /// Aktualisiert Kalibrierung (neue Achse/Bias).
  void updateCalibration({
    required List<double> rotationAxis,
    required List<double> gyroBias,
  }) {
    _signalChain.updateCalibration(
      rotationAxis: rotationAxis,
      gyroBias: gyroBias,
    );
  }

  /// Setzt den gesamten Engine-Zustand zurück.
  ///
  /// Aufrufen bei: neue Session, Übungswechsel, Reconnect.
  void reset() {
    _signalChain.reset();
    _repCounter.reset();
    _stateMachine.reset();
    _onlineAdapter.reset();
    _framesProcessed = 0;
    _framesRejected = 0;
  }

  /// Gibt alle Ressourcen frei.
  void dispose() {
    _repEventController.close();
  }

  // === DIAGNOSE-ZUGRIFF ===

  /// Zugriff auf den OnlineAdapter (für Diagnose/UI).
  OnlineAdapter get onlineAdapter => _onlineAdapter;

  /// Zugriff auf die SignalChain (für TemplateExtractor etc.).
  SignalChain get signalChain => _signalChain;

  /// Zugriff auf den RepCounter (für Diagnose).
  RepCounter get repCounter => _repCounter;

  /// Zugriff auf die State Machine.
  WorkoutStateMachine get stateMachine => _stateMachine;
}

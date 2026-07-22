/// Expliziter, deterministischer Zustandsautomat für WorkoutEngine.
///
/// Keine Signalverarbeitung — nur Zustandsübergänge basierend auf Events.
/// Trennt die Zustandslogik von der Signalverarbeitung (Single Responsibility).
///
/// Zustände:
///   idle → calibrating → active → resting/paused
///   idle → guidedCalibration → idle
///   active → connectionLost → idle
library;

/// Mögliche Zustände der Workout-Engine.
enum WorkoutState {
  /// Kein Training aktiv.
  idle,

  /// Auto-Kalibrierung (1 Rep, Legacy-Pfad).
  calibrating,

  /// Reps werden gezählt.
  active,

  /// Pause zwischen Sätzen (Timer läuft).
  resting,

  /// Manuell pausiert.
  paused,

  /// Guided Calibration 2.0 aktiv.
  guidedCalibration,

  /// BLE-Verbindung verloren.
  connectionLost,
}

/// Events, die Zustandsübergänge auslösen.
sealed class EngineEvent {}

/// Bewegung erkannt (Schwelle überschritten).
class MovementDetected extends EngineEvent {
  /// true, wenn bereits eine gültige Kalibrierung vorliegt.
  final bool hasValidCalibration;

  MovementDetected({required this.hasValidCalibration});
}

/// Kalibrierungs-Rep abgeschlossen.
class CalibrationRepComplete extends EngineEvent {
  final int repCount;

  CalibrationRepComplete({required this.repCount});
}

/// Kalibrierung vollständig abgeschlossen.
class CalibrationComplete extends EngineEvent {
  final double threshold;

  CalibrationComplete({required this.threshold});
}

/// Eine Rep wurde gezählt.
class RepCounted extends EngineEvent {
  final int repNumber;

  RepCounted({required this.repNumber});
}

/// Rest-Timer abgelaufen.
class RestTimerExpired extends EngineEvent {}

/// Pause-Timeout (keine Bewegung für X Sekunden).
class PauseTimeout extends EngineEvent {
  final Duration elapsed;

  PauseTimeout({required this.elapsed});
}

/// Benutzer hat pausiert.
class UserPaused extends EngineEvent {}

/// Benutzer hat fortgesetzt.
class UserResumed extends EngineEvent {}

/// BLE-Verbindung verloren.
class ConnectionLostEvent extends EngineEvent {}

/// BLE-Verbindung wiederhergestellt.
class ConnectionRestored extends EngineEvent {}

/// Guided Calibration gestartet.
class GuidedCalibrationStarted extends EngineEvent {}

/// Guided Calibration abgeschlossen.
class GuidedCalibrationFinished extends EngineEvent {}

/// Deterministischer Zustandsautomat für WorkoutEngine.
///
/// Verwendung:
/// ```dart
/// final sm = WorkoutStateMachine(hasValidCalibration: false);
/// final newState = sm.handleEvent(MovementDetected(hasValidCalibration: false));
/// // newState == WorkoutState.calibrating
/// ```
class WorkoutStateMachine {
  /// true, wenn eine gültige Kalibrierung vorliegt.
  final bool hasValidCalibration;

  /// Timeout für Rest-Phase (Satzpause).
  final Duration restTimeout;

  /// Timeout für Pause-Erkennung (keine Bewegung).
  final Duration pauseTimeout;

  WorkoutState _state = WorkoutState.idle;
  DateTime _lastTransitionAt = DateTime.now();
  DateTime? _lastRepAt;

  /// Erstellt den Zustandsautomaten.
  ///
  /// [hasValidCalibration]: true, wenn Profil-Kalibrierung vorhanden.
  /// [restTimeout]: Dauer der Satzpause (Standard: 30s).
  /// [pauseTimeout]: Dauer bis Pause-Erkennung (Standard: 4s).
  WorkoutStateMachine({
    required this.hasValidCalibration,
    this.restTimeout = const Duration(seconds: 30),
    this.pauseTimeout = const Duration(seconds: 4),
  });

  /// Aktueller Zustand.
  WorkoutState get currentState => _state;

  /// Zeitstempel des letzten Übergangs.
  DateTime get lastTransitionAt => _lastTransitionAt;

  /// Zeitstempel der letzten Rep (für Pause-Timeout).
  DateTime? get lastRepAt => _lastRepAt;

  /// Verarbeitet ein Event und gibt den neuen Zustand zurück.
  ///
  /// Wirft [StateError] bei ungültigem Übergang.
  WorkoutState handleEvent(EngineEvent event) {
    final newState = _transition(event);
    if (newState != _state) {
      _state = newState;
      _lastTransitionAt = DateTime.now();
    }
    return _state;
  }

  /// Interne Übergangslogik.
  WorkoutState _transition(EngineEvent event) {
    switch (_state) {
      case WorkoutState.idle:
        return _handleIdle(event);
      case WorkoutState.calibrating:
        return _handleCalibrating(event);
      case WorkoutState.active:
        return _handleActive(event);
      case WorkoutState.resting:
        return _handleResting(event);
      case WorkoutState.paused:
        return _handlePaused(event);
      case WorkoutState.guidedCalibration:
        return _handleGuidedCalibration(event);
      case WorkoutState.connectionLost:
        return _handleConnectionLost(event);
    }
  }

  WorkoutState _handleIdle(EngineEvent event) {
    switch (event) {
      case MovementDetected(:final hasValidCalibration):
        // Mit gültiger Kalibrierung: direkt zu active
        // Ohne: erst kalibrieren
        return hasValidCalibration ? WorkoutState.active : WorkoutState.calibrating;
      case GuidedCalibrationStarted():
        return WorkoutState.guidedCalibration;
      case ConnectionLostEvent():
        return WorkoutState.connectionLost;
      default:
        return WorkoutState.idle;
    }
  }

  WorkoutState _handleCalibrating(EngineEvent event) {
    switch (event) {
      case CalibrationRepComplete():
        return WorkoutState.active;
      case CalibrationComplete():
        return WorkoutState.active;
      case ConnectionLostEvent():
        return WorkoutState.connectionLost;
      default:
        return WorkoutState.calibrating;
    }
  }

  WorkoutState _handleActive(EngineEvent event) {
    switch (event) {
      case RepCounted():
        _lastRepAt = DateTime.now();
        return WorkoutState.active;
      case PauseTimeout():
        return WorkoutState.resting;
      case UserPaused():
        return WorkoutState.paused;
      case ConnectionLostEvent():
        return WorkoutState.connectionLost;
      default:
        return WorkoutState.active;
    }
  }

  WorkoutState _handleResting(EngineEvent event) {
    switch (event) {
      case MovementDetected():
        return WorkoutState.active;
      case RestTimerExpired():
        return WorkoutState.idle;
      case ConnectionLostEvent():
        return WorkoutState.connectionLost;
      default:
        return WorkoutState.resting;
    }
  }

  WorkoutState _handlePaused(EngineEvent event) {
    switch (event) {
      case UserResumed():
        return WorkoutState.active;
      case MovementDetected():
        return WorkoutState.active;
      case ConnectionLostEvent():
        return WorkoutState.connectionLost;
      default:
        return WorkoutState.paused;
    }
  }

  WorkoutState _handleGuidedCalibration(EngineEvent event) {
    switch (event) {
      case GuidedCalibrationFinished():
        return WorkoutState.idle;
      case ConnectionLostEvent():
        return WorkoutState.connectionLost;
      default:
        return WorkoutState.guidedCalibration;
    }
  }

  WorkoutState _handleConnectionLost(EngineEvent event) {
    switch (event) {
      case ConnectionRestored():
        return WorkoutState.idle;
      default:
        return WorkoutState.connectionLost;
    }
  }

  /// Setzt auf idle zurück (bei Reconnect oder Session-Ende).
  void reset() {
    _state = WorkoutState.idle;
    _lastTransitionAt = DateTime.now();
    _lastRepAt = null;
  }

  /// Prüft, ob Pause-Timeout erreicht ist.
  ///
  /// [now]: Aktueller Zeitpunkt (für Testbarkeit injizierbar).
  bool isPauseTimeoutReached({DateTime? now}) {
    if (_state != WorkoutState.active) return false;
    if (_lastRepAt == null) return false;

    final elapsed = (now ?? DateTime.now()).difference(_lastRepAt!);
    return elapsed >= pauseTimeout;
  }
}

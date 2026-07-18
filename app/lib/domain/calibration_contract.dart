/// Vertrag zwischen dem Kalibrierungs-Algorithmus (CalibrationController,
/// Konzept 2.0 Paket 2/3) und der UI (CalibrationWizardScreen, Paket 4-9).
/// Diese Datei definiert nur die Schnittstelle, keine Implementierung -
/// die echte Implementierung (Known-Count-Optimierung, portiert aus
/// tools/workout_engine_simulation.py) gehoert in calibration_controller.dart.
library;

import 'dart:async';

import 'models/exercise_profile.dart';
import 'workout_engine.dart' show SensorSample;

/// Fortschrittsstufen der gefuehrten Kalibrierung 2.0.
enum CalibrationStage {
  /// Stufe 0: Ruhephase, Baseline/Rauschboden/Gyro-Bias.
  restBaseline,

  /// Stufe A: 1 Wiederholung, PCA-Rotationsachse.
  singleRepAxis,

  /// Stufe B: bekannte Anzahl Wiederholungen (Known-Count-Sweep).
  knownCountFit,

  /// Stufe C: 3 langsame Wiederholungen, Tempo-Robustheit.
  tempoCheck,

  /// Stufe D: Ergebnis anzeigen, Nutzer bestaetigt oder startet neu.
  review,

  /// Kalibrierung fehlgeschlagen (z.B. zu wenig Bewegung erkannt).
  failed,
}

/// Separater Domain-Service fuer die gefuehrte Kalibrierung. Haelt NIEMALS
/// WorkoutState selbst - WorkoutEngine bleibt alleiniger Owner davon und
/// wendet das Ergebnis erst an, wenn isComplete true ist.
abstract class CalibrationController {
  CalibrationStage get stage;
  Stream<CalibrationStage> get stageStream;

  /// Fortschritt innerhalb der AKTUELLEN Stufe, 0.0-1.0.
  double get progress;

  /// Wie viele Wiederholungen in der aktuellen Stufe bereits gezaehlt
  /// wurden (relevant fuer Stufe A/B/C). 0 in Stufe 0/D.
  int get repsCountedInCurrentStage;

  /// Ziel-Wiederholungszahl der aktuellen Stufe (1 in Stufe A, 5 in
  /// Stufe B, 3 in Stufe C). 0 in Stufe 0/D.
  int get targetRepsForCurrentStage;

  /// Wird fuer JEDES eingehende IMU-Sample aufgerufen, solange die
  /// Kalibrierung laeuft. Darf NICHT blockieren.
  void onSample(SensorSample sample);

  bool get isComplete;

  /// Ergebnis, sobald isComplete true ist UND die Kalibrierung
  /// erfolgreich war. Null, wenn noch nicht fertig ODER fehlgeschlagen.
  ExerciseProfile? get result;

  /// Nicht-null nur, wenn isComplete true ist UND result null ist.
  String? get failureReason;

  void cancel();
  void reset();

  /// Gibt interne Subscriptions/StreamController frei. Muss vom Aufrufer
  /// (CalibrationWizardScreen.dispose()) aufgerufen werden.
  void dispose();
}

/// TEMPORAER: Platzhalter-Implementierung von CalibrationController, bis
/// die echte Known-Count-Implementierung (Konzept 2.0 Paket 2, portiert aus
/// tools/workout_engine_simulation.py) verfuegbar ist. Erlaubt es, den
/// kompletten Wizard-Flow (Stufe 0-D) bereits jetzt end-to-end zu bauen und
/// zu zeigen, OHNE den echten Algorithmus vorwegzunehmen.
///
/// WICHTIG: Das erzeugte ExerciseProfile ist NICHT aus echten Sensordaten
/// berechnet, sondern eine plausible Fuellung, damit die UI etwas zum
/// Anzeigen hat. qualityScore ist bewusst 0.0, damit needsRecalibration
/// (siehe ExerciseProfile) automatisch true liefert und der Nutzer nicht
/// denkt, das sei bereits eine echte Kalibrierung.
///
/// Sobald calibration_controller.dart mit der echten Implementierung
/// existiert: nur an der EINEN Stelle ersetzen, wo dieser Platzhalter
/// aktuell instanziiert wird (home_screen.dart, Kalibrierungs-Button).
library;

import 'dart:async';

import 'calibration_contract.dart';
import 'models/exercise_profile.dart';
import 'workout_engine.dart' show SensorSample;

class PlaceholderCalibrationController implements CalibrationController {
  PlaceholderCalibrationController({required this.exerciseId});

  final String exerciseId;

  static const Map<CalibrationStage, int> _samplesPerStage = {
    CalibrationStage.restBaseline: 100,
    CalibrationStage.singleRepAxis: 75,
    CalibrationStage.knownCountFit: 375,
    CalibrationStage.tempoCheck: 300,
  };

  static const List<CalibrationStage> _stageOrder = [
    CalibrationStage.restBaseline,
    CalibrationStage.singleRepAxis,
    CalibrationStage.knownCountFit,
    CalibrationStage.tempoCheck,
    CalibrationStage.review,
  ];

  static const Map<CalibrationStage, int> _targetReps = {
    CalibrationStage.restBaseline: 0,
    CalibrationStage.singleRepAxis: 1,
    CalibrationStage.knownCountFit: 5,
    CalibrationStage.tempoCheck: 3,
    CalibrationStage.review: 0,
  };

  int _stageIndex = 0;
  int _samplesInStage = 0;
  bool _cancelled = false;
  final _stageController = StreamController<CalibrationStage>.broadcast();

  @override
  CalibrationStage get stage => _stageOrder[_stageIndex];

  @override
  Stream<CalibrationStage> get stageStream => _stageController.stream;

  @override
  double get progress {
    final target = _samplesPerStage[stage];
    if (target == null || target == 0) return 0.0;
    return (_samplesInStage / target).clamp(0.0, 1.0);
  }

  @override
  int get repsCountedInCurrentStage =>
      (progress * targetRepsForCurrentStage).floor();

  @override
  int get targetRepsForCurrentStage => _targetReps[stage] ?? 0;

  @override
  void onSample(SensorSample sample) {
    if (_cancelled || isComplete) return;
    if (stage == CalibrationStage.review) return;
    _samplesInStage++;
    final target = _samplesPerStage[stage] ?? 1;
    if (_samplesInStage >= target) {
      _samplesInStage = 0;
      if (_stageIndex < _stageOrder.length - 1) {
        _stageIndex++;
        _stageController.add(stage);
      }
    }
  }

  @override
  bool get isComplete => stage == CalibrationStage.review && !_cancelled;

  @override
  ExerciseProfile? get result {
    if (!isComplete) return null;
    return ExerciseProfile(
      exerciseId: exerciseId,
      rotationAxis: const [0.0, 1.0, 0.0],
      chosenSignal: ChosenSignal.combined,
      theta: 1.2,
      minRepIntervalSeconds: 0.8,
      medianTSeconds: 1.6,
      madTSeconds: 0.2,
      gyroBias: const [0.0, 0.0, 0.0],
      qualityScore: 0.0,
      calibratedAt: DateTime.now(),
      migratedFrom: 0,
    );
  }

  @override
  String? get failureReason => null;

  @override
  void cancel() => _cancelled = true;

  @override
  void reset() {
    _stageIndex = 0;
    _samplesInStage = 0;
    _cancelled = false;
  }

  @override
  void dispose() {
    _stageController.close();
  }
}

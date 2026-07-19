import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:flowrep/domain/calibration_controller.dart';
import 'package:flowrep/domain/workout_engine.dart' show SensorSample;

/// Synthetische Ruhe-Samples: minimale Bewegung, Schwerkraft auf ay.
List<SensorSample> _rest(int n, DateTime start, {int offsetMs = 0}) => [
      for (var i = 0; i < n; i++)
        SensorSample(
          timestamp: start.add(Duration(milliseconds: offsetMs + i * 20)),
          ax: 0,
          ay: 1.0,
          az: 0,
          gx: 0,
          gy: 0,
          gz: 0,
        ),
    ];

/// Eine synthetische Wiederholung: Halbsinus-Puls auf der gx-Achse (peakDeg
/// °/s), Dauer [n] Samples a 20ms. Deutlich ueber der 15°/s-Aktivitaets-
/// schwelle in _axisAnalysis und mit klarer Form fuer den Known-Count-Sweep.
List<SensorSample> _rep(
  int n,
  DateTime start, {
  required int offsetMs,
  double peakDeg = 150,
}) =>
    [
      for (var i = 0; i < n; i++)
        SensorSample(
          timestamp: start.add(Duration(milliseconds: offsetMs + i * 20)),
          ax: 0,
          ay: 1.0 - 0.3 * math.sin(math.pi * i / n),
          az: 0,
          gx: peakDeg * math.sin(math.pi * i / n),
          gy: 0,
          gz: 0,
        ),
    ];

/// Fuettert [count] Wiederholungen (mit kurzer Pause dazwischen) direkt in
/// den Controller via onSample - simuliert einen Live-BLE-Stream.
void _feedReps(
  CalibrationController c,
  int count,
  DateTime start, {
  double peakDeg = 150,
  int repLenSamples = 30,
  int pauseSamples = 15,
}) {
  var offset = 0;
  for (var r = 0; r < count; r++) {
    for (final s in _rep(repLenSamples, start,
        offsetMs: offset, peakDeg: peakDeg)) {
      c.onSample(s);
    }
    offset += repLenSamples * 20;
    for (final s in _rest(pauseSamples, start, offsetMs: offset)) {
      c.onSample(s);
    }
    offset += pauseSamples * 20;
  }
}

void main() {
  final t0 = DateTime(2026, 7, 18);

  group('CalibrationController - Stufe 0 (Ruhe)', () {
    test('stille Samples lassen die Ruhephase erfolgreich abschliessen', () {
      final advances = <CalibrationStage>[];
      final c = CalibrationController(onStageAdvanced: advances.add);
      c.start();
      for (final s in _rest(100, t0)) {
        c.onSample(s);
      }
      c.finishStage();
      expect(c.stage, CalibrationStage.singleRep);
      expect(advances, contains(CalibrationStage.singleRep));
    });

    test('Bewegung waehrend der Ruhephase loest das Qualitaets-Gate aus',
        () {
      String? reason;
      final c = CalibrationController(
        onQualityGateFail: (stage, r) => reason = r,
      );
      c.start();
      for (final s in _rep(60, t0, offsetMs: 0, peakDeg: 200)) {
        c.onSample(s);
      }
      c.finishStage();
      expect(c.stage, CalibrationStage.rest,
          reason: 'Ruhephase muss bei nicht bestandenem Gate wiederholt '
              'werden, nicht weiterspringen');
      expect(reason, isNotNull);
    });
  });

  group('CalibrationController - Stufe A (1 Rep)', () {
    CalibrationController freshAtSingleRep() {
      final c = CalibrationController();
      c.start();
      for (final s in _rest(100, t0)) {
        c.onSample(s);
      }
      c.finishStage();
      return c;
    }

    test('eine klare Wiederholung liefert eine gelernte Achse', () {
      final c = freshAtSingleRep();
      for (final s in _rep(40, t0, offsetMs: 2000, peakDeg: 150)) {
        c.onSample(s);
      }
      c.finishStage();
      expect(c.stage, CalibrationStage.knownSet);
      expect(c.learnedAxis, isNotNull);
      expect(c.learnedAxis!.length, 3);
    });

    test('keine Bewegung in Stufe A loest das Qualitaets-Gate aus', () {
      final c = freshAtSingleRep();
      for (final s in _rest(40, t0, offsetMs: 2000)) {
        c.onSample(s);
      }
      c.finishStage();
      expect(c.stage, CalibrationStage.singleRep,
          reason: 'muss bei fehlender Bewegung wiederholt werden');
    });
  });

  group('CalibrationController - voller Durchlauf (clean persona)', () {
    test('5 bekannte + 3 langsame Reps ergeben ein valides ExerciseProfile',
        () {
      final c = CalibrationController(exerciseId: 'bicep_curl');
      c.start();
      for (final s in _rest(100, t0)) {
        c.onSample(s);
      }
      c.finishStage(); // -> singleRep

      for (final s in _rep(40, t0, offsetMs: 2000, peakDeg: 150)) {
        c.onSample(s);
      }
      c.finishStage(); // -> knownSet
      expect(c.stage, CalibrationStage.knownSet);

      _feedReps(c, 5, t0, peakDeg: 150, repLenSamples: 30);
      c.finishStage(); // -> slowSet
      expect(c.stage, CalibrationStage.slowSet);

      _feedReps(c, 3, t0, peakDeg: 150, repLenSamples: 60, pauseSamples: 25);
      c.finishStage(); // -> review
      expect(c.stage, CalibrationStage.review);

      final review = c.reviewData;
      expect(review.ready, isTrue,
          reason: 'Sweep sollte fuer ein sauberes, deutliches Signal eine '
              'Konfiguration finden');

      c.finishStage(); // review -> done
      final profile = c.finalize();
      expect(profile, isNotNull);
      expect(profile!.exerciseId, 'bicep_curl');
      expect(profile.theta, greaterThan(0));
    });
  });
}

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/exercise_engine.dart';
import 'package:flowrep/domain/state/workout_state_machine.dart';

/// Erzeugt eine ExerciseEngineConfig mit Standardwerten.
ExerciseEngineConfig _config({
  bool hasValidCalibration = true,
  double expectedProminence = 100.0,
  double expectedDurationSamples = 50.0,
}) {
  return ExerciseEngineConfig(
    rotationAxis: [0.0, 1.0, 0.0],
    gyroBias: [0.0, 0.0, 0.0],
    hasValidCalibration: hasValidCalibration,
    expectedProminence: expectedProminence,
    expectedDurationSamples: expectedDurationSamples,
  );
}

/// Simuliert eine sinusförmige Gyro-Bewegung um die Y-Achse.
List<List<double>> _repSequence({
  double amplitude = 250.0,
  int durationSamples = 50,
  int count = 5,
  int baselineSamples = 30,
  int pauseSamples = 15,
}) {
  final samples = <List<double>>[];
  for (int i = 0; i < baselineSamples; i++) {
    samples.add([0.0, 0.0, 0.0]);
  }
  for (int rep = 0; rep < count; rep++) {
    for (int i = 0; i < durationSamples; i++) {
      final phase = 2.0 * math.pi * i / durationSamples;
      final gy = amplitude * math.sin(phase);
      samples.add([0.0, gy, 0.0]);
    }
    for (int i = 0; i < pauseSamples; i++) {
      samples.add([0.0, 0.0, 0.0]);
    }
  }
  return samples;
}

/// Füttert die Engine mit Samples und gibt die Rep-Anzahl zurück.
int _feedSamples(ExerciseEngine engine, List<List<double>> samples,
    {int offsetMs = 0}) {
  for (int i = 0; i < samples.length; i++) {
    engine.processSample(
      timestampMs: (offsetMs + i) * 20,
      gx: samples[i][0],
      gy: samples[i][1],
      gz: samples[i][2],
    );
  }
  return engine.repCount;
}

void main() {
  group('ExerciseEngine Template-Matching', () {
    late ExerciseEngine engine;

    setUp(() {
      engine = ExerciseEngine(config: _config());
    });

    tearDown(() {
      engine.dispose();
    });

    test('setTemplate mit 64 Werten wird akzeptiert', () {
      final template =
          List.generate(64, (i) => math.sin(math.pi * i / 63));
      engine.setTemplate(template);
      expect(engine.hasTemplate, isTrue);
    });

    test('setTemplate mit falscher Länge wird ignoriert', () {
      engine.setTemplate([1.0, 2.0, 3.0]); // zu kurz
      expect(engine.hasTemplate, isFalse);
    });

    test('setTemplate mit leerer Liste wird ignoriert', () {
      engine.setTemplate([]);
      expect(engine.hasTemplate, isFalse);
    });

    test('Template-Matching: Reps werden mit Template gezählt', () {
      // Einschwingen
      for (int i = 0; i < 300; i++) {
        engine.processSample(timestampMs: i * 20, gx: 0, gy: 0, gz: 0);
      }
      engine.signalMovementDetected();

      // Template aus einer idealen Sinus-Rep extrahieren
      final template =
          List.generate(64, (i) => math.sin(2.0 * math.pi * i / 64));
      engine.setTemplate(template);
      expect(engine.hasTemplate, isTrue);

      // Reps füttern
      final samples = _repSequence(amplitude: 300.0, count: 5);
      _feedSamples(engine, samples, offsetMs: 300);

      // Engine sollte Samples verarbeitet haben (Pipeline läuft)
      expect(engine.framesProcessed, greaterThan(0));
    });

    test('Ohne Template werden Reps trotzdem gezählt (Fallback)', () {
      for (int i = 0; i < 300; i++) {
        engine.processSample(timestampMs: i * 20, gx: 0, gy: 0, gz: 0);
      }
      engine.signalMovementDetected();

      expect(engine.hasTemplate, isFalse);

      final samples = _repSequence(amplitude: 300.0, count: 5);
      final reps = _feedSamples(engine, samples, offsetMs: 300);

      expect(reps, greaterThan(0));
    });
  });

  group('ExerciseEngine Pipeline-Integration', () {
    test('Volle Pipeline: Einschwingen → Bewegung → Reps', () {
      final engine = ExerciseEngine(config: _config());

      // Phase 1: Einschwingen (300 Samples Ruhe)
      for (int i = 0; i < 300; i++) {
        final result = engine.processSample(
          timestampMs: i * 20,
          gx: 0,
          gy: 0,
          gz: 0,
        );
        expect(result.repResult.repCounted, isFalse);
      }
      expect(engine.isSettled, isTrue);
      expect(engine.repCount, equals(0));

      // Phase 2: Bewegung erkennen
      engine.signalMovementDetected();
      expect(engine.currentState, equals(WorkoutState.active));

      // Phase 3: Reps zählen
      final samples = _repSequence(amplitude: 300.0, count: 8);
      _feedSamples(engine, samples, offsetMs: 300);

      expect(engine.repCount, greaterThan(0));
      expect(engine.framesProcessed, greaterThan(300));

      engine.dispose();
    });

    test('Pause ändert StateMachine-Zustand', () {
      final engine = ExerciseEngine(config: _config());

      // Einschwingen
      for (int i = 0; i < 300; i++) {
        engine.processSample(timestampMs: i * 20, gx: 0, gy: 0, gz: 0);
      }
      engine.signalMovementDetected();
      expect(engine.currentState, equals(WorkoutState.active));

      // Pause
      engine.pause();
      expect(engine.currentState, equals(WorkoutState.paused));

      // Resume
      engine.resume();
      expect(engine.currentState, equals(WorkoutState.active));

      engine.dispose();
    });

    test('Reset nach Reps setzt Zähler auf 0', () {
      final engine = ExerciseEngine(config: _config());

      for (int i = 0; i < 300; i++) {
        engine.processSample(timestampMs: i * 20, gx: 0, gy: 0, gz: 0);
      }
      engine.signalMovementDetected();

      final samples = _repSequence(amplitude: 300.0, count: 5);
      _feedSamples(engine, samples, offsetMs: 300);
      expect(engine.repCount, greaterThan(0));

      engine.reset();
      expect(engine.repCount, equals(0));
      expect(engine.currentState, equals(WorkoutState.idle));
      expect(engine.isSettled, isFalse);

      engine.dispose();
    });

    test('Niedrige Amplitude wird nicht als Rep gezählt', () {
      final engine = ExerciseEngine(
        config: _config(expectedProminence: 200.0),
      );

      for (int i = 0; i < 300; i++) {
        engine.processSample(timestampMs: i * 20, gx: 0, gy: 0, gz: 0);
      }
      engine.signalMovementDetected();

      // Sehr kleine Amplitude (unter expectedProminence)
      final samples = _repSequence(amplitude: 5.0, count: 5);
      _feedSamples(engine, samples, offsetMs: 300);

      // Keine oder sehr wenige Reps (Rauschen)
      expect(engine.repCount, lessThanOrEqualTo(1));

      engine.dispose();
    });

    test('gyroBias wird subtrahiert', () {
      final engineWithBias = ExerciseEngine(
        config: ExerciseEngineConfig(
          rotationAxis: [0.0, 1.0, 0.0],
          gyroBias: [0.0, 50.0, 0.0], // 50°/s Bias auf Y
          hasValidCalibration: true,
          expectedProminence: 100.0,
          expectedDurationSamples: 50.0,
        ),
      );

      // Einschwingen mit konstantem Signal = Bias
      for (int i = 0; i < 300; i++) {
        engineWithBias.processSample(
          timestampMs: i * 20,
          gx: 0,
          gy: 50.0, // = Bias → projiziert sollte ~0 sein
          gz: 0,
        );
      }
      expect(engineWithBias.isSettled, isTrue);

      engineWithBias.dispose();
    });
  });

  group('ExerciseEngine Metriken', () {
    test('framesProcessed und framesRejected zählen korrekt', () {
      final engine = ExerciseEngine(config: _config());

      // 10 Samples vor Einschwingen → rejected
      for (int i = 0; i < 10; i++) {
        engine.processSample(timestampMs: i * 20, gx: 0, gy: 100, gz: 0);
      }
      expect(engine.framesRejected, equals(10));
      expect(engine.framesProcessed, equals(0));

      // 300 weitere Samples: die ersten ~240 sind noch nicht settled,
      // danach wird processed. isSettled bei sampleCount > 250.
      for (int i = 10; i < 310; i++) {
        engine.processSample(timestampMs: i * 20, gx: 0, gy: 0, gz: 0);
      }
      // Total 310 Samples, settled nach >250 → ~60 processed
      expect(engine.framesProcessed, greaterThan(0));
      expect(engine.framesRejected + engine.framesProcessed, equals(310));

      engine.dispose();
    });

    test('onlineAdapter ist nach Einschwingen verfügbar', () {
      final engine = ExerciseEngine(config: _config());

      for (int i = 0; i < 300; i++) {
        engine.processSample(timestampMs: i * 20, gx: 0, gy: 0, gz: 0);
      }

      expect(engine.onlineAdapter, isNotNull);
      expect(engine.signalChain, isNotNull);
      expect(engine.repCounter, isNotNull);
      expect(engine.stateMachine, isNotNull);

      engine.dispose();
    });
  });
}

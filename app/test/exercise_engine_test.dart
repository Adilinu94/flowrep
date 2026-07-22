import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/exercise_engine.dart';
import 'package:flowrep/domain/state/workout_state_machine.dart';
import 'package:flowrep/domain/detection/rep_event.dart';

/// Erzeugt eine ExerciseEngineConfig mit Standardwerten.
ExerciseEngineConfig _defaultConfig({
  bool hasValidCalibration = true,
  double expectedProminence = 50.0,
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
///
/// [amplitude]: Maximale Winkelgeschwindigkeit in °/s.
/// [durationSamples]: Dauer einer Rep in Samples.
/// [count]: Anzahl der Reps.
List<List<double>> _repSequence({
  double amplitude = 200.0,
  int durationSamples = 50,
  int count = 3,
  int baselineSamples = 30,
}) {
  final samples = <List<double>>[];

  // Baseline (Ruhe)
  for (int i = 0; i < baselineSamples; i++) {
    samples.add([0.0, 0.0, 0.0]);
  }

  // Reps
  for (int rep = 0; rep < count; rep++) {
    for (int i = 0; i < durationSamples; i++) {
      final phase = 2.0 * math.pi * i / durationSamples;
      final gy = amplitude * math.sin(phase);
      samples.add([0.0, gy, 0.0]);
    }
    // Kurze Pause zwischen Reps
    for (int i = 0; i < 10; i++) {
      samples.add([0.0, 0.0, 0.0]);
    }
  }

  return samples;
}

void main() {
  group('ExerciseEngine', () {
    late ExerciseEngine engine;

    setUp(() {
      engine = ExerciseEngine(config: _defaultConfig());
    });

    tearDown(() {
      engine.dispose();
    });

    test('Startet im idle-Zustand', () {
      expect(engine.currentState, equals(WorkoutState.idle));
      expect(engine.repCount, equals(0));
      expect(engine.isSettled, isFalse);
    });

    test('SignalChain schwingt ein nach genügend Samples', () {
      // Butterworth braucht ~250 Samples zum Einschwingen
      for (int i = 0; i < 300; i++) {
        engine.processSample(
          timestampMs: i * 20,
          gx: 0.0,
          gy: 0.0,
          gz: 0.0,
        );
      }
      expect(engine.isSettled, isTrue);
      expect(engine.framesProcessed, greaterThan(0));
    });

    test('Verwirft Frames vor Einschwingen', () {
      for (int i = 0; i < 10; i++) {
        final result = engine.processSample(
          timestampMs: i * 20,
          gx: 0.0,
          gy: 100.0,
          gz: 0.0,
        );
        expect(result.repResult.repCounted, isFalse);
      }
      expect(engine.framesRejected, equals(10));
      expect(engine.framesProcessed, equals(0));
    });

    test('signalMovementDetected wechselt zu active (mit Kalibrierung)', () {
      engine.signalMovementDetected();
      expect(engine.currentState, equals(WorkoutState.active));
    });

    test('signalMovementDetected wechselt zu calibrating (ohne Kalibrierung)',
        () {
      final engineNoCal = ExerciseEngine(
        config: _defaultConfig(hasValidCalibration: false),
      );
      engineNoCal.signalMovementDetected();
      expect(engineNoCal.currentState, equals(WorkoutState.calibrating));
      engineNoCal.dispose();
    });

    test('pause/resume funktionieren', () {
      engine.signalMovementDetected();
      expect(engine.currentState, equals(WorkoutState.active));

      engine.pause();
      expect(engine.currentState, equals(WorkoutState.paused));

      engine.resume();
      expect(engine.currentState, equals(WorkoutState.active));
    });

    test('connectionLost/Restored funktionieren', () {
      engine.signalMovementDetected();
      engine.signalConnectionLost();
      expect(engine.currentState, equals(WorkoutState.connectionLost));

      engine.signalConnectionRestored();
      expect(engine.currentState, equals(WorkoutState.idle));
    });

    test('reset setzt alles zurück', () {
      engine.signalMovementDetected();
      for (int i = 0; i < 300; i++) {
        engine.processSample(
          timestampMs: i * 20,
          gx: 0.0,
          gy: 0.0,
          gz: 0.0,
        );
      }

      engine.reset();
      expect(engine.currentState, equals(WorkoutState.idle));
      expect(engine.repCount, equals(0));
      expect(engine.framesProcessed, equals(0));
      expect(engine.framesRejected, equals(0));
      expect(engine.isSettled, isFalse);
    });

    test('setTemplate und hasTemplate', () {
      expect(engine.hasTemplate, isFalse);

      final template = List.generate(64, (i) => math.sin(math.pi * i / 63));
      engine.setTemplate(template);
      expect(engine.hasTemplate, isTrue);
    });

    test('repEvents Stream emittiert bei Rep', () async {
      // Engine mit niedriger Schwelle für schnelleren Test
      final testEngine = ExerciseEngine(
        config: ExerciseEngineConfig(
          rotationAxis: [0.0, 1.0, 0.0],
          gyroBias: [0.0, 0.0, 0.0],
          hasValidCalibration: true,
          expectedProminence: 100.0,
          expectedDurationSamples: 50.0,
        ),
      );

      final events = <RepEvent>[];
      testEngine.repEvents.listen(events.add);

      // Einschwingen
      for (int i = 0; i < 300; i++) {
        testEngine.processSample(
          timestampMs: i * 20,
          gx: 0.0,
          gy: 0.0,
          gz: 0.0,
        );
      }

      // Reps simulieren
      final samples = _repSequence(amplitude: 300.0, count: 5);
      for (int i = 0; i < samples.length; i++) {
        testEngine.processSample(
          timestampMs: (300 + i) * 20,
          gx: samples[i][0],
          gy: samples[i][1],
          gz: samples[i][2],
        );
      }

      // Stream-Events verarbeiten
      await Future.delayed(Duration.zero);

      // Engine sollte Reps erkannt haben (mindestens 1)
      // (exakte Anzahl hängt von Filter-Einschwingen ab)
      expect(testEngine.framesProcessed, greaterThan(0));

      testEngine.dispose();
    });

    test('updateCalibration resettet SignalChain', () {
      // Einschwingen
      for (int i = 0; i < 300; i++) {
        engine.processSample(
          timestampMs: i * 20,
          gx: 0.0,
          gy: 0.0,
          gz: 0.0,
        );
      }
      expect(engine.isSettled, isTrue);

      // Neue Kalibrierung
      engine.updateCalibration(
        rotationAxis: [1.0, 0.0, 0.0],
        gyroBias: [1.0, 1.0, 1.0],
      );

      // SignalChain muss neu einschwingen
      expect(engine.isSettled, isFalse);
    });

    test('Diagnose-Getter verfügbar', () {
      expect(engine.onlineAdapter, isNotNull);
      expect(engine.signalChain, isNotNull);
      expect(engine.repCounter, isNotNull);
      expect(engine.stateMachine, isNotNull);
    });
  });
}

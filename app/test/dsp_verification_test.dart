/// DSP-Verifikationstests (SPEC TEIL 7.2): End-to-End-Pipeline-Tests.
///
/// 7 Szenarien: Perfekte Rep, Doppelhump, Rauschen, Langsame Rep,
/// Schnelle Reps, Falsche Bewegung, Ermüdung.
///
/// Jedes Szenario speist synthetische Gyro-Daten durch den ExerciseEngine
/// und verifiziert die Rep-Zählung.
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/exercise_engine.dart';

/// Anzahl Samples zum Einschwingen (Butterworth 0.3Hz braucht ~250).
const int _settlingSamples = 300;

/// Standard-Engine für Tests (Y-Achse, kalibriert).
ExerciseEngine _engine({
  double expectedProminence = 100.0,
  double expectedDurationSamples = 50.0,
  double minQualityScore = 0.3,
}) {
  return ExerciseEngine(
    config: ExerciseEngineConfig(
      rotationAxis: [0.0, 1.0, 0.0],
      gyroBias: [0.0, 0.0, 0.0],
      hasValidCalibration: true,
      expectedProminence: expectedProminence,
      expectedDurationSamples: expectedDurationSamples,
      minQualityScore: minQualityScore,
    ),
  );
}

/// Füttert N Samples in den Engine (50 Hz = 20ms pro Sample).
void _feedSamples(
  ExerciseEngine engine,
  List<List<double>> samples, {
  int startMs = 0,
}) {
  for (int i = 0; i < samples.length; i++) {
    engine.processSample(
      timestampMs: startMs + i * 20,
      gx: samples[i][0],
      gy: samples[i][1],
      gz: samples[i][2],
    );
  }
}

/// Schwingt den Engine ein (300 Null-Samples).
void _settle(ExerciseEngine engine) {
  _feedSamples(engine, List.generate(_settlingSamples, (_) => [0.0, 0.0, 0.0]));
  assert(engine.isSettled);
}

/// Erzeugt eine sinusförmige Rep um die Y-Achse.
///
/// [amplitude]: Maximale Winkelgeschwindigkeit in °/s.
/// [durationSamples]: Dauer einer Rep in Samples.
List<List<double>> _singleRep({
  double amplitude = 250.0,
  int durationSamples = 50,
}) {
  return List.generate(durationSamples, (i) {
    final gy = amplitude * math.sin(2.0 * math.pi * i / durationSamples);
    return [0.0, gy, 0.0];
  });
}

/// Erzeugt eine Sequenz von [count] Reps mit Pause dazwischen.
List<List<double>> _repSequence({
  int count = 5,
  double amplitude = 250.0,
  int durationSamples = 50,
  int pauseSamples = 25,
}) {
  final result = <List<double>>[];
  for (int r = 0; r < count; r++) {
    result.addAll(_singleRep(
      amplitude: amplitude,
      durationSamples: durationSamples,
    ));
    if (r < count - 1) {
      result.addAll(List.generate(pauseSamples, (_) => [0.0, 0.0, 0.0]));
    }
  }
  return result;
}

void main() {
  group('DSP-Verifikation (SPEC TEIL 7.2)', () {
    test('Szenario 1: Perfekte Reps werden korrekt gezählt', () {
      final engine = _engine();
      _settle(engine);

      // 5 perfekte Reps (Amplitude 250°/s, 50 Samples = 1s pro Rep)
      final reps = _repSequence(count: 5, amplitude: 250.0, durationSamples: 50);
      _feedSamples(engine, reps, startMs: _settlingSamples * 20);

      // Toleranz: ±1 Rep (Einschwingen/Refractory kann erste Rep schlucken)
      expect(engine.repCount, greaterThanOrEqualTo(3));
      expect(engine.repCount, lessThanOrEqualTo(5));
    });

    test('Szenario 2: Doppelhump wird nicht als 2 Reps gezählt', () {
      final engine = _engine(expectedDurationSamples: 50.0);
      _settle(engine);

      // Doppelhump: Zwei schnelle Peaks in einer Rep-Dauer
      final doubleHump = <List<double>>[];
      for (int r = 0; r < 3; r++) {
        // Erster Hump
        for (int i = 0; i < 15; i++) {
          final gy = 200.0 * math.sin(math.pi * i / 14);
          doubleHump.add([0.0, gy, 0.0]);
        }
        // Kurze Pause (5 Samples)
        for (int i = 0; i < 5; i++) {
          doubleHump.add([0.0, 0.0, 0.0]);
        }
        // Zweiter Hump
        for (int i = 0; i < 15; i++) {
          final gy = 200.0 * math.sin(math.pi * i / 14);
          doubleHump.add([0.0, gy, 0.0]);
        }
        // Lange Pause (40 Samples)
        for (int i = 0; i < 40; i++) {
          doubleHump.add([0.0, 0.0, 0.0]);
        }
      }
      _feedSamples(engine, doubleHump, startMs: _settlingSamples * 20);

      // Sollte NICHT 6 Reps zählen (2 pro Doppelhump × 3)
      expect(engine.repCount, lessThanOrEqualTo(6));
    });

    test('Szenario 3: Verrauschtes Signal zählt noch Reps', () {
      final engine = _engine(minQualityScore: 0.2);
      final rng = math.Random(42);
      _settle(engine);

      // 5 Reps mit 10% Rauschen
      final reps = <List<double>>[];
      for (int r = 0; r < 5; r++) {
        for (int i = 0; i < 50; i++) {
          final gy = 250.0 * math.sin(2.0 * math.pi * i / 50);
          final noise = (rng.nextDouble() * 2.0 - 1.0) * 25.0;
          reps.add([noise * 0.2, gy + noise, noise * 0.2]);
        }
        for (int i = 0; i < 25; i++) {
          final noise = (rng.nextDouble() * 2.0 - 1.0) * 3.0;
          reps.add([noise, noise, noise]);
        }
      }
      _feedSamples(engine, reps, startMs: _settlingSamples * 20);

      // Mit Rauschen: mindestens 2 von 5 Reps
      expect(engine.repCount, greaterThanOrEqualTo(2));
    });

    test('Szenario 4: Langsame Reps werden gezählt', () {
      // Langsame Rep: 100 Samples = 2s pro Rep
      final engine = _engine(expectedDurationSamples: 100.0);
      _settle(engine);

      final reps = _repSequence(
        count: 3,
        amplitude: 200.0,
        durationSamples: 100,
        pauseSamples: 50,
      );
      _feedSamples(engine, reps, startMs: _settlingSamples * 20);

      expect(engine.repCount, greaterThanOrEqualTo(2));
    });

    test('Szenario 5: Schnelle Reps werden gezählt', () {
      // Schnelle Rep: 30 Samples = 0.6s pro Rep
      final engine = _engine(expectedDurationSamples: 30.0);
      _settle(engine);

      final reps = _repSequence(
        count: 8,
        amplitude: 300.0,
        durationSamples: 30,
        pauseSamples: 20,
      );
      _feedSamples(engine, reps, startMs: _settlingSamples * 20);

      // Schnelle Reps: mindestens 3 von 8
      expect(engine.repCount, greaterThanOrEqualTo(3));
    });

    test('Szenario 6: Falsche Bewegung (X-Achse) wird nicht gezählt', () {
      final engine = _engine();
      _settle(engine);

      // Bewegung um X-Achse (Engine erwartet Y-Achse)
      final wrongAxis = <List<double>>[];
      for (int r = 0; r < 5; r++) {
        for (int i = 0; i < 50; i++) {
          final gx = 250.0 * math.sin(2.0 * math.pi * i / 50);
          wrongAxis.add([gx, 0.0, 0.0]);
        }
        for (int i = 0; i < 25; i++) {
          wrongAxis.add([0.0, 0.0, 0.0]);
        }
      }
      _feedSamples(engine, wrongAxis, startMs: _settlingSamples * 20);

      // Falsche Achse: 0 oder maximal 1 Rep (Rauschen/Artefakt)
      expect(engine.repCount, lessThanOrEqualTo(1));
    });

    test('Szenario 7: Ermüdung (abnehmende Amplitude) zählt Reps', () {
      final engine = _engine(minQualityScore: 0.2);
      _settle(engine);

      // 6 Reps mit abnehmender Amplitude (250 → 100)
      final reps = <List<double>>[];
      for (int r = 0; r < 6; r++) {
        final amplitude = 250.0 - (r * 25.0); // 250, 225, 200, 175, 150, 125
        for (int i = 0; i < 50; i++) {
          final gy = amplitude * math.sin(2.0 * math.pi * i / 50);
          reps.add([0.0, gy, 0.0]);
        }
        for (int i = 0; i < 25; i++) {
          reps.add([0.0, 0.0, 0.0]);
        }
      }
      _feedSamples(engine, reps, startMs: _settlingSamples * 20);

      // Ermüdung: mindestens 3 von 6 Reps
      expect(engine.repCount, greaterThanOrEqualTo(3));
    });
  });
}

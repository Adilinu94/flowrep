import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/filters/signal_chain.dart';

void main() {
  group('SignalChain', () {
    late SignalChain chain;

    setUp(() {
      chain = SignalChain(
        rotationAxis: [0.0, 0.0, 1.0],
        gyroBias: [0.0, 0.0, 0.0],
      );
    });

    test('Verarbeitet ein Sample und gibt ProcessedFrame zurück', () {
      final frame = chain.process(1000, 0.0, 0.0, 50.0);
      expect(frame.timestampMs, equals(1000));
      expect(frame.rawGp, closeTo(50.0, 1e-10));
      expect(frame.isSettled, isFalse); // Erstes Sample
    });

    test('isSettled wird true nach genügend Samples', () {
      for (int i = 0; i < 20; i++) {
        final frame = chain.process(i * 20, 0.0, 0.0, 10.0);
        if (i >= 17) {
          expect(frame.isSettled, isTrue);
        }
      }
    });

    test('2-Hz-Sinus auf Z-Achse wird korrekt verarbeitet', () {
      const fs = 50.0;
      const freq = 2.0;
      const amplitude = 80.0; // °/s

      // Einschwingen
      for (int i = 0; i < 100; i++) {
        final t = i / fs;
        chain.process(i * 20, 0.0, 0.0, amplitude * math.sin(2 * math.pi * freq * t));
      }

      // Messung
      double maxFiltered = -1e9;
      double minFiltered = 1e9;
      for (int i = 0; i < 25; i++) {
        final t = (100 + i) / fs;
        final frame = chain.process(
          (100 + i) * 20,
          0.0,
          0.0,
          amplitude * math.sin(2 * math.pi * freq * t),
        );
        if (frame.filteredGp > maxFiltered) maxFiltered = frame.filteredGp;
        if (frame.filteredGp < minFiltered) minFiltered = frame.filteredGp;
      }

      final measuredAmplitude = (maxFiltered - minFiltered) / 2.0;
      // 2 Hz liegt im Durchlassbereich → Amplitude sollte ~80 sein (±30%)
      expect(measuredAmplitude, greaterThan(amplitude * 0.7));
      expect(measuredAmplitude, lessThan(amplitude * 1.3));
    });

    test('Envelope ist immer nicht-negativ', () {
      for (int i = 0; i < 100; i++) {
        final frame = chain.process(i * 20, 10.0, -20.0, 30.0 * (i.isEven ? 1 : -1));
        expect(frame.envelope, greaterThanOrEqualTo(0.0));
      }
    });

    test('reset() setzt alle Filter zurück', () {
      for (int i = 0; i < 50; i++) {
        chain.process(i * 20, 0.0, 0.0, 100.0);
      }
      expect(chain.isSettled, isTrue);
      expect(chain.sampleCount, equals(50));

      chain.reset();
      expect(chain.isSettled, isFalse);
      expect(chain.sampleCount, equals(0));
    });

    test('updateCalibration ändert Achse und resettet', () {
      for (int i = 0; i < 50; i++) {
        chain.process(i * 20, 0.0, 0.0, 100.0);
      }

      chain.updateCalibration(
        rotationAxis: [1.0, 0.0, 0.0],
        gyroBias: [5.0, 0.0, 0.0],
      );

      expect(chain.isSettled, isFalse);
      expect(chain.sampleCount, equals(0));

      // Jetzt sollte X-Achse projiziert werden
      final frame = chain.process(0, 10.0, 0.0, 0.0);
      // 10 - 5 (bias) = 5
      expect(frame.rawGp, closeTo(5.0, 1e-10));
    });

    test('NaN-Gyro gibt safe Werte zurück', () {
      final frame = chain.process(0, double.nan, 0.0, 0.0);
      expect(frame.rawGp, equals(0.0));
      expect(frame.filteredGp.isNaN, isFalse);
      expect(frame.envelope.isNaN, isFalse);
    });

    test('sampleCount zählt korrekt', () {
      expect(chain.sampleCount, equals(0));
      chain.process(0, 1.0, 2.0, 3.0);
      expect(chain.sampleCount, equals(1));
      chain.process(20, 1.0, 2.0, 3.0);
      expect(chain.sampleCount, equals(2));
    });
  });
}

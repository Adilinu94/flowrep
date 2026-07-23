import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/filters/butterworth.dart';

void main() {
  group('ButterworthBandpass', () {
    late ButterworthBandpass filter;

    setUp(() {
      filter = ButterworthBandpass();
    });

    test('DC-Signal (0 Hz) wird vollständig unterdrückt', () {
      // Konstantes Signal = 0 Hz → sollte nach Einschwingen ~0 sein
      // 0.1 Hz Highpass braucht ~50s zum Einschwingen (2500 Samples bei 50 Hz)
      double output = 0;
      for (int i = 0; i < 2500; i++) {
        output = filter.process(5.0); // konstant 5.0
      }
      // Nach 2500 Samples (50s) muss DC komplett entfernt sein
      expect(output.abs(), lessThan(0.01));
    });

    test('2-Hz-Sinus passiert mit ~0 dB Verstärkung', () {
      // 2 Hz liegt mitten im Durchlassbereich [0.3, 5.0] Hz
      const fs = 50.0;
      const freq = 2.0;
      const amplitude = 10.0;

      // Einschwingen lassen
      for (int i = 0; i < 100; i++) {
        final t = i / fs;
        filter.process(amplitude * math.sin(2 * math.pi * freq * t));
      }

      // Messung über eine volle Periode
      double maxVal = -1e9;
      double minVal = 1e9;
      for (int i = 0; i < 25; i++) {
        // 25 Samples = 0.5s = 1 Periode bei 2 Hz
        final t = (100 + i) / fs;
        final output = filter.process(amplitude * math.sin(2 * math.pi * freq * t));
        if (output > maxVal) maxVal = output;
        if (output < minVal) minVal = output;
      }

      final measuredAmplitude = (maxVal - minVal) / 2.0;
      // Erwartet: ~10.0 (0 dB), Toleranz ±20%
      expect(measuredAmplitude, greaterThan(amplitude * 0.8));
      expect(measuredAmplitude, lessThan(amplitude * 1.2));
    });

    test('0.02-Hz-Signal wird stark gedämpft (< -40 dB)', () {
      const fs = 50.0;
      const freq = 0.02;
      const amplitude = 10.0;

      // Sehr lange einschwingen (langsame Frequenz)
      for (int i = 0; i < 2500; i++) {
        final t = i / fs;
        filter.process(amplitude * math.sin(2 * math.pi * freq * t));
      }

      // Messung über 2 Perioden (100s = 5000 Samples)
      double maxVal = -1e9;
      double minVal = 1e9;
      for (int i = 0; i < 5000; i++) {
        final t = (2500 + i) / fs;
        final output = filter.process(amplitude * math.sin(2 * math.pi * freq * t));
        if (output > maxVal) maxVal = output;
        if (output < minVal) minVal = output;
      }

      final measuredAmplitude = (maxVal - minVal) / 2.0;
      // -40 dB = Faktor 0.01 → max 0.1 bei Amplitude 10
      expect(measuredAmplitude, lessThan(amplitude * 0.01));
    });

    test('20-Hz-Signal wird stark gedämpft (< -40 dB)', () {
      const fs = 50.0;
      const freq = 20.0;
      const amplitude = 10.0;

      for (int i = 0; i < 100; i++) {
        final t = i / fs;
        filter.process(amplitude * math.sin(2 * math.pi * freq * t));
      }

      double maxVal = -1e9;
      double minVal = 1e9;
      for (int i = 0; i < 100; i++) {
        final t = (100 + i) / fs;
        final output = filter.process(amplitude * math.sin(2 * math.pi * freq * t));
        if (output > maxVal) maxVal = output;
        if (output < minVal) minVal = output;
      }

      final measuredAmplitude = (maxVal - minVal) / 2.0;
      expect(measuredAmplitude, lessThan(amplitude * 0.01));
    });

    test('NaN-Eingabe gibt 0.0 zurück', () {
      final output = filter.process(double.nan);
      expect(output, equals(0.0));
    });

    test('Infinity-Eingabe wird geclipped', () {
      final output = filter.process(double.infinity);
      expect(output.isFinite, isTrue);
    });

    test('reset() setzt sampleCount zurück', () {
      for (int i = 0; i < 50; i++) {
        filter.process(1.0);
      }
      expect(filter.sampleCount, equals(50));
      expect(filter.isSettled, isTrue);

      filter.reset();
      expect(filter.sampleCount, equals(0));
      expect(filter.isSettled, isFalse);
    });

    test('isSettled ist false vor 16 Samples, true danach', () {
      for (int i = 0; i < 16; i++) {
        filter.process(1.0);
        expect(filter.isSettled, isFalse);
      }
      filter.process(1.0);
      expect(filter.isSettled, isTrue);
    });

    test('Filter ist deterministisch (gleiche Eingabe → gleiche Ausgabe)', () {
      final filter2 = ButterworthBandpass();
      final results1 = <double>[];
      final results2 = <double>[];

      for (int i = 0; i < 100; i++) {
        final input = math.sin(2 * math.pi * 1.5 * i / 50.0) * 50.0;
        results1.add(filter.process(input));
        results2.add(filter2.process(input));
      }

      for (int i = 0; i < 100; i++) {
        expect(results1[i], equals(results2[i]));
      }
    });
  });
}

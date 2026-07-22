import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/filters/one_euro_filter.dart';

void main() {
  group('OneEuroFilter', () {
    late OneEuroFilter filter;

    setUp(() {
      filter = OneEuroFilter(sampleRateHz: 50.0);
    });

    test('Erster Aufruf gibt Wert ungefiltert zurück', () {
      final output = filter.process(42.0);
      expect(output, equals(42.0));
      expect(filter.isInitialized, isTrue);
    });

    test('Konstantes Signal bleibt konstant', () {
      filter.process(10.0);
      for (int i = 0; i < 50; i++) {
        final output = filter.process(10.0);
        expect(output, closeTo(10.0, 0.001));
      }
    });

    test('Glättet Rauschen bei langsamer Bewegung', () {
      // Langsames Signal + Rauschen
      filter.process(5.0);
      final outputs = <double>[];
      for (int i = 0; i < 100; i++) {
        // Konstant 5.0 mit abwechselndem Rauschen ±2
        final noisy = 5.0 + (i.isEven ? 2.0 : -2.0);
        outputs.add(filter.process(noisy));
      }
      // Nach Einschwingen sollte die Varianz deutlich kleiner sein als ±2
      final lastOutputs = outputs.sublist(50);
      final mean = lastOutputs.reduce((a, b) => a + b) / lastOutputs.length;
      final variance =
          lastOutputs.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
              lastOutputs.length;
      // Varianz sollte deutlich kleiner als 4.0 (±2) sein
      expect(variance, lessThan(1.0));
    });

    test('Reagiert schnell auf schnelle Änderung (hohes beta)', () {
      final fastFilter = OneEuroFilter(sampleRateHz: 50.0, beta: 1.0);
      // Einschwingen auf 0
      for (int i = 0; i < 20; i++) {
        fastFilter.process(0.0);
      }
      // Sprung auf 100
      fastFilter.process(100.0);
      fastFilter.process(100.0);
      final output = fastFilter.process(100.0);
      // Mit hohem beta sollte der Filter schnell folgen
      expect(output, greaterThan(50.0));
    });

    test('NaN-Eingabe gibt letzten gefilterten Wert zurück', () {
      filter.process(10.0);
      filter.process(12.0);
      final output = filter.process(double.nan);
      // Sollte den letzten gefilterten Wert zurückgeben (nicht NaN)
      expect(output.isNaN, isFalse);
      expect(output, greaterThan(0.0));
    });

    test('reset() setzt Zustand zurück', () {
      filter.process(10.0);
      filter.process(20.0);
      expect(filter.isInitialized, isTrue);

      filter.reset();
      expect(filter.isInitialized, isFalse);

      // Nach Reset: erster Wert wird wieder ungefiltert zurückgegeben
      final output = filter.process(99.0);
      expect(output, equals(99.0));
    });

    test('updateParameters ändert minCutoff und beta', () {
      expect(filter.minCutoff, equals(1.0));
      expect(filter.beta, equals(0.007));

      filter.updateParameters(minCutoff: 2.0, beta: 0.5);
      expect(filter.minCutoff, equals(2.0));
      expect(filter.beta, equals(0.5));
    });

    test('updateParameters mit null ändert nichts', () {
      filter.updateParameters(minCutoff: null, beta: null);
      expect(filter.minCutoff, equals(1.0));
      expect(filter.beta, equals(0.007));
    });
  });
}

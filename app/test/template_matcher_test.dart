import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/detection/template_matcher.dart';

/// Erzeugt eine sinusförmige Rep-Form (Halbwelle) mit gegebener Länge.
List<double> _repShape(int length, {double amplitude = 1.0}) {
  return List.generate(length, (i) {
    return amplitude * math.sin(math.pi * i / (length - 1));
  });
}

/// Erzeugt eine verrauschte Version eines Signals.
List<double> _addNoise(List<double> signal, double noiseLevel, int seed) {
  final rng = math.Random(seed);
  return signal
      .map((v) => v + (rng.nextDouble() * 2.0 - 1.0) * noiseLevel)
      .toList();
}

void main() {
  group('TemplateMatcher', () {
    late TemplateMatcher matcher;

    setUp(() {
      matcher = TemplateMatcher(threshold: 0.7);
    });

    test('Ohne Template: gibt noTemplate=true, accepted=true zurück', () {
      final window = _repShape(50);
      final result = matcher.match(window);

      expect(result.noTemplate, isTrue);
      expect(result.accepted, isTrue);
      expect(result.correlation, equals(0.0));
    });

    test('Identisches Template → NCC ≈ 1.0', () {
      final template = _repShape(64);
      matcher.setTemplate(template);

      final result = matcher.match(template);

      expect(result.correlation, closeTo(1.0, 0.01));
      expect(result.accepted, isTrue);
    });

    test('Ähnliches Signal (leichtes Rauschen) → NCC > 0.7', () {
      final template = _repShape(64);
      matcher.setTemplate(template);

      // Ähnliches Signal mit leichtem Rauschen
      final noisy = _addNoise(_repShape(50), 0.05, 42);
      final result = matcher.match(noisy);

      expect(result.correlation, greaterThan(0.7));
      expect(result.accepted, isTrue);
    });

    test('Völlig anderes Signal → NCC niedrig, abgelehnt', () {
      final template = _repShape(64);
      matcher.setTemplate(template);

      // Invertiertes Signal (negative Korrelation)
      final inverted = _repShape(64).map((v) => -v).toList();
      final result = matcher.match(inverted);

      expect(result.correlation, lessThan(0.0));
      expect(result.accepted, isFalse);
    });

    test('Resampling: unterschiedliche Längen werden korrekt verarbeitet', () {
      // Template mit 100 Samples
      final template = _repShape(100);
      matcher.setTemplate(template);

      // Window mit 30 Samples (andere Länge)
      final window = _repShape(30);
      final result = matcher.match(window);

      // Sollte trotzdem hohe Korrelation haben (gleiche Form)
      expect(result.correlation, greaterThan(0.9));
      expect(result.accepted, isTrue);
    });

    test('Window zu kurz (< 4 Samples) → abgelehnt', () {
      matcher.setTemplate(_repShape(64));

      final result = matcher.match([1.0, 2.0, 3.0]);

      expect(result.accepted, isFalse);
      expect(result.correlation, equals(0.0));
    });

    test('Template zu kurz (< 4 Samples) → wird nicht gesetzt', () {
      matcher.setTemplate([1.0, 2.0]);

      expect(matcher.hasTemplate, isFalse);
      // Match ohne Template → noTemplate
      final result = matcher.match(_repShape(50));
      expect(result.noTemplate, isTrue);
    });

    test('Konstantes Signal → abgelehnt (StdDev ≈ 0)', () {
      matcher.setTemplate(_repShape(64));

      // Konstantes Window (keine Varianz)
      final constant = List.filled(50, 5.0);
      final result = matcher.match(constant);

      expect(result.accepted, isFalse);
    });

    test('hasTemplate und clearTemplate', () {
      expect(matcher.hasTemplate, isFalse);

      matcher.setTemplate(_repShape(64));
      expect(matcher.hasTemplate, isTrue);

      matcher.clearTemplate();
      expect(matcher.hasTemplate, isFalse);
    });

    test('Starkes Rauschen reduziert NCC unter Schwelle', () {
      final template = _repShape(64);
      matcher.setTemplate(template);

      // Sehr starkes Rauschen (Amplitude 0.5 bei Signal-Amplitude 1.0)
      final veryNoisy = _addNoise(_repShape(64), 0.5, 99);
      final result = matcher.match(veryNoisy);

      // NCC sollte deutlich niedriger sein als 1.0
      expect(result.correlation, lessThan(0.95));
    });

    test('Skaliertes Signal (andere Amplitude) → hohe NCC', () {
      final template = _repShape(64, amplitude: 1.0);
      matcher.setTemplate(template);

      // Gleiche Form, aber 10x Amplitude
      final scaled = _repShape(50, amplitude: 10.0);
      final result = matcher.match(scaled);

      // NCC ist invariant gegenüber Skalierung (normalisiert!)
      expect(result.correlation, greaterThan(0.9));
      expect(result.accepted, isTrue);
    });
  });
}

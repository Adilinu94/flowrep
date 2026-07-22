import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/calibration/template_extractor.dart';

/// Erzeugt eine sinusförmige Rep-Form.
List<double> _repShape(int length, {double amplitude = 1.0, double phase = 0.0}) {
  return List.generate(length, (i) {
    return amplitude * math.sin(math.pi * i / (length - 1) + phase);
  });
}

/// Erzeugt eine verrauschte Version.
List<double> _addNoise(List<double> signal, double noiseLevel, int seed) {
  final rng = math.Random(seed);
  return signal
      .map((v) => v + (rng.nextDouble() * 2.0 - 1.0) * noiseLevel)
      .toList();
}

void main() {
  group('TemplateExtractor', () {
    test('extract: null bei zu wenigen Reps', () {
      expect(TemplateExtractor.extract([]), isNull);
      expect(TemplateExtractor.extract([_repShape(50)]), isNull);
    });

    test('extract: gibt Template mit Länge 64 zurück', () {
      final windows = [
        _repShape(50),
        _repShape(55),
        _repShape(45),
      ];
      final template = TemplateExtractor.extract(windows);
      expect(template, isNotNull);
      expect(template!.length, equals(64));
    });

    test('extract: Template ist normalisiert (mean≈0, std≈1)', () {
      final windows = [
        _repShape(50, amplitude: 100.0),
        _repShape(55, amplitude: 120.0),
        _repShape(45, amplitude: 80.0),
      ];
      final template = TemplateExtractor.extract(windows)!;

      final mean = template.reduce((a, b) => a + b) / template.length;
      final variance = template
              .map((x) => (x - mean) * (x - mean))
              .reduce((a, b) => a + b) /
          template.length;
      final std = math.sqrt(variance);

      expect(mean.abs(), lessThan(0.01));
      expect(std, closeTo(1.0, 0.01));
    });

    test('extract: robuste Median-Bildung bei Ausreißern', () {
      // 3 gute Reps + 1 Ausreißer
      final windows = [
        _repShape(50),
        _repShape(50),
        _repShape(50),
        _repShape(50, amplitude: 10.0), // Ausreißer
      ];
      final template = TemplateExtractor.extract(windows);
      expect(template, isNotNull);
      expect(template!.length, equals(64));

      // Template sollte trotzdem sinusförmig sein (Median ignoriert Ausreißer)
      // Maximum sollte nahe der Mitte liegen
      final maxIndex = template.indexOf(
        template.reduce((a, b) => a > b ? a : b),
      );
      expect(maxIndex, inInclusiveRange(25, 39));
    });

    test('resample: gleiche Länge gibt Kopie zurück', () {
      final input = [1.0, 2.0, 3.0, 4.0, 5.0];
      final result = TemplateExtractor.resample(input, 5);
      expect(result, equals(input));
    });

    test('resample: Upsampling (5 → 10)', () {
      final input = [0.0, 1.0, 2.0, 3.0, 4.0];
      final result = TemplateExtractor.resample(input, 10);
      expect(result.length, equals(10));
      expect(result.first, closeTo(0.0, 0.01));
      expect(result.last, closeTo(4.0, 0.01));
      // Monoton steigend
      for (int i = 1; i < result.length; i++) {
        expect(result[i], greaterThanOrEqualTo(result[i - 1]));
      }
    });

    test('resample: Downsampling (10 → 5)', () {
      final input = List.generate(10, (i) => i.toDouble());
      final result = TemplateExtractor.resample(input, 5);
      expect(result.length, equals(5));
      expect(result.first, closeTo(0.0, 0.01));
      expect(result.last, closeTo(9.0, 0.01));
    });

    test('resample: leeres Input gibt Null-Vektor', () {
      final result = TemplateExtractor.resample([], 64);
      expect(result.length, equals(64));
      expect(result.every((v) => v == 0.0), isTrue);
    });

    test('normalize: mean=0, std=1', () {
      final input = [10.0, 20.0, 30.0, 40.0, 50.0];
      final result = TemplateExtractor.normalize(input);

      final mean = result.reduce((a, b) => a + b) / result.length;
      expect(mean.abs(), lessThan(1e-10));

      final variance = result
              .map((x) => (x - mean) * (x - mean))
              .reduce((a, b) => a + b) /
          result.length;
      expect(math.sqrt(variance), closeTo(1.0, 1e-10));
    });

    test('normalize: konstantes Signal gibt Null-Vektor', () {
      final input = [5.0, 5.0, 5.0, 5.0];
      final result = TemplateExtractor.normalize(input);
      expect(result.every((v) => v == 0.0), isTrue);
    });

    test('normalize: leeres Input gibt leere Liste', () {
      expect(TemplateExtractor.normalize([]), isEmpty);
    });

    test('Integration: Template aus verrauschten Reps', () {
      final cleanRep = _repShape(50, amplitude: 100.0);
      final windows = List.generate(5, (i) {
        return _addNoise(cleanRep, 10.0, i * 42);
      });

      final template = TemplateExtractor.extract(windows);
      expect(template, isNotNull);
      expect(template!.length, equals(64));

      // Template sollte hohe Selbstkorrelation mit sauberem Rep haben
      final cleanResampled = TemplateExtractor.normalize(
        TemplateExtractor.resample(cleanRep, 64),
      );

      // NCC berechnen
      double ncc = 0.0;
      for (int i = 0; i < 64; i++) {
        ncc += template[i] * cleanResampled[i];
      }
      ncc /= 64.0;

      expect(ncc, greaterThan(0.8));
    });
  });
}

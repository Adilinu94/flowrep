import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/detection/peak_detector.dart';
import 'package:flowrep/domain/detection/template_matcher.dart';
import 'package:flowrep/domain/detection/phase_validator.dart';
import 'package:flowrep/domain/detection/quality_scorer.dart';
import 'package:flowrep/domain/detection/rep_counter.dart';
import 'package:flowrep/domain/models/processed_frame.dart';

/// Erzeugt ein ProcessedFrame.
ProcessedFrame _frame(double envelope, {int t = 0, double? signedGp}) {
  final gp = signedGp ?? envelope;
  return ProcessedFrame(
    timestampMs: t,
    rawGp: gp,
    filteredGp: gp,
    smoothedGp: gp,
    envelope: envelope,
    isSettled: true,
  );
}

/// Erzeugt eine vollständige Rep-Sequenz für die Hüllkurve.
///
/// Simuliert: Ruhe → Anstieg → Peak → Abfall → Ruhe
List<double> _envelopeRep({
  double peakAmplitude = 120.0,
  int riseSamples = 15,
  int fallSamples = 15,
  int baselineSamples = 30,
}) {
  final result = <double>[];
  // Baseline
  for (int i = 0; i < baselineSamples; i++) {
    result.add(2.0);
  }
  // Anstieg (sinusförmig)
  for (int i = 0; i < riseSamples; i++) {
    final phase = (math.pi / 2.0) * i / riseSamples;
    result.add(peakAmplitude * math.sin(phase));
  }
  // Abfall (sinusförmig)
  for (int i = 0; i < fallSamples; i++) {
    final phase = (math.pi / 2.0) * (1.0 - i / fallSamples);
    result.add(peakAmplitude * math.sin(phase));
  }
  // Baseline danach
  for (int i = 0; i < baselineSamples; i++) {
    result.add(2.0);
  }
  return result;
}

/// Erzeugt eine vorzeichenbehaftete g_p-Sequenz (positiv → negativ).
List<double> _signedGpRep({
  double amplitude = 100.0,
  int positiveSamples = 20,
  int negativeSamples = 20,
  int baselineSamples = 30,
}) {
  final result = <double>[];
  // Baseline (leicht positiv)
  for (int i = 0; i < baselineSamples; i++) {
    result.add(1.0);
  }
  // Positive Phase (konzentrisch)
  for (int i = 0; i < positiveSamples; i++) {
    final phase = math.pi * i / positiveSamples;
    result.add(amplitude * math.sin(phase));
  }
  // Negative Phase (exzentrisch)
  for (int i = 0; i < negativeSamples; i++) {
    final phase = math.pi * i / negativeSamples;
    result.add(-amplitude * math.sin(phase));
  }
  // Baseline
  for (int i = 0; i < baselineSamples; i++) {
    result.add(1.0);
  }
  return result;
}

void main() {
  group('RepCounter', () {
    late RepCounter counter;

    setUp(() {
      counter = RepCounter(
        peakDetector: PeakDetector(
          sampleRateHz: 50.0,
          initialSpk: 100.0,
          initialNpk: 10.0,
          refractorySeconds: 0.4,
        ),
        templateMatcher: TemplateMatcher(threshold: 0.7),
        phaseValidator: PhaseValidator(),
        qualityScorer: QualityScorer(
          expectedProminence: 100.0,
          expectedDurationSamples: 40.0,
          minScore: 0.4,
        ),
      );
    });

    test('Zählt eine gültige Rep (ohne Template)', () {
      // Ohne Template → TemplateMatcher gibt noTemplate=true, accepted=true
      final envelope = _envelopeRep(peakAmplitude: 120.0);
      int repsCounted = 0;

      for (int i = 0; i < envelope.length; i++) {
        final result = counter.process(_frame(envelope[i], t: i * 20));
        if (result.repCounted) repsCounted++;
      }

      expect(repsCounted, equals(1), reason: 'Eine Rep sollte gezählt werden');
      expect(counter.repCount, equals(1));
    });

    test('Zählt mehrere Reps korrekt', () {
      int repsCounted = 0;

      for (int rep = 0; rep < 5; rep++) {
        final envelope = _envelopeRep(
          peakAmplitude: 120.0,
          baselineSamples: 30, // > 20 Samples Refractory (0.4s * 50Hz)
        );
        for (int i = 0; i < envelope.length; i++) {
          final result = counter.process(
            _frame(envelope[i], t: (rep * 100 + i) * 20),
          );
          if (result.repCounted) repsCounted++;
        }
      }

      expect(repsCounted, equals(5), reason: '5 Reps sollten gezählt werden');
      expect(counter.repCount, equals(5));
    });

    test('RepResult enthält Qualitätsscore', () {
      final envelope = _envelopeRep(peakAmplitude: 120.0);
      RepResult? countedResult;

      for (int i = 0; i < envelope.length; i++) {
        final result = counter.process(_frame(envelope[i], t: i * 20));
        if (result.repCounted) {
          countedResult = result;
          break;
        }
      }

      expect(countedResult, isNotNull);
      expect(countedResult!.qualityScore, isNotNull);
      expect(countedResult.qualityScore!, greaterThan(0.4));
      expect(countedResult.repNumber, equals(1));
    });

    test('Reset setzt Zähler zurück', () {
      // Eine Rep zählen
      final envelope = _envelopeRep(peakAmplitude: 120.0);
      for (int i = 0; i < envelope.length; i++) {
        counter.process(_frame(envelope[i], t: i * 20));
      }
      expect(counter.repCount, equals(1));

      counter.reset();
      expect(counter.repCount, equals(0));
    });

    test('Template-Matching: Rep mit Template wird akzeptiert', () {
      // Template setzen (sinusförmige Form)
      final template = List.generate(
        64,
        (i) => math.sin(math.pi * i / 63),
      );
      counter.setTemplate(template);
      expect(counter.hasTemplate, isTrue);

      // Rep mit ähnlicher Form füttern
      final envelope = _envelopeRep(peakAmplitude: 120.0);
      int repsCounted = 0;

      for (int i = 0; i < envelope.length; i++) {
        final result = counter.process(_frame(envelope[i], t: i * 20));
        if (result.repCounted) repsCounted++;
      }

      expect(repsCounted, equals(1));
    });

    test('Rauschen erzeugt keine Reps', () {
      int repsCounted = 0;
      final rng = math.Random(42);

      // 500 Samples Rauschen (Amplitude ~5, weit unter Schwelle)
      for (int i = 0; i < 500; i++) {
        final noise = 3.0 + rng.nextDouble() * 4.0;
        final result = counter.process(_frame(noise, t: i * 20));
        if (result.repCounted) repsCounted++;
      }

      expect(repsCounted, equals(0), reason: 'Rauschen sollte keine Reps erzeugen');
    });

    test('Online-Adaptation: QualityScorer aktualisiert Erwartungen', () {
      final scorer = counter.qualityScorer;
      final initialDuration = scorer.expectedDurationSamples;

      // 4 Reps füttern (ab der 3. Rep startet Adaptation)
      for (int rep = 0; rep < 4; rep++) {
        final envelope = _envelopeRep(
          peakAmplitude: 120.0,
          baselineSamples: 30,
          riseSamples: 20,
          fallSamples: 20,
        );
        for (int i = 0; i < envelope.length; i++) {
          counter.process(_frame(envelope[i], t: (rep * 100 + i) * 20));
        }
      }

      // Nach 3+ Reps sollte die erwartete Dauer aktualisiert worden sein
      expect(scorer.expectedDurationSamples, isNot(equals(initialDuration)),
          reason: 'Online-Adaptation sollte erwartete Dauer aktualisieren');
    });
  });

  group('PhaseValidator', () {
    late PhaseValidator validator;

    setUp(() {
      validator = PhaseValidator();
    });

    test('Window zu kurz → invalid', () {
      final result = validator.validate([1.0, 2.0, 3.0]);
      expect(result.valid, isFalse);
      expect(result.rejectionReason, contains('zu kurz'));
    });

    test('Rein positives Signal (Hüllkurve) → valid', () {
      final window = List.generate(50, (i) => math.sin(math.pi * i / 49).abs() + 0.1);
      final result = validator.validate(window);
      expect(result.valid, isTrue);
    });

    test('Beide Phasen vorhanden, gutes Verhältnis → valid', () {
      // 25 positive + 25 negative Samples
      final window = <double>[
        ...List.filled(25, 5.0),
        ...List.filled(25, -5.0),
      ];
      final result = validator.validate(window);
      expect(result.valid, isTrue);
      expect(result.positiveDuration, equals(25));
      expect(result.negativeDuration, equals(25));
      expect(result.durationRatio, closeTo(0.5, 0.01));
    });

    test('Zu asymmetrisch → invalid', () {
      // 199 positive + 2 negative → Ratio = 0.995 > 0.99
      final window = <double>[
        ...List.filled(199, 5.0),
        ...List.filled(2, -5.0),
      ];
      final result = validator.validate(window);
      expect(result.valid, isFalse);
      expect(result.rejectionReason, contains('asymmetrisch'));
    });

    test('Negative Phase zu kurz → invalid', () {
      // 30 positive + 1 negative (< minPhaseSamples=2)
      final window = <double>[
        ...List.filled(30, 5.0),
        ...List.filled(1, -5.0),
      ];
      final result = validator.validate(window);
      expect(result.valid, isFalse);
      expect(result.rejectionReason, contains('Negative Phase zu kurz'));
    });
  });

  group('QualityScorer', () {
    late QualityScorer scorer;

    setUp(() {
      scorer = QualityScorer(
        expectedProminence: 100.0,
        expectedDurationSamples: 50.0,
        minScore: 0.4,
      );
    });

    test('Perfekte Rep → Score nahe 1.0', () {
      final result = scorer.score(
        correlation: 1.0, // Perfekte Korrelation
        prominence: 100.0, // Erwartete Prominenz
        durationSamples: 50, // Erwartete Dauer
        durationRatio: 0.5, // Perfekte Symmetrie
      );

      expect(result.score, closeTo(1.0, 0.01));
      expect(result.accepted, isTrue);
    });

    test('Schlechte Rep → Score unter minScore', () {
      final result = scorer.score(
        correlation: -0.5, // Negative Korrelation
        prominence: 10.0, // Viel zu niedrig
        durationSamples: 10, // Viel zu kurz
        durationRatio: 0.95, // Sehr asymmetrisch
      );

      expect(result.score, lessThan(0.4));
      expect(result.accepted, isFalse);
    });

    test('Einzel-Scores sind korrekt aufgeteilt', () {
      final result = scorer.score(
        correlation: 0.5,
        prominence: 100.0,
        durationSamples: 50,
        durationRatio: 0.5,
      );

      // correlation=0.5 → corrScore = (0.5+1)/2 = 0.75
      expect(result.correlationScore, closeTo(0.75, 0.01));
      // prominence=100, expected=100 → romScore = 1.0
      expect(result.romScore, closeTo(1.0, 0.01));
      // duration=50, expected=50 → tempoScore = 1.0
      expect(result.tempoScore, closeTo(1.0, 0.01));
      // ratio=0.5 → symmetryScore = 1.0
      expect(result.symmetryScore, closeTo(1.0, 0.01));
    });

    test('updateExpectations ändert erwartete Werte', () {
      scorer.updateExpectations(
        expectedProminence: 200.0,
        expectedDurationSamples: 80.0,
      );

      expect(scorer.expectedProminence, equals(200.0));
      expect(scorer.expectedDurationSamples, equals(80.0));
    });
  });
}

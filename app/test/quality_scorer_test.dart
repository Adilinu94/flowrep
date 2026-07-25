import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/detection/quality_scorer.dart';

void main() {
  group('QualityScorer', () {
    test('a perfect rep (correlation=1, prominence/duration/ratio at '
        'expectation) scores 1.0 and is accepted', () {
      final scorer = QualityScorer(
        expectedProminence: 100.0,
        expectedDurationSamples: 50.0,
      );
      final result = scorer.score(
        correlation: 1.0,
        prominence: 100.0,
        durationSamples: 50,
        durationRatio: 0.5,
      );
      expect(result.score, closeTo(1.0, 0.001));
      expect(result.accepted, isTrue);
    });

    test('worst-possible correlation alone does not sink an otherwise '
        'perfect rep below the default minScore', () {
      final scorer = QualityScorer(
        expectedProminence: 100.0,
        expectedDurationSamples: 50.0,
      );
      final result = scorer.score(
        correlation: -1.0, // corrScore = 0.0
        prominence: 100.0,
        durationSamples: 50,
        durationRatio: 0.5,
      );
      // 0.40*0 + 0.25*1 + 0.20*1 + 0.15*1 = 0.60
      expect(result.score, closeTo(0.60, 0.001));
      expect(result.accepted, isTrue);
    });

    test('a rep that is bad on all four dimensions scores near zero and '
        'is rejected', () {
      final scorer = QualityScorer(
        expectedProminence: 100.0,
        expectedDurationSamples: 50.0,
      );
      final result = scorer.score(
        correlation: -1.0,
        prominence: 0.0,
        durationSamples: 0,
        durationRatio: 1.0,
      );
      expect(result.score, closeTo(0.0, 0.001));
      expect(result.accepted, isFalse);
    });

    test(
        'regression guard (2026-07-25, Policy "Überzählen > Unterzählen"): '
        'a weak-correlation, zero-ROM rep that the OLD minScore=0.4 would '
        'have accepted is now rejected by the raised default (0.55)', () {
      final scorer = QualityScorer(
        expectedProminence: 100.0,
        expectedDurationSamples: 50.0,
      );
      final result = scorer.score(
        correlation: -0.2, // corrScore = 0.4
        prominence: 0.0, // romScore = 0.0 (zero ROM)
        durationSamples: 50, // tempoScore = 1.0
        durationRatio: 0.5, // symmetryScore = 1.0
      );
      // 0.40*0.4 + 0.25*0 + 0.20*1 + 0.15*1 = 0.51
      expect(result.score, closeTo(0.51, 0.001));
      expect(result.score, greaterThanOrEqualTo(0.4),
          reason: 'Sanity: this case must clear the OLD threshold, or the '
              'regression guard proves nothing.');
      expect(result.accepted, isFalse,
          reason: 'Must be rejected under the new minScore=0.55 - if this '
              'is accepted, the Überzählen-Policy tightening regressed.');
    });

    test('romScore penalises overshoot and undershoot of the expected '
        'prominence symmetrically (ROM policy: neither is "extra good")',
        () {
      final scorer = QualityScorer(
        expectedProminence: 100.0,
        expectedDurationSamples: 50.0,
      );
      final under = scorer.score(
        correlation: 1.0,
        prominence: 50.0, // 50% of expected
        durationSamples: 50,
        durationRatio: 0.5,
      );
      final over = scorer.score(
        correlation: 1.0,
        prominence: 150.0, // 150% of expected
        durationSamples: 50,
        durationRatio: 0.5,
      );
      expect(under.romScore, closeTo(0.5, 0.001));
      expect(over.romScore, closeTo(0.5, 0.001));
    });

    test('updateExpectations changes expectedProminence/expectedDuration '
        'used by subsequent score() calls', () {
      final scorer = QualityScorer(
        expectedProminence: 100.0,
        expectedDurationSamples: 50.0,
      );
      scorer.updateExpectations(expectedProminence: 200.0);
      expect(scorer.expectedProminence, 200.0);
      expect(scorer.expectedDurationSamples, 50.0,
          reason: 'Passing only expectedProminence must not touch duration.');

      final result = scorer.score(
        correlation: 1.0,
        prominence: 200.0, // now matches the updated expectation
        durationSamples: 50,
        durationRatio: 0.5,
      );
      expect(result.romScore, closeTo(1.0, 0.001));
    });
  });
}

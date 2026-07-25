import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/detection/phase_validator.dart';

void main() {
  group('PhaseValidator', () {
    test('a window shorter than 4 samples is invalid with a length reason',
        () {
      final validator = PhaseValidator();
      final result = validator.validate([1.0, -1.0]);
      expect(result.valid, isFalse);
      expect(result.rejectionReason, contains('Window zu kurz'));
    });

    test('a purely positive (envelope-style) window is accepted as valid',
        () {
      final validator = PhaseValidator();
      final result = validator.validate([1.0, 2.0, 3.0, 2.0, 1.0]);
      expect(result.valid, isTrue);
      expect(result.negativeDuration, 0);
    });

    test('a balanced positive/negative window (ratio ~0.5) is valid', () {
      final validator = PhaseValidator();
      final window = [
        ...List.filled(10, 1.0),
        ...List.filled(10, -1.0),
      ];
      final result = validator.validate(window);
      expect(result.valid, isTrue);
      expect(result.durationRatio, closeTo(0.5, 0.001));
    });

    test('a phase shorter than minPhaseSamples is rejected with that reason',
        () {
      final validator = PhaseValidator();
      final window = [1.0, ...List.filled(10, -1.0)]; // positive: 1 sample
      final result = validator.validate(window);
      expect(result.valid, isFalse);
      expect(result.rejectionReason, contains('Positive Phase zu kurz'));
    });

    test(
        'regression guard (2026-07-25, Policy "Überzählen > Unterzählen"): '
        'a ratio=0.10 window that the OLD bounds [0.05, 0.99] would have '
        'accepted is now rejected by the tightened default [0.15, 0.85]',
        () {
      final validator = PhaseValidator();
      // 2 positive / 18 negative -> ratio = 0.10.
      final window = [
        ...List.filled(2, 1.0),
        ...List.filled(18, -1.0),
      ];
      final result = validator.validate(window);
      expect(result.durationRatio, closeTo(0.10, 0.001));
      expect(result.durationRatio, greaterThanOrEqualTo(0.05),
          reason: 'Sanity: this case must clear the OLD lower bound, or '
              'the regression guard proves nothing.');
      expect(result.valid, isFalse,
          reason: 'Must be rejected under the new minDurationRatio=0.15 - '
              'if this is valid, the Überzählen-Policy tightening '
              'regressed.');
      expect(result.rejectionReason, contains('asymmetrisch'));
    });

    test('a ratio just inside the tightened bounds (0.20) is valid', () {
      final validator = PhaseValidator();
      // 4 positive / 16 negative -> ratio = 0.20.
      final window = [
        ...List.filled(4, 1.0),
        ...List.filled(16, -1.0),
      ];
      final result = validator.validate(window);
      expect(result.durationRatio, closeTo(0.20, 0.001));
      expect(result.valid, isTrue);
    });

    test('custom bounds passed to the constructor override the defaults',
        () {
      final validator = PhaseValidator(
        minDurationRatio: 0.30,
        maxDurationRatio: 0.70,
      );
      // ratio = 0.20, inside the tightened DEFAULT but outside this custom
      // 0.30 lower bound.
      final window = [
        ...List.filled(4, 1.0),
        ...List.filled(16, -1.0),
      ];
      final result = validator.validate(window);
      expect(result.valid, isFalse);
    });
  });
}

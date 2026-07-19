import 'package:flutter_test/flutter_test.dart';

import 'package:flowrep/data/providers/batch_dedup_tracker.dart';

void main() {
  group('BatchDedupTracker', () {
    test('first batch is never a duplicate', () {
      final tracker = BatchDedupTracker();
      expect(tracker.shouldSkip(1000), isFalse);
      expect(tracker.duplicateSkips, 0);
      expect(tracker.estimatedMissedBatches, 0);
    });

    test('the exact same timestamp read again is a duplicate', () {
      final tracker = BatchDedupTracker();
      tracker.shouldSkip(1000);
      expect(tracker.shouldSkip(1000), isTrue);
      expect(tracker.shouldSkip(1000), isTrue);
      expect(tracker.duplicateSkips, 2);
    });

    test('a new timestamp at the expected interval is not a duplicate and '
        'is not counted as a missed batch', () {
      final tracker = BatchDedupTracker(expectedBatchIntervalMs: 80);
      tracker.shouldSkip(1000);
      expect(tracker.shouldSkip(1080), isFalse);
      expect(tracker.shouldSkip(1160), isFalse);
      expect(tracker.duplicateSkips, 0);
      expect(tracker.estimatedMissedBatches, 0);
    });

    test('small jitter around the expected interval does not falsely '
        'register as a missed batch', () {
      final tracker = BatchDedupTracker(expectedBatchIntervalMs: 80);
      tracker.shouldSkip(1000);
      // A few ms of normal read()-timing jitter, not a real gap.
      expect(tracker.shouldSkip(1090), isFalse);
      expect(tracker.estimatedMissedBatches, 0);
    });

    test(
        'this is the actual S5 case: a gap of several batch intervals is '
        'detected and counted, not silently ignored', () {
      final tracker = BatchDedupTracker(expectedBatchIntervalMs: 80);
      tracker.shouldSkip(1000);
      // 3 batch-intervals later (~240ms) with nothing read in between -
      // 2 batches were likely produced by the firmware and never seen.
      expect(tracker.shouldSkip(1240), isFalse); // still new data, just late
      expect(tracker.estimatedMissedBatches, 2);
    });

    test('a reconnect (timestamp resets to a smaller value) resynchronises '
        'silently instead of reporting a huge negative gap as missed '
        'batches', () {
      final tracker = BatchDedupTracker(expectedBatchIntervalMs: 80);
      tracker.shouldSkip(50000);
      expect(tracker.shouldSkip(80), isFalse); // new session, small timestamp again
      expect(tracker.estimatedMissedBatches, 0);
    });

    test('reset() clears all counters and duplicate-detection state', () {
      final tracker = BatchDedupTracker(expectedBatchIntervalMs: 80);
      tracker.shouldSkip(1000);
      tracker.shouldSkip(1000); // duplicate
      tracker.shouldSkip(1400); // gap -> missed batches
      expect(tracker.duplicateSkips, greaterThan(0));
      expect(tracker.estimatedMissedBatches, greaterThan(0));

      tracker.reset();
      expect(tracker.duplicateSkips, 0);
      expect(tracker.estimatedMissedBatches, 0);
      // And the very next timestamp is treated as a fresh first batch,
      // not compared against pre-reset state.
      expect(tracker.shouldSkip(5), isFalse);
    });
  });
}

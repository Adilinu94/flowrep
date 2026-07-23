import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/vision/tracking_quality.dart';

void main() {
  group('TrackingQualityTracker E3/E5', () {
    test('starts lost and reaches tracking after good frames', () {
      final t = TrackingQualityTracker(
        framesToTrack: 2,
        framesToLose: 3,
        emaAlpha: 1.0, // raw = smoothed for deterministic test
      );
      expect(t.state, TrackingQuality.lost);
      expect(t.update(0.9), TrackingQuality.partial); // first good → partial path
      expect(t.update(0.9), TrackingQuality.tracking);
      expect(t.state, TrackingQuality.tracking);
    });

    test('hysteresis: stays tracking until enough lost frames', () {
      final t = TrackingQualityTracker(
        framesToTrack: 2,
        framesToLose: 3,
        emaAlpha: 1.0,
      );
      t.update(0.9);
      t.update(0.9);
      expect(t.state, TrackingQuality.tracking);

      // single drop should not immediately lose
      expect(t.update(0.0), TrackingQuality.tracking);
      expect(t.update(0.0), TrackingQuality.tracking);
      expect(t.update(0.0), TrackingQuality.lost);
    });

    test('null confidence treated as zero', () {
      final t = TrackingQualityTracker(emaAlpha: 1.0, framesToLose: 1);
      t.update(0.9);
      t.update(0.9);
      expect(t.update(null), anyOf(TrackingQuality.lost, TrackingQuality.partial));
    });

    test('reset clears state', () {
      final t = TrackingQualityTracker(emaAlpha: 1.0, framesToTrack: 1);
      t.update(0.9);
      t.reset();
      expect(t.state, TrackingQuality.lost);
      expect(t.hasSample, isFalse);
    });
  });
}

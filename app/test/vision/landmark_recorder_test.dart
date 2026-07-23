import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/camera_pose_provider.dart';
import 'package:flowrep/data/repositories/landmark_session_recorder.dart';

void main() {
  group('LandmarkSessionRecorder E9', () {
    List<FlowPoseLandmark> fake33() => List.generate(
          33,
          (i) => FlowPoseLandmark(
            x: i / 33,
            y: 0.5,
            confidence: 0.8,
          ),
        );

    test('disabled by default writes nothing', () {
      final sink = MemoryLandmarkSink();
      final rec = LandmarkSessionRecorder(sink: sink, enabled: false);
      final ok = rec.maybeRecord(
        timestampMs: 1000,
        meanConfidence: 0.8,
        landmarks: fake33(),
      );
      expect(ok, isFalse);
      expect(sink.lines, isEmpty);
      expect(rec.framesWritten, 0);
    });

    test('enabled writes header then data via formatFrame', () {
      final sink = MemoryLandmarkSink();
      final rec = LandmarkSessionRecorder(
        sink: sink,
        enabled: true,
        minIntervalMs: 50,
      );
      final lms = fake33();
      expect(
        rec.maybeRecord(
          timestampMs: 1000,
          meanConfidence: 0.75,
          landmarks: lms,
        ),
        isTrue,
      );
      expect(sink.lines.first, LandmarkSessionRecorder.csvHeader);
      expect(sink.lines.length, 2);
      expect(sink.lines[1], startsWith('1000,0.7500,'));
      expect(rec.framesWritten, 1);

      // throttle
      expect(
        rec.maybeRecord(
          timestampMs: 1020,
          meanConfidence: 0.7,
          landmarks: lms,
        ),
        isFalse,
      );
      expect(
        rec.maybeRecord(
          timestampMs: 1100,
          meanConfidence: 0.7,
          landmarks: lms,
        ),
        isTrue,
      );
      expect(rec.framesWritten, 2);
    });

    test('formatFrame is stable schema (33 landmarks)', () {
      final line = LandmarkSessionRecorder.formatFrame(
        timestampMs: 42,
        meanConfidence: 1.0,
        landmarks: fake33(),
      );
      final parts = line.split(',');
      // timestamp + conf + 33*3
      expect(parts.length, 2 + 33 * 3);
    });
  });
}

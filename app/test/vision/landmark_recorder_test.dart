import 'dart:io';

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

    test('FileLandmarkSink grows a real file on disk', () async {
      final dir = await Directory.systemTemp.createTemp('flowrep_lm_');
      final file = File('${dir.path}${Platform.pathSeparator}session.csv');
      final sink = FileLandmarkSink(file);
      final rec = LandmarkSessionRecorder(
        sink: sink,
        enabled: true,
        minIntervalMs: 0,
      );
      expect(rec.outputPath, file.path);
      rec.maybeRecord(
        timestampMs: 1,
        meanConfidence: 0.9,
        landmarks: fake33(),
      );
      rec.maybeRecord(
        timestampMs: 200,
        meanConfidence: 0.8,
        landmarks: fake33(),
      );
      rec.close();

      expect(file.existsSync(), isTrue);
      final body = file.readAsStringSync();
      expect(body, contains('timestampMs'));
      expect(body.trim().split('\n').length, greaterThanOrEqualTo(3));
      expect(file.lengthSync(), greaterThan(50));

      await dir.delete(recursive: true);
    });

    test('LandmarkFilePaths.createSessionFile uses injected base dir', () async {
      final dir = await Directory.systemTemp.createTemp('flowrep_lm_base_');
      final file = await LandmarkFilePaths.createSessionFile(
        getBaseDirectory: () async => dir,
        now: DateTime.utc(2026, 7, 23, 12, 0, 0),
      );
      expect(file.path, contains('landmark_logs'));
      expect(file.path, contains('landmarks_'));
      expect(Directory(file.parent.path).existsSync(), isTrue);
      await dir.delete(recursive: true);
    });
  });
}

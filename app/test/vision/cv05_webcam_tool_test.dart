import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/vision/vision_config.dart';

void main() {
  group('CV-05 webcam tool structural', () {
    test('tools/webcam_rep_counter.py exists with matching thresholds', () {
      final script = File('../tools/webcam_rep_counter.py');
      expect(script.existsSync(), isTrue, reason: 'script at repo tools/');
      final text = script.readAsStringSync();
      const cfg = VisionConfig();
      expect(
        text.contains('ANGLE_DOWN_THRESHOLD = ${cfg.angleDownThreshold.toInt()}') ||
            text.contains('ANGLE_DOWN_THRESHOLD = 160.0'),
        isTrue,
      );
      expect(
        text.contains('ANGLE_UP_THRESHOLD = 90.0'),
        isTrue,
      );
      expect(text.contains('MIN_REP_INTERVAL = 0.5'), isTrue);
      expect(text.contains('def calculate_angle'), isTrue);
      expect(text.contains('class RepCounter'), isTrue);
      // Headless probe + MediaPipe Tasks landmarker (D3 automation path).
      expect(text.contains('--headless'), isTrue);
      expect(text.contains('--max-frames'), isTrue);
      expect(text.contains('PoseLandmarker'), isTrue);
      expect(text.contains('elbow_angle_from_landmarks'), isTrue);
    });

    test('tools/requirements-cv.txt lists mediapipe and opencv', () {
      final req = File('../tools/requirements-cv.txt').readAsStringSync();
      expect(req.contains('mediapipe'), isTrue);
      expect(req.contains('opencv'), isTrue);
    });
  });
}

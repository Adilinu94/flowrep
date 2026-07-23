import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CV structural (CV-01 foundation)', () {
    test('vision domain files exist', () {
      expect(File('lib/domain/vision/vision_config.dart').existsSync(), isTrue);
      expect(
          File('lib/domain/vision/angle_calculator.dart').existsSync(), isTrue);
      expect(
          File('lib/domain/vision/pose_rep_counter.dart').existsSync(), isTrue);
    });

    test('Android CAMERA permission optional', () {
      final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(m.contains('android.permission.CAMERA'), isTrue);
      expect(
        m.contains('android.hardware.camera" android:required="false"') ||
            m.contains("android.hardware.camera' android:required=\"false\"") ||
            m.contains('android:required="false"'),
        isTrue,
      );
    });

    test('iOS camera usage string present', () {
      final p = File('ios/Runner/Info.plist').readAsStringSync();
      expect(p.contains('NSCameraUsageDescription'), isTrue);
      expect(p.contains('lokal verarbeitet'), isTrue);
    });

    test('IMU engines not modified by CV scaffold (file markers)', () {
      // CV must not flip the new pipeline flag.
      final engine = File('lib/domain/workout_engine.dart').readAsStringSync();
      expect(engine.contains('bool _useNewPipeline = false'), isTrue);
    });

    test('live camera session passes real armConfidence (no 0.8 placeholder)',
        () {
      final session =
          File('lib/presentation/screens/camera_session_screen.dart')
              .readAsStringSync();
      expect(session.contains('primaryElbow'), isTrue);
      expect(session.contains('primary.confidence'), isTrue);
      // Hardcoded live-frame placeholder must not reappear.
      expect(session.contains('confidence: 0.8'), isFalse);
      expect(session.contains('confidence:0.8'), isFalse);

      final mapper =
          File('lib/data/providers/camera_pose_provider.dart').readAsStringSync();
      expect(mapper.contains('armConfidence'), isTrue);
      expect(mapper.contains('confidence: l.visibility'), isTrue);
      expect(mapper.contains('primaryElbow'), isTrue);
    });
  });
}

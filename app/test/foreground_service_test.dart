import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';
import 'package:flowrep/data/services/foreground_service_manager.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/repositories/i_workout_repository.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:flowrep/presentation/providers/engine_provider.dart';

class _NoopRepo implements IWorkoutRepository {
  @override
  Future<void> saveCorrection(CorrectionEvent event) async {}

  @override
  Future<void> saveSession(WorkoutSession session) async {}

  @override
  Future<List<WorkoutSession>> getHistory() async => const [];

  @override
  Future<void> deleteAllUserData() async {}
}

void main() {
  group('ForegroundServiceManager (P0-5)', () {
    setUp(() {
      ForegroundServiceManager.debugSkipPlatform = true;
    });

    tearDown(() {
      ForegroundServiceManager.debugSkipPlatform = false;
    });

    test('start/stop toggles isRunning without platform', () async {
      final mgr = ForegroundServiceManager();
      expect(mgr.isRunning, isFalse);
      await mgr.start();
      expect(mgr.isRunning, isTrue);
      await mgr.start(); // idempotent
      expect(mgr.isRunning, isTrue);
      await mgr.stop();
      expect(mgr.isRunning, isFalse);
    });
  });

  group('EngineNotifier FGS lifecycle (P0-5)', () {
    late EngineNotifier notifier;

    setUp(() {
      ForegroundServiceManager.debugSkipPlatform = true;
      notifier = EngineNotifier.create(
        sensorProvider: MockSensorProvider(),
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
        repository: _NoopRepo(),
      );
    });

    tearDown(() {
      notifier.dispose();
      ForegroundServiceManager.debugSkipPlatform = false;
    });

    test('startCounting starts FGS; stopCounting stops it', () async {
      expect(notifier.debugFgService.isRunning, isFalse);
      notifier.startCounting();
      // unawaited start — yield microtask
      await Future<void>.delayed(Duration.zero);
      expect(notifier.debugFgService.isRunning, isTrue);

      notifier.stopCounting();
      await Future<void>.delayed(Duration.zero);
      expect(notifier.debugFgService.isRunning, isFalse);
    });

    test('endSession stops FGS', () async {
      notifier.startCounting();
      await Future<void>.delayed(Duration.zero);
      expect(notifier.debugFgService.isRunning, isTrue);
      await notifier.endSession();
      expect(notifier.debugFgService.isRunning, isFalse);
    });
  });

  group('P0-5 structural wiring', () {
    test('pubspec declares flutter_foreground_task', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('flutter_foreground_task:'), isTrue);
    });

    test('AndroidManifest has connectedDevice ForegroundService', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(
        manifest.contains(
          'com.pravera.flutter_foreground_task.service.ForegroundService',
        ),
        isTrue,
      );
      expect(manifest.contains('connectedDevice'), isTrue);
      expect(
        manifest.contains('FOREGROUND_SERVICE_CONNECTED_DEVICE'),
        isTrue,
      );
    });

    test('engine_provider wires fgService start/stop', () {
      final src =
          File('lib/presentation/providers/engine_provider.dart')
              .readAsStringSync();
      expect(src.contains('ForegroundServiceManager'), isTrue);
      expect(src.contains('_fgService.start()'), isTrue);
      expect(src.contains('_fgService.stop()'), isTrue);
    });
  });
}

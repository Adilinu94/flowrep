import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/repositories/i_workout_repository.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:flowrep/presentation/providers/engine_provider.dart';
import 'package:flowrep/presentation/providers/lifecycle_provider.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLifecycleObserver (P1-2)', () {
    test('forwards lifecycle events and dispose is safe', () {
      AppLifecycleState? last;
      final observer = AppLifecycleObserver(
        onStateChanged: (s) => last = s,
      );
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(last, AppLifecycleState.paused);
      observer.dispose();
      // Second dispose would fail if not careful — only dispose once.
    });
  });

  group('EngineNotifier lifecycle rest-timer (P1-2)', () {
    late EngineNotifier notifier;

    setUp(() {
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
    });

    test('paused freezes rest countdown; resumed continues', () async {
      notifier.debugSetRestDurationSeconds(10);
      notifier.showCorrectionForLastSet(3);
      notifier.dismissCorrection();
      expect(notifier.state.isRestTimerActive, isTrue);
      final before = notifier.state.restTimerSecondsRemaining;

      notifier.debugOnAppLifecycle(AppLifecycleState.paused);
      // Timer cancelled — wait would not decrement
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(notifier.state.restTimerSecondsRemaining, before);

      notifier.debugOnAppLifecycle(AppLifecycleState.resumed);
      expect(notifier.state.isRestTimerActive, isTrue);
      expect(notifier.state.restTimerSecondsRemaining, before);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/repositories/i_workout_repository.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:flowrep/presentation/providers/engine_provider.dart';
import 'package:flowrep/presentation/widgets/rest_timer_widget.dart';

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
  group('EngineNotifier Rest-Timer (P0-2)', () {
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

    test('dismissCorrection startet Rest-Timer mit Default 90s', () {
      notifier.showCorrectionForLastSet(8);
      notifier.dismissCorrection();
      expect(notifier.state.showCorrectionDialog, isFalse);
      expect(notifier.state.isRestTimerActive, isTrue);
      expect(notifier.state.restTimerSecondsRemaining, 90);
    });

    test('confirmCorrection startet Rest-Timer (via dismiss)', () async {
      notifier.debugAddCompletedSet(
        ExerciseSet(
          id: 's1',
          exerciseId: 'bicep_curl',
          countedReps: 5,
          endedAt: DateTime.now(),
          reps: [],
        ),
      );
      notifier.showCorrectionForLastSet(5);
      await notifier.confirmCorrection();
      expect(notifier.state.isRestTimerActive, isTrue);
      expect(notifier.state.restTimerSecondsRemaining, 90);
    });

    test('skipRest stoppt den Timer', () {
      notifier.showCorrectionForLastSet(3);
      notifier.dismissCorrection();
      expect(notifier.state.isRestTimerActive, isTrue);
      notifier.skipRest();
      expect(notifier.state.isRestTimerActive, isFalse);
    });

    test('startCounting stoppt aktiven Rest-Timer', () {
      notifier.showCorrectionForLastSet(3);
      notifier.dismissCorrection();
      expect(notifier.state.isRestTimerActive, isTrue);
      notifier.startCounting();
      expect(notifier.state.isCountingActive, isTrue);
      expect(notifier.state.isRestTimerActive, isFalse);
    });

    test('Rest-Timer zählt herunter und endet bei 0', () async {
      notifier.debugSetRestDurationSeconds(2);
      notifier.showCorrectionForLastSet(1);
      notifier.dismissCorrection();
      expect(notifier.state.restTimerSecondsRemaining, 2);
      expect(notifier.state.isRestTimerActive, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(notifier.state.restTimerSecondsRemaining, 1);
      expect(notifier.state.isRestTimerActive, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(notifier.state.isRestTimerActive, isFalse);
    });

    test('dispose cancelt Rest-Timer ohne Exception', () {
      notifier.showCorrectionForLastSet(2);
      notifier.dismissCorrection();
      expect(notifier.state.isRestTimerActive, isTrue);
      notifier.dispose();
      // Second dispose not called; tearDown skipped via reassignment
      // Create fresh to satisfy tearDown pattern:
      notifier = EngineNotifier.create(
        sensorProvider: MockSensorProvider(),
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
        repository: _NoopRepo(),
      );
    });
  });

  group('RestTimerWidget', () {
    testWidgets('zeigt Countdown und Skip-Button', (tester) async {
      var skipped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RestTimerWidget(
              secondsRemaining: 90,
              totalSeconds: 90,
              onSkip: () => skipped = true,
            ),
          ),
        ),
      );
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);
      await tester.tap(find.text('Pause überspringen'));
      expect(skipped, isTrue);
    });
  });
}

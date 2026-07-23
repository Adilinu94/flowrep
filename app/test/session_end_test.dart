import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/repositories/i_workout_repository.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:flowrep/presentation/providers/engine_provider.dart';
import 'package:flowrep/presentation/widgets/session_summary_dialog.dart';

class _CapturingRepo implements IWorkoutRepository {
  final List<WorkoutSession> sessions = [];
  final List<CorrectionEvent> corrections = [];

  @override
  Future<void> saveCorrection(CorrectionEvent event) async {
    corrections.add(event);
  }

  @override
  Future<void> saveSession(WorkoutSession session) async {
    sessions.add(session);
  }

  @override
  Future<List<WorkoutSession>> getHistory() async =>
      List.unmodifiable(sessions);

  @override
  Future<void> deleteAllUserData() async {
    sessions.clear();
    corrections.clear();
  }
}

void main() {
  group('EngineNotifier endSession (P0-3)', () {
    late EngineNotifier notifier;
    late _CapturingRepo repo;

    setUp(() {
      repo = _CapturingRepo();
      notifier = EngineNotifier.create(
        sensorProvider: MockSensorProvider(),
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
        repository: repo,
      );
    });

    tearDown(() {
      notifier.dispose();
    });

    test('aggregiert Sets mit effectiveReps und speichert Session', () async {
      notifier.debugAddCompletedSet(
        ExerciseSet(
          id: 'a',
          exerciseId: 'bicep_curl',
          countedReps: 10,
          correctedReps: 9,
          endedAt: DateTime.now(),
          reps: [],
        ),
      );
      notifier.debugAddCompletedSet(
        ExerciseSet(
          id: 'b',
          exerciseId: 'bicep_curl',
          countedReps: 8,
          endedAt: DateTime.now(),
          reps: [],
        ),
      );

      await notifier.endSession();

      expect(notifier.state.showSessionSummary, isTrue);
      expect(notifier.state.sessionTotalSets, 2);
      // 9 (corrected) + 8 (uncorrected) = 17
      expect(notifier.state.sessionTotalReps, 17);
      expect(notifier.state.sessionDuration, isNotNull);
      expect(notifier.state.isCountingActive, isFalse);
      expect(notifier.state.isRestTimerActive, isFalse);

      expect(repo.sessions, hasLength(1));
      expect(repo.sessions.single.sets, hasLength(2));
      expect(repo.sessions.single.endedAt, isNotNull);
      expect(repo.sessions.single.sets.first.effectiveReps, 9);
      expect(repo.sessions.single.sets.first.countedReps, 10);
    });

    test('ohne Sets: Summary 0, kein saveSession', () async {
      await notifier.endSession();
      expect(notifier.state.sessionTotalSets, 0);
      expect(notifier.state.sessionTotalReps, 0);
      expect(notifier.state.showSessionSummary, isTrue);
      expect(repo.sessions, isEmpty);
    });

    test('stoppt Counting und Rest-Timer', () async {
      notifier.startCounting();
      notifier.showCorrectionForLastSet(5);
      notifier.dismissCorrection();
      expect(notifier.state.isRestTimerActive, isTrue);

      await notifier.endSession();
      expect(notifier.state.isCountingActive, isFalse);
      expect(notifier.state.isRestTimerActive, isFalse);
      expect(notifier.state.showCorrectionDialog, isFalse);
    });

    test('dismissSessionSummary schließt Summary', () async {
      await notifier.endSession();
      expect(notifier.state.showSessionSummary, isTrue);
      notifier.dismissSessionSummary();
      expect(notifier.state.showSessionSummary, isFalse);
    });

    test('nach endSession sind completedSets geleert', () async {
      notifier.debugAddCompletedSet(
        ExerciseSet(
          id: 'x',
          exerciseId: 'bicep_curl',
          countedReps: 3,
          endedAt: DateTime.now(),
          reps: [],
        ),
      );
      await notifier.endSession();
      expect(notifier.debugCompletedSets, isEmpty);
    });
  });

  group('SessionSummaryDialog', () {
    testWidgets('zeigt Sätze und Wiederholungen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionSummaryDialog(
              totalSets: 3,
              totalReps: 24,
              duration: const Duration(minutes: 12),
              onDismiss: () {},
            ),
          ),
        ),
      );
      expect(find.text('Training beendet'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
      expect(find.text('12 min'), findsOneWidget);
      expect(find.text('Fertig'), findsOneWidget);
    });
  });
}

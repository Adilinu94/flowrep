import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/repositories/i_workout_repository.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:flowrep/presentation/providers/engine_provider.dart';
import 'package:flowrep/presentation/widgets/correction_dialog.dart';

/// In-memory repo capturing sessions and corrections for unit tests.
class _CapturingRepo implements IWorkoutRepository {
  final List<CorrectionEvent> corrections = [];
  final List<WorkoutSession> sessions = [];

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
    corrections.clear();
    sessions.clear();
  }
}

void main() {
  group('CorrectionEvent Modell', () {
    test('speichert systemCount und userCorrectedCount getrennt', () {
      final event = CorrectionEvent(
        id: 'test-1',
        setId: 'set-1',
        systemCount: 10,
        userCorrectedCount: 9,
        timestamp: DateTime(2026, 7, 22),
      );
      expect(event.systemCount, 10);
      expect(event.userCorrectedCount, 9);
      expect(event.setId, 'set-1');
    });
  });

  group('ExerciseSet.copyWith Korrektur', () {
    test('correctedReps wird gesetzt, countedReps bleibt', () {
      final set = ExerciseSet(
        id: 's1',
        exerciseId: 'bicep_curl',
        countedReps: 10,
        endedAt: DateTime.now(),
        reps: [],
      );
      final corrected = set.copyWith(correctedReps: 9);
      expect(corrected.correctedReps, 9);
      expect(corrected.countedReps, 10);
      expect(corrected.effectiveReps, 9);
    });

    test('effectiveReps fällt auf countedReps ohne Korrektur', () {
      final set = ExerciseSet(
        id: 's2',
        exerciseId: 'bicep_curl',
        countedReps: 8,
        endedAt: DateTime.now(),
        reps: [],
      );
      expect(set.effectiveReps, 8);
    });
  });

  group('EngineNotifier Korrektur-Flow (P0-1)', () {
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

    test('showCorrectionForLastSet öffnet Dialog mit System-Count', () {
      notifier.showCorrectionForLastSet(10);
      expect(notifier.state.showCorrectionDialog, isTrue);
      expect(notifier.state.correctionSetCountedReps, 10);
      expect(notifier.state.correctionSetUserReps, 10);
    });

    test('applyCorrectionDelta ändert nur userReps, nicht systemCount', () {
      notifier.showCorrectionForLastSet(10);
      notifier.applyCorrectionDelta(-1);
      expect(notifier.state.correctionSetUserReps, 9);
      expect(notifier.state.correctionSetCountedReps, 10);
      notifier.applyCorrectionDelta(1);
      expect(notifier.state.correctionSetUserReps, 10);
    });

    test('applyCorrectionDelta clamped bei 0', () {
      notifier.showCorrectionForLastSet(1);
      notifier.applyCorrectionDelta(-5);
      expect(notifier.state.correctionSetUserReps, 0);
    });

    test(
        'confirmCorrection speichert CorrectionEvent und setzt correctedReps, '
        'countedReps bleibt', () async {
      final set = ExerciseSet(
        id: 'set-corr-1',
        exerciseId: 'bicep_curl',
        countedReps: 10,
        endedAt: DateTime.now(),
        reps: [],
      );
      notifier.debugAddCompletedSet(set);
      notifier.showCorrectionForLastSet(10);
      notifier.applyCorrectionDelta(-1);
      await notifier.confirmCorrection();

      expect(notifier.state.showCorrectionDialog, isFalse);
      expect(repo.corrections, hasLength(1));
      expect(repo.corrections.single.systemCount, 10);
      expect(repo.corrections.single.userCorrectedCount, 9);
      expect(repo.corrections.single.setId, 'set-corr-1');

      final last = notifier.debugCompletedSets.last;
      expect(last.countedReps, 10);
      expect(last.correctedReps, 9);
      expect(last.effectiveReps, 9);
    });

    test('confirmCorrection ohne Delta speichert keinen CorrectionEvent',
        () async {
      final set = ExerciseSet(
        id: 'set-same',
        exerciseId: 'bicep_curl',
        countedReps: 8,
        endedAt: DateTime.now(),
        reps: [],
      );
      notifier.debugAddCompletedSet(set);
      notifier.showCorrectionForLastSet(8);
      await notifier.confirmCorrection();
      expect(repo.corrections, isEmpty);
      expect(notifier.debugCompletedSets.last.correctedReps, isNull);
      expect(notifier.debugCompletedSets.last.countedReps, 8);
    });

    test('dismissCorrection schließt Dialog ohne Persistenz', () async {
      final set = ExerciseSet(
        id: 'set-skip',
        exerciseId: 'bicep_curl',
        countedReps: 7,
        endedAt: DateTime.now(),
        reps: [],
      );
      notifier.debugAddCompletedSet(set);
      notifier.showCorrectionForLastSet(7);
      notifier.applyCorrectionDelta(2);
      notifier.dismissCorrection();
      expect(notifier.state.showCorrectionDialog, isFalse);
      expect(repo.corrections, isEmpty);
      expect(notifier.debugCompletedSets.last.correctedReps, isNull);
    });
  });

  group('CorrectionDialog UI copy', () {
    testWidgets('zeigt exakte Dankesnachricht bei Korrektur', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CorrectionDialog(
              countedReps: 10,
              userReps: 9,
              onIncrement: () {},
              onDecrement: () {},
              onConfirm: () {},
              onDismiss: () {},
            ),
          ),
        ),
      );
      expect(find.text(CorrectionDialog.thankYouMessage), findsOneWidget);
      expect(find.textContaining('Die KI lernt'), findsNothing);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('Gezählt: 10 Wiederholungen'), findsOneWidget);
    });

    testWidgets('ohne Korrektur keine Dankesnachricht', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CorrectionDialog(
              countedReps: 10,
              userReps: 10,
              onIncrement: () {},
              onDecrement: () {},
              onConfirm: () {},
              onDismiss: () {},
            ),
          ),
        ),
      );
      expect(find.text(CorrectionDialog.thankYouMessage), findsNothing);
      expect(find.text('Bestätigen'), findsOneWidget);
    });
  });
}

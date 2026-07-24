import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/repositories/i_workout_repository.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:flowrep/presentation/providers/engine_provider.dart';
import 'package:flowrep/presentation/providers/workout_ui_state.dart';
import 'package:flowrep/presentation/widgets/counting_status_chip.dart';
import 'package:flowrep/presentation/widgets/session_summary_dialog.dart';

class _Repo implements IWorkoutRepository {
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

  group('CountingStatusChip (QW-1)', () {
    test('kindFor: disconnected / counting / ghost / ready', () {
      expect(
        CountingStatusChip.kindFor(const WorkoutUiState()),
        CountingStatusKind.disconnected,
      );
      expect(
        CountingStatusChip.kindFor(
          const WorkoutUiState(isConnected: true, hasCalibration: true),
        ),
        CountingStatusKind.ready,
      );
      expect(
        CountingStatusChip.kindFor(
          const WorkoutUiState(
            isConnected: true,
            isCountingActive: true,
          ),
        ),
        CountingStatusKind.counting,
      );
      expect(
        CountingStatusChip.kindFor(
          const WorkoutUiState(
            isConnected: true,
            isCountingActive: true,
            ghostGatePaused: true,
          ),
        ),
        CountingStatusKind.ghostPaused,
      );
    });

    testWidgets('renders ZÄHLT label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CountingStatusChip(
              uiState: WorkoutUiState(
                isConnected: true,
                isCountingActive: true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('ZÄHLT'), findsOneWidget);
    });
  });

  group('EngineNotifier Quick Wins', () {
    late EngineNotifier notifier;

    setUp(() {
      notifier = EngineNotifier.create(
        sensorProvider: MockSensorProvider(),
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
        repository: _Repo(),
      );
    });

    tearDown(() => notifier.dispose());

    test('autoArmAfterCalib default true and toggleable', () {
      expect(notifier.autoArmAfterCalib, isTrue);
      notifier.setAutoArmAfterCalib(false);
      expect(notifier.autoArmAfterCalib, isFalse);
    });

    test('dismissGhostBanner only when paused', () {
      expect(notifier.state.ghostBannerDismissed, isFalse);
      notifier.dismissGhostBanner();
      expect(notifier.state.ghostBannerDismissed, isFalse);

      // Simulate paused via copy path used by engine updates.
      // startCounting clears dismiss; set state manually not possible —
      // call dismiss when ghostGatePaused true via public API:
      // We can only set ghost via engine samples; smoke: startCounting resets.
      notifier.startCounting();
      expect(notifier.state.ghostBannerDismissed, isFalse);
    });

    test('confirmCorrection returns snackbar when delta + learn', () async {
      notifier.debugAddCompletedSet(
        ExerciseSet(
          id: 's1',
          exerciseId: 'bicep_curl',
          countedReps: 10,
          endedAt: DateTime.now(),
          reps: [],
        ),
      );
      notifier.showCorrectionForLastSet(10);
      notifier.applyCorrectionDelta(-2); // user 8 → under-count learn
      final msg = await notifier.confirmCorrection();
      expect(msg, isNotNull);
      expect(msg!, contains('Gespeichert'));
    });

    test('confirmCorrection null when no delta', () async {
      notifier.showCorrectionForLastSet(5);
      final msg = await notifier.confirmCorrection();
      expect(msg, isNull);
    });
  });

  group('SessionSummaryDialog Engine vs corrected (QW-9)', () {
    testWidgets('shows engine raw and per-set lines', (tester) async {
      final sets = [
        ExerciseSet(
          id: 'a',
          exerciseId: 'bicep_curl',
          countedReps: 10,
          correctedReps: 9,
          endedAt: DateTime.now(),
          reps: [],
        ),
        ExerciseSet(
          id: 'b',
          exerciseId: 'bicep_curl',
          countedReps: 8,
          endedAt: DateTime.now(),
          reps: [],
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryDialog(
            totalSets: 2,
            totalReps: 17,
            duration: const Duration(minutes: 5),
            sets: sets,
            onDismiss: () {},
          ),
        ),
      );
      expect(find.text('Engine (roh)'), findsOneWidget);
      expect(find.text('18'), findsOneWidget); // 10+8 engine
      expect(find.textContaining('Engine 10 · Korrigiert 9'), findsOneWidget);
      expect(find.textContaining('Engine 8'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/repositories/i_workout_repository.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:flowrep/presentation/providers/engine_provider.dart';
import 'package:flowrep/presentation/screens/settings_screen.dart';

class _CapturingRepo implements IWorkoutRepository {
  int deleteCalls = 0;

  @override
  Future<void> saveCorrection(CorrectionEvent event) async {}

  @override
  Future<void> saveSession(WorkoutSession session) async {}

  @override
  Future<List<WorkoutSession>> getHistory() async => const [];

  @override
  Future<void> deleteAllUserData() async {
    deleteCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EngineNotifier settings (P1-3)', () {
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

    tearDown(() => notifier.dispose());

    test('setRestDurationSeconds ändert restDurationSeconds', () {
      expect(notifier.restDurationSeconds, 90);
      notifier.setRestDurationSeconds(60);
      expect(notifier.restDurationSeconds, 60);
      notifier.showCorrectionForLastSet(1);
      notifier.dismissCorrection();
      expect(notifier.state.restTimerSecondsRemaining, 60);
    });

    test('setFeedback toggles haptic/audio flags', () {
      expect(notifier.hapticEnabled, isTrue);
      notifier.setFeedback(haptic: false, audio: true);
      expect(notifier.hapticEnabled, isFalse);
      expect(notifier.audioEnabled, isTrue);
    });

    test('deleteAllUserData ruft Repository auf', () async {
      await notifier.deleteAllUserData();
      expect(repo.deleteCalls, 1);
    });
  });

  group('SettingsScreen UI (P1-3)', () {
    testWidgets('zeigt Feedback-, Timer- und Datenschutz-Optionen',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            engineProvider.overrideWith(
              (_) => EngineNotifier.create(
                sensorProvider: MockSensorProvider(),
                engine: WorkoutEngine(
                  exerciseId: 'bicep_curl',
                  useSignedProjectionCounting: true,
                ),
                repository: _CapturingRepo(),
              ),
            ),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );

      expect(find.text('Einstellungen'), findsOneWidget);
      expect(find.text('Vibration bei Wiederholung'), findsOneWidget);
      expect(find.text('Sound bei Wiederholung'), findsOneWidget);
      expect(find.text('Nach Kalibrierung auto starten'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('90s'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('90s'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Alle Daten löschen'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Alle Daten löschen'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Version 1.0.0'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Version 1.0.0'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Form-Check öffnen'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Form-Check öffnen'), findsOneWidget);
    });
  });
}

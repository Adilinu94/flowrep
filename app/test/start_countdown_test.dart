import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/repositories/i_workout_repository.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:flowrep/presentation/providers/engine_provider.dart';
import 'package:flowrep/presentation/widgets/start_countdown_button.dart';

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
  group('EngineNotifier Start-Countdown (Bauplan Phase 2)', () {
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

    test('beginStartCountdown startet Countdown mit Default-Dauer 3s', () {
      notifier.beginStartCountdown();
      expect(notifier.state.isStartCountdownActive, isTrue);
      expect(notifier.state.startCountdownSecondsRemaining, 3);
      expect(notifier.state.isCountingActive, isFalse);
    });

    test('Countdown zählt herunter und ruft danach startCounting auf',
        () async {
      notifier.debugSetStartCountdownSeconds(2);
      notifier.beginStartCountdown();
      expect(notifier.state.startCountdownSecondsRemaining, 2);

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(notifier.state.startCountdownSecondsRemaining, 1);
      expect(notifier.state.isCountingActive, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(notifier.state.isStartCountdownActive, isFalse);
      expect(notifier.state.isCountingActive, isTrue);
    });

    test('beginStartCountdown ist No-Op wenn bereits am Zählen', () {
      notifier.startCounting();
      expect(notifier.state.isCountingActive, isTrue);
      notifier.beginStartCountdown();
      expect(notifier.state.isStartCountdownActive, isFalse);
      expect(notifier.state.isCountingActive, isTrue);
    });

    test('startCounting bricht einen laufenden Countdown sauber ab', () {
      notifier.beginStartCountdown();
      expect(notifier.state.isStartCountdownActive, isTrue);
      notifier.startCounting();
      expect(notifier.state.isCountingActive, isTrue);
      expect(notifier.state.isStartCountdownActive, isFalse);
    });

    test('dispose cancelt Start-Countdown ohne Exception', () {
      notifier.beginStartCountdown();
      expect(notifier.state.isStartCountdownActive, isTrue);
      notifier.dispose();
      // Frisch anlegen, damit tearDown() nicht doppelt dispose()t:
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

  group('StartCountdownButton', () {
    testWidgets('ohne Kalibrierung: Button sichtbar aber deaktiviert',
        (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StartCountdownButton(
              enabled: false,
              isCountdownActive: false,
              secondsRemaining: 3,
              onPressed: () => pressed = true,
            ),
          ),
        ),
      );
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(button.onPressed, isNull);
      await tester.tap(find.text('Zählen starten'), warnIfMissed: false);
      expect(pressed, isFalse);
    });

    testWidgets('mit Kalibrierung: Tap ruft onPressed auf', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StartCountdownButton(
              enabled: true,
              isCountdownActive: false,
              secondsRemaining: 3,
              onPressed: () => pressed = true,
            ),
          ),
        ),
      );
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(button.onPressed, isNotNull);
      await tester.tap(find.text('Zählen starten'));
      expect(pressed, isTrue);
    });

    testWidgets('während Countdown: zeigt Zahl statt Button',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StartCountdownButton(
              enabled: true,
              isCountdownActive: true,
              secondsRemaining: 2,
              onPressed: () {},
            ),
          ),
        ),
      );
      expect(find.text('Start in 2…'), findsOneWidget);
      expect(find.text('Zählen starten'), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/state/workout_state_machine.dart';

void main() {
  group('WorkoutStateMachine', () {
    late WorkoutStateMachine sm;

    setUp(() {
      sm = WorkoutStateMachine(hasValidCalibration: false);
    });

    test('Startet im idle-Zustand', () {
      expect(sm.currentState, equals(WorkoutState.idle));
    });

    test('idle → calibrating bei Bewegung ohne Kalibrierung', () {
      final newState = sm.handleEvent(
        MovementDetected(hasValidCalibration: false),
      );
      expect(newState, equals(WorkoutState.calibrating));
    });

    test('idle → active bei Bewegung mit Kalibrierung', () {
      final smCalibrated = WorkoutStateMachine(hasValidCalibration: true);
      final newState = smCalibrated.handleEvent(
        MovementDetected(hasValidCalibration: true),
      );
      expect(newState, equals(WorkoutState.active));
    });

    test('idle → guidedCalibration bei GuidedCalibrationStarted', () {
      final newState = sm.handleEvent(GuidedCalibrationStarted());
      expect(newState, equals(WorkoutState.guidedCalibration));
    });

    test('calibrating → active bei CalibrationRepComplete', () {
      sm.handleEvent(MovementDetected(hasValidCalibration: false));
      expect(sm.currentState, equals(WorkoutState.calibrating));

      final newState = sm.handleEvent(CalibrationRepComplete(repCount: 1));
      expect(newState, equals(WorkoutState.active));
    });

    test('calibrating → active bei CalibrationComplete', () {
      sm.handleEvent(MovementDetected(hasValidCalibration: false));
      final newState = sm.handleEvent(CalibrationComplete(threshold: 5.0));
      expect(newState, equals(WorkoutState.active));
    });

    test('active → active bei RepCounted (bleibt)', () {
      sm.handleEvent(MovementDetected(hasValidCalibration: true));
      // Direkt zu active (hasValidCalibration im Event überschreibt)
      final sm2 = WorkoutStateMachine(hasValidCalibration: true);
      sm2.handleEvent(MovementDetected(hasValidCalibration: true));
      expect(sm2.currentState, equals(WorkoutState.active));

      final newState = sm2.handleEvent(RepCounted(repNumber: 1));
      expect(newState, equals(WorkoutState.active));
      expect(sm2.lastRepAt, isNotNull);
    });

    test('active → resting bei PauseTimeout', () {
      final sm2 = WorkoutStateMachine(hasValidCalibration: true);
      sm2.handleEvent(MovementDetected(hasValidCalibration: true));
      expect(sm2.currentState, equals(WorkoutState.active));

      final newState = sm2.handleEvent(
        PauseTimeout(elapsed: const Duration(seconds: 5)),
      );
      expect(newState, equals(WorkoutState.resting));
    });

    test('active → paused bei UserPaused', () {
      final sm2 = WorkoutStateMachine(hasValidCalibration: true);
      sm2.handleEvent(MovementDetected(hasValidCalibration: true));

      final newState = sm2.handleEvent(UserPaused());
      expect(newState, equals(WorkoutState.paused));
    });

    test('resting → active bei MovementDetected', () {
      final sm2 = WorkoutStateMachine(hasValidCalibration: true);
      sm2.handleEvent(MovementDetected(hasValidCalibration: true));
      sm2.handleEvent(PauseTimeout(elapsed: const Duration(seconds: 5)));
      expect(sm2.currentState, equals(WorkoutState.resting));

      final newState = sm2.handleEvent(
        MovementDetected(hasValidCalibration: true),
      );
      expect(newState, equals(WorkoutState.active));
    });

    test('resting → idle bei RestTimerExpired', () {
      final sm2 = WorkoutStateMachine(hasValidCalibration: true);
      sm2.handleEvent(MovementDetected(hasValidCalibration: true));
      sm2.handleEvent(PauseTimeout(elapsed: const Duration(seconds: 5)));

      final newState = sm2.handleEvent(RestTimerExpired());
      expect(newState, equals(WorkoutState.idle));
    });

    test('paused → active bei UserResumed', () {
      final sm2 = WorkoutStateMachine(hasValidCalibration: true);
      sm2.handleEvent(MovementDetected(hasValidCalibration: true));
      sm2.handleEvent(UserPaused());
      expect(sm2.currentState, equals(WorkoutState.paused));

      final newState = sm2.handleEvent(UserResumed());
      expect(newState, equals(WorkoutState.active));
    });

    test('guidedCalibration → idle bei GuidedCalibrationFinished', () {
      sm.handleEvent(GuidedCalibrationStarted());
      expect(sm.currentState, equals(WorkoutState.guidedCalibration));

      final newState = sm.handleEvent(GuidedCalibrationFinished());
      expect(newState, equals(WorkoutState.idle));
    });

    test('connectionLost → idle bei ConnectionRestored', () {
      sm.handleEvent(ConnectionLostEvent());
      expect(sm.currentState, equals(WorkoutState.connectionLost));

      final newState = sm.handleEvent(ConnectionRestored());
      expect(newState, equals(WorkoutState.idle));
    });

    test('ConnectionLost von jedem Zustand möglich', () {
      // Von active
      final sm2 = WorkoutStateMachine(hasValidCalibration: true);
      sm2.handleEvent(MovementDetected(hasValidCalibration: true));
      sm2.handleEvent(ConnectionLostEvent());
      expect(sm2.currentState, equals(WorkoutState.connectionLost));
    });

    test('reset() setzt auf idle zurück', () {
      final sm2 = WorkoutStateMachine(hasValidCalibration: true);
      sm2.handleEvent(MovementDetected(hasValidCalibration: true));
      sm2.handleEvent(RepCounted(repNumber: 1));
      expect(sm2.currentState, equals(WorkoutState.active));

      sm2.reset();
      expect(sm2.currentState, equals(WorkoutState.idle));
      expect(sm2.lastRepAt, isNull);
    });

    test('isPauseTimeoutReached prüft korrekt', () {
      final sm2 = WorkoutStateMachine(
        hasValidCalibration: true,
        pauseTimeout: const Duration(seconds: 4),
      );
      sm2.handleEvent(MovementDetected(hasValidCalibration: true));
      sm2.handleEvent(RepCounted(repNumber: 1));

      // Direkt nach Rep: kein Timeout
      expect(sm2.isPauseTimeoutReached(), isFalse);

      // Nach 5 Sekunden: Timeout erreicht
      final future = sm2.lastRepAt!.add(const Duration(seconds: 5));
      expect(sm2.isPauseTimeoutReached(now: future), isTrue);
    });

    test('lastTransitionAt wird aktualisiert', () {
      final before = DateTime.now();
      sm.handleEvent(MovementDetected(hasValidCalibration: false));
      final after = DateTime.now();

      expect(sm.lastTransitionAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(sm.lastTransitionAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });
  });
}

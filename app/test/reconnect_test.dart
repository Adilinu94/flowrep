import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/repositories/i_workout_repository.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:flowrep/presentation/providers/engine_provider.dart';

/// Controllable sensor for reconnect unit tests (no 2s mock delay).
class ControllableSensorProvider implements ISensorProvider {
  final _connectionController =
      StreamController<SensorConnectionState>.broadcast();
  final _sampleController = StreamController<SensorSample>.broadcast();
  int connectCalls = 0;
  bool failNextConnect = false;

  @override
  Stream<SensorConnectionState> get connectionState =>
      _connectionController.stream;

  @override
  Stream<SensorSample> get samples => _sampleController.stream;

  @override
  Future<void> connect() async {
    connectCalls++;
    if (failNextConnect) {
      failNextConnect = false;
      _connectionController.add(SensorConnectionState.connecting);
      _connectionController.add(SensorConnectionState.disconnected);
      throw Exception('connect failed');
    }
    _connectionController.add(SensorConnectionState.connecting);
    _connectionController.add(SensorConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    _connectionController.add(SensorConnectionState.disconnected);
  }

  /// Unexpected drop (not via disconnect()) — simulates BLE loss.
  void emitUnexpectedDisconnect() {
    _connectionController.add(SensorConnectionState.disconnected);
  }

  @override
  Future<int> readBatteryPercent() async => 80;

  @override
  void simulateRepetition() {}

  void dispose() {
    _connectionController.close();
    _sampleController.close();
  }
}

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
  group('EngineNotifier Reconnect (P0-4)', () {
    late ControllableSensorProvider sensor;
    late EngineNotifier notifier;

    setUp(() {
      sensor = ControllableSensorProvider();
      notifier = EngineNotifier.create(
        sensorProvider: sensor,
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
        repository: _NoopRepo(),
      );
      notifier.debugSetReconnectDelay(const Duration(milliseconds: 50));
    });

    tearDown(() {
      notifier.dispose();
      sensor.dispose();
    });

    test('unerwarteter Disconnect startet isReconnecting', () async {
      await notifier.connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifier.state.isConnected, isTrue);

      sensor.emitUnexpectedDisconnect();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(notifier.state.isConnected, isFalse);
      expect(notifier.state.isReconnecting, isTrue);
      expect(notifier.state.reconnectAttempt, greaterThanOrEqualTo(1));
      expect(notifier.debugUserInitiatedDisconnect, isFalse);
    });

    test('user disconnect startet KEIN Auto-Reconnect', () async {
      await notifier.connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final callsBefore = sensor.connectCalls;

      await notifier.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(notifier.state.isConnected, isFalse);
      expect(notifier.state.isReconnecting, isFalse);
      expect(notifier.debugUserInitiatedDisconnect, isTrue);
      // No extra connect from reconnect timer
      expect(sensor.connectCalls, callsBefore);
    });

    test('Auto-Reconnect ruft connect() nach Delay erneut auf', () async {
      await notifier.connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final callsAfterFirst = sensor.connectCalls;

      sensor.emitUnexpectedDisconnect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifier.state.isReconnecting, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(sensor.connectCalls, greaterThan(callsAfterFirst));
      expect(notifier.state.isConnected, isTrue);
      expect(notifier.state.isReconnecting, isFalse);
    });
  });
}

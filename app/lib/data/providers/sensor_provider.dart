import 'dart:async';
import 'dart:math';

import '../../domain/workout_engine.dart';

enum ConnectionState { disconnected, connecting, connected }

/// Abstraction so the rest of the app never knows whether it is talking to
/// real BLE hardware or the Mock provider. See GYM_TRACKER_ARCHITEKTUR.md,
/// Prinzip "Web-First Testing".
abstract class ISensorProvider {
  Stream<ConnectionState> get connectionState;
  Stream<SensorSample> get samples;

  Future<void> connect();
  Future<void> disconnect();
  Future<int> readBatteryPercent();
}

/// Simulates a connected device and a plausible bicep-curl-like motion
/// pattern, so the UI and Workout Engine can be exercised in Chrome/desktop
/// without any hardware - this IS Phase 0's actual, explicit test target.
class MockSensorProvider implements ISensorProvider {
  final _connectionController = StreamController<ConnectionState>.broadcast();
  final _sampleController = StreamController<SensorSample>.broadcast();
  Timer? _sampleTimer;
  Timer? _repCycleTimer;
  final _random = Random();
  double _cyclePhase = 0.0;
  bool _simulatingRep = false;

  @override
  Stream<ConnectionState> get connectionState => _connectionController.stream;

  @override
  Stream<SensorSample> get samples => _sampleController.stream;

  @override
  Future<void> connect() async {
    _connectionController.add(ConnectionState.connecting);
    await Future.delayed(const Duration(seconds: 2));
    _connectionController.add(ConnectionState.connected);
    _startStreaming();
  }

  @override
  Future<void> disconnect() async {
    _sampleTimer?.cancel();
    _repCycleTimer?.cancel();
    _connectionController.add(ConnectionState.disconnected);
  }

  @override
  Future<int> readBatteryPercent() async => 85;

  /// Emits samples at ~50 Hz (20ms interval), matching the real firmware
  /// rate from protocol.yaml, so engine behaviour in Mock mode is
  /// representative of the real timing.
  void _startStreaming() {
    _sampleTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      _cyclePhase += 0.05;
      _sampleController.add(_generateSample());
    });
  }

  /// Call this from the UI/test to simulate the user performing one
  /// bicep-curl-like repetition: a smooth rise and fall in acceleration
  /// magnitude over roughly 1.5 seconds.
  void simulateRepetition() {
    if (_simulatingRep) return;
    _simulatingRep = true;
    const steps = 30; // ~1.5s at 20ms/step, half up half down
    var step = 0;
    _repCycleTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      step++;
      if (step >= steps) {
        t.cancel();
        _simulatingRep = false;
      }
    });
  }

  SensorSample _generateSample() {
    // Baseline resting noise plus, while `_simulatingRep` is active, a
    // sine-shaped excursion loosely resembling a curl's acceleration
    // profile. This is intentionally simple - it exists to exercise the
    // Workout Engine's state machine end-to-end, not to be a realistic
    // biomechanical model.
    final noise = () => (_random.nextDouble() - 0.5) * 0.05;
    double repComponent = 0.0;
    if (_simulatingRep) {
      repComponent = sin(_cyclePhase * 4) .abs() * 1.8;
    }
    return SensorSample(
      timestamp: DateTime.now(),
      ax: noise(),
      ay: 1.0 + repComponent + noise(), // gravity baseline + movement
      az: noise(),
      gx: repComponent * 40 + noise() * 10,
      gy: noise() * 10,
      gz: noise() * 10,
    );
  }

  void dispose() {
    _sampleTimer?.cancel();
    _repCycleTimer?.cancel();
    _connectionController.close();
    _sampleController.close();
  }
}

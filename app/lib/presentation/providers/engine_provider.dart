import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/providers/ble_sensor_provider.dart';
import '../../data/providers/sensor_provider.dart';
import '../../data/repositories/csv_session_recorder.dart';
import '../../data/security/calibration_store.dart';
import '../../domain/workout_engine.dart';
import 'workout_ui_state.dart';

/// Riverpod-Provider für den Engine-State (SPEC TEIL 6, §6.2).
///
/// Ersetzt die gesamte setState-Logik aus dem alten HomeScreen.
final engineProvider =
    StateNotifierProvider<EngineNotifier, WorkoutUiState>((ref) {
  throw UnimplementedError(
    'engineProvider muss mit EngineNotifier.create() überschrieben werden. '
    'Siehe main.dart: ProviderScope(overrides: [...])',
  );
});

/// StateNotifier der die WorkoutEngine + BLE-Verbindung + CSV-Recording
/// kapselt und einen immutablen [WorkoutUiState] emittiert.
class EngineNotifier extends StateNotifier<WorkoutUiState> {
  EngineNotifier._({
    required ISensorProvider sensorProvider,
    required WorkoutEngine engine,
  })  : _sensorProvider = sensorProvider,
        _engine = engine,
        super(const WorkoutUiState());

  /// Factory: erstellt den Notifier und bindet alle Streams.
  static EngineNotifier create({
    required ISensorProvider sensorProvider,
    required WorkoutEngine engine,
  }) {
    final notifier = EngineNotifier._(
      sensorProvider: sensorProvider,
      engine: engine,
    );
    notifier._bind();
    return notifier;
  }

  final ISensorProvider _sensorProvider;
  final WorkoutEngine _engine;
  final CalibrationStore _calibrationStore = CalibrationStore();
  final CsvSessionRecorder _recorder = CsvSessionRecorder();

  StreamSubscription<dynamic>? _samplesSub;
  StreamSubscription<dynamic>? _eventsSub;
  StreamSubscription<dynamic>? _recorderSamplesSub;
  StreamSubscription<dynamic>? _connectionSub;
  Timer? _refreshTimer;
  Timer? _recordingSampleCountTimer;
  String? _bleDeviceId;
  File? _lastRecordingFile;

  bool get isMock => _sensorProvider is MockSensorProvider;
  WorkoutEngine get engine => _engine;
  ISensorProvider get sensorProvider => _sensorProvider;

  void _bind() {
    _samplesSub = _sensorProvider.samples.listen(_engine.processSample);
    _eventsSub = _engine.events.listen(_onEngineEvent);
    _recorderSamplesSub = _sensorProvider.samples.listen(_recorder.onSample);
    _connectionSub = _sensorProvider.connectionState.listen(
      _onConnectionState,
      onError: (Object error) {
        state = state.copyWith(errorText: error.toString());
      },
    );
  }

  void _onConnectionState(SensorConnectionState connState) {
    switch (connState) {
      case SensorConnectionState.connected:
        state = state.copyWith(
          isConnected: true,
          isConnecting: false,
          errorText: null,
        );
        if (!isMock) {
          final provider = _sensorProvider as BleSensorProvider;
          _bleDeviceId = provider.remoteId;
          _loadCalibration();
          _updateBleDiagnostics();
        }
        _engine.handleReconnect();
        _refreshTimer?.cancel();
        _refreshTimer = Timer.periodic(
          const Duration(milliseconds: 500),
          (_) => _periodicRefresh(),
        );
        _refreshBattery();
      case SensorConnectionState.connecting:
        state = state.copyWith(isConnecting: true, isConnected: false);
        _refreshTimer?.cancel();
      case SensorConnectionState.disconnected:
        state = state.copyWith(isConnected: false, isConnecting: false);
        _refreshTimer?.cancel();
        _engine.handleDisconnect();
    }
  }

  void _periodicRefresh() {
    if (!isMock) {
      _updateBleDiagnostics();
    }
    // Force state update for live diagnostics
    state = state.copyWith(
      engineSampleCount: _engine.diagEngineSampleCount,
      engineThreshold: _engine.peakThreshold,
      engineBaseline: _engine.baselineLevel,
    );
  }

  void _updateBleDiagnostics() {
    final provider = _sensorProvider;
    if (provider is BleSensorProvider) {
      state = state.copyWith(
        mtu: provider.lastNegotiatedMtu,
        receivedBatches: provider.receivedBatches,
        pollingRateHz: provider.pollingRateHz,
        parseErrors: provider.parseErrors,
      );
    }
  }

  void _onEngineEvent(WorkoutEngineEvent event) {
    _recorder.onEngineStateChanged(event.state);
    state = state.copyWith(
      workoutState: event.state,
      repsInCurrentSet: event.repsInCurrentSet,
      lastCompletedSetCount: event.completedSet?.countedReps,
      calibratedThreshold: event.calibratedThreshold ?? state.calibratedThreshold,
      calibrationPeaksFound: event.calibratedThreshold != null
          ? _engine.calibrationPeaksFound
          : state.calibrationPeaksFound,
    );
    if (event.calibratedThreshold != null) {
      _saveCalibration();
    }
  }

  Future<void> connect() async {
    state = state.copyWith(errorText: null);
    try {
      await _sensorProvider.connect();
    } catch (e) {
      state = state.copyWith(
        isConnected: false,
        isConnecting: false,
        errorText: e.toString(),
      );
    }
  }

  Future<void> disconnect() async {
    await _sensorProvider.disconnect();
  }

  void simulateRepetition() {
    _sensorProvider.simulateRepetition();
  }

  void toggleDummyStream() {
    final provider = _sensorProvider;
    if (provider is BleSensorProvider) {
      provider.toggleDummyStream();
    }
  }

  Future<void> _refreshBattery() async {
    try {
      final percent = await _sensorProvider.readBatteryPercent();
      state = state.copyWith(batteryPercent: percent);
    } catch (e) {
      state = state.copyWith(errorText: 'Akku lesen fehlgeschlagen: $e');
    }
  }

  Future<void> _loadCalibration() async {
    if (isMock) return;
    final provider = _sensorProvider as BleSensorProvider;
    final deviceId = provider.remoteId;
    if (deviceId == null) return;
    _bleDeviceId = deviceId;

    final profile = await _calibrationStore.loadProfile(
      exerciseId: _engine.exerciseId,
      deviceId: deviceId,
    );
    if (profile != null) {
      state = state.copyWith(calibratedThreshold: profile.theta);
      _engine.applyCalibration(
        peakThreshold: profile.theta,
        minThresholdAboveBaseline: 0.10,
        rotationAxis: profile.migratedFrom == 0 ? profile.rotationAxis : null,
        gyroBias: profile.migratedFrom == 0 ? profile.gyroBias : null,
      );
    }
  }

  Future<void> _saveCalibration() async {
    if (_bleDeviceId == null) return;
    await _calibrationStore.save(
      deviceId: _bleDeviceId!,
      peakThreshold: _engine.peakThreshold,
      minThresholdAboveBaseline: _engine.minThresholdAboveBaseline,
      baselineLevel: _engine.baselineLevel,
    );
  }

  /// Reload calibration (called after CalibrationWizardScreen saves).
  void reloadCalibration() => _loadCalibration();

  // === CSV Recording ===

  Future<void> toggleRecording() async {
    if (state.isRecording) {
      _recordingSampleCountTimer?.cancel();
      _recordingSampleCountTimer = null;
      final file = await _recorder.stop(_engine.exerciseId);
      _lastRecordingFile = file;
      state = state.copyWith(
        isRecording: false,
        recordedSampleCount: _recorder.sampleCount,
        lastRecordingFileName:
            file?.path.split(Platform.pathSeparator).last,
      );
    } else {
      _recorder.start();
      _lastRecordingFile = null;
      state = state.copyWith(
        isRecording: true,
        recordedSampleCount: 0,
        lastRecordingFileName: null,
      );
      _recordingSampleCountTimer =
          Timer.periodic(const Duration(milliseconds: 300), (_) {
        state = state.copyWith(recordedSampleCount: _recorder.sampleCount);
      });
    }
  }

  Future<void> shareLastRecording() async {
    final file = _lastRecordingFile;
    if (file == null) return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'FlowRep-Aufnahme'),
    );
  }

  bool get hasLastRecording => _lastRecordingFile != null;
  @override
  void dispose() {
    _refreshTimer?.cancel();
    _recordingSampleCountTimer?.cancel();
    _samplesSub?.cancel();
    _eventsSub?.cancel();
    _recorderSamplesSub?.cancel();
    _connectionSub?.cancel();
    _recorder.dispose();
    _engine.dispose();
    final provider = _sensorProvider;
    if (provider is BleSensorProvider) {
      provider.dispose();
    } else if (provider is MockSensorProvider) {
      provider.dispose();
    }
    super.dispose();
  }
}

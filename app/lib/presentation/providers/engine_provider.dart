import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/providers/ble_sensor_provider.dart';
import '../../data/providers/sensor_provider.dart';
import '../../data/repositories/csv_session_recorder.dart';
import '../../data/security/calibration_store.dart';
import '../../domain/models/workout_models.dart';
import '../../domain/repositories/i_workout_repository.dart';
import '../../domain/workout_engine.dart';
import '../services/feedback_service.dart';
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
    IWorkoutRepository? repository,
  })  : _sensorProvider = sensorProvider,
        _engine = engine,
        _repository = repository,
        super(const WorkoutUiState());

  /// Factory: erstellt den Notifier und bindet alle Streams.
  static EngineNotifier create({
    required ISensorProvider sensorProvider,
    required WorkoutEngine engine,
    IWorkoutRepository? repository,
  }) {
    final notifier = EngineNotifier._(
      sensorProvider: sensorProvider,
      engine: engine,
      repository: repository,
    );
    notifier._bind();
    notifier._feedbackService.init();
    return notifier;
  }

  final ISensorProvider _sensorProvider;
  final WorkoutEngine _engine;
  final IWorkoutRepository? _repository;
  final CalibrationStore _calibrationStore = CalibrationStore();
  final CsvSessionRecorder _recorder = CsvSessionRecorder();
  final FeedbackService _feedbackService = FeedbackService();

  // Session-Tracking (Phase 5.2)
  DateTime? _sessionStartedAt;
  final List<ExerciseSet> _completedSets = [];

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
    _samplesSub = _sensorProvider.samples.listen(_onSampleGated);
    _eventsSub = _engine.events.listen(_onEngineEvent);
    _recorderSamplesSub = _sensorProvider.samples.listen(_recorder.onSample);
    _connectionSub = _sensorProvider.connectionState.listen(
      _onConnectionState,
      onError: (Object error) {
        state = state.copyWith(errorText: error.toString());
      },
    );
  }

  /// Zähl-Gating: Samples werden nur an die Engine weitergeleitet,
  /// wenn der Benutzer das Zählen explizit gestartet hat.
  /// Verhindert „App zählt permanent bei Alltagsbewegung“.
  void _onSampleGated(dynamic sample) {
    if (!state.isCountingActive) return;
    _engine.processSample(sample);
  }

  /// Startet das Zählen (Engine erhält ab jetzt Samples).
  void startCounting() {
    if (state.isCountingActive) return;
    state = state.copyWith(isCountingActive: true);
  }

  /// Stoppt das Zählen und setzt die Engine zurück auf idle.
  void stopCounting() {
    if (!state.isCountingActive) return;
    _engine.pause();
    state = state.copyWith(
      isCountingActive: false,
      workoutState: WorkoutState.idle,
      repsInCurrentSet: 0,
    );
  }

  /// Wählt eine Übung aus (V1: nur bicep_curl verfügbar).
  /// Lädt die Kalibrierung für die neue Übung neu.
  void selectExercise(String exerciseId) {
    if (exerciseId == state.selectedExerciseId) return;
    // Zählen stoppen falls aktiv
    if (state.isCountingActive) stopCounting();
    state = state.copyWith(
      selectedExerciseId: exerciseId,
      hasCalibration: false,
      calibratedThreshold: null,
    );
    // Kalibrierung für neue Übung laden
    _loadCalibration();
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

    // Session-Start tracken
    if (event.state == WorkoutState.active && _sessionStartedAt == null) {
      _sessionStartedAt = DateTime.now();
    }

    // Rep-Feedback (Phase 5.1)
    if (event.repsInCurrentSet > state.repsInCurrentSet) {
      _feedbackService.onRepCounted(qualityScore: state.lastQualityScore);
    }

    // Satz abgeschlossen → Feedback + Persistence
    if (event.completedSet != null) {
      _feedbackService.onSetCompleted(
          repCount: event.completedSet!.countedReps);
      _onSetCompleted(event.completedSet!);
    }

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

  /// Satz abgeschlossen: persistieren (Phase 5.2).
  void _onSetCompleted(ExerciseSet completedSet) {
    _completedSets.add(completedSet);
    _saveSession();
  }

  /// Aktuelle Session in DB speichern.
  Future<void> _saveSession() async {
    final repo = _repository;
    if (repo == null || _sessionStartedAt == null) return;
    final session = WorkoutSession(
      id: _generateId(),
      startedAt: _sessionStartedAt!,
      endedAt: DateTime.now(),
      sets: List.unmodifiable(_completedSets),
    );
    try {
      await repo.saveSession(session);
    } catch (_) {
      // DB-Fehler nicht fatal — Logging wäre hier sinnvoll.
    }
  }

  String _generateId() {
    final r = Random();
    return '${DateTime.now().millisecondsSinceEpoch}-${r.nextInt(99999)}';
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
      state = state.copyWith(
        calibratedThreshold: profile.theta,
        hasCalibration: true,
      );
      _engine.applyCalibration(
        peakThreshold: profile.theta,
        minThresholdAboveBaseline: 0.10,
        rotationAxis: profile.migratedFrom == 0 ? profile.rotationAxis : null,
        gyroBias: profile.migratedFrom == 0 ? profile.gyroBias : null,
        chosenSignal: profile.migratedFrom == 0 ? profile.chosenSignal : null,
        minRepIntervalSeconds: profile.minRepIntervalSeconds,
        prominenceMin: profile.prominenceMin > 0 ? profile.prominenceMin : null,
        repTemplate: profile.repTemplate,
        templateCorrThreshold: profile.templateCorrThreshold,
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
    _feedbackService.dispose();
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

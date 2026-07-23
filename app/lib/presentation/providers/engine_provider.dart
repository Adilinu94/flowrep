import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/logger.dart';
import '../../data/providers/ble_sensor_provider.dart';
import '../../data/providers/sensor_provider.dart';
import '../../data/repositories/csv_session_recorder.dart';
import '../../data/security/calibration_store.dart';
import '../../data/services/foreground_service_manager.dart';
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
  final ForegroundServiceManager _fgService = ForegroundServiceManager();

  // Session-Tracking (Phase 5.2)
  DateTime? _sessionStartedAt;
  final List<ExerciseSet> _completedSets = [];

  StreamSubscription<dynamic>? _samplesSub;
  StreamSubscription<dynamic>? _eventsSub;
  StreamSubscription<dynamic>? _recorderSamplesSub;
  StreamSubscription<dynamic>? _connectionSub;
  Timer? _refreshTimer;
  Timer? _recordingSampleCountTimer;
  Timer? _restTimer;
  int _restDurationSeconds = 90; // SPEC §5.2.1 / P0-2 default
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 10;
  bool _userInitiatedDisconnect = false;
  Duration? _reconnectDelayOverride; // tests only
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
    _stopRestTimer(); // P0-2: Pausen-Timer stoppen bei neuem Satz
    // P0-5: keep BLE alive under screen lock (Android connectedDevice FGS)
    unawaited(_fgService.start());
    state = state.copyWith(isCountingActive: true);
  }

  /// Stoppt das Zählen und setzt die Engine zurück auf idle.
  void stopCounting() {
    if (!state.isCountingActive) return;
    _engine.pause();
    unawaited(_fgService.stop());
    state = state.copyWith(
      isCountingActive: false,
      workoutState: WorkoutState.idle,
      repsInCurrentSet: 0,
    );
  }

  // === Manuelle Korrektur (SPEC §5.1.4 / P0-1) ===

  /// Zeigt den Korrektur-Dialog für den zuletzt abgeschlossenen Satz.
  void showCorrectionForLastSet(int countedReps) {
    state = state.copyWith(
      showCorrectionDialog: true,
      correctionSetCountedReps: countedReps,
      correctionSetUserReps: countedReps,
    );
  }

  /// Wendet eine Korrektur an (+1 oder -1).
  void applyCorrectionDelta(int delta) {
    final current =
        state.correctionSetUserReps ?? state.correctionSetCountedReps ?? 0;
    final newValue = (current + delta).clamp(0, 999);
    state = state.copyWith(correctionSetUserReps: newValue);
  }

  /// Bestätigt die Korrektur und speichert [CorrectionEvent] bei Abweichung.
  /// [countedReps] bleibt unverändert; nur [ExerciseSet.correctedReps] wird gesetzt.
  Future<void> confirmCorrection() async {
    final countedReps = state.correctionSetCountedReps;
    final userReps = state.correctionSetUserReps;
    if (countedReps == null || userReps == null) {
      dismissCorrection();
      return;
    }

    if (userReps != countedReps) {
      if (_completedSets.isNotEmpty) {
        final lastSet = _completedSets.last;
        _completedSets[_completedSets.length - 1] =
            lastSet.copyWith(correctedReps: userReps);
      }

      final repo = _repository;
      if (repo != null) {
        final event = CorrectionEvent(
          id: _generateId(),
          setId: _completedSets.isNotEmpty ? _completedSets.last.id : 'unknown',
          systemCount: countedReps,
          userCorrectedCount: userReps,
          timestamp: DateTime.now(),
        );
        try {
          await repo.saveCorrection(event);
        } catch (_) {
          // DB-Fehler nicht fatal
        }
      }

      _saveSession();
    }

    dismissCorrection();
  }

  /// Schließt den Korrektur-Dialog ohne zu speichern.
  /// Startet danach den Pausen-Timer (P0-2), außer [startRest] ist false
  /// (z.B. bei Session-Ende).
  void dismissCorrection({bool startRest = true}) {
    if (state.showCorrectionDialog) {
      state = state.copyWith(showCorrectionDialog: false);
    }
    if (startRest) {
      _startRestTimer();
    }
  }

  // === Pausen-Timer (SPEC Phase 2, §5.2.1 / P0-2) ===

  /// Startet den Pausen-Timer nach Satzende / Korrektur-Dialog.
  void _startRestTimer() {
    _restTimer?.cancel();
    state = state.copyWith(
      isRestTimerActive: true,
      restTimerSecondsRemaining: _restDurationSeconds,
    );
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.restTimerSecondsRemaining - 1;
      if (remaining <= 0) {
        _stopRestTimer();
      } else {
        state = state.copyWith(restTimerSecondsRemaining: remaining);
      }
    });
  }

  /// Stoppt den Pausen-Timer (manuell, bei Start, dispose, Session-Ende).
  void _stopRestTimer() {
    _restTimer?.cancel();
    _restTimer = null;
    if (state.isRestTimerActive) {
      state = state.copyWith(isRestTimerActive: false);
    }
  }

  /// Öffentlicher Zugriff: Timer manuell stoppen („Pause überspringen").
  void skipRest() => _stopRestTimer();

  /// Rest duration used for UI progress (default 90s).
  int get restDurationSeconds => _restDurationSeconds;

  // === Session-Beenden-Flow (P0-3) ===

  /// Beendet die aktuelle Trainingssession.
  /// Speichert alle Sets, stoppt Timer, zeigt Zusammenfassung.
  Future<void> endSession() async {
    if (state.isCountingActive) {
      _engine.pause();
    }
    await _fgService.stop();
    _stopRestTimer();
    dismissCorrection(startRest: false);

    final totalSets = _completedSets.length;
    final totalReps = _completedSets.fold<int>(
      0,
      (sum, s) => sum + s.effectiveReps,
    );
    final duration = _sessionStartedAt != null
        ? DateTime.now().difference(_sessionStartedAt!)
        : null;

    final repo = _repository;
    if (repo != null &&
        _sessionStartedAt != null &&
        _completedSets.isNotEmpty) {
      final session = WorkoutSession(
        id: _generateId(),
        startedAt: _sessionStartedAt!,
        endedAt: DateTime.now(),
        sets: List.unmodifiable(_completedSets),
      );
      try {
        await repo.saveSession(session);
      } catch (_) {
        // DB-Fehler nicht fatal
      }
    }

    state = state.copyWith(
      isCountingActive: false,
      workoutState: WorkoutState.idle,
      repsInCurrentSet: 0,
      showSessionSummary: true,
      sessionTotalSets: totalSets,
      sessionTotalReps: totalReps,
      sessionDuration: duration,
    );

    _sessionStartedAt = null;
    _completedSets.clear();
  }

  /// Schließt die Session-Zusammenfassung.
  void dismissSessionSummary() {
    state = state.copyWith(showSessionSummary: false);
  }

  /// Exposes completed sets for tests (read-only view of last set correction).
  @visibleForTesting
  List<ExerciseSet> get debugCompletedSets =>
      List.unmodifiable(_completedSets);

  /// Inject a completed set for unit tests of correction/session flows.
  @visibleForTesting
  void debugAddCompletedSet(ExerciseSet set) {
    _completedSets.add(set);
    _sessionStartedAt ??= DateTime.now();
  }

  /// Override rest duration for faster unit tests.
  @visibleForTesting
  void debugSetRestDurationSeconds(int seconds) {
    _restDurationSeconds = seconds;
  }

  /// Force near-instant reconnect delays in unit tests.
  @visibleForTesting
  void debugSetReconnectDelay(Duration delay) {
    _reconnectDelayOverride = delay;
  }

  /// Whether the last disconnect was user-initiated (for tests).
  @visibleForTesting
  bool get debugUserInitiatedDisconnect => _userInitiatedDisconnect;

  /// Foreground service manager (P0-5) for tests.
  @visibleForTesting
  ForegroundServiceManager get debugFgService => _fgService;

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
        _userInitiatedDisconnect = false;
        _cancelReconnect();
        _reconnectAttempt = 0;
        state = state.copyWith(
          isConnected: true,
          isConnecting: false,
          errorText: null,
          isReconnecting: false,
          reconnectAttempt: 0,
        );
        final sensor = _sensorProvider;
        if (sensor is BleSensorProvider) {
          _bleDeviceId = sensor.remoteId;
          _loadCalibration();
          _updateBleDiagnostics();
        }
        _engine.handleReconnect();
        _refreshTimer?.cancel();
        _refreshTimer = Timer.periodic(
          const Duration(milliseconds: 500),
          (_) => _periodicRefresh(),
        );
        if (sensor is BleSensorProvider) {
          _refreshBattery();
        }
      case SensorConnectionState.connecting:
        state = state.copyWith(isConnecting: true, isConnected: false);
        _refreshTimer?.cancel();
      case SensorConnectionState.disconnected:
        state = state.copyWith(isConnected: false, isConnecting: false);
        _refreshTimer?.cancel();
        _engine.handleDisconnect();
        // Auto-Reconnect (P0-4) only when not user-initiated
        if (!_userInitiatedDisconnect) {
          _startReconnect();
        }
    }
  }

  // === Reconnection-Strategie (SPEC §5.2.4 / P0-4) ===

  void _startReconnect() {
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      state = state.copyWith(
        isReconnecting: false,
        errorText: 'Verbindung konnte nicht wiederhergestellt werden. '
            'Bitte manuell verbinden.',
      );
      return;
    }

    _reconnectAttempt++;
    final delay = _reconnectDelayForAttempt(_reconnectAttempt);

    state = state.copyWith(
      isReconnecting: true,
      reconnectAttempt: _reconnectAttempt,
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (_userInitiatedDisconnect) return;
      try {
        await _sensorProvider.connect();
      } catch (_) {
        // Failed connect → next attempt when disconnected is re-emitted
        // or schedule next attempt if still disconnected.
        if (!_userInitiatedDisconnect && !state.isConnected) {
          _startReconnect();
        }
      }
    });
  }

  Duration _reconnectDelayForAttempt(int attempt) {
    if (_reconnectDelayOverride != null) return _reconnectDelayOverride!;
    // Exponential backoff: 1s, 2s, 4s, 8s, max 16s
    final delaySec = (1 << (attempt - 1)).clamp(1, 16);
    return Duration(seconds: delaySec);
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (state.isReconnecting) {
      state = state.copyWith(isReconnecting: false);
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

    // Satz abgeschlossen → Feedback + Persistence + Korrektur-Dialog
    if (event.completedSet != null) {
      _feedbackService.onSetCompleted(
          repCount: event.completedSet!.countedReps);
      _onSetCompleted(event.completedSet!);
      // Korrektur-Dialog zeigen (SPEC §5.1.4 / P0-1)
      showCorrectionForLastSet(event.completedSet!.countedReps);
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
    _userInitiatedDisconnect = false;
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
    _userInitiatedDisconnect = true; // Kein Auto-Reconnect
    _cancelReconnect();
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
      // theta unit follows chosenSignal (gP °/s vs combined). Hardware
      // 2026-07-23: missing chosenSignal put gP-scale theta into combined
      // _peakThreshold → counting dead. origin/main + this path pass
      // chosenSignal for non-migrated profiles.
      state = state.copyWith(
        calibratedThreshold: profile.theta,
        hasCalibration: true,
      );
      final axis = profile.migratedFrom == 0 ? profile.rotationAxis : null;
      final bias = profile.migratedFrom == 0 ? profile.gyroBias : null;
      _engine.applyCalibration(
        peakThreshold: profile.theta,
        minThresholdAboveBaseline: 0.10,
        rotationAxis: axis,
        gyroBias: bias,
        chosenSignal: profile.migratedFrom == 0 ? profile.chosenSignal : null,
        minRepIntervalSeconds: profile.minRepIntervalSeconds,
        prominenceMin: profile.prominenceMin > 0 ? profile.prominenceMin : null,
        repTemplate: profile.repTemplate,
        templateCorrThreshold: profile.templateCorrThreshold,
      );
      // Shadow new pipeline once axis exists (_useNewPipeline stays false).
      if (axis != null && bias != null) {
        _engine.enableShadowMode();
      }
      AppLogger.i(
        'Loaded profile: signal=${profile.chosenSignal.name} '
        'theta=${profile.theta.toStringAsFixed(3)} '
        'q=${profile.qualityScore.toStringAsFixed(2)} '
        'axis=${axis != null}',
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
    _restTimer?.cancel();
    _restTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_fgService.stop());
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

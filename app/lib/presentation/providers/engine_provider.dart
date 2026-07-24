import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/logger.dart';
import '../../data/providers/ble_error_mapper.dart';
import '../../data/providers/ble_sensor_provider.dart';
import '../../data/providers/sensor_provider.dart';
import '../../data/repositories/csv_session_recorder.dart';
import '../../data/security/calibration_store.dart';
import '../../data/services/export_service.dart';
import '../../data/services/foreground_service_manager.dart';
import '../../domain/config/engine_constants.dart';
import '../../domain/device_event.dart';
import '../../domain/exercises/exercise_targets.dart';
import '../../domain/metrics/form_quality.dart';
import '../../domain/metrics/placement_energy_monitor.dart';
import '../../domain/metrics/sensor_health_monitor.dart';
import '../../domain/metrics/set_quality_score.dart';
import '../../domain/metrics/velocity_metrics.dart';
import '../../domain/ml/exercise_classifier.dart';
import '../../domain/models/exercise_profile.dart';
import '../../domain/models/workout_models.dart';
import '../../domain/repositories/i_workout_repository.dart';
import '../../domain/vision/fusion_engine.dart';
import '../../domain/vision/pose_rep_counter.dart';
import '../../domain/workout_engine.dart';
import '../services/feedback_service.dart';
import 'lifecycle_provider.dart';
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
    notifier._initLifecycleObserver();
    return notifier;
  }

  final ISensorProvider _sensorProvider;
  final WorkoutEngine _engine;
  final IWorkoutRepository? _repository;
  final CalibrationStore _calibrationStore = CalibrationStore();
  final CsvSessionRecorder _recorder = CsvSessionRecorder();
  final FeedbackService _feedbackService = FeedbackService();
  final ForegroundServiceManager _fgService = ForegroundServiceManager();
  AppLifecycleObserver? _lifecycleObserver;
  /// Seconds remaining when rest timer was paused by app backgrounding (P1-2).
  int? _restSecondsWhenPaused;

  // CV-04: optional fusion layer (does not change IMU counting authority).
  final FusionEngine _fusionEngine = FusionEngine();
  final PoseRepCounter _poseRepCounter = PoseRepCounter();
  bool _cameraEnabled = false;

  // Session-Tracking (Phase 5.2)
  DateTime? _sessionStartedAt;
  final List<ExerciseSet> _completedSets = [];
  /// Snapshot for summary dialog after [endSession] clears live sets.
  List<ExerciseSet> _lastSessionSets = const [];
  bool _lastSessionHadPr = false;
  final ExerciseTargets _targets = ExerciseTargets();
  final ExerciseClassifier _classifier = HeuristicExerciseClassifier();
  final List<double> _imuWindowBuf = <double>[];
  static const int _imuWindowMax = 104; // ~2 s @ 52 Hz
  final SensorHealthMonitor _sensorHealth = SensorHealthMonitor();
  final PlacementEnergyMonitor _placement = PlacementEnergyMonitor();
  /// Sticky flags for the current set (reset on startCounting / set end).
  bool _setHadPacketLoss = false;
  bool _setHadGhostPause = false;
  bool _setHadSensorUnhealthy = false;
  Timer? _idleDisconnectTimer;
  static const Duration _idleDisconnectAfter = Duration(minutes: 15);
  bool _adaptiveRestEnabled = true;
  bool _vbtEnabled = true;

  StreamSubscription<dynamic>? _samplesSub;
  StreamSubscription<dynamic>? _eventsSub;
  StreamSubscription<dynamic>? _recorderSamplesSub;
  StreamSubscription<dynamic>? _connectionSub;
  StreamSubscription<DeviceEvent>? _deviceEventSub;
  /// When true, M5 BtnA drives startCounting / endSetManually.
  bool _m5ButtonControlEnabled = true;
  /// After successful calib reload, auto-start counting (Audit QW-2). Default on.
  bool _autoArmAfterCalib = true;
  Timer? _refreshTimer;
  Timer? _recordingSampleCountTimer;
  Timer? _restTimer;
  int _restDurationSeconds = kDefaultRestDurationSeconds; // P0-2 / P2-6
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = kMaxReconnectAttempts;
  bool _userInitiatedDisconnect = false;
  Duration? _reconnectDelayOverride; // tests only
  String? _bleDeviceId;
  File? _lastRecordingFile;

  bool get isMock => _sensorProvider is MockSensorProvider;
  WorkoutEngine get engine => _engine;
  ISensorProvider get sensorProvider => _sensorProvider;
  List<ExerciseSet> get lastSessionSets => List.unmodifiable(_lastSessionSets);
  bool get lastSessionHadPr => _lastSessionHadPr;
  ExerciseTargets get targets => _targets;
  bool get adaptiveRestEnabled => _adaptiveRestEnabled;
  bool get vbtEnabled => _vbtEnabled;

  void _bind() {
    _samplesSub = _sensorProvider.samples.listen(_onSample);
    _eventsSub = _engine.events.listen(_onEngineEvent);
    _recorderSamplesSub = _sensorProvider.samples.listen(_recorder.onSample);
    _connectionSub = _sensorProvider.connectionState.listen(
      _onConnectionState,
      onError: (Object error) {
        state = state.copyWith(errorText: error.toString());
      },
    );
    _deviceEventSub = _sensorProvider.deviceEvents.listen(_onDeviceEvent);
  }

  /// M5 BtnA (COUNT_PRIMARY): start counting, or end set while counting.
  void _onDeviceEvent(DeviceEvent event) {
    if (!_m5ButtonControlEnabled) return;
    if (event.id != DeviceEventId.countPrimary) return;

    if (!state.isCountingActive) {
      startCounting();
      unawaited(_feedbackService.onDeviceButton(isStart: true));
      AppLogger.i('M5 BtnA → startCounting');
      return;
    }
    // User decision: stop path = Satz beenden (correction dialog follows).
    endSetManually();
    unawaited(_feedbackService.onDeviceButton(isStart: false));
    AppLogger.i('M5 BtnA → endSetManually');
  }

  /// All connected samples update health; only counting forwards to engine.
  /// Health runs even when idle so bad gyro-rest is visible before start.
  void _onSample(dynamic sample) {
    if (sample is! SensorSample) return;

    _sensorHealth.push(
      gyroMagnitude: sample.gyroMagnitude,
      accelMagnitude: sample.accelMagnitude,
    );
    final healthChanged =
        _sensorHealth.isUnhealthy != state.sensorHealthUnhealthy;
    if (_sensorHealth.isUnhealthy) {
      _setHadSensorUnhealthy = true;
    }

    if (!state.isCountingActive) {
      if (healthChanged) {
        state = state.copyWith(
          sensorHealthUnhealthy: _sensorHealth.isUnhealthy,
          sensorHealthMessage: _sensorHealth.message,
          clearSensorHealthMessage: !_sensorHealth.isUnhealthy,
        );
      }
      return;
    }

    _engine.processSample(sample);
    _noteActivity();
    _pushImuWindow(sample);

    // Placement: after engine update so diagGpAbs is current.
    _placement.push(
      accelMagnitude: sample.accelMagnitude,
      gpAbs: _engine.diagGpAbs,
      theta: _engine.diagGpThreshold ?? state.calibratedThreshold,
    );

    final ghostNow = _engine.ghostGatePaused;
    if (ghostNow) _setHadGhostPause = true;

    final needUi = ghostNow != state.ghostGatePaused ||
        healthChanged ||
        _placement.shouldWarn != state.placementWarn ||
        state.diagnoseOverlayEnabled;
    if (needUi) {
      state = state.copyWith(
        ghostGatePaused: ghostNow,
        ghostBannerDismissed:
            ghostNow ? state.ghostBannerDismissed : false,
        sensorHealthUnhealthy: _sensorHealth.isUnhealthy,
        sensorHealthMessage: _sensorHealth.message,
        clearSensorHealthMessage: !_sensorHealth.isUnhealthy,
        placementWarn: _placement.shouldWarn,
        engineSampleCount: _engine.diagEngineSampleCount,
        engineThreshold: _engine.diagGpThreshold ?? state.engineThreshold,
        engineBaseline: _engine.baselineLevel,
      );
    }
  }

  void _pushImuWindow(SensorSample s) {
    final mag = s.gyroMagnitude;
    _imuWindowBuf.add(mag);
    if (_imuWindowBuf.length > _imuWindowMax) {
      _imuWindowBuf.removeRange(0, _imuWindowBuf.length - _imuWindowMax);
    }
    // Shadow suggestion ~every second once the buffer is full (FR-A4 heuristic).
    if (_imuWindowBuf.length >= _imuWindowMax &&
        _engine.diagEngineSampleCount % 50 == 0) {
      unawaited(_maybeSuggestExercise());
    }
  }

  Future<void> _maybeSuggestExercise() async {
    final suggestion = await _classifier.classify(
      ImuWindow(
        samples: List<double>.from(_imuWindowBuf),
        sampleRateHz: 50,
        endedAt: DateTime.now(),
      ),
    );
    if (suggestion == null) return;
    if (suggestion.exerciseId == state.selectedExerciseId) return;
    if (suggestion.confidence < 0.6) return;
    state = state.copyWith(
      exerciseSuggestion: suggestion.exerciseId,
      exerciseSuggestionConfidence: suggestion.confidence,
    );
  }

  void acceptExerciseSuggestion() {
    final id = state.exerciseSuggestion;
    if (id == null) return;
    selectExercise(id);
    state = state.copyWith(clearExerciseSuggestion: true);
  }

  void dismissExerciseSuggestion() {
    state = state.copyWith(clearExerciseSuggestion: true);
  }

  /// Startet das Zählen (Engine erhält ab jetzt Samples).
  void startCounting() {
    if (state.isCountingActive) return;
    _stopRestTimer(); // P0-2: Pausen-Timer stoppen bei neuem Satz
    _engine.resetGhostGate();
    _imuWindowBuf.clear();
    _placement.reset();
    _setHadPacketLoss = false;
    _setHadGhostPause = false;
    _setHadSensorUnhealthy = _sensorHealth.isUnhealthy;
    // Re-apply profile so gP/gyroMag thresholds are live even if connect
    // raced handleReconnect before the first load finished.
    unawaited(_loadCalibration());
    // P0-5: keep BLE alive under screen lock (Android connectedDevice FGS)
    unawaited(_fgService.start());
    _cancelIdleDisconnect();
    state = state.copyWith(
      isCountingActive: true,
      ghostGatePaused: false,
      ghostBannerDismissed: false,
      placementWarn: false,
    );
  }

  /// Hide ghost banner for the current pause (counting stays paused until motion).
  void dismissGhostBanner() {
    if (!state.ghostGatePaused) return;
    state = state.copyWith(ghostBannerDismissed: true);
  }

  /// Stoppt das Zählen und setzt die Engine zurück auf idle.
  /// Does NOT end the current set — use [endSetManually] first if needed.
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

  /// Manuelles Satzende → Korrektur-Dialog (kein Auto-Timeout).
  void endSetManually() {
    if (!state.isCountingActive && state.repsInCurrentSet <= 0) return;
    _engine.endSetManually();
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
  ///
  /// Returns a short snackbar message when something was saved / learned
  /// (Audit QW-5). Null if dismissed without meaningful action.
  Future<String?> confirmCorrection() async {
    final countedReps = state.correctionSetCountedReps;
    final userReps = state.correctionSetUserReps;
    if (countedReps == null || userReps == null) {
      dismissCorrection();
      return null;
    }

    String? message;
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

      // Online learning (rule-based, not ML): nudge thresholds from error.
      final learned = await _learnFromCorrection(
        systemCount: countedReps,
        userCount: userReps,
      );

      _saveSession();
      message = learned
          ? 'Gespeichert — Schwelle angepasst'
          : 'Gespeichert';
    }

    dismissCorrection();
    return message;
  }

  /// Rule-based threshold adaptation after a user correction.
  ///
  /// Over-count (system > user) → raise θ (stricter, fewer false reps).
  /// Under-count (system < user) → lower θ (more sensitive).
  /// Persists into [CalibrationStore] so the next session inherits it.
  /// Spec: store CorrectionEvent forever; never claim "KI lernt" in UI copy.
  /// Returns true when θ was nudged (in-memory and/or persisted).
  Future<bool> _learnFromCorrection({
    required int systemCount,
    required int userCount,
  }) async {
    if (systemCount <= 0 && userCount <= 0) return false;
    final sys = systemCount < 1 ? 1 : systemCount;
    final ratio = sys / (userCount < 1 ? 1 : userCount);
    // ratio > 1: over-count; ratio < 1: under-count
    double factor = 1.0;
    if (ratio > 1.05) {
      factor = (1.0 + 0.15 * (ratio - 1.0)).clamp(1.05, 1.25);
    } else if (ratio < 0.95) {
      factor = (1.0 - 0.15 * (1.0 - ratio)).clamp(0.80, 0.95);
    } else {
      return false; // within noise band
    }

    _engine.nudgeDirectionAwareThreshold(factor);

    final deviceId = _bleDeviceId;
    if (deviceId == null || isMock) return true;
    try {
      final profile = await _calibrationStore.loadProfile(
        exerciseId: _engine.exerciseId,
        deviceId: deviceId,
      );
      if (profile == null || profile.migratedFrom != 0) return true;
      final newTheta = (profile.theta * factor).clamp(30.0, 250.0);
      final updated = ExerciseProfile(
        exerciseId: profile.exerciseId,
        rotationAxis: profile.rotationAxis,
        chosenSignal: profile.chosenSignal,
        theta: newTheta,
        minRepIntervalSeconds: profile.minRepIntervalSeconds,
        prominenceMin: profile.prominenceMin,
        medianTSeconds: profile.medianTSeconds,
        madTSeconds: profile.madTSeconds,
        gyroBias: profile.gyroBias,
        spkInit: profile.spkInit,
        npkInit: profile.npkInit,
        repTemplate: profile.repTemplate,
        templateCorrThreshold: profile.templateCorrThreshold,
        expectedProminence: profile.expectedProminence,
        prominenceTolerance: profile.prominenceTolerance,
        concentricRatioExpected: profile.concentricRatioExpected,
        durationRatioMin: profile.durationRatioMin,
        durationRatioMax: profile.durationRatioMax,
        qualityScore: profile.qualityScore,
        calibratedAt: DateTime.now(),
        migratedFrom: 0,
      );
      await _calibrationStore.saveProfile(profile: updated);
      // Keep UI calibrated label in sync.
      state = state.copyWith(calibratedThreshold: newTheta);
      AppLogger.i(
        'Learned from correction system=$systemCount user=$userCount '
        'θ ${profile.theta.toStringAsFixed(1)}→${newTheta.toStringAsFixed(1)}',
      );
    } catch (_) {
      // Non-fatal — in-memory nudge already applied.
    }
    return true;
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
    var seconds = _restDurationSeconds;
    if (_adaptiveRestEnabled && state.lastSetVelocityLossPct != null) {
      seconds = VelocityMetrics.adaptiveRestSeconds(
        baseSeconds: _restDurationSeconds,
        velocityLossPct: state.lastSetVelocityLossPct,
      );
    }
    state = state.copyWith(
      isRestTimerActive: true,
      restTimerSecondsRemaining: seconds,
    );
    if (state.blindModeEnabled) {
      unawaited(_feedbackService.onSetCompleted(repCount: 0));
    }
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.restTimerSecondsRemaining - 1;
      if (remaining <= 0) {
        _stopRestTimer();
        if (state.blindModeEnabled) {
          unawaited(_feedbackService.onRepCounted());
        }
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

  /// Settings (P1-3): change default rest duration between sets.
  void setRestDurationSeconds(int seconds) {
    if (seconds < 1) return;
    _restDurationSeconds = seconds;
  }

  bool get hapticEnabled => _feedbackService.enableHaptic;
  bool get audioEnabled => _feedbackService.enableAudio;

  void setFeedback({bool? haptic, bool? audio}) {
    if (haptic != null) _feedbackService.enableHaptic = haptic;
    if (audio != null) _feedbackService.enableAudio = audio;
  }

  bool get m5ButtonControlEnabled => _m5ButtonControlEnabled;
  bool get buttonHapticEnabled => _feedbackService.buttonHaptic;
  bool get buttonAudioEnabled => _feedbackService.buttonAudio;

  void setM5ButtonControlEnabled(bool enabled) {
    _m5ButtonControlEnabled = enabled;
  }

  bool get autoArmAfterCalib => _autoArmAfterCalib;

  void setAutoArmAfterCalib(bool enabled) {
    _autoArmAfterCalib = enabled;
  }

  void setButtonFeedback({bool? haptic, bool? audio}) {
    if (haptic != null) _feedbackService.buttonHaptic = haptic;
    if (audio != null) _feedbackService.buttonAudio = audio;
  }

  void setDiagnoseOverlayEnabled(bool enabled) {
    state = state.copyWith(diagnoseOverlayEnabled: enabled);
  }

  void setVbtMetricsEnabled(bool enabled) {
    _vbtEnabled = enabled;
    state = state.copyWith(vbtMetricsEnabled: enabled);
  }

  void setAdaptiveRestEnabled(bool enabled) {
    _adaptiveRestEnabled = enabled;
  }

  void setBlindModeEnabled(bool enabled) {
    state = state.copyWith(blindModeEnabled: enabled);
    if (enabled) {
      _feedbackService.enableAudio = true;
      _feedbackService.enableHaptic = true;
    }
  }

  void setGhostGateEnabled(bool enabled) {
    _engine.ghostGateEnabled = enabled;
  }

  /// Idle seconds before ghost-pause freezes counting (0 = off). Default 45.
  void setGhostIdlePauseSeconds(int seconds) {
    _engine.ghostIdlePauseSeconds = seconds;
  }

  int get ghostIdlePauseSeconds => _engine.ghostIdlePauseSeconds;

  void setExerciseTarget({required int sets, required int reps}) {
    _targets.set(state.selectedExerciseId, sets: sets, reps: reps);
    state = state.copyWith(targetSets: sets, targetReps: reps);
  }

  void clearExerciseTarget() {
    _targets.clear(state.selectedExerciseId);
    state = state.copyWith(clearTargets: true);
  }

  /// FR-B2/B15: export all history via OS share sheet.
  Future<void> exportHistory() async {
    final repo = _repository;
    if (repo == null) return;
    final history = await repo.getHistory();
    await ExportService.exportAndShare(history);
  }

  void _noteActivity() {
    _idleDisconnectTimer?.cancel();
    if (!state.isConnected || state.isCountingActive) return;
    _idleDisconnectTimer = Timer(_idleDisconnectAfter, () {
      if (!state.isCountingActive && state.isConnected) {
        unawaited(disconnect());
      }
    });
  }

  void _cancelIdleDisconnect() {
    _idleDisconnectTimer?.cancel();
    _idleDisconnectTimer = null;
  }

  /// DSGVO: clear workout DB + calibration profiles (P1-3).
  Future<void> deleteAllUserData() async {
    try {
      await _repository?.deleteAllUserData();
    } catch (_) {}
    try {
      await _calibrationStore.deleteAll();
    } catch (_) {}
    state = state.copyWith(
      hasCalibration: false,
      calibratedThreshold: null,
    );
  }

  // === App-Lifecycle (P1-2) ===

  void _initLifecycleObserver() {
    // WidgetsBinding may be unavailable in pure dart unit tests.
    try {
      _lifecycleObserver = AppLifecycleObserver(
        onStateChanged: _onAppLifecycleChanged,
      );
    } catch (_) {
      _lifecycleObserver = null;
    }
  }

  void _onAppLifecycleChanged(AppLifecycleState lifecycleState) {
    switch (lifecycleState) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Pause rest countdown while backgrounded; keep BLE reconnect active.
        if (state.isRestTimerActive) {
          _restSecondsWhenPaused = state.restTimerSecondsRemaining;
          _restTimer?.cancel();
          _restTimer = null;
        }
        break;
      case AppLifecycleState.resumed:
        if (state.isCountingActive && _sensorProvider is BleSensorProvider) {
          _updateBleDiagnostics();
        }
        // Resume rest timer if it was active when paused.
        if (_restSecondsWhenPaused != null && !state.isCountingActive) {
          final remaining = _restSecondsWhenPaused!;
          _restSecondsWhenPaused = null;
          if (remaining > 0) {
            state = state.copyWith(
              isRestTimerActive: true,
              restTimerSecondsRemaining: remaining,
            );
            _restTimer?.cancel();
            _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
              final next = state.restTimerSecondsRemaining - 1;
              if (next <= 0) {
                _stopRestTimer();
              } else {
                state = state.copyWith(restTimerSecondsRemaining: next);
              }
            });
          }
        }
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Test hook: simulate lifecycle without WidgetsBinding.
  @visibleForTesting
  void debugOnAppLifecycle(AppLifecycleState lifecycleState) {
    _onAppLifecycleChanged(lifecycleState);
  }

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

    _lastSessionSets = List.unmodifiable(_completedSets);
    _lastSessionHadPr = false;
    final repo = _repository;
    List<WorkoutSession> prior = const [];
    if (repo != null) {
      try {
        prior = await repo.getHistory();
      } catch (_) {}
    }
    for (final set in _lastSessionSets) {
      if (PersonalRecords.isRepsPr(set: set, priorSessions: prior)) {
        _lastSessionHadPr = true;
        break;
      }
    }

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
      completedSetsTowardTarget: 0,
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

  // === CV-04: optional camera fusion (stats / future UI) ===

  void setCameraEnabled(bool enabled) {
    _cameraEnabled = enabled;
    if (!enabled) {
      _poseRepCounter.reset();
    }
    state = state.copyWith(cameraEnabled: enabled);
  }

  bool get isCameraEnabled => _cameraEnabled;

  FusionEngine get fusionEngine => _fusionEngine;

  PoseRepCounter get poseRepCounter => _poseRepCounter;

  /// Feed elbow angle from CameraPoseProvider into pose counter + fusion.
  ///
  /// [confidence] must be real landmark/pose visibility for live frames
  /// (see [PoseFrameMapper.armConfidence]). Default 1.0 is only for
  /// synthetic unit paths that intentionally omit confidence.
  void processCameraAngle({
    required double elbowAngleDegrees,
    required int timestampMs,
    double confidence = 1.0,
  }) {
    if (!_cameraEnabled) return;
    final result = _poseRepCounter.processAngle(
      elbowAngleDegrees: elbowAngleDegrees,
      timestampMs: timestampMs,
    );
    if (result.repCounted) {
      _fusionEngine.onCameraRep(
        timestampMs: timestampMs,
        confidence: confidence,
      );
    }
  }

  /// Wählt eine Übung aus (V1: nur bicep_curl verfügbar).
  /// Lädt die Kalibrierung für die neue Übung neu.
  void selectExercise(String exerciseId) {
    if (exerciseId == state.selectedExerciseId) return;
    // Zählen stoppen falls aktiv
    if (state.isCountingActive) stopCounting();
    final t = _targets.of(exerciseId);
    state = state.copyWith(
      selectedExerciseId: exerciseId,
      hasCalibration: false,
      calibratedThreshold: null,
      targetSets: t?.targetSets,
      targetReps: t?.targetReps,
      clearTargets: t == null,
      clearExerciseSuggestion: true,
      completedSetsTowardTarget: 0,
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
        _sensorHealth.reset();
        _placement.reset();
        state = state.copyWith(
          isConnected: false,
          isConnecting: false,
          sensorHealthUnhealthy: false,
          clearSensorHealthMessage: true,
          placementWarn: false,
        );
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
    final delaySec =
        (1 << (attempt - 1)).clamp(1, kMaxReconnectBackoffSeconds);
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
      _checkPacketLoss(); // P2-5
    }
    // Force state update for live diagnostics
    state = state.copyWith(
      engineSampleCount: _engine.diagEngineSampleCount,
      engineThreshold: _engine.peakThreshold,
      engineBaseline: _engine.baselineLevel,
    );
  }

  /// Warns when BLE packet loss exceeds threshold while counting (P2-5).
  void _checkPacketLoss() {
    final provider = _sensorProvider;
    if (provider is! BleSensorProvider) return;
    final total =
        provider.jitterOutputFrames + provider.jitterDroppedFrames;
    if (total <= 0) return;
    final underrunRate = provider.jitterDroppedFrames / total;
    if (underrunRate > kPacketLossWarnThreshold && state.isCountingActive) {
      _setHadPacketLoss = true;
      if (state.errorText == null ||
          !(state.errorText!.contains('Paketverlust'))) {
        state = state.copyWith(
          errorText:
              'Hoher Paketverlust (${(underrunRate * 100).round()}%). '
              'Zählung möglicherweise ungenau. Stick näher ans Handy halten.',
        );
      }
    }
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
      // CV-04: notify fusion for stats only — IMU remains authoritative.
      // getDecision right after onImuRep so agreement counters advance even
      // when Form-Check is not polling frames (camera window may still match).
      final ts = DateTime.now().millisecondsSinceEpoch;
      _fusionEngine.onImuRep(timestampMs: ts);
      if (_cameraEnabled) {
        _fusionEngine.getDecision(currentTimestampMs: ts);
      }
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
    final loss = VelocityMetrics.setVelocityLossPct(completedSet.reps);
    final toward = state.completedSetsTowardTarget + 1;
    final quality = SetQualityScore.forSet(
      reps: completedSet.reps,
      packetLossWarned: _setHadPacketLoss,
      sensorUnhealthy: _setHadSensorUnhealthy || _sensorHealth.isUnhealthy,
      ghostPausedDuringSet: _setHadGhostPause,
    );
    // Reset per-set sticky flags for the next set.
    _setHadPacketLoss = false;
    _setHadGhostPause = false;
    _setHadSensorUnhealthy = _sensorHealth.isUnhealthy;
    _placement.reset();
    state = state.copyWith(
      lastSetVelocityLossPct: loss,
      completedSetsTowardTarget: toward,
      lastSetQualityScore: quality.score01,
      lastSetQualityLabel: '${quality.label} (${quality.percent}%)',
      lastQualityScore: quality.score01,
      placementWarn: false,
    );
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
        errorText: BleErrorMapper.toUserMessage(e),
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
      final low = percent > 0 && percent < 15;
      state = state.copyWith(
        batteryPercent: percent,
        // Sticky until reconnect — UI shows snackbar once via home listener.
        lowBatteryWarned: low ? true : state.lowBatteryWarned,
      );
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
        minThresholdAboveBaseline: kMinThresholdAboveBaseline,
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
  /// When [autoArmAfterCalib] is on and device is connected, starts counting
  /// so users do not hit the silent 0-rep trap (Audit QW-2).
  void reloadCalibration() {
    unawaited(_reloadCalibrationAndMaybeArm());
  }

  Future<void> _reloadCalibrationAndMaybeArm() async {
    await _loadCalibration();
    if (!_autoArmAfterCalib) return;
    if (!state.isConnected || !state.hasCalibration) return;
    if (state.isCountingActive) return;
    startCounting();
    AppLogger.i('Auto-arm after calib → startCounting');
  }

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
    _cancelIdleDisconnect();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _lifecycleObserver?.dispose();
    _lifecycleObserver = null;
    unawaited(_fgService.stop());
    _samplesSub?.cancel();
    _eventsSub?.cancel();
    _recorderSamplesSub?.cancel();
    _connectionSub?.cancel();
    _deviceEventSub?.cancel();
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

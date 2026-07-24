import '../../domain/workout_engine.dart';

/// Immutable UI-State für den HomeScreen (SPEC TEIL 6, §6.2).
///
/// Wird von [EngineNotifier] verwaltet und von Widgets via Riverpod konsumiert.
class WorkoutUiState {
  final WorkoutState workoutState;
  final int repsInCurrentSet;
  final int? lastCompletedSetCount;
  final double? lastQualityScore;
  final double? calibratedThreshold;
  final int calibrationPeaksFound;
  final bool isConnected;
  final bool isConnecting;
  final int? batteryPercent;
  final String? errorText;

  // BLE-Diagnostik (nur !kReleaseMode relevant)
  final int? mtu;
  final int? receivedBatches;
  final double? pollingRateHz;
  final int? parseErrors;
  final int? engineSampleCount;
  final double? engineThreshold;
  final double? engineBaseline;

  // CSV-Recording
  final bool isRecording;
  final int recordedSampleCount;
  final String? lastRecordingFileName;

  // Zähl-Gating (Start-Button)
  final bool isCountingActive;

  // Exercise Selection
  final String selectedExerciseId;
  final bool hasCalibration;

  // Manuelle Korrektur (SPEC §5.1.4 / P0-1)
  final bool showCorrectionDialog;
  final int? correctionSetCountedReps;
  final int? correctionSetUserReps;

  // Pausen-Timer (SPEC Phase 2 / P0-2)
  final bool isRestTimerActive;
  final int restTimerSecondsRemaining;

  // Session-Zusammenfassung (P0-3)
  final bool showSessionSummary;
  final int sessionTotalSets;
  final int sessionTotalReps;
  final Duration? sessionDuration;

  // Reconnection (P0-4)
  final bool isReconnecting;
  final int reconnectAttempt;

  // Optional CV camera validator (CV-04 UI)
  final bool cameraEnabled;

  // Doc 15: diagnose overlay, VBT, ghost, blind mode, low battery
  final bool diagnoseOverlayEnabled;
  final bool vbtMetricsEnabled;
  final bool ghostGatePaused;
  /// User dismissed ghost banner for current pause streak (Audit QW-3).
  final bool ghostBannerDismissed;
  final bool blindModeEnabled;
  final bool lowBatteryWarned;
  final double? lastSetVelocityLossPct;
  final String? exerciseSuggestion;
  final double? exerciseSuggestionConfidence;

  // Exercise targets (FR-B9)
  final int? targetSets;
  final int? targetReps;
  final int completedSetsTowardTarget;

  const WorkoutUiState({
    this.workoutState = WorkoutState.idle,
    this.repsInCurrentSet = 0,
    this.lastCompletedSetCount,
    this.lastQualityScore,
    this.calibratedThreshold,
    this.calibrationPeaksFound = 0,
    this.isConnected = false,
    this.isConnecting = false,
    this.batteryPercent,
    this.errorText,
    this.mtu,
    this.receivedBatches,
    this.pollingRateHz,
    this.parseErrors,
    this.engineSampleCount,
    this.engineThreshold,
    this.engineBaseline,
    this.isRecording = false,
    this.recordedSampleCount = 0,
    this.lastRecordingFileName,
    this.isCountingActive = false,
    this.selectedExerciseId = 'bicep_curl',
    this.hasCalibration = false,
    this.showCorrectionDialog = false,
    this.correctionSetCountedReps,
    this.correctionSetUserReps,
    this.isRestTimerActive = false,
    this.restTimerSecondsRemaining = 90,
    this.showSessionSummary = false,
    this.sessionTotalSets = 0,
    this.sessionTotalReps = 0,
    this.sessionDuration,
    this.isReconnecting = false,
    this.reconnectAttempt = 0,
    this.cameraEnabled = false,
    this.diagnoseOverlayEnabled = false,
    this.vbtMetricsEnabled = true,
    this.ghostGatePaused = false,
    this.ghostBannerDismissed = false,
    this.blindModeEnabled = false,
    this.lowBatteryWarned = false,
    this.lastSetVelocityLossPct,
    this.exerciseSuggestion,
    this.exerciseSuggestionConfidence,
    this.targetSets,
    this.targetReps,
    this.completedSetsTowardTarget = 0,
  });

  WorkoutUiState copyWith({
    WorkoutState? workoutState,
    int? repsInCurrentSet,
    int? lastCompletedSetCount,
    double? lastQualityScore,
    double? calibratedThreshold,
    int? calibrationPeaksFound,
    bool? isConnected,
    bool? isConnecting,
    int? batteryPercent,
    String? errorText,
    int? mtu,
    int? receivedBatches,
    double? pollingRateHz,
    int? parseErrors,
    int? engineSampleCount,
    double? engineThreshold,
    double? engineBaseline,
    bool? isRecording,
    int? recordedSampleCount,
    String? lastRecordingFileName,
    bool? isCountingActive,
    String? selectedExerciseId,
    bool? hasCalibration,
    bool? showCorrectionDialog,
    int? correctionSetCountedReps,
    int? correctionSetUserReps,
    bool? isRestTimerActive,
    int? restTimerSecondsRemaining,
    bool? showSessionSummary,
    int? sessionTotalSets,
    int? sessionTotalReps,
    Duration? sessionDuration,
    bool? isReconnecting,
    int? reconnectAttempt,
    bool? cameraEnabled,
    bool? diagnoseOverlayEnabled,
    bool? vbtMetricsEnabled,
    bool? ghostGatePaused,
    bool? ghostBannerDismissed,
    bool? blindModeEnabled,
    bool? lowBatteryWarned,
    double? lastSetVelocityLossPct,
    bool clearLastSetVelocityLossPct = false,
    String? exerciseSuggestion,
    bool clearExerciseSuggestion = false,
    double? exerciseSuggestionConfidence,
    int? targetSets,
    int? targetReps,
    bool clearTargets = false,
    int? completedSetsTowardTarget,
  }) {
    return WorkoutUiState(
      workoutState: workoutState ?? this.workoutState,
      repsInCurrentSet: repsInCurrentSet ?? this.repsInCurrentSet,
      lastCompletedSetCount: lastCompletedSetCount ?? this.lastCompletedSetCount,
      lastQualityScore: lastQualityScore ?? this.lastQualityScore,
      calibratedThreshold: calibratedThreshold ?? this.calibratedThreshold,
      calibrationPeaksFound: calibrationPeaksFound ?? this.calibrationPeaksFound,
      isConnected: isConnected ?? this.isConnected,
      isConnecting: isConnecting ?? this.isConnecting,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      errorText: errorText,
      mtu: mtu ?? this.mtu,
      receivedBatches: receivedBatches ?? this.receivedBatches,
      pollingRateHz: pollingRateHz ?? this.pollingRateHz,
      parseErrors: parseErrors ?? this.parseErrors,
      engineSampleCount: engineSampleCount ?? this.engineSampleCount,
      engineThreshold: engineThreshold ?? this.engineThreshold,
      engineBaseline: engineBaseline ?? this.engineBaseline,
      isRecording: isRecording ?? this.isRecording,
      recordedSampleCount: recordedSampleCount ?? this.recordedSampleCount,
      lastRecordingFileName: lastRecordingFileName ?? this.lastRecordingFileName,
      isCountingActive: isCountingActive ?? this.isCountingActive,
      selectedExerciseId: selectedExerciseId ?? this.selectedExerciseId,
      hasCalibration: hasCalibration ?? this.hasCalibration,
      showCorrectionDialog:
          showCorrectionDialog ?? this.showCorrectionDialog,
      correctionSetCountedReps:
          correctionSetCountedReps ?? this.correctionSetCountedReps,
      correctionSetUserReps:
          correctionSetUserReps ?? this.correctionSetUserReps,
      isRestTimerActive: isRestTimerActive ?? this.isRestTimerActive,
      restTimerSecondsRemaining:
          restTimerSecondsRemaining ?? this.restTimerSecondsRemaining,
      showSessionSummary: showSessionSummary ?? this.showSessionSummary,
      sessionTotalSets: sessionTotalSets ?? this.sessionTotalSets,
      sessionTotalReps: sessionTotalReps ?? this.sessionTotalReps,
      sessionDuration: sessionDuration ?? this.sessionDuration,
      isReconnecting: isReconnecting ?? this.isReconnecting,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      cameraEnabled: cameraEnabled ?? this.cameraEnabled,
      diagnoseOverlayEnabled:
          diagnoseOverlayEnabled ?? this.diagnoseOverlayEnabled,
      vbtMetricsEnabled: vbtMetricsEnabled ?? this.vbtMetricsEnabled,
      ghostGatePaused: ghostGatePaused ?? this.ghostGatePaused,
      ghostBannerDismissed:
          ghostBannerDismissed ?? this.ghostBannerDismissed,
      blindModeEnabled: blindModeEnabled ?? this.blindModeEnabled,
      lowBatteryWarned: lowBatteryWarned ?? this.lowBatteryWarned,
      lastSetVelocityLossPct: clearLastSetVelocityLossPct
          ? null
          : (lastSetVelocityLossPct ?? this.lastSetVelocityLossPct),
      exerciseSuggestion: clearExerciseSuggestion
          ? null
          : (exerciseSuggestion ?? this.exerciseSuggestion),
      exerciseSuggestionConfidence: clearExerciseSuggestion
          ? null
          : (exerciseSuggestionConfidence ?? this.exerciseSuggestionConfidence),
      targetSets: clearTargets ? null : (targetSets ?? this.targetSets),
      targetReps: clearTargets ? null : (targetReps ?? this.targetReps),
      completedSetsTowardTarget:
          completedSetsTowardTarget ?? this.completedSetsTowardTarget,
    );
  }
}

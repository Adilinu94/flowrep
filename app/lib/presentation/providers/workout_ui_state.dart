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
    );
  }
}

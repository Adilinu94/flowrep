import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/ble_sensor_provider.dart';
import '../providers/engine_provider.dart';
import '../providers/workout_ui_state.dart';
import '../widgets/connection_status_card.dart';
import '../widgets/correction_dialog.dart';
import '../widgets/exercise_selector_card.dart';
import '../widgets/onboarding_banner.dart';
import '../widgets/rep_counter_display.dart';
import '../widgets/set_history_card.dart';
import '../widgets/signal_debug_view.dart';
import 'calibration/calibration_wizard_screen.dart';
import 'history_screen.dart';

/// HomeScreen (SPEC TEIL 6, §6.4): ~150 Zeilen statt 734.
///
/// Konsumiert [engineProvider] via Riverpod. Alle Geschäftslogik
/// lebt in [EngineNotifier], alle UI-Bausteine in separaten Widgets.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiState = ref.watch(engineProvider);
    final notifier = ref.read(engineProvider.notifier);

    // Korrektur-Dialog (P0-1 SPEC §5.1.4)
    ref.listen<WorkoutUiState>(engineProvider, (prev, next) {
      if (next.showCorrectionDialog && !(prev?.showCorrectionDialog ?? false)) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => Consumer(
            builder: (context, dialogRef, _) {
              final s = dialogRef.watch(engineProvider);
              return CorrectionDialog(
                countedReps: s.correctionSetCountedReps ?? 0,
                userReps: s.correctionSetUserReps ?? 0,
                onIncrement: () => notifier.applyCorrectionDelta(1),
                onDecrement: () => notifier.applyCorrectionDelta(-1),
                onConfirm: () async {
                  await notifier.confirmCorrection();
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                onDismiss: () {
                  notifier.dismissCorrection();
                  Navigator.of(dialogContext).pop();
                },
              );
            },
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('FlowRep'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Verlauf',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Verbindungsstatus
              ConnectionStatusCard(
                statusText: _statusText(uiState, notifier.isMock),
                isConnected: uiState.isConnected,
                batteryPercent: uiState.batteryPercent,
                errorText: uiState.errorText,
                onConnect: notifier.connect,
                onDisconnect: notifier.disconnect,
              ),
              const SizedBox(height: 16),

              // Debug-Diagnostik (nur !kReleaseMode + BLE)
              if (uiState.isConnected && !notifier.isMock)
                SignalDebugView(
                  uiState: uiState,
                  workoutStateName: uiState.workoutState.name,
                ),

              if (uiState.isConnected) ...[
                const SizedBox(height: 16),

                // Übungsauswahl
                ExerciseSelectorCard(
                  selectedExerciseId: uiState.selectedExerciseId,
                  hasCalibration: uiState.hasCalibration,
                  onExerciseSelected: notifier.selectExercise,
                ),
                const SizedBox(height: 16),

                // Onboarding (nur wenn nicht kalibriert)
                if (!uiState.hasCalibration && !notifier.isMock)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: OnboardingBanner(
                      isConnected: uiState.isConnected,
                      hasCalibration: uiState.hasCalibration,
                      onCalibratePressed: () =>
                          _openCalibrationWizard(context, notifier),
                    ),
                  ),

                // Start/Stop Zähl-Gating
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: uiState.isCountingActive
                        ? notifier.stopCounting
                        : notifier.startCounting,
                    icon: Icon(
                      uiState.isCountingActive
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_outline,
                      size: 28,
                    ),
                    label: Text(
                      uiState.isCountingActive
                          ? 'Zählen stoppen'
                          : 'Zählen starten',
                      style: const TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: uiState.isCountingActive
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Rep-Counter
                RepCounterDisplay(
                  repCount: uiState.repsInCurrentSet,
                  qualityScore: uiState.lastQualityScore,
                ),
                const SizedBox(height: 8),
                Text('Zustand: ${uiState.workoutState.name}'),
                const SizedBox(height: 8),
                // Letzter Satz
                SetHistoryCard(lastSetCount: uiState.lastCompletedSetCount),
                const SizedBox(height: 16),

                // Mock: Rep simulieren
                if (notifier.isMock)
                  ElevatedButton(
                    onPressed: notifier.simulateRepetition,
                    child: const Text('Wiederholung simulieren (Mock)'),
                  ),

                // BLE: Dummy-Stream + Kalibrierung
                if (!notifier.isMock) ...[
                  ElevatedButton(
                    onPressed: notifier.toggleDummyStream,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                    child: const Text('Dummy Stream',
                        style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _openCalibrationWizard(context, notifier),
                    icon: const Icon(Icons.tune),
                    label: const Text('Mit Assistent kalibrieren'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],

                // Kalibrierungs-Info
                if (uiState.calibratedThreshold != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Kalibriert: ${uiState.calibratedThreshold!.toStringAsFixed(2)}g '
                    '(${uiState.calibrationPeaksFound} Peaks)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],

                // CSV-Recording (nur Debug + BLE)
                if (!kReleaseMode && !notifier.isMock) ...[
                  const SizedBox(height: 12),
                  _buildRecordingSection(context, uiState, notifier),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingSection(
    BuildContext context,
    WorkoutUiState uiState,
    EngineNotifier notifier,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: notifier.toggleRecording,
              icon: Icon(
                  uiState.isRecording ? Icons.stop : Icons.fiber_manual_record),
              label: Text(uiState.isRecording
                  ? 'Aufnahme stoppen (${uiState.recordedSampleCount})'
                  : 'Aufnahme starten'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    uiState.isRecording ? Colors.red : Colors.red.shade200,
                foregroundColor: Colors.white,
              ),
            ),
            if (notifier.hasLastRecording) ...[
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: notifier.shareLastRecording,
                icon: const Icon(Icons.share),
                label: const Text('Teilen'),
              ),
            ],
          ],
        ),
        if (uiState.lastRecordingFileName != null)
          Text(
            'Gespeichert: ${uiState.lastRecordingFileName}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  Future<void> _openCalibrationWizard(
      BuildContext context, EngineNotifier notifier) async {
    final provider = notifier.sensorProvider;
    if (provider is! BleSensorProvider) return;
    final deviceId = provider.remoteId;
    if (deviceId == null) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => CalibrationWizardScreen(
          samples: provider.samples,
          exerciseId: notifier.engine.exerciseId,
          deviceId: deviceId,
        ),
      ),
    );
    if (saved == true) {
      notifier.reloadCalibration();
    }
  }

  String _statusText(WorkoutUiState uiState, bool isMock) {
    if (uiState.isConnected) {
      return isMock ? 'Verbunden (Mock)' : 'Verbunden (BLE)';
    }
    if (uiState.isConnecting) {
      return isMock ? 'Verbinde (Mock) …' : 'Verbinde mit GymTracker …';
    }
    return 'Getrennt';
  }
}

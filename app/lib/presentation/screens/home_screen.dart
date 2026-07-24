import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/ble_sensor_provider.dart';
import '../../domain/workout_engine.dart' show WorkoutState;
import '../providers/engine_provider.dart';
import '../providers/workout_ui_state.dart';
import '../widgets/connection_status_card.dart';
import '../widgets/correction_dialog.dart';
import '../widgets/counting_status_chip.dart';
import '../widgets/diagnose_overlay.dart';
import '../widgets/exercise_selector_card.dart';
import '../widgets/onboarding_banner.dart';
import '../widgets/rep_counter_display.dart';
import '../widgets/rest_timer_widget.dart';
import '../widgets/session_summary_dialog.dart';
import '../widgets/set_history_card.dart';
import '../widgets/signal_debug_view.dart';
import '../widgets/fusion_status_badge.dart';
import 'calibration/calibration_wizard_screen.dart';
import 'camera_session_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

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

    // Dialoge (P0-1 Korrektur, P0-3 Session-Zusammenfassung)
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
                  final msg = await notifier.confirmCorrection();
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  if (msg != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg)),
                    );
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
      if (next.showSessionSummary && !(prev?.showSessionSummary ?? false)) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => SessionSummaryDialog(
            totalSets: next.sessionTotalSets,
            totalReps: next.sessionTotalReps,
            duration: next.sessionDuration,
            sets: notifier.lastSessionSets,
            showPrBadge: notifier.lastSessionHadPr,
            onDismiss: () {
              notifier.dismissSessionSummary();
              Navigator.of(dialogContext).pop();
            },
          ),
        );
      }
      // FR-A2: low battery snackbar once when crossing into warned state.
      if (next.lowBatteryWarned &&
          next.batteryPercent != null &&
          next.batteryPercent! < 15 &&
          !(prev?.lowBatteryWarned ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'M5-Akku niedrig (${next.batteryPercent} %). Bitte laden.',
            ),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('FlowRep'),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip: 'Form-Check (Kamera, zählt nicht statt IMU)',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CameraSessionScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Einstellungen',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
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
          child: uiState.isCountingActive
              ? _buildActiveSetBody(context, uiState, notifier)
              : _buildSetupBody(context, uiState, notifier),
        ),
      ),
    );
  }

  /// Gym-first HUD while counting (Audit U-01 Active Set).
  Widget _buildActiveSetBody(
    BuildContext context,
    WorkoutUiState uiState,
    EngineNotifier notifier,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CountingStatusChip(uiState: uiState),
        if (uiState.batteryPercent != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'M5 ${uiState.batteryPercent}%'
              '${uiState.isReconnecting ? ' · Reconnect…' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 12),
        ..._healthBanners(context, uiState, notifier),
        RepCounterDisplay(
          repCount: uiState.repsInCurrentSet,
          qualityScore: uiState.lastQualityScore,
        ),
        if (uiState.targetSets != null && uiState.targetReps != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Ziel: Satz ${uiState.completedSetsTowardTarget}/'
              '${uiState.targetSets} · ${uiState.targetReps} Wdh.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.tonalIcon(
            onPressed: uiState.repsInCurrentSet > 0 ||
                    uiState.workoutState == WorkoutState.active ||
                    uiState.workoutState == WorkoutState.calibrating
                ? notifier.endSetManually
                : null,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Satz beenden', style: TextStyle(fontSize: 18)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: notifier.stopCounting,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Zählen stoppen'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Satz endet nur manuell — danach echte Reps bestätigen. M5 BtnA = Satzende.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        if (uiState.isRestTimerActive) ...[
          const SizedBox(height: 16),
          RestTimerWidget(
            secondsRemaining: uiState.restTimerSecondsRemaining,
            totalSeconds: notifier.restDurationSeconds,
            onSkip: notifier.skipRest,
          ),
        ],
        TextButton.icon(
          onPressed: () => _confirmEndSession(context, notifier),
          icon: const Icon(Icons.stop, size: 18),
          label: const Text('Training beenden'),
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
        ),
        if (uiState.diagnoseOverlayEnabled) ...[
          const SizedBox(height: 8),
          DiagnoseOverlay(
            uiState: uiState,
            engine: notifier.engine,
            packetLossHint: uiState.errorText != null &&
                    uiState.errorText!.contains('Paketverlust')
                ? uiState.errorText
                : null,
          ),
        ],
        if (notifier.isMock)
          ElevatedButton(
            onPressed: notifier.simulateRepetition,
            child: const Text('Wiederholung simulieren (Mock)'),
          ),
      ],
    );
  }

  /// Setup / between-sets layout (connection, calib, history, debug).
  Widget _buildSetupBody(
    BuildContext context,
    WorkoutUiState uiState,
    EngineNotifier notifier,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ConnectionStatusCard(
          statusText: _statusText(uiState, notifier.isMock),
          isConnected: uiState.isConnected,
          batteryPercent: uiState.batteryPercent,
          errorText: uiState.errorText,
          onConnect: notifier.connect,
          onDisconnect: notifier.disconnect,
        ),
        const SizedBox(height: 10),
        CountingStatusChip(uiState: uiState),
        if (uiState.cameraEnabled) ...[
          const SizedBox(height: 8),
          FusionStatusBadge(
            cameraEnabled: true,
            imuOnlyReps: notifier.fusionEngine.imuOnlyReps,
            cameraOnlyReps: notifier.fusionEngine.cameraOnlyReps,
            fusedReps: notifier.fusionEngine.fusedReps,
            poseReps: notifier.poseRepCounter.repCount,
          ),
        ],
        if (uiState.isReconnecting)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Verbindung verloren — Versuch ${uiState.reconnectAttempt}…',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade800,
                      ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        if (uiState.isConnected &&
            !notifier.isMock &&
            !uiState.diagnoseOverlayEnabled)
          SignalDebugView(
            uiState: uiState,
            workoutStateName: uiState.workoutState.name,
          ),
        if (uiState.diagnoseOverlayEnabled) ...[
          DiagnoseOverlay(
            uiState: uiState,
            engine: notifier.engine,
            packetLossHint: uiState.errorText != null &&
                    uiState.errorText!.contains('Paketverlust')
                ? uiState.errorText
                : null,
          ),
          const SizedBox(height: 8),
        ],
        ..._healthBanners(context, uiState, notifier),
        if (uiState.exerciseSuggestion != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: Text(
                'Vorschlag: ${uiState.exerciseSuggestion}'
                '${uiState.exerciseSuggestionConfidence != null ? ' (${(uiState.exerciseSuggestionConfidence! * 100).round()} %)' : ''}',
              ),
              subtitle: const Text(
                'Nur Hinweis — IMU zählt weiter mit der gewählten Übung.',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: notifier.dismissExerciseSuggestion,
                    child: const Text('Nein'),
                  ),
                  FilledButton(
                    onPressed: notifier.acceptExerciseSuggestion,
                    child: const Text('Übernehmen'),
                  ),
                ],
              ),
            ),
          ),
        if (uiState.isConnected) ...[
          const SizedBox(height: 16),
          ExerciseSelectorCard(
            selectedExerciseId: uiState.selectedExerciseId,
            hasCalibration: uiState.hasCalibration,
            onExerciseSelected: notifier.selectExercise,
          ),
          const SizedBox(height: 16),
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
          if (uiState.hasCalibration)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Tippe „Zählen starten“ (oder M5 BtnA) — sonst bleiben Reps bei 0.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: notifier.startCounting,
              icon: const Icon(Icons.play_circle_outline, size: 28),
              label: const Text('Zählen starten', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          if (uiState.lastCompletedSetCount != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _confirmEndSession(context, notifier),
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Training beenden'),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            ),
          ],
          const SizedBox(height: 16),
          RepCounterDisplay(
            repCount: uiState.repsInCurrentSet,
            qualityScore: uiState.lastQualityScore,
          ),
          if (uiState.lastSetQualityLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Letzter Satz: ${uiState.lastSetQualityLabel}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (uiState.targetSets != null && uiState.targetReps != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Ziel: Satz ${uiState.completedSetsTowardTarget}/'
                '${uiState.targetSets} · ${uiState.targetReps} Wdh.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (uiState.vbtMetricsEnabled &&
              uiState.lastSetVelocityLossPct != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Letzter Satz Velocity-Loss: '
                '${uiState.lastSetVelocityLossPct!.toStringAsFixed(0)} % '
                '(relativ)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (uiState.isRestTimerActive) ...[
            const SizedBox(height: 16),
            RestTimerWidget(
              secondsRemaining: uiState.restTimerSecondsRemaining,
              totalSeconds: notifier.restDurationSeconds,
              onSkip: notifier.skipRest,
            ),
          ],
          const SizedBox(height: 8),
          SetHistoryCard(
            lastSetCount: uiState.lastCompletedSetCount,
            velocityLossPct: uiState.vbtMetricsEnabled
                ? uiState.lastSetVelocityLossPct
                : null,
          ),
          const SizedBox(height: 16),
          if (notifier.isMock)
            ElevatedButton(
              onPressed: notifier.simulateRepetition,
              child: const Text('Wiederholung simulieren (Mock)'),
            ),
          if (!notifier.isMock) ...[
            ElevatedButton(
              onPressed: notifier.toggleDummyStream,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Dummy Stream', style: TextStyle(fontSize: 12)),
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
          if (uiState.calibratedThreshold != null) ...[
            const SizedBox(height: 8),
            Text(
              'Kalibriert: θ=${uiState.calibratedThreshold!.toStringAsFixed(1)} '
              '(${uiState.calibrationPeaksFound} Peaks)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (!kReleaseMode && !notifier.isMock) ...[
            const SizedBox(height: 12),
            _buildRecordingSection(context, uiState, notifier),
          ],
        ],
      ],
    );
  }

  List<Widget> _healthBanners(
    BuildContext context,
    WorkoutUiState uiState,
    EngineNotifier notifier,
  ) {
    final out = <Widget>[];
    if (uiState.sensorHealthUnhealthy && uiState.sensorHealthMessage != null) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MaterialBanner(
            backgroundColor: Colors.red.shade50,
            content: Text(uiState.sensorHealthMessage!),
            actions: const [SizedBox.shrink()],
          ),
        ),
      );
    }
    if (uiState.placementWarn) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MaterialBanner(
            backgroundColor: Colors.amber.shade50,
            content: const Text(
              'Bewegung erkannt, aber wenig Signal auf der gelernten Achse. '
              'Sensorlage prüfen und ggf. neu kalibrieren.',
            ),
            actions: const [SizedBox.shrink()],
          ),
        ),
      );
    }
    if (uiState.ghostGatePaused && !uiState.ghostBannerDismissed) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MaterialBanner(
            content: const Text(
              'Zählung pausiert: wenig Bewegung erkannt '
              '(Ablegen/Wackeln). Weiter trainieren zum Fortsetzen.',
            ),
            actions: [
              TextButton(
                onPressed: notifier.dismissGhostBanner,
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
    }
    return out;
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

  void _confirmEndSession(BuildContext context, EngineNotifier notifier) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Training beenden?'),
        content: const Text(
          'Möchtest du das Training beenden? '
          'Alle Sätze werden gespeichert.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              notifier.endSession();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Beenden'),
          ),
        ],
      ),
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
      return isMock ? 'Verbinde (Mock) …' : 'Verbinde mit FlowRep …';
    }
    return 'Getrennt';
  }
}

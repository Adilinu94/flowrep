import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/export_service.dart';
import '../providers/engine_provider.dart';
import 'camera_session_screen.dart';
import 'sensor_placement_tutorial.dart';

/// Einstellungs-Screen (P1-3): Feedback, Pausen-Timer, Datenschutz, Info.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late bool _hapticEnabled;
  late bool _audioEnabled;
  late int _restDurationSeconds;
  late bool _vbtEnabled;
  late bool _adaptiveRest;
  late bool _blindMode;
  late bool _diagnose;
  int _targetSets = 4;
  int _targetReps = 12;

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(engineProvider.notifier);
    final ui = ref.read(engineProvider);
    _hapticEnabled = notifier.hapticEnabled;
    _audioEnabled = notifier.audioEnabled;
    _restDurationSeconds = notifier.restDurationSeconds;
    _vbtEnabled = notifier.vbtEnabled;
    _adaptiveRest = notifier.adaptiveRestEnabled;
    _blindMode = ui.blindModeEnabled;
    _diagnose = ui.diagnoseOverlayEnabled;
    _targetSets = ui.targetSets ?? 4;
    _targetReps = ui.targetReps ?? 12;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(engineProvider.notifier);
    final ui = ref.watch(engineProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Feedback', style: Theme.of(context).textTheme.titleSmall),
          SwitchListTile(
            title: const Text('Vibration bei Wiederholung'),
            value: _hapticEnabled,
            onChanged: (v) {
              setState(() => _hapticEnabled = v);
              notifier.setFeedback(haptic: v);
            },
          ),
          SwitchListTile(
            title: const Text('Sound bei Wiederholung'),
            value: _audioEnabled,
            onChanged: (v) {
              setState(() => _audioEnabled = v);
              notifier.setFeedback(audio: v);
            },
          ),
          SwitchListTile(
            title: const Text('Audio-First / Blind-Mode'),
            subtitle: const Text('Haptik+Sound für Training ohne Blick aufs Display'),
            value: _blindMode,
            onChanged: (v) {
              setState(() => _blindMode = v);
              notifier.setBlindModeEnabled(v);
            },
          ),
          const Divider(),
          Text('Pausen-Timer', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 60, label: Text('60s')),
              ButtonSegment(value: 90, label: Text('90s')),
              ButtonSegment(value: 120, label: Text('120s')),
            ],
            selected: {_restDurationSeconds},
            onSelectionChanged: (s) => _setRest(notifier, s.first),
          ),
          SwitchListTile(
            title: const Text('Adaptive Pause (VBT)'),
            subtitle: const Text('Längere Pause bei hohem Velocity-Loss'),
            value: _adaptiveRest,
            onChanged: (v) {
              setState(() => _adaptiveRest = v);
              notifier.setAdaptiveRestEnabled(v);
            },
          ),
          const Divider(),
          Text('Metriken & Training', style: Theme.of(context).textTheme.titleSmall),
          SwitchListTile(
            title: const Text('Velocity-Metriken anzeigen'),
            subtitle: const Text('Relative Peak/Loss — keine m/s'),
            value: _vbtEnabled,
            onChanged: (v) {
              setState(() => _vbtEnabled = v);
              notifier.setVbtMetricsEnabled(v);
            },
          ),
          ListTile(
            title: const Text('Ziel Sätze × Reps'),
            subtitle: Text('Aktuell: $_targetSets × $_targetReps'),
            trailing: FilledButton.tonal(
              onPressed: () {
                notifier.setExerciseTarget(sets: _targetSets, reps: _targetReps);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Ziel $_targetSets×$_targetReps für ${ui.selectedExerciseId}',
                    ),
                  ),
                );
              },
              child: const Text('Setzen'),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _targetSets.toDouble(),
                  min: 1,
                  max: 8,
                  divisions: 7,
                  label: '$_targetSets Sätze',
                  onChanged: (v) => setState(() => _targetSets = v.round()),
                ),
              ),
              Expanded(
                child: Slider(
                  value: _targetReps.toDouble(),
                  min: 3,
                  max: 20,
                  divisions: 17,
                  label: '$_targetReps Wdh',
                  onChanged: (v) => setState(() => _targetReps = v.round()),
                ),
              ),
            ],
          ),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('Sensor-Platzierung'),
            subtitle: const Text('Kurzes Tutorial'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SensorPlacementTutorial(),
                ),
              );
            },
          ),
          const Divider(),
          Text('Kamera (optional)', style: Theme.of(context).textTheme.titleSmall),
          SwitchListTile(
            title: const Text('Kamera-Validierung freigeben'),
            subtitle: const Text('Öffnet den Kamera-Validator (IMU bleibt primär)'),
            value: ui.cameraEnabled,
            onChanged: (v) {
              notifier.setCameraEnabled(v);
              setState(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.videocam),
            title: const Text('Kamera-Session öffnen'),
            subtitle: const Text('Preview + Pose-Fusion-Stats'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CameraSessionScreen(),
                ),
              );
            },
          ),
          const Divider(),
          Text('Entwickler', style: Theme.of(context).textTheme.titleSmall),
          SwitchListTile(
            title: const Text('Diagnose-Overlay'),
            subtitle: const Text('Envelope, θ, Ghost-Gate, Shadow, BLE'),
            value: _diagnose,
            onChanged: (v) {
              setState(() => _diagnose = v);
              notifier.setDiagnoseOverlayEnabled(v);
            },
          ),
          SwitchListTile(
            title: const Text('Ghost-Rep-Watchdog'),
            subtitle: const Text(
              'Pausiert Zählung nur nach längerer Ruhe (Ablegen), '
              'nicht nach kurzen Pausen zwischen Reps',
            ),
            value: notifier.engine.ghostGateEnabled,
            onChanged: (v) {
              notifier.setGhostGateEnabled(v);
              setState(() {});
            },
          ),
          if (notifier.engine.ghostGateEnabled) ...[
            Text(
              'Ghost-Pause nach Inaktivität',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 30, label: Text('30s')),
                ButtonSegment(value: 45, label: Text('45s')),
                ButtonSegment(value: 90, label: Text('90s')),
                ButtonSegment(value: 0, label: Text('Aus')),
              ],
              selected: {notifier.ghostIdlePauseSeconds},
              onSelectionChanged: (s) {
                notifier.setGhostIdlePauseSeconds(s.first);
                setState(() {});
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Default 45 s — kurze Satz-Pausen zählen weiter.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const Divider(),
          Text('Datenschutz & Export', style: Theme.of(context).textTheme.titleSmall),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Trainingsdaten exportieren'),
            subtitle: const Text(ExportService.privacyNotice, maxLines: 3),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await notifier.exportHistory();
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('Export gestartet (Share-Sheet).')),
                );
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text('Export fehlgeschlagen: $e')),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Alle Daten löschen'),
            subtitle: const Text('DSGVO: entfernt alle lokalen Daten'),
            onTap: () => _confirmDeleteAllData(notifier),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('FlowRep'),
            subtitle: Text('Version 1.0.0-rc.1'),
          ),
        ],
      ),
    );
  }

  void _setRest(EngineNotifier notifier, int seconds) {
    setState(() => _restDurationSeconds = seconds);
    notifier.setRestDurationSeconds(seconds);
  }

  Future<void> _confirmDeleteAllData(EngineNotifier notifier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alle Daten löschen?'),
        content: const Text(
          'Dies entfernt ALLE gespeicherten Workouts und Kalibrierungen. '
          'Diese Aktion kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await notifier.deleteAllUserData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alle Daten wurden gelöscht.')),
      );
    }
  }
}

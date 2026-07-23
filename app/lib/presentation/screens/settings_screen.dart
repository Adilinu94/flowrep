import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/engine_provider.dart';
import 'camera_session_screen.dart';

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

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(engineProvider.notifier);
    _hapticEnabled = notifier.hapticEnabled;
    _audioEnabled = notifier.audioEnabled;
    _restDurationSeconds = notifier.restDurationSeconds;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(engineProvider.notifier);

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
          const Divider(),
          Text('Kamera (optional)', style: Theme.of(context).textTheme.titleSmall),
          SwitchListTile(
            title: const Text('Kamera-Validierung freigeben'),
            subtitle: const Text('Öffnet den Kamera-Validator (IMU bleibt primär)'),
            value: ref.watch(engineProvider).cameraEnabled,
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
          Text('Datenschutz', style: Theme.of(context).textTheme.titleSmall),
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
            subtitle: Text('Version 1.0.0'),
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

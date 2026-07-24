import 'package:flutter/material.dart';

/// Short sensor placement tutorial (Doc 15 FR-B7).
class SensorPlacementTutorial extends StatelessWidget {
  const SensorPlacementTutorial({super.key, this.onDone});

  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sensor platzieren')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            Icons.watch,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'So sitzt der M5StickC am besten',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const _Step(
            n: 1,
            title: 'Unterarm, stramm aber bequem',
            body:
                'Befestige den Stick am trainierenden Arm (z. B. Bizeps-Curl), '
                'Display idealerweise nach außen/oben — immer gleich pro Übung.',
          ),
          const _Step(
            n: 2,
            title: 'Kalibrierung nicht überspringen',
            body:
                'Guided Calib lernt deine Bewegungsachse. Ohne Calib zählt die '
                'App ungenauer und empfindlicher für Wackeln.',
          ),
          const _Step(
            n: 3,
            title: 'Während des Satzes fest tragen',
            body:
                'Ablegen oder wildes Schütteln kann Ghost-Reps erzeugen. '
                'Nach dem Satz „Satz beenden“ tippen.',
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              onDone?.call();
              Navigator.of(context).maybePop();
            },
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.body});

  final int n;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            child: Text('$n', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(body, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

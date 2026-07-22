import 'package:flutter/material.dart';

import '../../data/providers/ble_sensor_provider.dart';
import '../../domain/models/exercise_definition.dart';
import 'home_screen.dart';

/// App entry point as of 2026-07-22 (Adi: Uebungsauswahl) - replaces the
/// previous setup where main.dart went straight into a single, hardcoded
/// HomeScreen(exerciseId: 'bicep_curl'). Picking an exercise here decides
/// which persisted ExerciseProfile the following HomeScreen loads/saves
/// (see ExerciseDefinition doc comment) - calibrating one exercise never
/// affects another's profile.
class ExerciseSelectionScreen extends StatelessWidget {
  const ExerciseSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Übung wählen')),
      body: ListView.builder(
        itemCount: kSupportedExercises.length,
        itemBuilder: (context, index) {
          final exercise = kSupportedExercises[index];
          return ListTile(
            title: Text(exercise.displayName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => HomeScreen(
                    // Real BLE for hardware tests. MockSensorProvider()
                    // for web/CI only - same toggle-by-hand pattern as
                    // main.dart used before this screen existed; keep
                    // both in sync if you flip one.
                    sensorProvider: BleSensorProvider(),
                    exerciseId: exercise.id,
                    exerciseDisplayName: exercise.displayName,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

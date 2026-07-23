import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/providers/ble_sensor_provider.dart';
import 'data/repositories/drift_database.dart';
import 'domain/workout_engine.dart';
import 'presentation/providers/engine_provider.dart';
import 'presentation/screens/home_screen.dart';

/// Entry point.
///
/// Hardware verification / agent-4 follow-up: uses [BleSensorProvider] so the
/// app talks to the real M5StickC Plus2. For CI/web without hardware, switch
/// back to [MockSensorProvider] (one line below).
void main() {
  // Real BLE for hardware tests. MockSensorProvider() for web/CI only.
  final sensorProvider = BleSensorProvider();
  final engine = WorkoutEngine(
    exerciseId: 'bicep_curl',
    useSignedProjectionCounting: true,
  );
  final db = AppDatabase();
  final repository = DriftWorkoutRepository(db);

  runApp(
    ProviderScope(
      overrides: [
        engineProvider.overrideWith(
          (_) => EngineNotifier.create(
            sensorProvider: sensorProvider,
            engine: engine,
            repository: repository,
          ),
        ),
      ],
      child: const FlowRepApp(),
    ),
  );
}

class FlowRepApp extends StatelessWidget {
  const FlowRepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlowRep',
      theme:
          ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

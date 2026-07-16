import 'package:flutter/material.dart';

import 'data/providers/ble_sensor_provider.dart';
import 'data/providers/sensor_provider.dart';
import 'presentation/screens/home_screen.dart';

/// Entry point. Phase 0/1: wired to MockSensorProvider so this runs with
/// `flutter run -d chrome` without any hardware. Swapping to real BLE is a
/// one-line change once hardware arrives - see BleSensorProvider and
/// docs/GYM_TRACKER_ARCHITEKTUR.md Phase 0, Aufgabe 7.
///
/// TEMPORARY: currently using BleSensorProvider() for real hardware BLE
/// streaming validation. Revert to MockSensorProvider() for CI/web builds.
void main() {
  runApp(const FlowRepApp());
}

class FlowRepApp extends StatelessWidget {
  const FlowRepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlowRep',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: HomeScreen(sensorProvider: BleSensorProvider()),
    );
  }
}

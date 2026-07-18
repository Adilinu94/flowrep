import 'package:flutter/material.dart';

import 'data/providers/ble_sensor_provider.dart';
import 'data/providers/sensor_provider.dart';
import 'presentation/screens/home_screen.dart';

/// Entry point.
///
/// Hardware verification / agent-4 follow-up: uses [BleSensorProvider] so the
/// app talks to the real M5StickC Plus2. For CI/web without hardware, switch
/// back to [MockSensorProvider] (one line below).
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
      // Real BLE for hardware tests. MockSensorProvider() for web/CI only.
      home: HomeScreen(sensorProvider: BleSensorProvider()),
    );
  }
}

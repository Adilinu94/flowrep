import 'package:flutter/material.dart';

import '../../data/providers/sensor_provider.dart';
import '../../domain/workout_engine.dart';

/// Phase 0/1 screen: connect button, status text, live rep counter.
/// Runs against MockSensorProvider in Chrome/desktop (no hardware needed);
/// swap to BleSensorProvider once real hardware is available - see
/// docs/GYM_TRACKER_ARCHITEKTUR.md Abschnitt 5.0 (Phase 0) and 5.1 (Phase 1).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.sensorProvider});

  final MockSensorProvider sensorProvider;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ConnectionState _connectionState = ConnectionState.disconnected;
  WorkoutState _workoutState = WorkoutState.idle;
  int _repsInCurrentSet = 0;
  int? _lastCompletedSetCount;
  late final WorkoutEngine _engine;

  @override
  void initState() {
    super.initState();
    _engine = WorkoutEngine(exerciseId: 'bicep_curl');

    widget.sensorProvider.connectionState.listen((state) {
      setState(() => _connectionState = state);
    });

    widget.sensorProvider.samples.listen(_engine.processSample);

    _engine.events.listen((event) {
      setState(() {
        _workoutState = event.state;
        _repsInCurrentSet = event.repsInCurrentSet;
        if (event.completedSet != null) {
          _lastCompletedSetCount = event.completedSet!.countedReps;
        }
      });
    });
  }

  String get _statusText {
    switch (_connectionState) {
      case ConnectionState.disconnected:
        return 'Getrennt';
      case ConnectionState.connecting:
        return 'Verbinde (Mock) …';
      case ConnectionState.connected:
        return 'Verbunden (Mock)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FlowRep')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_statusText, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            if (_connectionState == ConnectionState.disconnected)
              ElevatedButton(
                onPressed: () => widget.sensorProvider.connect(),
                child: const Text('Gerät verbinden'),
              ),
            if (_connectionState == ConnectionState.connected) ...[
              Text(
                '$_repsInCurrentSet',
                style: const TextStyle(fontSize: 96, fontWeight: FontWeight.bold),
              ),
              Text('Zustand: ${_workoutState.name}'),
              if (_lastCompletedSetCount != null)
                Text('Letzter Satz: $_lastCompletedSetCount Wiederholungen'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => widget.sensorProvider.simulateRepetition(),
                child: const Text('Wiederholung simulieren (Mock)'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }
}

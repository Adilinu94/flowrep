import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/logger.dart';
import 'data/providers/ble_sensor_provider.dart';
import 'data/repositories/drift_database.dart';
import 'domain/workout_engine.dart';
import 'presentation/providers/engine_provider.dart';
import 'presentation/screens/home_screen.dart';

/// Entry point.
///
/// Hardware verification: uses [BleSensorProvider] so the app talks to the
/// real M5StickC Plus2. For CI/web without hardware, switch to
/// [MockSensorProvider].
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Globaler Error Handler (P1-1): loggt alle unbehandelten Flutter-Fehler.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.e(
      'FLUTTER-ERROR: ${details.exceptionAsString()}',
      stack: details.stack,
    );
  };

  // PlatformDispatcher catches async errors outside Flutter framework.
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.e('PLATFORM-ERROR: $error', error: error, stack: stack);
    return true;
  };

  runZonedGuarded(() {
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
  }, (error, stack) {
    AppLogger.e('ZONE-ERROR: $error', error: error, stack: stack);
  });
}

class FlowRepApp extends StatelessWidget {
  const FlowRepApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Release: benutzerfreundliche Fehlerseite statt rotem Screen (P1-1)
    ErrorWidget.builder = (details) {
      if (kDebugMode) {
        return ErrorWidget(details.exception);
      }
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Ein unerwarteter Fehler ist aufgetreten.',
                    style: TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Bitte starte die App neu.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => SystemNavigator.pop(),
                    child: const Text('App schließen'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    };

    return MaterialApp(
      title: 'FlowRep',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowrep/domain/workout_engine.dart' show SensorSample;
import 'package:flowrep/presentation/screens/calibration/calibration_wizard_screen.dart';

/// Widget-Tests: Verdrahtung Wizard ↔ CalibrationController.
void main() {
  testWidgets('Ruhephase mit stillen Samples schaltet zu "Eine Wiederholung"',
      (tester) async {
    final samplesController = StreamController<SensorSample>();
    addTearDown(samplesController.close);

    await tester.pumpWidget(MaterialApp(
      home: CalibrationWizardScreen(
        samples: samplesController.stream,
        exerciseId: 'bicep_curl',
        deviceId: 'test-device',
        // Skip briefing + countdown in tests.
        prepareCountdownSeconds: 0,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Ruhe'), findsWidgets);
    expect(find.textContaining('Arm still halten'), findsOneWidget);

    final now = DateTime.now();
    for (var i = 0; i < 110; i++) {
      samplesController.add(SensorSample(
        timestamp: now.add(Duration(milliseconds: i * 20)),
        ax: 0,
        ay: 1.0,
        az: 0,
        gx: 0,
        gy: 0,
        gz: 0,
      ));
    }
    await tester.pump();

    await tester.tap(find.text('Weiter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Eine Wiederholung'), findsWidgets);
    expect(find.textContaining('Genau 1 Bizeps-Curl'), findsOneWidget);
  });

  testWidgets('Briefing zeigt Aufgabe vor Countdown; Samples ignoriert',
      (tester) async {
    final samplesController = StreamController<SensorSample>();
    addTearDown(samplesController.close);

    await tester.pumpWidget(MaterialApp(
      home: CalibrationWizardScreen(
        samples: samplesController.stream,
        exerciseId: 'bicep_curl',
        deviceId: 'test-device',
        prepareCountdownSeconds: 5,
      ),
    ));
    await tester.pump();

    // Task visible before any countdown.
    expect(find.textContaining('Arm still halten'), findsOneWidget);
    expect(find.textContaining('Danach: 1 einzelne Curl'), findsOneWidget);
    expect(find.text('Bereit — 5s'), findsOneWidget);

    // Samples during briefing ignored.
    final now = DateTime.now();
    for (var i = 0; i < 50; i++) {
      samplesController.add(SensorSample(
        timestamp: now.add(Duration(milliseconds: i * 20)),
        ax: 0,
        ay: 1.0,
        az: 0,
        gx: 0,
        gy: 0,
        gz: 0,
      ));
    }
    await tester.pump();
    expect(find.textContaining('s aufgezeichnet'), findsNothing);

    // Start countdown.
    await tester.tap(find.text('Bereit — 5s'));
    await tester.pump();
    expect(find.textContaining('Start in'), findsOneWidget);

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('s aufgezeichnet'), findsOneWidget);
    expect(find.text('Weiter'), findsOneWidget);
  });

  testWidgets('Abbrechen schliesst den Wizard mit Ergebnis false',
      (tester) async {
    final samplesController = StreamController<SensorSample>();
    addTearDown(samplesController.close);
    bool? result;

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => CalibrationWizardScreen(
                  samples: samplesController.stream,
                  exerciseId: 'bicep_curl',
                  deviceId: 'test-device',
                  prepareCountdownSeconds: 0,
                ),
              ),
            );
          },
          child: const Text('open'),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Abbrechen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result, isFalse);
  });
}

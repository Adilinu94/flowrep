import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowrep/domain/workout_engine.dart' show SensorSample;
import 'package:flowrep/presentation/screens/calibration/calibration_wizard_screen.dart';

/// Bewusst schmal geschnittener Widget-Test: prueft die Verdrahtung
/// zwischen CalibrationWizardScreen und dem ECHTEN CalibrationController
/// (kein Fake) fuer den am klarsten spezifizierten Uebergang (Ruhe-Gate:
/// |gyro|-Mittel < 15 °/s, Accel-Sigma < 0,12g, min 2s - siehe
/// calibration_controller.dart _finishRest). Tiefergehende Mehrstufen-
/// Flows (knownSet/slowSet-Sweep) haengen von Algorithmus-internen
/// Schwellen ab, die praeziser in einem dedizierten
/// calibration_controller_test.dart (Agent 2) abgedeckt werden sollten -
/// siehe Statusbericht.
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
      ),
    ));
    await tester.pump();

    expect(find.text('Ruhephase'), findsOneWidget);

    // ~2s stillstehende Samples bei 50 Hz (Standard sampleRateHz).
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

    expect(find.text('Eine Wiederholung'), findsOneWidget);
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

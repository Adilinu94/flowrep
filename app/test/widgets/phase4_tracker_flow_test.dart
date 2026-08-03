import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:flowrep/presentation/providers/engine_provider.dart';
import 'package:flowrep/presentation/screens/home_screen.dart';
import 'package:flowrep/presentation/widgets/weight_input_field.dart';

/// Phase 4 Bauplan Schritt 4: Widget-Integrationstest über mehrere Schritte
/// hinweg (nicht nur Einzelkomponenten), so weit ohne echte BLE-Hardware
/// möglich - Vorlage für das Riverpod/Mock-Setup ist home_screen_test.dart.
///
/// Der Kalibrierungs-Wizard selbst ist NICHT Teil dieses Tests (eigene
/// Tests: calibration_wizard_screen_test.dart) und im Mock-Modus ohnehin
/// nicht erreichbar - siehe Kommentar auf debugSetHasCalibration() in
/// engine_provider.dart. Getestet wird der Ablauf AB "kalibriert":
/// Gewicht eintragen -> Start-Knopf -> Countdown -> zählen -> Satz beenden
/// -> Korrektur -> nächster Satz -> Training beenden (Bauplan Phase 4
/// Schritt 3).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EngineNotifier notifier;

  Widget buildTestApp() {
    return ProviderScope(
      overrides: [
        engineProvider.overrideWith((_) {
          notifier = EngineNotifier.create(
            sensorProvider: MockSensorProvider(),
            engine: WorkoutEngine(
              exerciseId: 'bicep_curl',
              useSignedProjectionCounting: true,
            ),
          );
          return notifier;
        }),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  testWidgets(
      'voller Ablauf: verbinden -> Gewicht -> Countdown -> zählen -> '
      'Korrektur -> Satz 2 ohne neuen Knopf -> Training beenden',
      (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    // 1. Verbinden (MockSensorProvider.connect() hat 2s simulierte Zeit).
    await notifier.connect();
    await tester.pump(const Duration(seconds: 3));

    // 2. Kalibrierung: Wizard im Mock-Modus nicht erreichbar, Zustand
    // direkt herstellen (siehe Kommentar auf debugSetHasCalibration).
    notifier.debugSetHasCalibration(true);
    notifier.debugSetStartCountdownSeconds(1);
    await tester.pump();

    // Bauplan Phase 4 Schritt 2: Reihenfolge ExerciseSelectorCard ->
    // Kalibrierungs-Status -> Gewichtsfeld -> Start-Knopf. Weight-Feld und
    // Start-Knopf müssen jetzt sichtbar sein.
    expect(find.byType(WeightInputField), findsOneWidget);
    expect(find.text('Zählen starten'), findsOneWidget);

    // 3. Gewicht eintragen.
    await tester.enterText(
      find.descendant(
        of: find.byType(WeightInputField),
        matching: find.byType(TextField),
      ),
      '20',
    );
    await tester.pump();
    expect(notifier.state.pendingWeightKg, 20.0);

    // 4. Start-Knopf -> Countdown -> Zählung. Kette manuell nachvollzogen
    // (Bauplan Schritt 3): beginStartCountdown() ruft nach Ablauf wirklich
    // startCounting() auf - hier am echten Widget-Baum verifiziert, nicht
    // nur am Provider isoliert (siehe start_countdown_test.dart aus
    // Phase 2, das deckt nur den Provider ab, nicht die UI-Kette).
    await tester.tap(find.text('Zählen starten'));
    await tester.pump();
    expect(find.textContaining('Start in'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(notifier.state.isCountingActive, isTrue);

    // 5. _buildSetupBody (inkl. Start-Knopf) ist während der Zählung
    // komplett weg - eine Ebene höher gegated (home_screen.dart Zeile 138:
    // isCountingActive schaltet zwischen _buildSetupBody/_buildActiveSetBody
    // um), nicht nur über StartCountdownButton.enabled. Das war der
    // Punkt, an dem die vorherige Session unsicher war, ob es einen
    // Bug gibt - hier verifiziert: kein Bug, robuster als angenommen.
    expect(find.text('Zählen starten'), findsNothing);
    expect(find.text('Satz beenden'), findsOneWidget);

    // 6. Wiederholung simulieren (echter Tap auf den Mock-Button, nicht
    // notifier.simulateRepetition() direkt - übt den echten Widget-Pfad).
    await tester.tap(find.text('Wiederholung simulieren (Mock)'));
    await tester.pump(const Duration(seconds: 2)); // ~1.5s Rep-Zyklus
    expect(notifier.state.repsInCurrentSet, greaterThan(0),
        reason: 'muss über die echte Engine-Pipeline zählen, nicht nur '
            'eine UI-Zahl hochsetzen');

    // 7. Satz beenden -> Korrektur-Dialog.
    await tester.tap(find.text('Satz beenden'));
    await tester.pump();
    expect(find.text('Satz beendet'), findsOneWidget);

    // 8. Bestätigen -> Dialog zu, Satz gespeichert MIT dem eingetragenen
    // Gewicht (Integration Phase 2/3/4: Countdown-Flow + Gewichtsfeld +
    // Korrektur greifen tatsächlich ineinander, nicht nur nebeneinander).
    await tester.tap(find.text('Bestätigen'));
    await tester.pump();
    expect(find.text('Satz beendet'), findsNothing);
    expect(notifier.debugCompletedSets, hasLength(1));
    expect(notifier.debugCompletedSets.single.weightKg, 20.0);

    // 9. KERNBEFUND (Bauplan Schritt 3, siehe STATUS_FORTSCHRITT.md für
    // die volle Einordnung): kein neuer Start-Knopf/Countdown für Satz 2.
    // isCountingActive bleibt über die ganze Session hinweg true (wird
    // nur in stopCounting()/endSession() zurückgesetzt, NICHT in
    // _onSetCompleted()); Satz 2 beginnt automatisch bei
    // Bewegungserkennung über denselben idle->active-Übergang in
    // workout_engine.dart, der vor Phase 2 die Auto-Arm-Logik war. Dieser
    // Test dokumentiert das AKTUELLE Verhalten als Regressionsanker -
    // ob das dem Wortlaut "Countdown vor JEDEM Satz" genügt, ist eine
    // offene Rückfrage an Adi, keine Annahme dieses Tests.
    expect(notifier.state.isCountingActive, isTrue);
    expect(find.text('Zählen starten'), findsNothing);
    expect(notifier.state.repsInCurrentSet, 0);

    await tester.tap(find.text('Wiederholung simulieren (Mock)'));
    await tester.pump(const Duration(seconds: 2));
    expect(notifier.state.repsInCurrentSet, greaterThan(0),
        reason: 'Satz 2 zählt bereits ohne jeden neuen Knopfdruck - das '
            'ist der Kernbefund, kein Testaufbau-Zufall');

    // 10. Satz 2 abschließen, dann Training beenden (Bestätigungsdialog).
    await tester.tap(find.text('Satz beenden'));
    await tester.pump();
    await tester.tap(find.text('Bestätigen'));
    await tester.pump();
    expect(notifier.debugCompletedSets, hasLength(2));

    await tester.tap(find.text('Training beenden'));
    await tester.pump();
    expect(find.text('Training beenden?'), findsOneWidget);
    await tester.tap(find.text('Beenden'));
    await tester.pump();

    expect(notifier.state.isCountingActive, isFalse);
    expect(notifier.debugCompletedSets, isEmpty,
        reason: 'endSession() speichert die Session und leert '
            '_completedSets für die nächste');
  });
}

# Bauplan Agent 3: Guided Calibration 2.0 – UI & Persistenz

> Eigenständiges Arbeitspaket für das FlowRep-Projekt. Du brauchst keine anderen Baupläne – die Schnittstelle, gegen die du baust, steht komplett in Abschnitt 4 dieses Dokuments und ist identisch mit der, die Agent 2 implementiert.

## 0. Wer du bist

Du bist einer von vier parallel arbeitenden KI-Agenten. Du bist zuständig für: **die Bildschirme, durch die der Nutzer die neue geführte Kalibrierung durchläuft, plus Speicherung/Migration der Kalibrierdaten.** Du bist NICHT zuständig für den Zähl-Algorithmus selbst (das macht Agent 2, du konsumierst nur dessen Ergebnis) und NICHT für die Live-Zählung im normalen Betrieb (Agent 1).

## 1. Auftrag in einem Satz

Baue einen Wizard-Bildschirm für die fünf Kalibrierungsstufen (Ruhe → 1 Rep → 5 bekannte Reps → 3 langsame Reps → Review), gegen eine feste `CalibrationController`-Schnittstelle (die du mit einem Fake simulierst, falls Agent 2 noch nicht fertig ist), plus Speicherung des Ergebnisses inklusive sauberer Migration alter Kalibrierdaten.

## 2. Repo-Zugriff & erstes Vorgehen (PFLICHT vor jeder Änderung)

1. `git checkout main && git pull origin main`.
2. Lies `docs/Umbauplan Flowrep/KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md` komplett, besonders die Abschnitte zu UI/UX-Ablauf, Erfolgskriterien (§7) und Migrationsstrategie für alte Kalibrierdaten.
3. Sieh dir `app/lib/data/security/calibration_store.dart` an (aktueller Speicherstand für Kalibrierdaten) und `app/lib/data/repositories/drift_database.dart` (Datenbankschicht). **Hinweis:** `drift_database.dart` war zuletzt mitten in einem Namenskonflikt-Fix (Domain-Modelle vs. generierte Drift-Klassen, gelöst über einen `as domain`-Import-Alias). Prüfe den aktuellen Stand selbst – möglicherweise ist das bereits erledigt (Commit-Botschaft-Stichwort: "domain-Praefix").

## 3. Kontext, den du brauchst

Siehe Bauplan-Kontext: FlowRep zählt Bizeps-Curls, die neue Kalibrierung führt den Nutzer durch 5 Stufen (0 Ruhe, A 1 Rep, B 5 bekannte Reps, C 3 langsame Reps, D Review). Der komplette Algorithmus ist NICHT deine Aufgabe – du bekommst von `CalibrationController` (Agent 2s Arbeit) über einen `Stream<CalibrationStage>` mitgeteilt, in welcher Stufe der Nutzer gerade ist, und am Ende ein `CalibrationResult`.

**Wichtig für Stufe D (Review):** Der Nutzer soll das Ergebnis sehen und ggf. korrigieren/neu starten können, BEVOR es dauerhaft gespeichert wird. Erfolgskriterium aus dem Konzeptdokument: Korrekturrate < 15% – d.h., die Review-Stufe ist kein Nice-to-have, sondern zentral für die Erfolgsmessung des ganzen Features.

**Migration alter Kalibrierdaten:** Falls ein Nutzer bereits eine Kalibrierung im alten Format hat (Ein-Wiederholung-Auto-Kalibrierung), darf das beim App-Update nicht abstürzen oder stillschweigend verworfen werden. Vorgabe: alte Daten automatisch in ein "v1-Legacy"-Profil einwickeln, das weiter funktioniert, aber dem Nutzer eine Empfehlung zeigt, neu zu kalibrieren (kein Zwang, keine Blockade).

## 4. Die Schnittstelle, gegen die du baust (identisch zu Agent 2s Bauplan)

```dart
enum CalibrationStage { restBaseline, singleRepAxis, knownCountFit, tempoCheck, review, failed }

class CalibrationResult {
  final bool success;
  final String? failureReason;
  final double peakThreshold;
  final List<double> rotationAxis;
  final double baselineGyroNorm;
  final double baselineNoiseFloor;
  final double tempoRobustnessScore;
  final int repsUsedForFit;
}

abstract class CalibrationController {
  CalibrationStage get stage;
  Stream<CalibrationStage> get stageStream;
  void onSample(ImuSample sample);
  bool get isComplete;
  CalibrationResult? get result;
  void cancel();
  void reset();
}
```

**Falls diese Klasse zum Zeitpunkt deiner Arbeit noch nicht in `app/lib/domain/calibration_controller.dart` existiert:** Baue dir selbst ein `FakeCalibrationController` (implements `CalibrationController`) in deinem Test-Ordner, das über einen Timer künstlich durch die Stufen läuft und ein plausibles `CalibrationResult` liefert. Damit kannst du deine UI komplett bauen und testen, ohne auf Agent 2 zu warten. Wenn Agent 2s echte Klasse verfügbar ist, tauschst du im UI-Code nur die konkrete Implementierung aus (Dependency Injection / Konstruktor-Parameter statt hartem `new`), nicht die UI-Logik selbst.

## 5. Dateien, die dir gehören

- NEU: `app/lib/presentation/screens/calibration/` – neuer Ordner für den Wizard (z.B. `calibration_wizard_screen.dart` plus je nach deinem Aufbau ein Widget pro Stufe, oder ein Screen mit internem State – folge dem bestehenden Stil in `presentation/screens/`, den du im Repo vorfindest).
- `app/lib/data/security/calibration_store.dart` – neues Profilformat + Legacy-Migration.
- `app/lib/data/repositories/drift_database.dart` – NUR falls für die Kalibrierprofil-Speicherung ein Schema-Zusatz nötig ist. Prüfe zuerst, ob `calibration_store.dart` (flutter_secure_storage-basiert) allein ausreicht, bevor du die Datenbankschicht anfässt – kleinere Änderung ist besser.
- `app/lib/presentation/screens/home_screen.dart` – **GENAU EINE Ergänzung:** ein Einstiegspunkt (Button/Menüeintrag), der zum neuen Wizard navigiert, ersetzt den alten Auto-Kalibrierungs-Trigger falls vorhanden. Keine sonstigen Änderungen an dieser Datei – dort arbeitet niemand sonst, aber sie enthält Dinge wie die `ENG:`-Diagnosezeile, `_bindEngine()`, Reconnect-Handling, die alle unverändert bleiben müssen.
- NEU: Tests für Store/Migration, z.B. `app/test/calibration_store_test.dart`.

## 6. Dateien, die du NICHT anfassen darfst

`workout_engine.dart`, `calibration_controller.dart` (nur lesen, nicht schreiben – das ist Agent 2s Datei), `ble_sensor_provider.dart`, `workout_engine_simulation.py`, `firmware/*`, `docs/reference/protocol.yaml`.

## 7. Aufgaben, Schritt für Schritt

### Schritt A – UI-Grundgerüst (sofort startbar)
1. `FakeCalibrationController` bauen (siehe Abschnitt 4).
2. Wizard-Screen(s) für die 5 Stufen: pro Stufe klare Anweisung an den Nutzer ("Halte still" / "Mache genau 1 Wiederholung" / "Mache genau 5 Wiederholungen in deinem normalen Tempo" / "Mache 3 langsame Wiederholungen" / Review-Ansicht mit Ergebnis).
3. Stufe D (Review): zeige `peakThreshold`, `tempoRobustnessScore`, ggf. eine einfache verständliche Einordnung (nicht nur Rohzahlen – der Nutzer ist kein Ingenieur). Biete zwei Aktionen: "Übernehmen" (→ speichern über `calibration_store.dart`) und "Neu starten" (→ `controller.reset()`).
4. Abbrechen-Möglichkeit in jeder Stufe (`controller.cancel()`), die sauber zum vorherigen Screen zurückführt, ohne einen halb-fertigen Zustand zu hinterlassen.
5. Ergänze in `home_screen.dart` GENAU den einen Navigationseinstieg (Abschnitt 5).

### Schritt B – Persistenz & Migration
1. In `calibration_store.dart`: neues Profilformat für `CalibrationResult` (alle Felder aus Abschnitt 4 persistieren).
2. Versionsfeld einführen, falls nicht schon vorhanden (z.B. `profileVersion: int`), damit künftige Formate sauber unterscheidbar sind.
3. Migrationslogik: beim Laden, falls ein Profil im alten Ein-Wiederholung-Format vorgefunden wird, automatisch in ein "v1-Legacy"-Wrapper-Profil überführen (weiter nutzbar, aber mit einem Flag `recommendRecalibration = true`), NICHT einfach verwerfen oder einen Absturz riskieren.
4. Wenn Stufe D "Übernehmen" gedrückt wird: neues Profil speichern, altes (falls Legacy) überschreiben.
5. Zeige irgendwo sichtbar (z.B. auf dem Home-Screen oder in den Einstellungen – dein Ermessen, aber dokumentiere die Entscheidung) einen dezenten Hinweis, wenn `recommendRecalibration == true` ist.

## 8. Definition of Done

- [ ] `flutter analyze` meldet 0 Fehler.
- [ ] `flutter test` – bestehende Suite bleibt grün, plus deine neuen Tests für Store/Migration.
- [ ] Wizard lässt sich mit dem `FakeCalibrationController` komplett durchklicken, alle 5 Stufen, inkl. Abbrechen und Review-Neustart.
- [ ] Migration: ein Testfall, der ein altes Profil lädt und bestätigt, dass daraus ein gültiges, nutzbares Legacy-Profil mit `recommendRecalibration = true` wird, ohne Exception.
- [ ] `home_screen.dart`-Diff zeigt wirklich nur die eine Navigations-Ergänzung (`git diff app/lib/presentation/screens/home_screen.dart` selbst gegenlesen, bevor du committest).
- [ ] `git diff --stat` zeigt nur Dateien aus Abschnitt 5.

## 9. Git-Workflow (PFLICHT, keine Ausnahmen)

```
git checkout main
git pull origin main
git checkout -b agent3-calibration-ui
# ... arbeiten, testen ...
git add app/lib/presentation/screens/calibration/ app/lib/presentation/screens/home_screen.dart app/lib/data/security/calibration_store.dart app/test/calibration_store_test.dart
git commit -m "feat(calibration-ui): Guided Calibration 2.0 Wizard + Persistenz + Legacy-Migration (Konzept 2.0, Paket 4-9)"
git push origin agent3-calibration-ui
```

Falls du `drift_database.dart` anfassen musstest: separat committen (`git add app/lib/data/repositories/drift_database.dart`, eigene Commit-Message), damit diese Änderung klar nachvollziehbar bleibt.

**Du merged NIEMALS selbst nach `main`.** Push deinen Branch, stoppe, warte auf Adi/Claude.

## 10. Fortschritt dokumentieren

Neuer Abschnitt am Ende von `docs/Umbauplan Flowrep/STATUS_FORTSCHRITT.md`, Kennung `Agent-3-CalibrationUI`, bestehendes Format nutzen, nichts Bestehendes überschreiben.

## 11. Wenn du blockiert bist

- Agent 2s echte Klasse ist noch nicht da: kein Problem, mit `FakeCalibrationController` weiterarbeiten (siehe Abschnitt 4), das ist der Normalfall, kein Blocker.
- Unklar, ob `calibration_store.dart` allein reicht oder `drift_database.dart` wirklich ein Schema-Update braucht: im Zweifel für die kleinere Änderung entscheiden (nur `calibration_store.dart`), dokumentieren, warum.
- Bestehender Stil/Aufbau von `presentation/screens/` ist uneindeutig: an bestehenden Screens orientieren, die im Repo vorhanden sind, nicht neu erfinden.

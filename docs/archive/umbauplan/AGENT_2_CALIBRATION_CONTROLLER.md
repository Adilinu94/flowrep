# Bauplan Agent 2: Guided Calibration 2.0 – Controller & Integration

> Eigenständiges Arbeitspaket für das FlowRep-Projekt. Du brauchst keine anderen Baupläne, um diese Aufgabe zu erledigen – die Schnittstelle, die andere Agenten brauchen, steht komplett in Abschnitt 4 dieses Dokuments.

## 0. Wer du bist

Du bist einer von vier parallel arbeitenden KI-Agenten. Du bist zuständig für: **den Algorithmus der neuen geführten Kalibrierung von Python nach Dart portieren und minimal-invasiv in die bestehende Zähl-Engine einhängen.** Du bist NICHT zuständig für die UI (Bildschirme, Wizard) und NICHT für die Speicherung der Kalibrierdaten – das macht Agent 3 gegen die Schnittstelle, die du hier lieferst.

## 1. Auftrag in einem Satz

Portiere die bereits validierte Python-Referenzimplementierung der Known-Count-Kalibrierung (`tools/workout_engine_simulation.py`) 1:1 nach Dart als neue, eigenständige Klasse `CalibrationController`, und hänge sie an exakt einer Stelle in `workout_engine.dart` ein.

## 2. Repo-Zugriff & erstes Vorgehen (PFLICHT vor jeder Änderung)

1. `git checkout main && git pull origin main`.
2. Lies `docs/Umbauplan Flowrep/KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md` komplett – das ist deine fachliche Spezifikation (Root-Cause-Analyse K1–K7, Architektur, Stufen 0/A/B/C/D, Erfolgskriterien). Dieser Bauplan fasst nur zusammen, was für dich direkt umsetzungsrelevant ist.
3. Öffne `tools/workout_engine_simulation.py` und finde folgende bereits fertige, geprüfte Funktionen – das ist dein Algorithmus, den du portierst, nicht neu erfindest: `stufe0_ruheanalyse`, `stufeA_achsenanalyse`, `known_count_sweep`, `median_minus_k_mad`, `stufeC_tempo_robustheit`, `stufeD_review_simulation`, `kalibriere_persona`, `zaehle_edge`, `kandidaten_signale`, `ema_glaettung`. Führe `python tools/workout_engine_simulation.py` aus und bestätige, dass es für alle Personas erfolgreich durchläuft (MAE ≤ 0,5), BEVOR du zu portieren beginnst. Falls es NICHT erfolgreich durchläuft: stopp, das widerspricht diesem Bauplan, dokumentiere es (Abschnitt 9) statt anzunehmen, es sei ok.
4. **Prüfe, ob Agent 1s Branch (`agent1-signal-pipeline`) bereits nach `main` gemerged wurde** (`git log main --oneline | grep -i "signal"` oder frag Adi direkt). Falls NEIN: Du darfst trotzdem sofort mit Schritt A (neue Datei, siehe unten) beginnen, aber NICHT mit Schritt B (Integration in workout_engine.dart). Warte darauf, dass dir mitgeteilt wird, dass gemerged wurde.

## 3. Kontext, den du brauchst

FlowRep zählt Bizeps-Curls über IMU-Daten. Die bisherige Kalibrierung ist fragil (im Konzeptdokument als K1–K7 dokumentiert, u.a.: nur 1 Wiederholung als Grundlage, keine feste Wiederholungszahl als Ziel, keine Tempo-Robustheit, keine Review-Möglichkeit für den Nutzer). Die neue Lösung führt den Nutzer durch fünf Stufen:

- **Stufe 0 (Ruhe):** Baseline und Rauschboden ermitteln, Gyro-Bias bestimmen.
- **Stufe A (1 Wiederholung):** Rotationsachse per PCA aus einer einzelnen Wiederholung bestimmen.
- **Stufe B (bekannte Anzahl, i.d.R. 5 Wiederholungen):** Der Nutzer macht eine FESTGELEGTE, dem System bekannte Anzahl an Wiederholungen. Ein Parameter-Sweep (`known_count_sweep`) findet die Schwelle, die exakt diese bekannte Anzahl korrekt zählt – das ist der Kern des neuen Ansatzes ("Known-Count-Optimierung").
- **Stufe C (Tempo-Robustheit):** 3 bewusst langsame Wiederholungen, um zu prüfen, ob die gefundene Schwelle auch bei anderem Tempo noch funktioniert.
- **Stufe D (Review):** Ergebnis dem Nutzer zeigen, mit Korrekturmöglichkeit (die Anzeige macht Agent 3, die Datengrundlage dafür lieferst du).

Die Simulation hat bereits bewiesen: Dieser Ansatz löst auch strukturell den alten Doppel-Peak-Bug (vorzeichenbehaftete Gyro-Projektion `g_p` statt reinem Betrag).

**Architektur-Vorgabe aus dem Konzeptdokument, nicht verhandelbar:** `CalibrationController` ist ein komplett separater Domain-Service. `WorkoutEngine` bleibt alleiniger Owner von `WorkoutState`. Der Controller verändert NIE direkt den State der Engine – er liefert nur Ergebnisse, die die Engine dann selbst anwendet.

## 4. Die Schnittstelle (verbindlich – andere Agenten bauen dagegen)

```dart
enum CalibrationStage { restBaseline, singleRepAxis, knownCountFit, tempoCheck, review, failed }

class CalibrationResult {
  final bool success;
  final String? failureReason;
  final double peakThreshold;        // aus median_minus_k_mad-Äquivalent, Stufe B
  final List<double> rotationAxis;   // PCA-Achse aus Stufe A, 3 Komponenten, normiert
  final double baselineGyroNorm;     // aus Stufe 0
  final double baselineNoiseFloor;   // aus Stufe 0
  final double tempoRobustnessScore; // aus Stufe C, 0.0–1.0
  final int repsUsedForFit;

  const CalibrationResult({
    required this.success,
    this.failureReason,
    required this.peakThreshold,
    required this.rotationAxis,
    required this.baselineGyroNorm,
    required this.baselineNoiseFloor,
    required this.tempoRobustnessScore,
    required this.repsUsedForFit,
  });
}

abstract class CalibrationController {
  CalibrationStage get stage;
  Stream<CalibrationStage> get stageStream;

  /// Wird von WorkoutEngine für JEDES eingehende IMU-Sample aufgerufen,
  /// solange WorkoutState.calibrating aktiv ist. Darf NICHT blockieren
  /// (keine synchronen Datei-/Netzwerkzugriffe in dieser Methode).
  void onSample(ImuSample sample);

  bool get isComplete;
  CalibrationResult? get result; // != null sobald isComplete == true

  void cancel();
  void reset();
}
```

Wenn du im Zuge der Implementierung merkst, dass sich diese ÖFFENTLICHE Signatur zwingend ändern muss: tu es, aber dokumentiere JEDE Änderung explizit und auffällig in deinem Statusbericht (Abschnitt 9) – Agent 3 baut blind gegen diese Signatur.

`ImuSample` – prüfe, ob dieser Typ (oder ein äquivalenter) bereits im Code existiert (vermutlich in `workout_engine.dart` oder einer eigenen Modell-Datei); falls ja, nutze den bestehenden Typ statt einen neuen zu erfinden.

## 5. Dateien, die dir gehören

- NEU: `app/lib/domain/calibration_controller.dart` (oder passend zur bestehenden Ordnerstruktur, z.B. `app/lib/domain/calibration/calibration_controller.dart` – prüfe existierende Konventionen im `domain`-Ordner und folge ihnen).
- NEU: `app/test/calibration_controller_test.dart`.
- `app/lib/domain/workout_engine.dart` – **NUR nach Freigabe (Abschnitt 2, Punkt 4), NUR der Integrations-Hook** (siehe Schritt B unten). Keine Änderungen am Live-Zählpfad (`_detectPeak` o.ä.) – das ist Agent 1s Bereich.

## 6. Aufgaben, Schritt für Schritt

### Schritt A – Reiner Algorithmus (sofort startbar, unabhängig von Agent 1)
1. Neue Datei `calibration_controller.dart` anlegen, Klassen aus Abschnitt 4 implementieren.
2. Portiere Funktion für Funktion aus der Python-Referenz:
   - `ema_glaettung` → EMA-Glättung als Dart-Funktion/Methode.
   - `kandidaten_signale` → Signalkandidaten-Berechnung (u.a. `g_p`, die vorzeichenbehaftete Gyro-Projektion auf die in Stufe A gefundene Achse).
   - `stufe0_ruheanalyse` → Baseline/Rauschboden/Gyro-Bias-Bestimmung.
   - `stufeA_achsenanalyse` → PCA-Achse aus einer Wiederholung. **Wichtig:** Für einen 3x3-Kovarianzfall brauchst du keine externe lineare-Algebra-Bibliothek – Power-Iteration auf der 3x3-Kovarianzmatrix reicht, um den dominanten Eigenvektor zu finden. Nutze das, um ohne neue Dependency auszukommen (das Konzeptdokument fordert explizit: V1 ohne neue Dependencies).
   - `known_count_sweep` + `median_minus_k_mad` → Kernstück von Stufe B: Parameter-Sweep, der die Schwelle findet, die exakt die bekannte Soll-Anzahl an Wiederholungen liefert.
   - `stufeC_tempo_robustheit` → Tempo-Robustheits-Score aus 3 langsamen Wiederholungen.
   - `stufeD_review_simulation` → hier NUR die Datengrundlage (welche Reps wirken unsicher/grenzwertig), NICHT die Anzeige – das macht Agent 3.
   - `kalibriere_persona` → das ist im Wesentlichen die Orchestrierung, die in deiner `CalibrationController`-Klasse als interner Stufenübergang (`stage`-Wechsel bei jedem `onSample`) landet.
3. Portiere `run_known_count_calibration_suite` sinngemäß nach `calibration_controller_test.dart`: dieselben Personas (clean, double_bump, weak, slow, inconsistent) als Dart-Testfälle, gleiche Erfolgskriterien (MAE ≤ 0,5).
4. Ziel: `flutter test test/calibration_controller_test.dart` ist grün, mit Ergebnissen, die den Python-Referenzwerten entsprechen (nicht zwingend bit-identisch, aber MAE ≤ 0,5 für alle Personas, wie in der Simulation bewiesen).

### Schritt B – Integration (ERST nach Freigabe, siehe Abschnitt 2.4)
1. In `workout_engine.dart`: im `calibrating`-Zweig der State Machine, GENAU EINEN Hook ergänzen: bei jedem eingehenden Sample `calibrationController.onSample(sample)` aufrufen (statt der alten Ein-Wiederholung-Auto-Kalibrierung).
2. Wenn `calibrationController.isComplete == true`: `calibrationController.result` auslesen, daraus die bestehenden Engine-Felder setzen (z.B. `peakThreshold`), und in den nächsten passenden State wechseln (`idle` oder `counting`, je nachdem, wie der bestehende Übergang nach Kalibrierung aktuell funktioniert – verifiziere das im Code, ändere die Übergangslogik selbst nicht, nur WOHER die Werte kommen).
3. Achte besonders auf ADR-020 (bereits gefixt): die neue Integration darf den `hasValidCalibration`-Schutz nicht umgehen oder entfernen.
4. Alten Ein-Wiederholung-Auto-Kalibrierungscode NICHT löschen, bis du sicher bist, dass nichts anderes im Code noch darauf verweist – im Zweifel auskommentieren + kommentieren, warum, statt löschen.

## 7. Definition of Done

- [ ] `flutter test test/calibration_controller_test.dart` grün, alle Personas MAE ≤ 0,5.
- [ ] Nach Schritt B: `flutter test` (komplette Suite) zeigt weiterhin "All tests passed!" – insbesondere die bestehenden Guided-Calibration-Regressionstests (Plateau-Fix, ADR-020) dürfen nicht brechen.
- [ ] `flutter analyze` meldet 0 Fehler.
- [ ] Keine neue Dependency in `pubspec.yaml` (siehe Schritt A.2, PCA per Power-Iteration statt Bibliothek).
- [ ] `git diff --stat` zeigt nur Dateien aus Abschnitt 5.

## 8. Git-Workflow (PFLICHT, keine Ausnahmen)

```
git checkout main
git pull origin main
git checkout -b agent2-calibration-controller
# Schritt A sofort, Schritt B erst nach Freigabe
git add app/lib/domain/calibration_controller.dart app/test/calibration_controller_test.dart
git commit -m "feat(calibration): CalibrationController V1 (Konzept 2.0, Paket 2) – Dart-Port der Python-Referenz"
# ... nach Freigabe, Schritt B ...
git add app/lib/domain/workout_engine.dart
git commit -m "feat(calibration): CalibrationController in WorkoutEngine eingehängt (Paket 3)"
git push origin agent2-calibration-controller
```

**Du merged NIEMALS selbst nach `main`.** Push deinen Branch, stoppe, warte auf Adi/Claude.

## 9. Fortschritt dokumentieren

Neuer Abschnitt am Ende von `docs/Umbauplan Flowrep/STATUS_FORTSCHRITT.md`, Kennung `Agent-2-CalibrationController`, bestehendes Format nutzen, nichts Bestehendes überschreiben. Dokumentiere explizit, falls sich die Schnittstelle aus Abschnitt 4 geändert hat.

## 10. Wenn du blockiert bist

- Python-Simulation läuft bei dir nicht erfolgreich durch (Schritt 2.3): nicht raten, was sie tun sollte – dokumentieren und mit dem Stand arbeiten, der tatsächlich da ist.
- Agent 1 ist noch nicht gemerged, du bist mit Schritt A fertig: nicht warten ohne zu pushen – Schritt-A-Branch trotzdem pushen (nur die neue Datei + Tests, kein workout_engine.dart-Diff), damit die Arbeit nicht verloren geht.
- Unklar, wie der bestehende Übergang von `calibrating` in den nächsten State aktuell funktioniert: im Code nachsehen, nicht annehmen. Wenn wirklich uneindeutig: dokumentieren statt raten.

# Koordinations-Übersicht: 4 parallele KI-Agenten auf FlowRep

**Für:** Adi (Lead / einziger Mensch im Loop)
**Von:** Claude, als Lead Systems Architect angefragt
**Datum:** 2026-07-17
**Zweck:** Diese Datei ist NICHT für die 4 Agenten gedacht. Sie ist deine Landkarte, um zu verstehen, wie die 4 Baupläne zusammenhängen, wo Abhängigkeiten bestehen und wo DU als Gatekeeper gebraucht wirst.

---

## 1. Warum diese Aufteilung so aussieht, wie sie aussieht

Ich habe die 4 Agenten nicht nach "Feature" geschnitten (z.B. "einer macht Kalibrierung komplett"), sondern nach **Datei-Eigentümerschaft**. Grund: Fast jedes Feature in diesem Projekt läuft am Ende durch `workout_engine.dart`. Wenn zwei Agenten dieselbe Datei gleichzeitig bearbeiten, bekommst du Merge-Konflikte, die schwächere Modelle nicht zuverlässig lösen können. Die Aufteilung unten minimiert Dateiüberschneidungen so weit, wie es der echte Code hergibt. Eine Überschneidung bleibt unvermeidbar (workout_engine.dart wird von Agent 1 UND Agent 2 berührt) – dafür gibt es unten eine explizite Sequenzierung, keine Hoffnung auf gutes Gelingen.

## 2. Die 4 Agenten im Überblick

| # | Name | Kernauftrag | Hauptdateien | Startet sofort? |
|---|------|-------------|---------------|------------------|
| 1 | Signal & Datenpipeline | P0 (App-Seite) + P1 + P2 aus RECHERCHE_ZAEHLROBUSTHEIT: ehrliche, robuste Zählung im Live-Betrieb | `workout_engine.dart` (Live-Zählpfad), `signal_processor.dart`, `ble_sensor_provider.dart`, `workout_engine_simulation.py`, `workout_engine_test.dart` | Ja, sofort |
| 2 | Calibration Controller | Guided Calibration 2.0, Paket 2+3: Known-Count-Engine aus Python nach Dart portieren + in WorkoutEngine einhängen | NEU: `calibration_controller.dart`, schmaler Hook in `workout_engine.dart` | Datei anlegen: sofort. Integration in workout_engine.dart: **erst nach Agent 1 gemerged** |
| 3 | Calibration UI & Persistenz | Guided Calibration 2.0, Paket 4–9: Wizard-UI, Speicherung, Migration alter Kalibrierdaten | NEU: `presentation/screens/calibration/*`, `calibration_store.dart`, `drift_database.dart`, 1 Zeile in `home_screen.dart` | Ja, sofort (baut gegen Schnittstelle aus Abschnitt 4, nicht gegen Agent 2s Code) |
| 4 | Firmware, Protokoll & Hardware-Verifikation | P0 (Firmware-Seite): ehrliche Timings, Clipping-Fix, Protokoll-Version; führt ALLE physischen Tests mit dir zusammen durch | `firmware/src/main.cpp`, `firmware/platformio.ini`, `docs/reference/protocol.yaml` | Ja, sofort (Protokoll-Spec als schnelles erstes Ergebnis) |

## 3. Die einzige harte Abhängigkeit: Agent 1 → Agent 2

Agent 1 verändert den Live-Zählpfad in `workout_engine.dart`. Agent 2 hängt seinen Controller an einer anderen Stelle in derselben Datei ein. Damit das nicht kollidiert:

1. Agent 1 arbeitet, testet, pusht seinen Branch.
2. **Du (oder ich, auf deine Anweisung) mergst Agent 1s Branch nach `main`.** Das ist der eine manuelle Gatekeeper-Schritt, den kein Agent selbst machen darf.
3. Erst danach checkt Agent 2 `main` neu aus, erstellt seinen eigenen Branch und beginnt mit dem Integrations-Schritt (Abschnitt 6 in Agent 2s Bauplan).

Agent 2 kann die neue Datei `calibration_controller.dart` selbst (den reinen Algorithmus, portiert aus der Python-Simulation) **sofort** anfangen – nur der letzte Schritt (Einhängen in workout_engine.dart) muss warten.

Agent 3 und Agent 4 haben diese Abhängigkeit nicht und laufen von Anfang an parallel.

## 4. Die Schnittstelle, die Agent 2 und Agent 3 zusammenhält

Damit Agent 3 die UI bauen kann, OHNE auf Agent 2s fertige Implementierung zu warten, bekommen beide Agenten exakt diesen Vertrag vorgegeben (Details in ihren jeweiligen Bauplänen, hier nur zur Übersicht):

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

Agent 3 baut die UI gegen ein Fake/Mock dieser Klasse. Wenn Agent 2 fertig ist, ist das Zusammenstecken danach nur noch Verkabelung, kein Rewrite.

## 5. Realistischer Scope – was am Ende NICHT "die fertige App" ist

Ich schreibe die Baupläne so, dass sie das **V1-Milestone** liefern, das die bestehenden Projektdokumente selbst schon definieren: robuste Live-Zählung + Guided Calibration 2.0 MVP (ohne Tap-to-Tag/Metronom, die sind explizit V2) + saubere Hardware-Verifikation. Das ist ein großer, gut abgegrenzter Schritt – aber keine store-fertige App mit Onboarding, Mehrfach-Übungs-Support, Branding etc. Das würde ich bewusst als nächste Runde behandeln, nicht in dieselben 4 Baupläne packen.

## 6. Was du zwischendurch tun musst

- Nach Agent 1: mergen (siehe Abschnitt 3).
- Für Agent 4: du bist die Hände. Der Bauplan gibt dir exakte Kommandos/Handlungen, die DU physisch ausführst (Gerät anschließen, Curl machen, Wert ablesen).
- Am Ende: eine finale Integrationsrunde (Agent 3s UI wirklich an Agent 2s fertigen Controller anschließen, alle 4 Branches nacheinander mergen, einmal `flutter test` + Simulation komplett durchlaufen lassen). Sag mir Bescheid, wenn alle 4 Branches stehen, dann übernehme ich diese letzte Runde.

## 7. Konkrete nächste Schritte für dich

1. Diese Übersicht lesen (fertig, du bist hier).
2. Die 4 Baupläne an 4 separate KI-Sessions geben (am besten: Datei in die jeweilige Session hochladen oder Repo-Zugriff geben, damit sie sie selbst lesen können).
3. Sobald Desktop-Commander bei mir wieder steht, committe und pushe ich alle 5 Dateien in `docs/Umbauplan Flowrep/agenten-baupläne/` – dann kann jeder Agent seinen Bauplan direkt aus der Repo lesen, statt dass du ihn einfügen musst.

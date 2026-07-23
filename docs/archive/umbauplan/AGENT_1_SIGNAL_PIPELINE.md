# Bauplan Agent 1: Signal & Datenpipeline

> Eigenständiges Arbeitspaket für das FlowRep-Projekt (Flutter-App + M5StickC-Plus2-Wearable, BLE, Wiederholungszählung beim Krafttraining). Du brauchst keine anderen Baupläne, um diese Aufgabe zu erledigen. Alle Pfade, Befehle und Entscheidungen unten sind so konkret wie möglich gehalten – wenn die Realität im Repo davon abweicht, gilt IMMER die Realität im Repo, nicht dieser Text. Prüfe deshalb jeden Pfad, bevor du ihn benutzt.

## 0. Wer du bist

Du bist einer von vier parallel arbeitenden KI-Agenten. Du bist zuständig für: **die Zählpipeline im laufenden Betrieb ehrlicher und robuster machen.** Du bist NICHT zuständig für die neue Guided-Calibration-UI, nicht für Firmware, nicht für Persistenz. Andere Agenten arbeiten gleichzeitig an anderen Dateien in derselben Repo – das ist beabsichtigt, kein Fehler.

## 1. Auftrag in einem Satz

Behebe die drei dokumentierten, noch offenen Schwächen der Live-Zählung (kein Refraktärfenster → Doppelzählung, gyrodominante Schwelle → verpasste langsame Wiederholungen, unehrliche Zeitbasis/Datenverlust in der Aufnahme) – erst per Python-Simulation bewiesen, dann als Dart-Port übernommen.

## 2. Repo-Zugriff & erstes Vorgehen (PFLICHT vor jeder Änderung)

1. Repo klonen bzw. vorhandenen Checkout nutzen: `https://github.com/Adilinu94/flowrep`
2. `git checkout main && git pull origin main` – hol dir garantiert den aktuellsten Stand, nicht irgendeinen gecachten.
3. `git log --oneline -20` ansehen. Prüfe, ob Commits mit folgenden Stichworten schon existieren, BEVOR du anfängst (falls ja: diese Arbeit ist schon erledigt, überspringen): "Settle-Gate"/ADR-020, `flutter_blue_plus` Versionsbump, NimBLE-Firmware-Merge. Diese waren zum Zeitpunkt dieses Bauplans bereits erledigt – falls du sie nicht findest, ist etwas verloren gegangen; melde das sofort (siehe Abschnitt 10), bevor du weitermachst.
4. Lies `docs/Umbauplan Flowrep/RECHERCHE_ZAEHLROBUSTHEIT_2026-07-16.md` komplett. Das ist deine fachliche Spezifikation (S1–S8 Schwachstellen, P0–P3 Priorisierung). Dieser Bauplan hier fasst nur zusammen, was für dich relevant ist – bei Widerspruch gilt das Originaldokument.
5. Lies `docs/Umbauplan Flowrep/STATUS_FORTSCHRITT.md`, mindestens die letzten 3–4 Einträge, um zu sehen, was seither passiert ist.

## 3. Kontext, den du brauchst

FlowRep zählt Bizeps-Curls über IMU-Daten (Gyro + Beschleunigung) vom M5StickC Plus2, per BLE an eine Flutter-App gesendet. Der Zähl-Kern ist ein State Machine (`WorkoutState`: idle/calibrating/counting/…) in `app/lib/domain/workout_engine.dart`. Es gibt zwei getrennte Signalpfade im Code: einen für die geführte Kalibrierung (Peak-Erkennung über `_findPeaksWithIndices`, bereits stabil und getestet) und einen für den normalen Live-Betrieb (Peak-/Schwellwert-Erkennung, vermutlich `_detectPeak` oder ähnlich benannt – verifiziere den exakten Namen selbst). **Du arbeitest ausschließlich am Live-Betrieb-Pfad, nicht an der Kalibrierungs-Peak-Erkennung.**

Bereits verifiziert und behoben (nicht nochmal anfassen): Baseline-Kontamination während Kalibrierung (S6, Commit `3907706`), Race Condition in Reconnect-Handling, Plateau-Bug im Median-Filter der Kalibrierung.

Noch offen und dein Auftrag (aus RECHERCHE_ZAEHLROBUSTHEIT, App-seitiger Anteil):

- **S1 – kein Refraktärfenster im Live-Pfad:** mehrfach reproduziert, dass eine echte Wiederholung als 2 gezählt wird (20 statt 10 bei Testserie). Die Kalibrierung hat bereits ein Refraktärfenster, der Live-Pfad nicht.
- **S2 – Schwelle gyro-dominiert (~114°/s):** langsame/kontrollierte Wiederholungen werden nicht erkannt.
- **S3 – Zeitbasis ist fiktiv:** Firmware sendet Batches ohne echtes Pacing, die App erzeugt aktuell künstliche, gleichmäßige 20ms-Abstände statt echter Zeitstempel. Das verzerrt jede zeitbasierte Berechnung (Tempo, Refraktärfenster in Echtzeit statt in Sample-Anzahl).
- **S5 – stiller Datenverlust** durch ein Dedup-Polling-Workaround in der BLE-Datenannahme.
- **S8 – Signal ist nur Betrag (magnitude), verliert Richtung** – Grundlage für den strukturellen Fix (P2).

## 4. Dateien, die dir gehören

- `app/lib/domain/workout_engine.dart` – **nur der Live-Zählpfad** (State `counting`/aktiver Betrieb). Fasse den Kalibrierungs-Zweig (`calibrating`-State-Handling, `_findPeaksWithIndices`) NICHT an.
- `app/lib/domain/signal_processor.dart` – falls diese Datei existiert (verifiziere zuerst; die DSP-Logik kann auch Teil von workout_engine.dart sein).
- `app/lib/data/providers/ble_sensor_provider.dart` – Zeitstempel-Handling, Dedup-Logik, Skalierung.
- `tools/workout_engine_simulation.py` – hier fügst du NEUE Funktionen/Tests hinzu, du löschst oder veränderst nicht die bestehenden Funktionen zur Guided-Calibration-2.0-Simulation (`stufe0_ruheanalyse`, `stufeA_achsenanalyse`, `known_count_sweep`, `median_minus_k_mad`, `stufeC_tempo_robustheit`, `stufeD_review_simulation`, `kalibriere_persona`, `run_known_count_calibration_suite`) – die gehören zu Agent 2s Referenzimplementierung.
- `app/test/workout_engine_test.dart` – neue Regressionstests ergänzen, bestehende 16 Tests dürfen nicht kaputtgehen.

## 5. Dateien, die du NICHT anfassen darfst

`calibration_controller.dart` (existiert noch nicht – falls doch, gehört sie Agent 2), alles unter `presentation/screens/calibration/`, `calibration_store.dart`, `drift_database.dart`, `firmware/*`, `docs/reference/protocol.yaml` (du LIEST diese Datei, du schreibst sie nicht – die Protokoll-Version kommt von Agent 4), `pubspec.yaml`/`pubspec.lock` (siehe Abschnitt 6, Sonderfall).

## 6. Aufgaben, Schritt für Schritt

**Wichtige Grundregel des Projekts (ADR-022): Simulation zuerst, Dart-Implementierung erst danach.** Kein Schritt unten überspringt das.

### Schritt A – P1: Refraktärfenster + adaptive Schwelle (kannst du sofort starten)
1. In `tools/workout_engine_simulation.py`: neue Funktion, die das bestehende `double_bump`-Persona-Signal (falls vorhanden, sonst selbst eine Persona mit doppeltem Peak pro Wiederholung bauen) durch die AKTUELLE Live-Zähllogik schickt und das bekannte Fehlverhalten reproduziert (20 statt 10).
2. Implementiere ein Refraktärfenster (Sperrzeit nach jedem gezählten Peak, in Sample-Anzahl gemessen, nicht in Echtzeit-ms – Begründung: S3, die Zeitbasis ist noch nicht ehrlich, siehe Schritt C). Bestimme die Fensterlänge NICHT durch Schätzen, sondern durch einen Parameter-Sweep über mehrere Personas (clean, double_bump, weak, slow, inconsistent – dieselben Personas, die Agent 2s Kalibrierungs-Code nutzt, falls schon vorhanden, sonst analog eigene bauen), genau wie es das Projekt bereits für Kalibrierungs-Parameter macht. Ziel: `double_bump` wird korrekt gezählt, `slow` wird NICHT fälschlich als 2 Wiederholungen gezählt.
3. Ergänze eine zweite, adaptive Schwelle statt der festen ~114°/s (S2), z.B. relativ zum in der Kalibrierung ermittelten `peakThreshold` statt eines Hardcodes. Nutze Prominence (Höhe des Peaks relativ zu seiner unmittelbaren Umgebung) als zusätzliches Kriterium, nicht nur absolute Höhe.
4. Erst wenn die Simulation für alle Personas stabil korrekt zählt: identische Logik nach `workout_engine.dart` portieren (Live-Pfad).
5. Neue Tests in `workout_engine_test.dart`: mindestens ein Test, der Doppelzählung bei kurz aufeinanderfolgenden Peaks verhindert, und einer, der eine bewusst langsame Wiederholung korrekt zählt.

### Schritt B – P2: Struktureller Signal-Fix (nach Schritt A)
1. In der Simulation: Signal von reinem Betrag (`|gyro|`) auf vorzeichenbehaftete Projektion auf eine Achse umstellen (`g_p`, "signed gyro projection") – die Achse liefert bei dir noch niemand, du nimmst vorerst die dominante Gyro-Achse direkt (nicht die PCA-Achse aus der Kalibrierung – das ist Agent 2s Baustelle; wenn Agent 2s `CalibrationController` bereits gemerged ist, wenn du hier ankommst, darfst du dessen `rotationAxis`-Ergebnis konsumieren, aber du implementierst nichts davon selbst).
2. Ergänze eine einfache ZUPT-artige Drift-Korrektur (Zero-Velocity-Update: wenn das Signal für X aufeinanderfolgende Samples nahe Null/Ruhe ist, Integrationsdrift zurücksetzen) – nur falls du tatsächlich eine Integration durchführst; falls die Zählung rein auf Peak-Erkennung im Rohsignal bleibt, ist dieser Punkt niedrigere Priorität, dokumentiere das explizit als "nicht umgesetzt, weil nicht nötig" statt es stillschweigend wegzulassen.
3. Beweise in der Simulation: der `double_bump`-Fall wird jetzt STRUKTURELL korrekt gezählt (nicht nur durchs Refraktärfenster kaschiert). Vergleiche Alt- vs. Neu-Suite explizit im Simulationsoutput (das Projekt macht das bereits so, siehe `run_known_count_calibration_suite` als Vorbild).
4. Erst danach: Port nach `workout_engine.dart`.

### Schritt C – P0 (App-Seite): ehrliche Zeitbasis, kein Datenverlust
**Voraussetzung: Agent 4 muss zuerst die neue Protokoll-Spezifikation liefern (`docs/reference/protocol.yaml`, kommt als dessen erstes, schnelles Ergebnis). Prüfe vor Beginn dieses Schritts, ob diese Datei bereits eine neue Protokollversion mit echten Zeitstempeln beschreibt. Falls nicht: Schritt C zurückstellen, mit Schritt A/B weitermachen, später zurückkommen.**
1. `ble_sensor_provider.dart`: echte Zeitstempel aus dem (neuen) Protokoll parsen statt künstliche 20ms-Abstände zu synthetisieren.
2. Dedup-Logik durchgehen: die aktuelle Lösung ist ein Polling-Workaround, der nachweislich still Daten verwerfen kann (S5). Ersetze das Kriterium so, dass kein Sample verworfen wird, das nicht nachweislich ein exaktes Duplikat ist (z.B. über die neue, echte Zeitstempel/Sequenznummer statt über einen Timing-Heuristik-Workaround).
3. Wenn Agent 4s Protokoll die Gyro-Skalierung ändert (Clipping-Fix, aktuell ±327,67°/s durch int16/100-Skalierung, echte Curls erreichen bis zu ~344°/s): Parsing entsprechend anpassen.

## 7. Definition of Done

Alle Punkte müssen erfüllt sein, bevor du deinen Branch pushst:

- [ ] `python tools/workout_engine_simulation.py` läuft durch, druckt für alle Personas (mindestens clean, double_bump, weak, slow, inconsistent) korrekte Zählung ohne die bekannten Fehler (kein 20-statt-10, keine verpassten langsamen Reps).
- [ ] `flutter analyze` (im `app/`-Verzeichnis; falls unter Windows ein `ProgramFiles(x86)`-Umgebungsfehler auftritt: `$env:"ProgramFiles(x86)" = "C:\Program Files (x86)"` vor dem Aufruf setzen) meldet 0 Fehler.
- [ ] `flutter test` zeigt "All tests passed!" – die bisherigen 16 Tests UND deine neuen Tests.
- [ ] Kein Merge-Konflikt-Risiko: `git diff --stat` zeigt NUR Dateien aus Abschnitt 4, keine aus Abschnitt 5.
- [ ] Du hast NICHT `git push origin main` ausgeführt.

## 8. Git-Workflow (PFLICHT, keine Ausnahmen)

```
git checkout main
git pull origin main
git checkout -b agent1-signal-pipeline
# ... arbeiten, testen ...
git add app/lib/domain/workout_engine.dart app/lib/domain/signal_processor.dart app/lib/data/providers/ble_sensor_provider.dart tools/workout_engine_simulation.py app/test/workout_engine_test.dart
# NIEMALS "git add -A" oder "git add ." blind verwenden – immer nur die Dateien, die dir gehören.
git commit -m "feat(engine): P1 refractory + adaptive threshold + P2 signed-gyro signal (RECHERCHE_ZAEHLROBUSTHEIT S1/S2/S8)"
git push origin agent1-signal-pipeline
```

**Du merged NIEMALS selbst nach `main`.** Du pusht deinen Branch und stoppst. Adi oder Claude übernehmen das Mergen. Das ist keine Höflichkeitsregel, sondern verhindert genau das Problem, das in diesem Projekt bereits einmal aufgetreten ist (zwei Sessions haben `main` auseinanderlaufen lassen).

Falls du beim Start feststellst, dass `pubspec.yaml`/`pubspec.lock` eine neue Dependency bräuchte: NICHT hinzufügen. In deinem Statusbericht (Abschnitt 9) vermerken und dort stehen lassen. Neue Dependencies sind der häufigste Grund für Lock-File-Konflikte zwischen parallelen Agenten.

## 9. Fortschritt dokumentieren

Füge am Ende von `docs/Umbauplan Flowrep/STATUS_FORTSCHRITT.md` einen NEUEN Abschnitt an (nichts Bestehendes überschreiben oder löschen), im bestehenden Format des Dokuments: Datum, Kennung `Agent-1-SignalPipeline`, was geprüft/gefunden/gefixt wurde, welche Tests grün sind, was noch offen ist.

## 10. Wenn du blockiert bist

- Wenn ein Pfad aus diesem Bauplan nicht existiert oder anders heißt: nicht raten, nicht improvisieren – im Statusbericht dokumentieren, mit dem naheliegendsten Ersatz weitermachen, klar kennzeichnen, dass es eine Annahme war.
- Wenn du merkst, dass du eine Datei außerhalb deiner Liste (Abschnitt 4) ändern müsstest, um deine Aufgabe zu lösen: NICHT tun. Stopp, im Statusbericht dokumentieren, was du bräuchtest und warum.
- Wenn Agent 4s Protokoll-Update (Schritt C) nach angemessener Zeit nicht vorliegt: Schritt A und B trotzdem fertigstellen und pushen, Schritt C separat nachreichen.

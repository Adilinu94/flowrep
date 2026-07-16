# Execution Plan – FlowRep (korrigierte Version)

**Ersetzt:** `Execution_Plan.txt` (vorherige KI-Sitzung)
**Wichtigster Unterschied:** Der ursprüngliche Plan begann mit "Phase 1: Initialisiere das Flutter-Projekt" – als wäre das Repository leer. Dieser Plan beginnt beim tatsächlichen Ist-Zustand (funktionierende BLE-Verbindung, Firmware, Datenbank, Guided-Calibration-UI, ein bekannter, lokalisierter Bug) und definiert nur die *nächsten* Schritte.

---

## Harte Regeln für die ausführende KI (unverändert aus dem Original, haben sich bewährt)

1. **Iterative Sperre:** Niemals mehr als eine Phase auf einmal. Keine Phase 2, solange Phase 1 nicht vom Product Manager abgenommen wurde.
2. **Keine Vorgriffe:** Keine Features aus späteren Phasen vorab implementieren.
3. **USER ACTION Pflicht:** Nach jeder Phase: Prosa-Erklärung + nummerierte Checkliste mit dem Titel "USER ACTION".
4. **Wartezyklus:** Nach USER ACTION stoppt die KI vollständig und wartet auf "Phase erfolgreich".
5. **Eskalation bei Blockaden:** Bei ungelösten Problemen: abbrechen, Problem beschreiben, auf Anweisung warten.
6. **Neu – Bestandsprüfung als Phase-0-Pflicht:** Vor Beginn jeder Phase liest die KI den tatsächlichen, aktuellen Stand von `master` (nicht `main`) und gleicht ihn mit der Phasenbeschreibung ab. Bei Widersprüchen: Eskalation statt Fortfahren.

---

## PHASE 0: Bestandsaufnahme und Vorbereitung

**Ziel:** Sicherstellen, dass die ausführende KI mit dem tatsächlichen Code arbeitet, nicht mit Annahmen.

**Aufgabe:**
1. Repository auf `master`-Branch klonen/auschecken (nicht `main` – dieser Branch ist veraltet und nie hardware-getestet).
2. `docs/04_ARCHITECTURE_DECISION_RECORDS.md` lesen, aktuell höchste ADR-Nummer notieren (Stand bei Erstellung dieses Plans: ADR-018; neue ADRs aus diesem Set beginnen bei ADR-019).
3. `app/lib/domain/workout_engine.dart`, `app/lib/domain/signal_processor.dart`, `tools/workout_engine_simulation.py`, `app/test/workout_engine_test.dart` lesen.
4. Bestätigen, dass der in ADR-020 (Dokument 02) beschriebene Bug tatsächlich im aktuellen Code vorliegt (Konstruktor-Default `calibrationReps = 1`, keine Überschreibung an den Instanziierungsstellen, kein Unterscheidungs-Flag im `idle`-State).

**Abnahmekriterium:** Die KI kann in eigenen Worten bestätigen, wo genau im Code der ADR-020-Bug liegt, unter Angabe der betroffenen Datei(en) und Zeilen/Methoden.

**USER ACTION:**
1. Bestätige, dass die KI den Bug korrekt im aktuellen Code lokalisiert hat.
2. Gib "Phase 0 erfolgreich" ein, um fortzufahren.

---

## PHASE 1: Bugfix – Kalibrierungs-Persistenz (ADR-020)

**Ziel:** Der aus der Guided Calibration ermittelte Schwellenwert bleibt nach Abschluss der Kalibrierung erhalten.

**Aufgabe:**
1. In `tools/workout_engine_simulation.py`: Guided-Calibration-Zustand nachbilden (falls noch nicht vorhanden) und den Regressionstest aus Dokument 04, Skript 2, hinzufügen. **Test muss zuerst fehlschlagen** (Beweis, dass er den Bug erkennt).
2. In `app/lib/domain/workout_engine.dart`: Fix gemäß Dokument 03, Abschnitt 4, implementieren (`_hasValidCalibration`-Flag, angepasste `idle`-State-Logik).
3. Denselben Regressionstest als Dart-Unit-Test in `app/test/workout_engine_test.dart` ergänzen.
4. `flutter analyze` und `flutter test` ausführen.

**Abnahmekriterium:** Der Regressionstest schlägt vor dem Fix fehl und ist nach dem Fix grün, in Python **und** in Dart. Alle bestehenden Tests bleiben grün.

**USER ACTION:**
1. Führe `python tools/workout_engine_simulation.py` aus (oder das entsprechende Test-Kommando) und bestätige den grünen Regressionstest.
2. Führe `flutter test` aus und bestätige 100 % grün.
3. Teste auf echter Hardware: Guided Calibration abschließen, direkt danach 10 Reps in normalem Tempo ausführen. Notiere gezählte vs. tatsächliche Anzahl.
4. Gib "Phase 1 erfolgreich" ein, um fortzufahren.

---

## PHASE 2: DSP-Verbesserung – Komplementärfilter in Python verfeinern

**Ziel:** Den in Dokument 04 skizzierten Komplementärfilter-Ansatz mit echten (nicht nur synthetischen) Daten prüfen und die Achsenzuordnung verifizieren, bevor Dart-Code geschrieben wird.

**Aufgabe:**
1. Mit dem bestehenden Aufzeichnungs-/Export-Mechanismus der App (falls vorhanden) oder über Serial-Logging: mindestens 5 Aufnahmen sammeln (siehe Dokument 07, Szenarien A und "Kurzpausen-Test").
2. Das Skript aus Dokument 04 so erweitern, dass es reale CSV-Daten statt synthetischer Daten einliest.
3. Prüfen: Welche Rohachse entspricht tatsächlich der Ellenbogen-Rotation (Gyro mit größter Amplitude während eines Curls)? Falls die Modellannahme aus Dokument 03 (Rotation um X, Gravitation zwischen Y/Z) nicht zutrifft, Formeln entsprechend anpassen.
4. Filterparameter (`baseAlpha`, Trust-Fenster-Breite) gegen reale Daten neu justieren, falls nötig.

**Abnahmekriterium:** Das Pause/Peak-Verhältnis auf realen Daten liegt spürbar unter dem, was die bestehende, unveränderte Pipeline auf denselben Daten liefert. Konkrete Zielzahl wird nach den ersten realen Messungen festgelegt (nicht vorab spekulativ, da reale Rauscheigenschaften noch unbekannt sind).

**USER ACTION:**
1. Stelle mindestens 5 CSV-Aufnahmen gemäß Dokument 07 bereit.
2. Prüfe die vorgelegte Auswertung (Pause/Peak-Verhältnis alt vs. neu, auf echten Daten).
3. Gib "Phase 2 erfolgreich" ein, um fortzufahren – oder "Phase 2 zurück an Start", falls die reale Achsenzuordnung von der Annahme abweicht und das Konzept überarbeitet werden muss.

---

## PHASE 3: Dart-Portierung der Gravitationskompensation

**Ziel:** Der in Phase 2 validierte Filter läuft live in der App.

**Aufgabe:**
1. `GravityEstimate`-Klasse und die in Dokument 03, Abschnitt 3, spezifizierten Methoden in `SignalProcessor` implementieren (kausale Variante, kein `filtfilt`-Äquivalent).
2. Unit-Test: Dieselben realen CSV-Daten aus Phase 2 als Fixture einlesen, Dart-Ausgabe mit der (kausalen!) Python-Referenzimplementierung vergleichen. **Erwartung ist Annäherung, nicht exakte Übereinstimmung** – siehe Non-Kausalitäts-Hinweis in Dokument 04, sofern die Python-Referenz `filtfilt` nutzt. Empfehlung: Für den Vergleich eine kausale Python-Variante (`scipy.signal.lfilter` oder die identische manuelle Rekursion) als Referenz verwenden, nicht `filtfilt`.
3. Bestehende Schwellenwerte (`peakThreshold` etc.) auf Basis der neuen, niedrigeren Signal-Skala neu kalibrieren (siehe Konsequenzen in ADR-019).
4. `flutter analyze`, `flutter test`.

**Abnahmekriterium:** App zeigt bei ruhig auf dem Tisch liegendem Sensor eine `dynMagnitude` nahe 0. Bei einer Testperson, die den Sensor langsam um 180° dreht (ohne zu schütteln), bleibt `dynMagnitude` niedrig (kein Fehlalarm durch reine Rotation ohne Beschleunigung).

**USER ACTION:**
1. Lege den Sensor flach hin, lies `dynMagnitude` in der Konsole ab (Soll: nahe 0).
2. Drehe den Sensor langsam, ohne ihn zu bewegen/zu schütteln, lies `dynMagnitude` ab (Soll: weiterhin niedrig).
3. Gib "Phase 3 erfolgreich" ein, um fortzufahren.

---

## PHASE 4: End-to-End-Vergleich alt vs. neu auf Hardware

**Ziel:** Belastbarer Vergleich zwischen der bisherigen Pipeline (Bugfix aus Phase 1, aber ohne Gravitationskompensation) und der neuen Pipeline (Phase 1 + 2 + 3) unter identischen Bedingungen.

**Aufgabe:**
1. Feature-Flag oder Build-Variante, die zwischen alter und neuer Signalverarbeitung umschaltet (für einen sauberen A/B-Vergleich, danach wieder entfernen – kein Dead Code langfristig).
2. Mindestens 10 Testsätze (verteilt auf mehrere Tage/Tageszeiten, siehe Dokument 01, Erfolgskriterien) mit beiden Varianten durchführen und Ergebnisse protokollieren (Testprotokoll-Vorlage im echten Repo, `docs/09_TESTPROTOKOLL_TEMPLATE.md`, weiterverwenden).

**Abnahmekriterium:** Erfolgskriterium aus `01_PROJECT_CHARTER_AND_SCOPE.md` (mind. 8 von 10 Sätzen innerhalb ±1 Rep) wird von der neuen Pipeline erreicht oder es liegt eine klare, dokumentierte Diagnose vor, warum nicht.

**USER ACTION:**
1. Führe die 10 Testsätze durch und trage die Ergebnisse in das Testprotokoll ein.
2. Gib "Phase 4 erfolgreich" ein – oder beschreibe die aufgetretenen Abweichungen für die nächste Debugging-Runde.

---

## PHASE 5 (optional, nur bei Bedarf): Klassischer ML-Klassifikator für mehrere Übungen

Wird erst begonnen, wenn Phase 4 erfolgreich abgeschlossen ist **und** eine zweite Übung tatsächlich unterstützt werden soll. Nicht Teil des aktuellen Umfangs – siehe ADR-021. Wird als eigenständiger Execution Plan nachgereicht, sobald relevant.

---

## Ausdrücklich NICHT Teil dieses Plans

Im Unterschied zum ursprünglichen Execution Plan enthält dieser Plan **keine** Phasen für: Flutter-Projekt-Neuinitialisierung, erneute BLE-Paketierungs-Entscheidung, erneute Wahl des BLE-Pakets, erneute Datenbank-Wahl, TFLite-Integration, 5-Phasen-Sequenzmodell-Training. Diese Dinge existieren bereits (erste Gruppe) oder sind gemäß ADR-021 bewusst zurückgestellt (zweite Gruppe).

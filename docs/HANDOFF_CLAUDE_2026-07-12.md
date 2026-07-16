# HANDOFF — Claude-Sitzung Ende (2026-07-12)

Diese Sitzung wird hier beendet, Adi macht in einem neuen Chat weiter. Dieses
Dokument ist der Einstiegspunkt für die nächste Session — bitte VOR jeder
Code-Änderung lesen, zusätzlich zur normalen Onboarding-Reihenfolge aus
`05_KI_ONBOARDING_PROMPT.md`.

## 0. Lesereihenfolge für die nächste Session

1. `05_KI_ONBOARDING_PROMPT.md` (wie immer, Pflicht)
2. **Dieses Dokument**
3. `HANDOFF_AN_NAECHSTE_KI_2026-07-12.md` — enthält die echten Serial-IMU-Rohdaten
   und 5 Hypothesen zum ungelösten Kernproblem (siehe Abschnitt 1 unten).
   Wurde von einer parallel arbeitenden KI-Session (im Dokument "Buffy +
   Gemini Thinker" genannt, siehe `DEBUGSESSION_2026-07-12.md`) geschrieben,
   bevor diese Claude-Sitzung begann.
4. `docs/FRAGEN_FUER_SCHLAUE_KI.md` — 10 konkrete technische Fragen, davon
   mehrere direkt relevant für Adis neue Anfrage (siehe Abschnitt 6 unten)
5. `docs/ANALYSE_EXTERNE_KI_2026-07-12.md` — die ursprüngliche Analyse dieser
   Claude-Sitzung, laufend aktualisiert, Status aller Punkte A–G

## 1. WICHTIGSTES ZUERST: Das Kernproblem ist vermutlich noch NICHT gelöst

**Nicht von den Fixes in Abschnitt 2/3 täuschen lassen.** Laut
`HANDOFF_AN_NAECHSTE_KI_2026-07-12.md` zeigte die App **nach einem einzelnen
echten Bizeps-Curl immer noch "0" Wiederholungen an** — trotz aller zu dem
Zeitpunkt bereits vorhandenen Fixes (B, C, D, E, G, plus mehrere weitere, siehe
dortige Tabelle). Das war ein Test im normalen Betrieb (Zustand "idle" laut
Screenshot), nicht im Guided-Calibration-Dialog.

Das ist **nicht dasselbe Problem**, das diese Claude-Sitzung gefunden und
gefixt hat (siehe Abschnitt 3 — der Median-Filter-Plateau-Fund betrifft
speziell die Peak-Erkennung *innerhalb* der Guided Calibration). Es ist
unklar, ob mein Fix das "0 Reps nach 1 Curl"-Symptom mitbehebt oder nicht —
das wurde in dieser Sitzung **nicht getestet**, weil kein Zugriff auf echte
Hardware besteht.

**Fünf offene Hypothesen aus `HANDOFF_AN_NAECHSTE_KI_2026-07-12.md` Abschnitt 5.1,
unverändert offen:**

a) Die Engine empfängt gar keine Samples (Stream-Subscription nicht aktiv)
b) `combinedSignal` erreicht nie `peakThreshold` (trotz Gyro-Beitrag)
c) `_baselineLevel` wird durch das erste High-Sample kontaminiert
d) Race Condition: `handleReconnect()` resettet die Engine, nachdem Samples
   schon fließen
e) Der `_bindEngine()`-Fix (Stream-Management-Refactor, siehe Tabelle in
   `HANDOFF_AN_NAECHSTE_KI_2026-07-12.md` Punkt B) hat selbst einen Bug

**Empfohlener erster Schritt der nächsten Session, noch vor der neuen Anfrage
aus Abschnitt 6:** `_diagEngineSampleCount` (existiert bereits als Public
Getter in `workout_engine.dart`) sichtbar machen — z. B. testweise im HomeScreen
neben dem Rep-Counter anzeigen — und dann einen echten Curl machen. Wenn die
Zahl nicht hochzählt, ist (a) bestätigt und alles andere ist erstmal
zweitrangig. Das ist der schnellste Weg, die 5 Hypothesen einzugrenzen.

## 2. Was in dieser Claude-Sitzung passiert ist (chronologisch)

1. Sehr gründliche Erstanalyse des Projekts (alle Onboarding-Docs, kompletter
   Code, Screenshots) auf Adis erste Anfrage hin — Ergebnis: 7 Punkte A–G,
   dokumentiert in `docs/ANALYSE_EXTERNE_KI_2026-07-12.md`
2. Adi gab GitHub-Zugriff (Token) — **funktionierte nicht**, siehe Abschnitt 5
3. Zugriff stattdessen über die bereits verbundene Filesystem-MCP-Verbindung
   auf `C:\Users\adini\Desktop\flowrep-main`
4. Beim erneuten Prüfen des aktuellen Stands (wie von Adi verlangt) stellte
   sich heraus: Punkte B, C, D, E, G waren zwischenzeitlich **bereits von
   einer anderen KI-Session** umgesetzt worden — direkt im Code verifiziert,
   nicht nur der Status-Datei geglaubt
5. Diese Sitzung übernahm Punkt F: `tools/workout_engine_simulation.py`
   komplett neu aufgebaut (Guided-Calibration-Pfad nachgebildet,
   Idle/Paused/Falling-Edge auf baseline-relativ synchronisiert), plus neue
   Dart-Tests in `workout_engine_test.dart`
6. Beim Testen der neu gebauten Simulation: **Fund** des Median-Filter-
   Plateau-Problems (siehe Abschnitt 3) — mit Simulation verifiziert (0/30
   vs. 30/30), dann nach Adis "kümmere dich um die letzten Punkte" in
   `workout_engine.dart` angewendet und der zugehörige Test von `skip:` befreit
7. Adi stellte eine neue, große Anfrage (99% Genauigkeit, Deep Learning,
   5 externe Repos analysieren) — **wurde begonnen, aber auf Adis Wunsch
   abgebrochen**, siehe Abschnitt 6
8. Dieses Handoff-Dokument

## 3. Der Median-Filter-Plateau-Fund und -Fix (Beitrag dieser Sitzung)

**Befund:** Der 5-Sample-Median-Filter in `_findPeaksWithIndices()`
(`workout_engine.dart`) erzeugte bei sauberen, kontrollierten Wiederholungen
ein mehrere Samples breites Plateau exakt am Scheitelpunkt. Eine strikte
Lokal-Maximum-Prüfung (`smoothed[i] > beide Nachbarn`) kann darin
strukturell keinen Punkt als Peak erkennen — auch wenn der Peak eindeutig
ist. Bei der realen App-Datenrate (~14–20 Hz) trat das in der Simulation in
30 von 30 Durchläufen auf (0/30 abgeschlossene Kalibrierungen).

**Fix:** `_findPeaksWithIndices()` ist jetzt tie-tolerant (`>=` statt `>` auf
einer Seite des Vergleichs — Standardtechnik gegen Plateaus in
Peak-Detektoren). Mit der Simulation verifiziert: 30/30 statt 0/30.

**Wichtige Einschränkung:** Das betrifft die Peak-Erkennung *innerhalb* der
Guided Calibration (`_findGyroValidatedPeaks()` → `_findPeaksWithIndices()`).
Ob das auch mit dem in Abschnitt 1 beschriebenen "0 Reps nach 1 Curl im
Normalbetrieb"-Symptom zusammenhängt, ist **nicht verifiziert** — das ist ein
anderer Codepfad (normale `active`-State-Zählung nutzt `_detectPeak()`
direkt, nicht `_findPeaksWithIndices()`). Auf echtem Gerät testen, nicht
davon ausgehen, dass das behoben ist.

## 4. Aktueller Dateistand

**Alle Änderungen wurden über die Filesystem-MCP-Verbindung direkt geschrieben
und sind auf der Festplatte — aber NICHTS wurde committed oder gepusht.**

| Datei | Was geändert |
|-------|-------------|
| `app/lib/domain/workout_engine.dart` | `_findPeaksWithIndices()`: `>=` statt `>` (Plateau-Fix) |
| `app/test/workout_engine_test.dart` | Neue Gruppe `WorkoutEngine.guidedCalibration` (4 Tests), 1 stale Kommentar korrigiert |
| `tools/workout_engine_simulation.py` | Komplett neu: `SignalProcessor`, `GuidedCalibrationSim` (jetzt = gefixter Stand), `GuidedCalibrationSimStrictLegacy` (altes Verhalten zum Vergleich), baseline-relative `WorkoutEngineSim` |
| `docs/ANALYSE_EXTERNE_KI_2026-07-12.md` | Laufend aktualisiert, Punkt F jetzt ✅ |
| `docs/HANDOFF_CLAUDE_2026-07-12.md` | Diese Datei (neu) |

**Für Adi — bitte selbst ausführen:**
```bash
cd C:\Users\adini\Desktop\flowrep-main
flutter analyze
flutter test
python3 tools/workout_engine_simulation.py
git add -A
git commit -m "Sync Python simulation with guided calibration; add tests; fix median-filter plateau bug in peak detection (Punkt F)"
git push
```
Ich konnte `flutter analyze`/`flutter test` **nicht selbst ausführen** (kein
Flutter-Toolchain in meiner Sandbox) — die Dart-Testkorrektheit wurde nur
durch sorgfältiges manuelles Nachvollziehen plus Gegenprobe der identischen
Logik in Python (dort tatsächlich ausgeführt) sichergestellt, nicht durch
echtes Kompilieren. Bitte vor dem Vertrauen in die Tests einmal wirklich
laufen lassen.

## 5. Tool-/Umgebungshinweise für die nächste Session

- **GitHub ist von Claudes Sandbox aus nicht erreichbar:** `bash_tool` bekommt
  für `github.com`, `api.github.com`, `codeload.github.com` konsistent
  `403 host_not_allowed` von der eigenen Netzwerk-Firewall (nicht von GitHub).
  Müsste in den Netzwerk-/Egress-Einstellungen für Code-Ausführung freigegeben
  werden, falls gewünscht. Ein GitHub-MCP-Connector war ebenfalls nicht aktiv.
- **Filesystem-MCP ist gelegentlich abgebrochen** (einmal in dieser Sitzung) —
  Symptom: Tools werfen "not found". Hilft: `tool_search` mit z. B. "filesystem
  read write directory" erneut aufrufen; falls das nicht hilft, liegt es am
  lokalen MCP-Server/-Client bei Adi (neu starten).
- **web_fetch funktioniert für öffentliche GitHub-Repos** (README, Dateibaum),
  aber nur für URLs, die schon im Gespräch aufgetaucht sind (vom Nutzer
  genannt oder aus einer vorherigen Suche/einem vorherigen Fetch zurückgegeben)
  — direkt eine vermutete Datei-URL wie `.../blob/main/irgendwas.py` zu raten
  scheitert. Erst die Repo-Hauptseite fetchen, dann Links daraus verwenden,
  oder web_search nutzen.
- Das private `Adilinu94/flowrep`-Repo auf GitHub selbst ist für Claude
  **nicht lesbar** (unauthentifizierter Zugriff → 404, da privat).

## 6. Neue, noch offene Anfrage von Adi (Ende dieser Sitzung)

Adi möchte danach als Nächstes:

1. **Ziel: ~99% Genauigkeit** bei der Rep-Erkennung
2. Recherche: welche Funktionen/Tools/Ansätze bräuchte es dafür
3. **Ist Deep Learning sinnvoll?** — explizit im Kontext, dass später auch
   andere Übungen (z. B. Latzug/Lat-Pulldown) erkannt werden sollen, die
   biomechanisch komplett anders aussehen als Bizeps-Curls
4. Analyse von 5 externen GitHub-Repos, jeweils bewerten ob nützlich, wenn
   ja **klonen und sehr genau analysieren**:
   - `https://github.com/YashsTiwari/TrackFit-AI`
   - `https://github.com/calumbruton/Vein`
   - `https://github.com/EfthimiosVlahos/SmartLift-Analysis-Project`
   - `https://github.com/teco-kit/whar-datasets`
   - `https://github.com/ayman23-ds/ML-Project-Fitness-Tracker`

**Stand der Recherche bei Abbruch:** Nur `TrackFit-AI`s README wurde
gefetcht (via `web_fetch`, funktionierte). Ersteindruck, noch nicht tief
verifiziert: Sieht nach einer Variante des bekannten "Full Stack ML
Tracker"-Kursprojekts (MetaMotion-Sensordaten, Barbell-Übungen: Squat, Bench,
Deadlift, Overhead Press, Row) aus — klassisches ML (Decision Trees, KNN, SVM,
Random Forest, kleine NN) mit sorgfältigem Feature Engineering
(Ausreißer-Entfernung via Chauvenet/LOF, Tiefpassfilter, PCA, Frequenz- und
Zeitbereichs-Features via Fourier-Transformation), **~97% Klassifikations-
genauigkeit ohne Deep Learning**. Datei `src/features/count_repetitions.py`
sollte als Nächstes angeschaut werden (Fetch-Versuch scheiterte, siehe
Abschnitt 5 zu web_fetch-Einschränkungen — erst per web_search finden).
Die anderen 4 Repos wurden noch **gar nicht** angeschaut. `whar-datasets` von
`teco-kit` ist vermutlich ein Datensatz-/Benchmark-Repo (TECO = bekannte
Ubicomp-Forschungsgruppe, Karlsruhe) — könnte für Trainings-/Vergleichsdaten
relevant sein, aber noch nicht geprüft.

**Für den Einstieg in diese Anfrage lohnt sich `docs/FRAGEN_FUER_SCHLAUE_KI.md`
als Struktur** — Frage 7 (Multi-Exercise-Erkennung) und Frage 10 (Rule-Based
vs. ML) decken sich fast wörtlich mit Adis heutiger Anfrage.

## 7. Empfohlene Priorisierung für die nächste Session

1. **Zuerst Abschnitt 1 dieses Dokuments klären** (funktioniert Rep-Zählung
   überhaupt, auch außerhalb der Kalibrierung?) — sonst ist jede
   Genauigkeits-Diskussion verfrüht
2. Danach `flutter test`/`flutter analyze`/`python3 tools/workout_engine_simulation.py`
   laufen lassen (siehe Abschnitt 4) und committen/pushen
3. Danach die neue Anfrage aus Abschnitt 6 fortsetzen: die 4 verbleibenden
   Repos analysieren, `count_repetitions.py` bei TrackFit-AI genauer ansehen,
   breitere Recherche zu 99%-Genauigkeit und Deep-Learning-Sinnhaftigkeit für
   Multi-Exercise-Erkennung, dabei `FRAGEN_FUER_SCHLAUE_KI.md` als Leitfaden
   nutzen

## 8. Andere relevante, heute entstandene Dokumente (Übersicht)

| Datei | Inhalt |
|-------|--------|
| `HANDOFF_AN_NAECHSTE_KI_2026-07-12.md` | Echte Serial-IMU-Rohdaten, 5 Hypothesen zum Kernproblem, Architektur-Übersicht |
| `STATUS_REPORT_2026-07-12.md` | Kompakte Zusammenfassung des Tagesstands |
| `IMU_HARDWARE_DEBUG_GUIDE.md` | Hardware-Debug-Anleitung falls IMU mal "FAIL" zeigt (I2C, WHO_AM_I etc.) — aktuell nicht akut, IMU liefert laut Serial-Daten echte Werte |
| `FRAGEN_FUER_SCHLAUE_KI.md` | 10 offene technische Fragen einer anderen KI-Session, teils deckungsgleich mit Adis neuer Anfrage |
| `ANALYSE_EXTERNE_KI_2026-07-12.md` | Diese Claude-Sitzung, Punkte A–G, laufend gepflegt |

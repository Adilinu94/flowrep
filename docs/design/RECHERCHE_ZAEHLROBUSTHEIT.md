
# RECHERCHE: Robustes Zählen — Doppel-Peaks, Zeitbasis, Winkel-Signal (2026-07-16)

**Auftrag von Adi:** Nach gründlichem Einarbeiten in das Projekt (Code + komplette Doku inkl. `master`-only-Dokumente via Git) eine gründliche Recherche, was an der Wiederholungserkennung/-zählung verbessert werden sollte. Der Prototyp hat weiterhin starke Probleme, Wiederholungen korrekt zu erkennen und zu zählen.

**Methodik:** (1) Verifikation der Ist-Implementierung Ende-zu-Ende im Code (Firmware `main.cpp`, `app/lib/domain/*`, `tools/*`, Tests) — alle Fundstellen mit Datei:Zeile. (2) Web-Recherche gezielt zu den verifizierten Schwachstellen: Peak-Detection-Algorithmik (Echtzeit + offline), winkelbasiertes Zählen per Gyro-Integration, ZUPT-Driftkontrolle, neuere Literatur 2024–2026. **Abgrenzung zu `RECHERCHE_99_PROZENT_GENAUIGKEIT_2026-07-14.md`:** Diese Recherche wiederholt die dortigen Empfehlungen (Autokorrelations-Filterebene, vorzeichenbehaftetes Gyro, `ExerciseProfile`, kein DL jetzt) nicht als "neue" Vorschläge, sondern setzt sie in konkrete, zitierte Algorithmus-Form um und ergänzt die bisher fehlende Ebene: die Datenpipeline (Zeitbasis, Skalierung, Datenverlust), ohne die jede Algorithmus-Verbesserung auf Sand gebaut ist.

> **UPDATE 2026-07-16 (Status-Check):** Alle Items wurden in dieser Session gegen die tatsächliche Codebase verifiziert. Status-Markierungen: ✅ = behoben, 🟡 = teilweise behoben, ❌ = offen. Begleitdokument: [`KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md`](KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md) — der detaillierte Plan für die Guided-Calibration-2.0-Überarbeitung, die mehrere der hier identifizierten Schwachstellen (insb. S1, S2, S7, K1–K7 im Konzeptdokument) adressiert.

---

## 1. Verifizierte Ist-Schwachstellen (Code-verifiziert, priorisiert)

| # | Schwachstelle | Beleg | Symptom | Status |
|---|---|---|---|---|
| S1 | **Kein Refractory/Lockout im Live-Pfad.** Rising Edge startet, Falling Edge zählt — beliebig oft pro Rep. Die einzige Mindestdistanz (`_minPeakDistanceSamples = 12`) existiert **nur** im Kalibrierungspfad | `workout_engine.dart:355-383` vs. `Z.198`; Simulation: **20 gezählt bei 10 erwartet** (`Umbauplan/STATUS_FORTSCHRITT.md` B, dreifach bestätigt) | Überzählen (Doppel-Peaks) | ❌ Offen |
| S2 | **Threshold ist gyro-dominiert:** kalibrierte Schwelle ~7,6 entspricht ≈ ≥114 °/s Gyro-Peak. Reps langsamer als das Kalibrierungstempo erreichen sie nie | `gyroWeight=0.05` (`workout_engine.dart:92`), Threshold 7,595 im Testlauf (`flutter_test_verify_claude.txt`) | Unterzählen (langsame Reps) | ❌ Offen |
| S3 | **Zeitbasis ist fiktiv:** Firmware-Pacing ist toter Code (`sampleIntervalMicros`/`lastSampleMicros`, `main.cpp:54-55`); 4 Samples pro Batch werden ohne Delay gelesen, dann `delay(20)` (`main.cpp:450`) → **Bursts**, keine 50 Hz. Der App-Parser **synthetisiert** trotzdem gleichmäßige 20-ms-Abstände (`ble_protocol_parser.dart:54`) | `main.cpp:23-24, 450`; ADR-011/017 (nur `master`): real ~18,4 Batches/s | EMA-α, Sample-Distanzen, alle Zeitkonstanten real um Faktor 4–8 daneben; Simulation nicht repräsentativ | ❌ Offen |
| S4 | **Gyro-Clipping im Wire-Format:** int16 ×0,01 °/s clippt bei ±327,67 °/s; echte Curls erreichen **344 °/s** (Messwert, `HANDOFF_AN_NAECHSTE_KI` 2.1) | `main.cpp:31, 432` | Peak-Kappung → Threshold-Kalibrierung auf gekappten Werten | ❌ Offen |
| S5 | **Stiller Datenverlust:** `read()`-Polling mit Timestamp-Dedup verwirft Batches (HyperOS-Workaround, `ble_sensor_provider.dart:222-302`) | ADR-011/017; `DEBUGDOSSIER_BLE_STREAMING_BUG.md` | Lücken im Signal, variable effektive Rate | ❌ Offen |
| S6 | **Baseline-Kontamination in Guided Calibration:** Baseline-EMA (α=0,01) lief während der Kalibrierung weiter, weil `_aboveThreshold` dort nie gesetzt wird → Baseline stieg Richtung ~4,0–5,7, Aktivierungsschwelle danach temporär zu hoch | `workout_engine.dart:233-238`; Test-Logs: baseline=3,98 | Erste Reps nach Kalibrierung werden verpasst | ✅ **Behoben** (Commit `3907706`, 2026-07-16): EMA-Bedingung erweitert auf `!_aboveThreshold && _state != WorkoutState.guidedCalibration` — Baseline während Kalibrierung eingefroren. Regressionstest verifiziert exakte Gleichheit. |
| S7 | Auto-Kalibrierung mit `calibrationReps=1`: ein untypischer erster Rep setzt den ganzen Threshold (nur geblockt, wenn bereits gültige Kalibrierung existiert — ADR-020-Fix) | `workout_engine.dart:87, 289-298` | Fragiler Threshold | 🟡 **Teilweise behoben**: `hasValidCalibration`-Flag (ADR-020, Commit `314302e`) blockiert 1-Rep-Auto-Kalibrierung wenn gültige Kalibrierung existiert. Für Erstnutzer ohne Kalibrierung greift sie noch. Vollständige Lösung via Guided-Calibration-2.0 (Known-Count). |
| S8 | Signal = Magnitude-only: `combined = \|accel\| + \|gyro\|×0,05` verwirft Richtung und Gravitationsreferenz; Gravitation (~1 g) bleibt als Offset im Signal | `signal_processor.dart:31-37` | Schwellen müssen Offset + Dynamik gleichzeitig abbilden | ❌ Offen |

**Kernaussage der Ist-Analyse:** S3–S5 sind keine Algorithmus-Probleme, sondern Datenpipeline-Probleme. Sie erklären auch, warum Simulation (gleichmäßige 50/15 Hz) und Hardware-Verhalten auseinanderlaufen und warum Parameter-Tuning bisher "Ratespiel" war (Zitat `HANDOFF_AN_NAECHSTE_KI`). **Reihenfolge ist entscheidend: erst Pipeline ehrlich machen (P0), dann Algorithmus (P1/P2).**

> **Status der Ist-Schwachstellen (Stand 2026-07-16):** Von 8 Schwachstellen (S1–S8) sind **1 behoben** (S6, Commit `3907706`), **1 teilweise behoben** (S7, ADR-020 `hasValidCalibration`), **6 offen** (S1, S2, S3, S4, S5, S8). Die offenen Items werden durch den [Guided-Calibration-2.0-Plan](KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md) (insb. S1/S2/S7 → Known-Count-Optimierung + Review; S8 → PCA/Winkel-Signal) und die P0-Pipeline-Maßnahmen adressiert.

---

## 2. Recherche-Ergebnisse (neu gegenüber RECHERCHE_99)

### 2.1 Warum Doppel-Peaks entstehen — und welches Signal sie per Konstruktion vermeidet

Ein Curl erzeugt in **Magnitude-Signalen** fast zwangsläufig zwei Buckel: einen beim konzentrischen Hochziehen, einen beim exzentrischen Abbremsen/Umkehren. Das ist der strukturelle Grund für S1 — kein Schwellenwert der Welt trennt zuverlässig "zweiter Buckel desselben Reps" von "erster Buckel des nächsten Reps", wenn das Kriterium nur Amplitude ist.

Der Ausweg liegt in der **Signaldimension, nicht im Schwellenwert**: Der **Ellenbogenwinkel** (bzw. die Bewegungsphase) hat pro Rep genau **ein** Maximum. Zwei etablierte, für **eine** einzelne IMU am Unterarm geeignete Ansätze:

1. **Vorzeichenbehaftete Winkelgeschwindigkeit** (projizierte Gyro-Achse statt `|gyro|`): ein vollständiger Curl = ein Nulldurchgangspaar (+ → − mit Mindest-Exkursion dazwischen). Wackeln ohne Richtungswechsel zählt nicht. Das ist die präzisierte Form der Empfehlung "Signal-Richtung statt Magnitude" aus RECHERCHE_99 (dort Punkt 2.3.2) und deckt sich mit der offenen Frage F3 (`FRAGEN_FUER_SCHLAUE_KI.md`).
2. **Integrierter Winkel mit Komplementärfilter** (Einzel-IMU, planare Bewegung — beim Curl weitgehend gegeben): Inklination aus Beschleunigung `φ_a = atan2(a_x, a_z)`; Fusion `φ(t) = (1−α)·(φ(t−Δt) + g·Δt) + α·φ_a(t)` mit α ≈ 0,02 — exakt so in der Bizeps-Curl-Literatur für die Hand-/Unterarm-Inklination eingesetzt (`angle = 0.98×(angle+gyro×dt) + 0.02×acc`, PMC8877759, dort mit 3750 gelabelten Curl-Reps gearbeitet; gleiche Filterstruktur für Ellbogen-Inklination in ideals.illinois.edu, `φ_f(t)=(1−α)(φ_{g}+φ_f(t−Δt))+α·φ_{a}(t)`).

   **Wichtig vs. Umbauplan Phase 2/3:** Der dort synthetisch getestete und verworfene Komplementärfilter diente der **Gravitationsentfernung aus dem Magnitude-Signal** (und verlor gegen die deployte Formel). Hier geht es um etwas anderes: ein **eigenes Zählsignal (Winkel/Phase)** statt eines "saubereren" Magnitude-Signals. Das verworfene Experiment sagt über diese Verwendung nichts aus.

3. **Driftkontrolle ohne zweiten Sensor — ZUPT-Analogie:** Gyro-Integration driftet; die Gegenmaßnahme ist die gleiche Idee wie Zero-Velocity-Update in der Fußgänger-Navigation (ZUPT; Übersicht: arXiv:2303.03757; adaptive Variante AZUPT, PMC7070454): In Ruhephasen (`|gyro|` < ε für ≥300 ms — zwischen Sätzen, zwischen Reps mit Pause) wird der Gyro-Bias neu geschätzt und der Winkel auf die Accel-Inklination zurückgezogen. Für repetitive Sportbewegungen wurde genau das validiert: ZUPT-Varianten, die "den erwarteten Endpunkt der repetitiven Bewegung" erkennen und dort den Zustand binden — Voraussetzung laut Studie wörtlich: Anfangs- und Endgeschwindigkeit der Wiederholung ≈ 0, und die Wiederholungen haben ähnliche Form (Coyte et al., Displacement-Schätzung für Sport-/Reha-Übungen). **Beim Curl ist beides erfüllt** (Arm startet und endet unten, fast still). Zusätzlich kann der Winkel am Rep-Ende auf den Satz-Startwert zurückgesetzt werden ("Zero-Angle-Update") — Drift kann sich dann pro Rep nicht akkumulieren.

### 2.2 Echtzeit-fähige Zählung: Der Pan-Tompkins-Transfer

Das Problem "ein Ereignis = ein ausgeprägter Peak + Nachschwingen, das nicht doppelt zählen darf" ist in der Biomedizin seit 40 Jahren gelöst (QRS-/R-Peak-Detektion im EKG, PPG-Pulsschläge). Der Pan-Tompkins-Baukasten ist kausal, echtzeitfähig, mikrocontroller-tauglich und 1:1 übertragbar:

| Baustein | EKG-Original | FlowRep-Übertrag |
|---|---|---|
| Duale adaptive Schwellen | `th1 = npk + 0,25·(spk − npk)`; laufende Schätzungen Signal- vs. Rausch-Peak: `spk = 0,125·peak + 0,875·spk`, `npk` analog (IEEE IWASI 2023, PPG-Variante, cris.unibo.it) | Ersetzt den starren `_peakThreshold`: Schwelle folgt automatisch Satz-zu-Satz-Varianz und Ermüdung (Peak-Höhen fallen im Satzverlauf — heutiger Fixwert kann das nicht) |
| **Refractory-Zeit** | 200 ms Sperrzeit nach jeder Detektion (Pan & Tompkins 1985, Validierung: dovepress PMC6263294) | `minRepInterval` nach jeder gezählten Rep — **direkter Fix für S1**. Aus der Kalibrierung ableitbar: ~0,5–0,6 × median(Repdauer der Kalibrierungsreps) statt globalem Konstantenwert |
| Searchback | Bei zu langem Intervall mit halber Schwelle erneut suchen (unibo-Fahrer-Monitoring-Variante, mit adaptivem `min_dist` aus Median der letzten Peak-Intervalle) | Fängt den Fehlmodus "Schwelle zu hoch → Rep verpasst" (S2) ab, ohne die Schwelle global zu senken |
| Prominenz statt Absoluthöhe | EasieRR: Peak-**Prominence** + Mindestabstand als robuste Kombination | Prominenz (Höhe über lokalem Tal) ist immun gegen den ~1-g-Gravitationsoffset (S8) und gegen Baseline-Drift — schwächt die Abhängigkeit von einer sauberen `_baselineLevel`-Schätzung (S6) |

### 2.3 Offline-/Kalibrierungs-Zählung: Das MM-Fit-Rezept (komplett zitierbar)

MM-Fit (UbiComp 2020, vradu.uk/publications/UbiComp2020.pdf) dokumentiert den derzeit am saubersten beschriebenen klassischen Zähl-Algorithmus für Wearable-IMU (dort für bereits segmentierte Sätze — exakt FlowReps Situation nach Satzende oder in der Kalibrierung):

1. Glättung: **Savitzky-Golay** (Grad 3) je Kanal — formtreuer als EMA, keine Phasenverschiebung wie bei gleitendem Mittelwert.
2. **PCA → 1D**: Projektion auf die erste Hauptkomponente statt handgestrickter `accel + 0,05·gyro`-Formel. Für die Guided Calibration aus den 10 Kalibrierungsreps lernbar — liefert automatisch die optimale Kanal-Gewichtung für *diese* Übung/Person/Sensorlage (ersetzt S8-Formelraten; verwandt mit MetaMotions "pro Übung eigener Kanal", RECHERCHE_99 Abschnitt 2.4).
3. Lokale Maxima, **amplitudenabsteigend sortiert**; ein Kandidat wird verworfen, wenn ein höherer Peak näher als `d_min` (pro Übung: minimal plausible Repdauer) liegt.
4. **Autokorrelations-Filter**: pro Kandidaten-Peak Periode `P` = Lag mit maximaler Autokorrelation im Fenster um den Peak (Lag-Suchbereich = [min, max] erwartete Repdauer); **kleinere Peaks im Abstand < 0,75·P werden entfernt**. — Das ist die präzisierte, publizierte Form der "zweiten Filterebene" aus RECHERCHE_99 (Punkt 2.3.1) und der direkte algorithmische Fix für das Doppel-Peak-Szenario 20/10.
5. Amplituden-Floor: Peaks < 0,5 × (40. Perzentil der verbleibenden Peak-Amplituden) entfernen.

Skawinski et al. (Aalto, 2019, ambientintelligence.aalto.fi — Einzel-3D-Beschleunigungssensor am Brustkorb) bestätigen dieselbe Familie mit **97,9 % Zählgenauigkeit** (10 Personen, 583 Reps): adaptive Schwelle `α = mean + (max − mean)·h_min` und **pro Übungstyp eigener `d_min`/`h_min`-Satz** — ein weiterer Beleg für das `ExerciseProfile` aus RECHERCHE_99.

**AMPD** (Scholkmann/Boss/Wolf, Algorithms 2012, doi:10.3390/a5040588): parameterfreie Multiskalen-Peakdetektion für quasi-periodische Signale, robust gegen hoch- und niederfrequentes Rauschen; Laufzeit-optimierte Variante T-AMPD (beei.org 3655, 2–25× schneller, gleiche Genauigkeit). Kandidat, die fragile Kombination aus Medianfilter + Plateau-Tie-Tolerance + 30.-Perzentil in der Guided Calibration (`workout_engine.dart:197-201, 480-560`) abzulösen bzw. als Cross-Check im Offline-Lab (`tools/dsp_lab_*`) — offline ist Laufzeit irrelevant.

### 2.4 Einordnung DL (Update 2024–2026, konsistent mit RECHERCHE_99)

- Few-Shot-/Siamese-Ansatz für universelles Zählen (arXiv:2410.00407, Okt 2024, 92-Hz-IMU, 28 Übungen, 19.777 Reps): **86,8 %** Wahrscheinlichkeit für ≥10 korrekt gezählte Reps — gut, aber **unter** der klassischen Per-Übung-Pipeline (Das et al.: 99,4 % valide Reps per übungsspezifischem Amplituden-Thresholding, smartwatch-accel; zitiert im Survey arXiv:2308.02420).
- Survey arXiv:2308.02420 (Püioio, S-Authority): klassische Peak-Detection + Per-Übung-Thresholding bleibt das genaueste IMU-Verfahren; HMM/Viterbi 90 %, DTW 61 %, rohe ANN 73,5 %.
- Czekaj 2024 (PMC11207732, Real-Time-HAR Übersichtstabelle): CNN-Ansätze liegen bei ±1 Rep in 90–91 % der Sätze (ETH/Reha-Studien) — d. h. das eigene Erfolgskriterium "≥8/10 Sätze innerhalb ±1" ist mit klassischer Pipeline erreichbar und liegt im publizierten Leistungsband.
- Fazit unverändert: **kein DL jetzt**; erst klassische Pipeline + `ExerciseProfile`, ML frühestens als Klassifikator (Übungserkennung), wenn mehrere Übungen anstehen (ADR-021 bleibt gültig).

---

## 3. Konkreter Verbesserungsplan (priorisiert)

**Erfolgskriterium (bestehend, unverändert):** ≥8 von 10 Testsätzen (10–15 Reps) innerhalb ±1 Rep; Korrekturrate < 15 %. Neu als Dauermetrik: **MAE pro Satz** (statt Pass/Fail, s. RECHERCHE_99 Abschnitt 3.2).

### P0 — Datenpipeline ehrlich machen (Voraussetzung für alles Weitere; kein Algorithmus-Wechsel)

| # | Maßnahme | Wo | Aufwand | Status |
|---|---|---|---|---|
| P0.1 | Echtes Sample-Pacing in der Firmware: Hardware-Timer (`esp_timer`/Ticker) mit 50 Hz, **pro Sample echter µs-Timestamp** (statt ein Batch-Timestamp + App-seitig erfundene 20-ms-Raster). `main.cpp:54-55` ist vorhandener, toter Ansatz — fertig machen | `firmware/src/main.cpp:400-450`, Wire-Format ggf. 4×uint32 | S | ❌ Offen — noch `delay(20)`, `sampleIntervalMicros` ist toter Code |
| P0.2 | Gyro-Skalierung fixen: ×0,01 °/s → **×0,1 °/s** (int16 → ±3276,7 °/s Vollausschlag, Auflösung 0,1 °/s ist mehr als ausreichend) — Clipping bei 344 °/s beseitigt | `main.cpp:31,432`; Parser-Skalierung `ble_protocol_parser.dart` spiegeln | S | ❌ Offen — noch `×0.01` in Firmware (`gx * 100.0f`, Z.432) und Parser (`gyroScale = 0.01`, Z.27) |
| P0.3 | App: aus echten Timestamps **gleichmäßiges 50-Hz-Raster resampeln** (linear reicht; Bursts → Lücken sichtbar statt versteckt), alle Zeitkonstanten (EMA-α, Fenster, Refractory) ab dann in **Sekunden** definieren, nie wieder in Samples | `ble_protocol_parser.dart`, `signal_processor.dart` | S–M | ❌ Offen — noch synthetisches `i * 20` Raster (Z.54), kein Resampling |
| P0.4 | Polling-Dedup darf nicht verwerfen: empfangene Batches in Queue, jedes Sample genau einmal verarbeiten; Lücken loggen (Diagnose `ENG:` erweitern um effektive Sample-Rate + dropped Batches) | `ble_sensor_provider.dart:222-302` | S | ❌ Offen — `continue` bei Duplicate-Timestamp (Z.253), keine Queue, keine Lücken-Logs |
| P0.5 | Baseline-Gate: Baseline-EMA nur aktualisieren in `idle`/`active` **und** wenn Signal nahe Ruhe (z. B. `|gyro| < 15 °/s`); **nie** während `guidedCalibration` | `workout_engine.dart:233-238` (Fix für S6) | S | 🟡 **Teilweise umgesetzt**: `guidedCalibration`-Freeze implementiert (Commit `3907706`, Z.235-236). **Noch offen:** „Signal nahe Ruhe"-Gate (`|gyro| < 15°/s`) und Beschränkung auf `idle`/`active` — Baseline aktualisiert sich derzeit auch in `calibrating`, `paused`, `connectionLost`. |
| P0.6 | Pflicht-Szenen A–G als echte CSVs aufnehmen (Funktion existiert: `csv_session_recorder.dart`), inkl. F (Kurzpausen) und G (Achsen-Verifikation). Damit wird `tools/dsp_lab_phase2_real_data.py` erstmals nützlich und jede P1/P2-Änderung ist gegen echte Daten prüfbar | Umbauplan/07 | Adi, ~1 h | ❌ Offen — `csv_session_recorder.dart` funktioniert (im E2E-Test bestätigt), aber keine echten Aufnahmen im Repo. Infrastruktur bereit, Aufnahmen fehlen. |

### P1 — Zähl-Quick-Wins im bestehenden Signalpfad (1–2 Tage, große Wirkung)

> **Status (Stand 2026-07-16):** Alle P1-Maßnahmen offen. Die Guided-Calibration-2.0-Konzept ([`KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md`](KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md)) schlägt vor, P1.1–P1.3 im Rahmen der Known-Count-Optimierung (Stufe B) zu integrieren — der Parameter-Sweep findet `minRepInterval`, `spk/npk`-Init und `minProminence` automatisch aus der bekannten Rep-Anzahl, statt sie manuell zu wählen.

1. **Refractory im Live-Pfad** (Fix S1): nach gezählter Rep Sperrzeit `minRepInterval = 0,55 × medianRepdauer` (Median aus Guided Calibration, Fallback 0,8 s). Simulation muss Doppel-Peak-Fall von 20/10 auf 10±1 bringen — bestehender Python-Simulationsfall existiert bereits und ist der Abnahmetest. ❌ Offen.
2. **Duale adaptive Schwellen** (Fix S2): `spk`/`npk`-Schätzer wie in 2.2; `_peakThreshold` wird zur Initialisierung, nicht zum Dauer-Fixwert. Searchback: kein Peak seit > 1,5 × etablierter Periode → mit `0,6 × th1` erneut suchen. ❌ Offen.
3. **Prominenz-Kriterium** zusätzlich/zu Absoluthöhe (Fix S8, mildert S6-Folgen): Peak zählt nur, wenn `peak − max(linkes Tal, rechtes Tal) ≥ minProminence` (aus Kalibrierung, z. B. 25 % der median-Exkursion). ❌ Offen.
4. Python-zuerst-Pflicht (ADR-022 bleibt): jede P1-Änderung zuerst in `tools/workout_engine_simulation.py` gegen **alle** Szenarien (sauber, Doppel-Peak, langsam, cheat, zittrig, Fehlstart, Kurzpausen), Metrik MAE. ❌ Offen.

### P2 — Struktureller Fix: Phasen-/Winkel-Signal als Zählbasis (der eigentliche Doppel-Peak-Killer)

> **Status (Stand 2026-07-16):** Alle P2-Maßnahmen offen. Der [Guided-Calibration-2.0-Plan](KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md) integriert P2.1 (PCA/Rotationsachse) als Stufe A des Kalibrierungs-Flows und P2.5 (ExerciseProfile) als Persistenz-Schritt (Stufe D). Die Implementierung erfolgt im Rahmen der 9 Arbeitspakete des Konzeptdokuments (Paket 2: CalibrationController, Paket 3: ExerciseProfile + Store).

1. **Zweites Zählsignal parallel aufbauen** (kein Big-Bang): projizierte, vorzeichenbehaftete Gyro-Komponente `g_p = g · a` (Rotationsachse `a` aus Guided Calibration per PCA auf die Gyro-Fenster der 10 Reps — gleiche Maschinerie wie P2 der Kalibrierung, doppelt genutzt). ❌ Offen.
2. **Rep = Nulldurchgangspaar**: `g_p` kreuzt nach oben über +ω_min → Rep beginnt; kreuzt nach unten unter −ω_min mit Zwischen-Exkursion ≥ θ_min (integriertes `g_p`) → Rep abgeschlossen, zählen. Wackeln ohne Vorzeichenwechsel + Exkursion zählt nie. ❌ Offen.
3. **Winkel-Integration mit ZUPT-Reset**: `θ(t)` aus `g_p` integriert; in Ruhefenstern (`|gyro| < ε`, ≥300 ms) Bias neu schätzen und `θ` auf Accel-Inklination `atan2`-Referenz ziehen (Komplementär α≈0,02, s. 2.1). Am Rep-Ende `θ`-Offset auf Satz-Start korrigieren → keine Drift-Akkumulation über den Satz. ❌ Offen.
4. **Autokorrelations-Kadenzfilter** (MM-Fit 0,75·P-Regel) als Validierungsebene über beiden Signalen; verwirft Kadenz-Brüche (Justierbewegungen, Frage F8). ❌ Offen.
5. Guided Calibration umstellt auf: PCA-Kanäle + Repdauer-Median + `d_min`/`minProminence`/`ω_min`/`θ_min` pro Übung ableiten (Grundlage des `ExerciseProfile` aus RECHERCHE_99 — jetzt, bei genau einer Übung, am günstigsten). ❌ Offen — siehe Guided-Calibration-2.0-Plan.
6. Offline-Verifikation in `tools/dsp_lab_phase2_real_data.py` gegen die P0.6-CSVs; AMPD als Referenz-Peakfinder für Ground-Truth-Abgleich. ❌ Offen.

### P3 — Später (bewusst zurückgestellt)

> **Status (Stand 2026-07-16):** Korrekt zurückgestellt. Das `ExerciseProfile`-Interface wird im Guided-Calibration-2.0-Plan (Paket 3) vorbereitet, aber nicht gehärtet.

- `ExerciseProfile` härten (pro Übung: Kanal/PCA-Basis, Schwellen, Repdauer-Korridor, Refractory-Faktor) — Interface schon bei P2.5 anlegen. ❌ Offen (Interface bei Calib-2.0 Paket 3 vorbereitet).
- Klassischer Übungs-**Klassifikator** (Random Forest auf Fenster-Features, ADR-021) erst ab Übung #2. ❌ Offen (bewusst zurückgestellt).
- Externe Validierung gegen öffentliche Datensätze (Microsoft `Exercise-Recognition-from-Wearable-Sensors`, RECHERCHE_99; **MM-Fit-Datensatz** — Smartwatch-IMU mit Rep-Labels, passt methodisch exakt). ❌ Offen (bewusst zurückgestellt).
- DL/Few-Shot (arXiv:2410.00407) beobachten, nicht bauen. ❌ Offen (bewusst zurückgestellt).

---

## 4. Anti-Liste (nicht tun / nicht erneut prüfen)

- **Kein Deep Learning jetzt** (RECHERCHE_99 Abschnitt 1, bestätigt durch 2024er-Literatur, s. 2.4).
- **Komplementärfilter zur Gravitationsentfernung im Magnitude-Pfad** nicht erneut synthetisch testen — durch Umbauplan Phase 2 erledigt und verworfen. (Der P2-Winkelpfad nutzt denselben Filtertyp für einen **anderen Zweck** und gehört an echte CSVs, nicht an synthetische Signale.)
- **Keine Zeitkonstanten mehr in Sample-Einheiten** definieren (S3) — jede neue Konstante in Sekunden/Hertz.
- **`filtfilt`/nicht-kausale Filter** nur im Offline-Lab, nie als Referenz für den Live-Pfad (Zero-Phase = nicht kausal implementierbar).
- Keine Parameter-Tuning-Runden ohne echte CSVs (P0.6 zuerst).

## 5. Offene Entscheidungen für Adi

1. **P0-Start bestätigen:** Firmware-Änderungen (Pacing, Timestamps, Skalierung) erfordern Reflash + Protokollversion-Bump (`01_protocol.yaml`) — OK?
2. **Zähl-Latenz:** Rep erst bei Abschluss (Rückkehr zur Startposition / zweitem Nulldurchgang) zählen = robustester Zeitpunkt, aber ~0,3–0,6 s nach dem sichtbaren Umkehrpunkt. Alternative: am Winkel-Maximum mit Refractory (schneller, minimal fehleranfälliger). Empfehlung: bei Abschluss zählen.
3. **Branch-Strategie** (aus `STATUS_FORTSCHRITT.md` übernommen, weiterhin offen): P0/P1 berühren Firmware **und** App — ohne kanonischen Branch entstehen sonst erneut divergierende Stände (aktuell: `master` bei Doku/Firmware vorn, `main` bei Engine vorn; `docs/Umbauplan Flowrep/` untracked).
4. **Guided-Calibration-2.0-MVP-Priorisierung** (neu, siehe [`KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md`](KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md)): Der Plan umfasst 9 Arbeitspakete — soll V1 nur Known-Count + Review umfassen (Pakete 1–4, ohne Tap/Metronom/Template), oder der volle Flow? Empfehlung: MVP ohne Tap/Metronom, dann erweitern.

---

## 5a. Querverweis: Guided-Calibration-2.0-Plan

Das Begleitdokument [`KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md`](KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md) konkretisiert die Kalibrierungs-Überarbeitung, die mehrere der hier identifizierten Schwachstellen adressiert:

| Hier identifiziert | Im Calib-2.0-Plan adressiert als |
|---|---|
| S1 (kein Refractory) | Known-Count-Optimierung Stufe B → `minRepInterval` aus Parameter-Sweep |
| S2 (threshold gyro-dominiert) | Stufe C (langsame Reps) + weiche Gyro-Bedingung (Vorzeichenwechsel statt ≥50°/s) |
| S7 (1-Rep-Auto-Kalibrierung fragil) | Komplett ersetzt durch Known-Count-Flow (Stufen 0/A/B/C/D) |
| S8 (Magnitude-only) | Stufe A: PCA → Rotationsachse → `g_p` (vorzeichenbehaftetes Signal) |
| P2.1–P2.5 (Winkel-Signal, ExerciseProfile) | Calib-2.0 Pakete 2–5 (CalibrationController, ExerciseProfile, Engine-Anbindung, UI) |
| P1.1–P1.3 (Refractory, duale Schwellen, Prominenz) | Calib-2.0 Stufe B: Parameter-Sweep findet alle drei automatisch aus bekannter Rep-Anzahl |

**Wichtig:** Der Calib-2.0-Plan ist so designed, dass er **auch vor P0** (ehrliche Zeitbasis) startbar ist — Known-Count und Review zählen Anzahl statt Absolut-Timing. Von P0 (insb. P0.3 Resampling) profitiert er aber. Die Empfehlung ist: P0.5 vervollständigen → Calib-2.0 Paket 1 (Simulation) → Pakete 2–4 (Kern) → P0.1–P0.4 (Pipeline) parallel → Calib-2.0 Pakete 5–9 (UI, Tap, Tests).

---

## 6. Quellen

| Quelle | Verwendet für | Authority |
|---|---|---|
| MM-Fit, UbiComp 2020 — vradu.uk/publications/UbiComp2020.pdf | Offline-Zählrezept (SavGol→PCA→d_min→Autokorrelation 0,75·P→Amplituden-Floor) | A (Paper-PDF) |
| Püioio-Survey — arxiv.org/pdf/2308.02420 | Lage der IMU-Zähl-Forschung; Das et al. 99,4 % Per-Übung-Thresholding; HMM 90 %; DTW 61 % | S |
| Few-Shot Rep Counting — arxiv.org/html/2410.00407v1 | DL-Stand 2024: 86,8 % P(≥10), 92 Hz IMU, 28 Übungen | S |
| Czekaj 2024 — pmc.ncbi.nlm.nih.gov/articles/PMC11207732 | Real-Time-HAR/Counting-Benchmarks (±1 Rep: 90–91 %) | S |
| Skawinski et al. 2019 — ambientintelligence.aalto.fi (…/Skawinski_19_WorkoutTypeRecognition.pdf) | Adaptive Schwelle `mean+(max−mean)·h_min`, Per-Übung-`d_min`, 97,9 % Zählgenauigkeit | A |
| Pan-Tompkins-Validierung — dovepress.com (PMC6263294) | Refractory 200 ms, duale Lern-Schwellen | A |
| PPG-PT-Variante — cris.unibo.it IEEE_IWASI_2023_postprint.pdf | `spk/npk`-Update-Formeln, adaptives Refractory | A |
| PPG-Searchback-Variante — cris.unibo.it Unobtrusive_Multimodal_Monitoring | Searchback + adaptiver `min_dist` aus Intervall-Median | A |
| EasieRR — besjournals.onlinelibrary.wiley.com (2041-210X.13393) | Prominenz + Refractory als robuste Kombination | S |
| Ellbogen-Inklination Einzel-/Zwei-IMU — ideals.illinois.edu (…/431257/data.pdf) | Komplementärfilter `φ=(1−α)(φ+g·dt)+α·atan2(...)` | S |
| Bizeps-Fatigue Crowd-Studie — ncbi.nlm.nih.gov/pmc/articles/PMC8877759 | 0,98/0,02-Komplementärfilter auf Curl-Daten; 3750 gelabelte Reps; Gyro-X als Label-Achse | S |
| Madgwick-Ellbogen (3 IMUs) — strokeconference.com.my/2023/docs/BPA03.pdf | Referenz für Mehr-IMU-Winkelschätzung (Eskalationspfad) | NA |
| ZUPT-Survey — arxiv.org/html/2303.03757v3 | ZUPT-Prinzip, Driftbindung in Ruhephasen | S |
| AZUPT — pmc.ncbi.nlm.nih.gov/articles/PMC7070454 | Adaptive Ruhe-Detektion (Schwellen aus Stillstands-Rauschen) | S |
| Coyte et al. — ro.uow.edu.au (…/50447022.pdf) | ZUPT für repetitive Sport-/Reha-Bewegungen (Endpunkt-Bindung, V=0-Anforderung) | NA |
| AMPD — doi.org/10.3390/a5040588 | Parameterfreie Multiskalen-Peakdetektion | S |
| T-AMPD — beei.org/index.php/EEI/article/view/3655 | Laufzeitoptimierung AMPD (2–25×) | NA |
| Simplexity/Bowflex ST560 — simplexitypd.com/blog/why-you-need-a-gyro-to-measure-position | Industrie-Beleg: Curl-Zählung produktreif nur mit Gyro (Winkel), nicht Accel allein | NA |

*Code-Fundstellen (S1–S8) wurden in dieser Sitzung direkt im Repo verifiziert; Simulationsergebnis 20/10 durch Ausführung von `tools/workout_engine_simulation.py` bestätigt.*

*Status-Update 2026-07-16: Alle Items wurden erneut gegen die Codebase verifiziert (Session Claude, Commits `3907706`, `3aecd27`, `314302e`). Siehe auch das Begleitdokument `KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md` für den detaillierten Kalibrierungs-Überarbeitungsplan.*

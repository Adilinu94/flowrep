# FlowRep 1.x/2.x — Verbesserungs-Leitfaden aus externer Recherche

> **Stand**: 22. Juli 2026
> **Basis**: Analyse von 8 GitHub-Repos, 1 Peer-Review-Studie (PMC), 1 Tech-Artikel (Edge Impulse)
> **Zweck**: Kuratierter, ticket-fähiger Backlog konkreter Verbesserungen für FlowRep über V1.0 hinaus
> **Verwandte Docs**: [00_UEBERSICHT](00_UEBERSICHT.md) · [13_OFFENE_PUNKTE](13_OFFENE_PUNKTE.md) · [07_CV_SENSOR_FUSION](07_CV_SENSOR_FUSION.md)

---

## 0. Wie dieses Dokument zu lesen ist

Jeder Verbesserungsvorschlag ist als **eigenständige Ticket-Karte** formuliert und
kann 1:1 in ein GitHub-Issue übernommen werden. Die Karten folgen einem festen Schema:

| Feld | Bedeutung |
|------|-----------|
| **Quelle** | Externes Repo/Studie, das die Idee liefert |
| **Priorität** | `V1.1` (Quick Win) · `V2.0` (Feature-Release) · `V3.0` (Vision/Langfrist) |
| **Kategorie** | `MUST` (Kern-Nutzen, klare Nachfrage) · `NICE` (Zusatz, differenzierend) |
| **Risiko** | `Niedrig` / `Mittel` / `Hoch` — technisches + Produktrisiko |
| **Machbarkeit** | Realistische Umsetzbarkeit mit dem aktuellen Stack |
| **Aufwand** | Grobschätzung in Personentagen (PT) |
| **Integration** | Betroffene bestehende Dateien + Einbaupunkt |
| **DoD** | Definition of Done — direkt als Akzeptanzkriterien nutzbar |

### Leitprinzipien (dürfen NIE verletzt werden)

Alle Vorschläge respektieren die harten FlowRep-Invarianten aus [00_UEBERSICHT](00_UEBERSICHT.md#verbotene-aktionen):

1. **IMU bleibt autoritativ.** Kamera/ML sind *Validatoren*, nie die Zählquelle für V1.x.
2. **`_useNewPipeline` bleibt `false`.** Neue Signalverarbeitung läuft zuerst im Shadow-Mode.
3. **`correctedReps` wird nie in `countedReps` zurückgeschrieben.** Der System-Count ist das ML-Trainingssignal.
4. **Keine „Die KI lernt dazu"-Kommunikation** in der UI.
5. **App funktioniert vollständig ohne Kamera und ohne Cloud.** Alle neuen Features sind additiv & degradierbar.

---

## 1. Analysierte Quellen & Relevanz

| # | Quelle | Kernthema | Relevanz | Wichtigste Erkenntnis |
|---|--------|-----------|----------|-----------------------|
| Q1 | [m351351/Velocity-Based-Training](https://github.com/m351351/Velocity-Based-Training) | ESP32 + BMI270 + BLE + Flutter | **Sehr hoch** | Hardware-Zwilling; VBT-Metriken, Battery, Deep Sleep |
| Q2 | [ayman23-ds/ML-Project-Fitness-Tracker](https://github.com/ayman23-ds/ML-Project-Fitness-Tracker) | IMU→Random Forest (99.4%) | **Sehr hoch** | Feature-Engineering + Exercise Recognition |
| Q3 | [Veto2922/Fitness-tracker-based-on-ML-2](https://github.com/Veto2922/Fitness-tracker-based-on-ML-2) | IMU→Exercise + Rep Counting | **Sehr hoch** | End-to-End ML-Pipeline-Referenz |
| Q4 | [PMC10857166](https://pmc.ncbi.nlm.nih.gov/articles/PMC10857166/) | CNN vs. klassisches ML (IMU) | **Hoch** | Wissenschaftliche Validierung, LOSO, 1-Sensor genügt |
| Q5 | [calumbruton/Vein](https://github.com/calumbruton/Vein) | Wearable IMU + Keras Rep-Count | **Hoch** | Sliding-Window + neuronales Netz |
| Q6 | [yoyuq/smart-fitness](https://github.com/yoyuq/smart-fitness) | ESP32-CAM + FastAPI + LLM-Coach | **Mittel** | 2-Stufen-Feedback (Engine → LLM) |
| Q7 | [LoboaTeresa/AI-Trainer](https://github.com/LoboaTeresa/AI-Trainer) | MediaPipe BlazePose + Form | **Mittel** | Winkel-basiertes Form-Feedback |
| Q8 | [GetFit / Edge Impulse (Medium)](https://coderscafetech.medium.com/getfit-build-your-own-teachable-fitness-tracker-for-your-workout-sessions-8bf4426f51fe) | TinyML „teachable" Tracker | **Mittel** | On-Device-Training / Personalisierung |
| Q9 | [Hrushi-d/Gym-Exercise-RepCounter](https://github.com/Hrushi-d/Gym-Exercise-RepCounter) | MediaPipe + OpenCV Winkel | **Niedrig** | Einfache State-Machine-Winkel-Logik |
| Q10 | [SravB/CV-Weightlifting-Coach](https://github.com/SravB/Computer-Vision-Weightlifting-Coach) | OpenPose + Ridge (Posture) | **Niedrig** | Posture-Regression (akademisch, veraltet) |

---

## Teil A — Verbesserungen aus externen Projekten

### A1 — Velocity-Based Training (VBT) Metriken

- **Quelle**: Q1 (VBT), Q5 (Vein)
- **Priorität**: `V1.1` · **Kategorie**: `MUST` · **Risiko**: Niedrig · **Machbarkeit**: Hoch · **Aufwand**: 2–3 PT

**Was**: Pro Rep zusätzlich zur Zählung eine **mittlere & Peak-Konzentrik-Geschwindigkeit**
(Mean/Peak Concentric Velocity), abgeleitete **geschätzte Explosivität** und **Velocity-Loss %**
über den Satz berechnen und anzeigen. VBT ist ein etablierter Trainingsansatz (Autoregulation):
Wenn die Geschwindigkeit um X % einbricht, ist der Satz „technisch" beendet.

**Algorithmus / Technische Details**:
- FlowRep hat bereits die geglättete Winkelgeschwindigkeit aus der Gyro-Pipeline
  (`GpProjection` → Butterworth → One-Euro → Envelope). Die **Envelope-Amplitude pro Peak**
  korreliert direkt mit der Bewegungsgeschwindigkeit.
- Pro erkanntem Rep (Peak im `PeakDetector`) das Zeitfenster der Konzentrik isolieren und
  berechnen:
  - `peakAngularVelocity = max(|envelope|)` im Rep-Fenster (bereits verfügbar als `peakMagnitude`).
  - `meanAngularVelocity = mean(|envelope|)` über die Konzentrik-Phase (`PhaseValidator` liefert Phasen).
  - `velocityLossPct = (peakVel[0] - peakVel[i]) / peakVel[0] * 100` — Referenz ist der erste (schnellste) Rep.
- **Keine neue Hardware nötig** — nur Aggregation vorhandener Signale.

**Integration / betroffene Dateien**:
- `Rep`-Modell in `lib/domain/models/workout_models.dart` um optionale Felder erweitern:
  `meanVelocity`, `peakVelocity` (bereits `peakMagnitude` vorhanden → wiederverwenden/umbenennen).
- `workout_engine.dart`: bei `_emitRep()` die Velocity-Werte anhängen.
- `drift_database.dart`: Spalten `mean_velocity`, `velocity_loss` (nullable, Migration additiv).
- UI: `home_screen.dart` / Session-Summary — kleine Velocity-Zeile pro Rep (opt-in via Settings).

**Vergleich mit bestehendem FlowRep**: FlowRep speichert heute nur `peakMagnitude` pro Rep.
VBT hebt genau diesen Wert vom „internen Debug-Wert" zum **sichtbaren Trainings-KPI**.

**Risiko**: Niedrig — keine Pipeline-Änderung, nur Ableitung. Kalibrierung „echte m/s" ist NICHT
möglich (Gyro misst Winkel, nicht linear) → wir zeigen **relative Velocity-Einheiten**, klar so beschriftet.

**DoD**:
- [ ] Pro Rep werden Mean/Peak-Velocity (relative Einheit) berechnet und persistiert.
- [ ] Velocity-Loss % pro Satz in der Session-Summary.
- [ ] Feature per Settings-Toggle abschaltbar (Default: an).
- [ ] Unit-Tests: Velocity-Aggregation, Velocity-Loss-Berechnung, DB-Migration.
- [ ] `_useNewPipeline` bleibt `false`.

---

### A2 — Akkustand-Anzeige des M5StickC (Battery Monitoring)

- **Quelle**: Q1 (VBT)
- **Priorität**: `V1.1` · **Kategorie**: `MUST` · **Risiko**: Niedrig · **Machbarkeit**: Hoch · **Aufwand**: 1–2 PT

**Was**: Batteriestand des M5StickC Plus2 in der App anzeigen (Prozent + Icon), Warnung bei <15 %.

**Algorithmus / Technische Details**:
- M5StickC Plus2 hat AXP192/PMIC → Firmware kann Akku-% als zusätzliches BLE-Feld senden.
- **Zwei Wege**:
  1. **BLE Battery Service (0x180F)** — Standard-GATT-Charakteristik `0x2A19`. Sauberste Lösung.
  2. Akku-Byte in bestehendes Notify-Paket packen (kompatibel, aber Protokoll ändern).
- Empfehlung: Standard-Battery-Service abonnieren, falls vorhanden; sonst graceful ausblenden.

**Integration / betroffene Dateien**:
- `lib/data/providers/ble_sensor_provider.dart`: zweite Charakteristik `0x2A19` abonnieren.
- `workout_ui_state.dart`: Feld `batteryLevel: int?`.
- `home_screen.dart`: Batterie-Icon in der Statuszeile (neben BLE-Status).
- **Firmware-Seite** (separates Repo): Battery-Service publizieren — als eigenes HW-Ticket.

**Vergleich**: FlowRep zeigt heute nur „Verbunden/Getrennt". Akkustand verhindert
Mid-Workout-Ausfälle → direkter QA-/Robustheitsgewinn (siehe [11_HARDWARE_QA](11_HARDWARE_QA_CHECKLISTE.md)).

**Risiko**: Niedrig auf App-Seite; Firmware-Änderung nötig → als Abhängigkeit markieren.

**DoD**:
- [ ] App liest Battery-Level (falls Charakteristik vorhanden), sonst UI degradiert sauber.
- [ ] Warn-Snackbar bei <15 %.
- [ ] Unit-Test für Parsing + Null-Fall.

---

### A3 — Stromspar-/Deep-Sleep-Strategie (BLE-seitig)

- **Quelle**: Q1 (VBT)
- **Priorität**: `V2.0` · **Kategorie**: `NICE` · **Risiko**: Mittel · **Machbarkeit**: Mittel · **Aufwand**: 2–3 PT (großteils Firmware)

**Was**: M5StickC in Deep Sleep, wenn keine Bewegung/keine App-Verbindung; Wake per Button/IMU-Interrupt.

**Technische Details**:
- App-Seite: sauberes „Idle → Disconnect" nach N Minuten ohne aktiven Satz signalisieren.
- Firmware: BMI270-Motion-Interrupt als Wake-Source; Deep Sleep spart ~10× Strom.
- FlowRep hat bereits **Reconnection mit Backoff (P0-4)** → Wiederaufwachen ist bereits abgedeckt.

**Integration**: `ble_sensor_provider.dart` (Idle-Timer + expliziter Disconnect), primär Firmware.

**Risiko**: Mittel — Wake-Latenz könnte UX stören; braucht HW-Tests.

**DoD**:
- [ ] App trennt nach konfigurierbarem Idle-Timeout aktiv.
- [ ] Reconnect nach Wake < 3 s (HW-Test dokumentiert in Doc 11).

---

### A4 — ML-basierte Exercise Recognition (automatische Übungserkennung)

- **Quelle**: Q2 (RF 99.4%), Q3 (End-to-End), Q4 (CNN/LOSO), Q5 (Vein)
- **Priorität**: `V2.0` · **Kategorie**: `MUST` · **Risiko**: Mittel · **Machbarkeit**: Mittel-Hoch · **Aufwand**: 8–12 PT

**Was**: Die Übung automatisch aus IMU-Daten erkennen, statt manueller Auswahl. Erste Stufe der Pipeline:
`IMU-Fenster → Klassifikator → {Bicep Curl, Squat, ...} + Confidence`.

**Algorithmus / Technische Details** (aus Q2/Q4 abgeleitet):
- **Input**: Sliding Window, 2 s @ ~52 Hz → ~104 Samples × Achsen. Q4 zeigt: **52 Hz reichen**,
  **1 Sensor am Handgelenk = 98.6 %** mit Scaling-FCN.
- **Feature-Engineering (klassischer Pfad, Q2)**: pro Fenster statistische Features
  (Mean, Std, Min, Max, MAD, Energie), spektrale Features (dominante Frequenz, spektrale Entropie),
  **Magnitude-Feature** `r = √(x²+y²+z²)` für **Orientierungs-Unabhängigkeit** (kritisch bei Wearables),
  optional PCA (3 Komponenten genügen). → Random Forest / SVM.
- **Deep-Learning-Pfad (Q4, empfohlen langfristig)**: 1D-CNN (FCN/ResNet-artig) direkt auf
  Roh-Zeitreihe; Prediction 1–2 ms vs. 93 ms klassisch, höhere Genauigkeit, kein Handcrafted-FE.
- **On-Device**: Export als **TFLite**, Inferenz via `tflite_flutter`. Fenster laufen im Shadow-Mode
  parallel zur IMU-Zählung, ohne die autoritative Zählung zu verändern.
- **Validierung (Pflicht, Q4)**: **Leave-One-Subject-Out (LOSO)** Cross-Validation. Ohne LOSO
  memoriert das Modell Nutzer-Biomechanik statt Übungsmuster → scheitert bei neuen Nutzern.

**Integration / betroffene Dateien**:
- Neues Modul `lib/domain/ml/exercise_classifier.dart` (Interface + TFLite-Impl).
- Datensammlung: bestehendes `landmark_session_recorder.dart`-Muster auf IMU übertragen
  → `imu_session_recorder.dart` (opt-in, lokal, für Trainingsdaten).
- Shadow-Anbindung in `engine_provider.dart`: Klassifikator-Output nur loggen/anzeigen, nicht zählen.
- Vorschlag-UI: „Erkannt: Bicep Curl (92 %) — übernehmen?" statt Auto-Switch.

**Vergleich**: Heute wählt der Nutzer die Übung manuell (`exercise_registry.dart`, 170 Zeilen).
ML-Recognition macht daraus einen **Vorschlag** — Nutzer behält Kontrolle (kein stiller Auto-Switch).

**Risiko**: Mittel — braucht Trainingsdaten (mehrere Personen!), sonst schlechte Generalisierung.
Datenschutz: Training lokal/anonymisiert. Mitigation: als Vorschlag, nie erzwungen.

**DoD**:
- [ ] IMU-Recorder (opt-in) sammelt gelabelte Fenster lokal.
- [ ] TFLite-Klassifikator läuft im Shadow-Mode, Ergebnis nur als UI-Vorschlag.
- [ ] LOSO-Report im Repo (Notebook/Doc), Accuracy pro Übung dokumentiert.
- [ ] `_useNewPipeline`/Zählquelle unverändert.

---

### A5 — Form-Quality-Score aus IMU (Range-of-Motion & Konsistenz)

- **Quelle**: Q3, Q7 (AI-Trainer), Q10
- **Priorität**: `V2.0` · **Kategorie**: `NICE` · **Risiko**: Niedrig-Mittel · **Machbarkeit**: Hoch · **Aufwand**: 3–4 PT

**Was**: Pro Rep einen **Qualitäts-Score (0–100)** aus IMU-Daten ableiten: Bewegungsumfang (ROM),
Tempo-Konsistenz, Symmetrie zwischen Reps. Feedback: „Rep 7 war 30 % flacher als dein Schnitt".

**Algorithmus / Technische Details**:
- **ROM-Proxy**: integrierte Winkelgeschwindigkeit über die Konzentrik = zurückgelegter Winkel.
  Kleinerer integrierter Winkel ⇒ flacherer Rep.
- **Tempo-Konsistenz**: Std der Rep-Dauer im Satz; hohe Streuung ⇒ Ermüdung/Formverlust.
- **Score-Aggregation**: gewichteter Mix `w1·ROM_norm + w2·Tempo_norm + w3·Peak_norm`,
  normiert gegen den Satz-Median (nicht gegen absolute Grenzen → nutzer-unabhängig).

**Integration**: `workout_engine.dart` (Aggregation pro Rep + pro Satz), Anzeige in Session-Summary.
Baut direkt auf A1 (Velocity) auf — gleiche Rep-Fenster.

**Risiko**: Niedrig-Mittel — „Qualität" ohne Referenz ist heikel; daher **relativ** zum eigenen Satz,
klar als Konsistenz-Indikator beschriftet (nicht als „richtige Form"-Urteil).

**DoD**:
- [ ] ROM-Proxy + Tempo-Konsistenz + Score pro Rep/Satz.
- [ ] Session-Summary hebt Ausreißer-Reps hervor.
- [ ] Unit-Tests für Score-Normalisierung.

---

### A6 — CV-Form-Feedback über Gelenkwinkel (Skelett-Overlay-Erweiterung)

- **Quelle**: Q7 (AI-Trainer BlazePose), Q9, Q10
- **Priorität**: `V2.0` · **Kategorie**: `NICE` · **Risiko**: Mittel · **Machbarkeit**: Mittel · **Aufwand**: 4–6 PT

**Was**: Die bestehende CV-Pipeline (MediaPipe/BlazePose, Doc 05–07, 14) nicht nur zum Zählen,
sondern für **Form-Hinweise** nutzen: Live-Gelenkwinkel, ROM-Marker, „Ellbogen driftet"-Warnung.

**Technische Details**:
- `AngleCalculator` + `PoseRepCounter` existieren bereits (CV-01/03).
- Erweiterung: pro Frame relevante Gelenkwinkel (z. B. Ellbogen, Knie) berechnen, Min/Max pro Rep
  tracken → **ROM-Score identisch zu A5, aber aus Kamera** → cross-check gegen IMU (Sensor-Fusion, Doc 07).
- Overlay: farbige Gelenke bei Grenzwert-Verletzung (`skeleton_painter.dart` erweitern).

**Integration**: `lib/domain/vision/*`, `skeleton_painter.dart`, `camera_session_screen.dart`.
Fusion-Hook in `fusion_pulse.dart` — Kamera bestätigt/relativiert IMU-ROM.

**Risiko**: Mittel — Kameraqualität/Beleuchtung; bleibt **optional** und degradiert (Leitprinzip 5).

**DoD**:
- [ ] Live-Gelenkwinkel + ROM pro Rep aus Kamera.
- [ ] Overlay-Warnfarbe bei Grenzverletzung.
- [ ] Cross-Check-Log gegen IMU-ROM (kein Zwang zur Übernahme).

---

### A7 — LLM-basiertes Coaching-Feedback (Post-Session)

- **Quelle**: Q6 (smart-fitness 2-Stufen-Architektur)
- **Priorität**: `V3.0` · **Kategorie**: `NICE` · **Risiko**: Hoch · **Machbarkeit**: Mittel · **Aufwand**: 6–10 PT

**Was**: Nach der Session strukturierte Daten (Reps, Velocity, ROM-Scores, Verlauf) an ein LLM geben,
das **personalisiertes Feedback in natürlicher Sprache** erzeugt: „Deine Squat-Tiefe fiel im 3. Satz ab."

**Architektur (aus Q6)**: Stufe 1 = deterministische Engine (Zahlen), Stufe 2 = LLM (Sprache).
LLM zählt NIE — es formuliert nur über bereits berechnete Metriken.

**Integration**: Neuer optionaler `coaching_service.dart`; Cloud-Call **nur mit explizitem Opt-in**.
Offline-Fallback: regelbasierte Textbausteine (kein Cloud-Zwang).

**Risiko**: Hoch — Datenschutz (Gesundheitsdaten!), Kosten, Konsistenz, Halluzination.
Mitigation: LLM bekommt nur aggregierte Zahlen, strikt via Template-Prompt, Opt-in, kein Rohdaten-Upload.

**DoD**:
- [ ] Opt-in-Flow mit klarer Datenschutz-Erklärung.
- [ ] Offline-Regel-Fallback funktioniert ohne Netz.
- [ ] LLM-Prompt getemplatet + Guardrails (nur gelieferte Zahlen verwenden).

---

### A8 — Robusteres Feature-Engineering für die IMU-Signalkette

- **Quelle**: Q2, Q4
- **Priorität**: `V2.0` · **Kategorie**: `NICE` · **Risiko**: Niedrig · **Machbarkeit**: Hoch · **Aufwand**: 2–3 PT

**Was**: Magnitude-Feature `r = √(x²+y²+z²)` und PCA-Vorverarbeitung als **Shadow-Signalquelle**
ergänzen, um Orientierungs-Unabhängigkeit zu erhöhen (Sensor-Rotation am Handgelenk).

**Technische Details**: FlowRep projiziert heute über `GpProjection` auf die Hauptachse.
Ergänzend Magnitude-Kanal berechnen → robuster gegen unterschiedliche Anlege-Orientierung.
Als Shadow-Signal parallel loggen und gegen die Live-Zählung vergleichen (kein Umschalten).

**Integration**: neue Stufe in der Shadow-Pipeline (nicht die autoritative), Logging via bestehendem Logger.

**Risiko**: Niedrig — reines Zusatzsignal, Shadow-only.

**DoD**:
- [ ] Magnitude-Kanal berechnet + geloggt.
- [ ] Vergleichs-Metrik (Zähl-Delta Magnitude vs. gP) dokumentiert.
- [ ] Live-Pfad unverändert.

---

### A9 — Leave-One-Subject-Out (LOSO) Evaluations-Harness

- **Quelle**: Q4 (PMC-Studie)
- **Priorität**: `V2.0` · **Kategorie**: `MUST` (für jedes ML-Feature) · **Risiko**: Niedrig · **Machbarkeit**: Hoch · **Aufwand**: 2 PT

**Was**: Reproduzierbares Offline-Evaluationsskript (Python), das Modelle mit LOSO validiert —
Voraussetzung für A4/A5. Verhindert die häufigste Falle: Modell memoriert Nutzer statt Übung.

**Integration**: `tools/ml/` (analog zum bestehenden Python-Webcam-Tool aus Doc 08).
Input: exportierte IMU-Sessions; Output: Accuracy/Confusion-Matrix pro Übung + pro Subjekt.

**Risiko**: Niedrig — reines Offline-Tooling, kein App-Impact.

**DoD**:
- [ ] `tools/ml/loso_eval.py` mit README.
- [ ] Confusion-Matrix + Per-Subject-Accuracy als Output.
- [ ] In CI optional als Report-Artefakt.

---

### A10 — On-Device „Teachable"-Personalisierung (Kalibrierungs-Presets)

- **Quelle**: Q8 (Edge Impulse GetFit), Q5 (Vein)
- **Priorität**: `V3.0` · **Kategorie**: `NICE` · **Risiko**: Mittel · **Machbarkeit**: Mittel · **Aufwand**: 4–6 PT

**Was**: Nutzer nimmt kurz Referenz-Reps auf → App speichert ein **persönliches Schwellen-Preset**
(Peak-Amplitude θ, Rep-Dauer-Bänder) pro Übung. Kein echtes On-Device-Training, sondern
**leichtgewichtige Kalibrierung** vorhandener Pipeline-Parameter.

**Technische Details**: Aus 3–5 Referenz-Reps Median-θ und Dauer-Bänder ableiten →
`gP`-Härtungs-Parameter (theta-floor, Excursion-Gate) nutzerspezifisch justieren.
Speichern als Preset in Drift-DB, pro Übung wählbar.

**Integration**: `exercise_registry.dart` (Preset-Referenz), Kalibrier-Flow im Onboarding,
`workout_engine.dart` liest Preset-θ statt globalem Default.

**Risiko**: Mittel — schlechte Referenzaufnahme verschlechtert Zählung; daher „Zurücksetzen auf Standard" immer möglich.

**DoD**:
- [ ] Kalibrier-Flow erzeugt Preset pro Übung.
- [ ] Preset persistiert + umschaltbar + rücksetzbar.
- [ ] A/B-Vergleich Preset vs. Default dokumentiert.

---

## Teil B — 10 eigene, zusätzliche Verbesserungsideen

> Nicht aus den Repos abgeleitet, sondern aus dem FlowRep-Kontext (BLE-Wearable, Single-Sensor,
> lokale-first, Trainings-Tracking) heraus entworfen. Jede respektiert die Leitprinzipien.

### B1 — „Set-Autopilot": intelligente Ruhepausen-Vorschläge
- **Priorität**: `V1.1` · **Kategorie**: `NICE` · **Risiko**: Niedrig · **Aufwand**: 1–2 PT
- **Was**: Der bestehende Pausen-Timer (P0-2, 90 s) wird adaptiv: bei hohem Velocity-Loss (A1)
  längere Pause vorschlagen, bei geringem eine kürzere. Kombiniert VBT-Autoregulation mit dem Timer.
- **Integration**: `RestTimer`-Widget + `workout_engine.dart` (Velocity-Loss-Input).
- **DoD**: Timer-Default passt sich an Velocity-Loss an; manuell überschreibbar.

### B2 — Session-Export als CSV/JSON (Datenhoheit)
- **Priorität**: `V1.1` · **Kategorie**: `MUST` · **Risiko**: Niedrig · **Aufwand**: 1 PT
- **Was**: Kompletten Trainingsverlauf lokal als CSV/JSON exportieren (Share-Sheet). Fördert
  Vertrauen (lokale-first) und liefert nebenbei Trainingsdaten für A4/A9.
- **Integration**: neuer `export_service.dart`, nutzt Drift-Queries; Settings-Eintrag „Daten exportieren".
- **DoD**: Export enthält Sätze, Reps, Korrekturen, Velocity; teilbar via OS-Share.

### B3 — Rep-Timeline-Visualisierung pro Satz
- **Priorität**: `V1.1` · **Kategorie**: `NICE` · **Risiko**: Niedrig · **Aufwand**: 2 PT
- **Was**: Nach dem Satz ein kleines Sparkline-Diagramm der Envelope/Peaks — visuelles Feedback,
  wo Reps erkannt wurden (auch didaktisch bei Fehlzählungen).
- **Integration**: neues `rep_timeline.dart`-Widget in der Session-Summary; Daten aus `reps`-Liste.
- **DoD**: Sparkline zeigt Peaks + Rep-Marker; rein lesend.

### B4 — Persönliche Rekorde & Fortschritts-Badges
- **Priorität**: `V2.0` · **Kategorie**: `NICE` · **Risiko**: Niedrig · **Aufwand**: 2–3 PT
- **Was**: PRs erkennen (meiste Reps, höchste Velocity, längste Serie) und dezent feiern.
  Retention-Feature ohne Gamification-Overkill.
- **Integration**: `records_service.dart` + Drift-Aggregate; Anzeige in History-Screen.
- **DoD**: PR-Erkennung pro Übung; Badge in der Session-Summary bei neuem PR.

### B5 — Trainingsverlauf / History-Screen mit Trends
- **Priorität**: `V2.0` · **Kategorie**: `MUST` · **Risiko**: Niedrig · **Aufwand**: 3 PT
- **Was**: Volumen (Sätze×Reps) und Velocity-Trend pro Übung über Zeit (Wochen/Monate).
  Macht FlowRep vom Einzel-Session-Tool zum Tracker.
- **Integration**: neuer `history_screen.dart`, Drift-Zeitreihen-Queries, `fl_chart` o. Ä.
- **DoD**: Trend-Charts pro Übung; Zeitraum-Filter; rein lesend.

### B6 — Watchdog gegen „Ghost-Reps" bei Ablegen/Wackeln
- **Priorität**: `V1.1` · **Kategorie**: `MUST` · **Risiko**: Niedrig · **Aufwand**: 1–2 PT
- **Was**: Erkennen, wenn das Gerät abgelegt/nicht getragen wird (niedrige, nicht-periodische
  Aktivität) und Zählung pausieren. Adressiert direkt HW-Beobachtung A3/B3 aus Doc 13 (Wackeln → Fehlzählung).
- **Technik**: Aktivitäts-Gate über Envelope-Varianz + fehlende Periodizität (Autokorrelation).
- **Integration**: zusätzliches Gate in `workout_engine.dart` (Shadow-verträglich, konservativ).
- **DoD**: Bei Ablegen keine neuen Reps; Unit-Test mit synthetischem Rausch-Signal.

### B7 — Onboarding-Tutorial für Sensor-Platzierung
- **Priorität**: `V1.1` · **Kategorie**: `NICE` · **Risiko**: Niedrig · **Aufwand**: 1–2 PT
- **Was**: Kurzer bebilderter Flow: Wo/wie sitzt der M5StickC, warum Kalibrierung. Reduziert
  die #1-Fehlerquelle bei Wearables (falsche Orientierung → schlechte Zählung, siehe A8).
- **Integration**: erweitert bestehendes Onboarding; einmalig, überspringbar.
- **DoD**: Tutorial beim Erststart; jederzeit in Settings erneut aufrufbar.

### B8 — „Blind-Mode" / Audio-First-Training
- **Priorität**: `V2.0` · **Kategorie**: `NICE` · **Risiko**: Niedrig · **Aufwand**: 2 PT
- **Was**: Reine Audio-Führung (Rep-Klick, Ansage bei Satzende, Pausen-Ende) für Training
  ohne Blick aufs Handy. Baut auf Sound-Asset (P1-5) + Glanceability (P2-3) auf.
- **Integration**: `feedback_service.dart` erweitern (TTS-Ansagen), Settings-Toggle.
- **DoD**: Vollständiger Satz ohne Bildschirmkontakt führbar; respektiert Stumm-Schalter.

### B9 — Konfigurierbare Übungs-Profile (Ziel-Reps/Sätze)
- **Priorität**: `V2.0` · **Kategorie**: `NICE` · **Risiko**: Niedrig · **Aufwand**: 2 PT
- **Was**: Pro Übung Zielwerte (z. B. 4×12) definieren; Fortschrittsanzeige „Satz 2/4".
  Strukturiert das Training, ohne Zwang.
- **Integration**: `exercise_registry.dart` + Drift-Preset; Anzeige in `home_screen.dart`.
- **DoD**: Ziele setzbar/persistent; Fortschritt sichtbar; optional.

### B10 — Diagnose-/Debug-Overlay für Feldtests (Developer-Mode)
- **Priorität**: `V1.1` · **Kategorie**: `MUST` (für HW-QA) · **Risiko**: Niedrig · **Aufwand**: 1–2 PT
- **Was**: Versteckter Entwickler-Modus, der Live-Signal (Envelope, θ-Schwelle, Peaks, Paketrate,
  Shadow-Pipeline-Delta) einblendet. Beschleunigt die offene HW-Validierung (A1–A5 in Doc 13) massiv.
- **Integration**: Overlay über `home_screen.dart`, Aktivierung via versteckter Geste in Settings.
- **DoD**: Overlay zeigt Live-Signale + Shadow-Delta; standardmäßig aus; kein Release-UI-Impact.

---

## Teil C — Konsolidierte Roadmap

### V1.1 — Quick Wins (datenschutzfreundlich, geringes Risiko, hoher Nutzen)

| ID | Feature | Kat. | Aufwand | Risiko |
|----|---------|------|---------|--------|
| A1 | VBT-Velocity-Metriken | MUST | 2–3 PT | Niedrig |
| A2 | Akkustand-Anzeige | MUST | 1–2 PT | Niedrig |
| B2 | Session-Export CSV/JSON | MUST | 1 PT | Niedrig |
| B6 | Ghost-Rep-Watchdog | MUST | 1–2 PT | Niedrig |
| B10 | Diagnose-Overlay (Dev) | MUST | 1–2 PT | Niedrig |
| B1 | Adaptive Ruhepausen | NICE | 1–2 PT | Niedrig |
| B3 | Rep-Timeline-Sparkline | NICE | 2 PT | Niedrig |
| B7 | Sensor-Platzierungs-Tutorial | NICE | 1–2 PT | Niedrig |

### V2.0 — Feature-Release (ML & Tiefe)

| ID | Feature | Kat. | Aufwand | Risiko |
|----|---------|------|---------|--------|
| A4 | ML Exercise Recognition | MUST | 8–12 PT | Mittel |
| A9 | LOSO-Eval-Harness | MUST | 2 PT | Niedrig |
| B5 | History/Trends-Screen | MUST | 3 PT | Niedrig |
| A5 | IMU Form-Quality-Score | NICE | 3–4 PT | Niedrig-Mittel |
| A6 | CV-Form-Feedback (Winkel) | NICE | 4–6 PT | Mittel |
| A8 | Magnitude/PCA Shadow-Signal | NICE | 2–3 PT | Niedrig |
| A3 | Deep-Sleep-Strategie | NICE | 2–3 PT | Mittel |
| B4 | PRs & Badges | NICE | 2–3 PT | Niedrig |
| B8 | Audio-First-Mode | NICE | 2 PT | Niedrig |
| B9 | Übungs-Profile (Ziele) | NICE | 2 PT | Niedrig |

### V3.0 — Vision (Cloud/Personalisierung, höheres Risiko)

| ID | Feature | Kat. | Aufwand | Risiko |
|----|---------|------|---------|--------|
| A7 | LLM Post-Session-Coaching | NICE | 6–10 PT | Hoch |
| A10 | Teachable-Personalisierung | NICE | 4–6 PT | Mittel |

---

## Teil D — Ticket-Backlog (Copy-Paste-fähig)

> Format pro Zeile: `[ID] Titel — Priorität/Kategorie — Aufwand`. Details in der jeweiligen Karte oben.

```
[FR-A1]  VBT-Velocity-Metriken pro Rep + Velocity-Loss %   — V1.1/MUST — 2-3 PT
[FR-A2]  M5StickC Akkustand via BLE 0x180F                 — V1.1/MUST — 1-2 PT
[FR-A3]  Deep-Sleep + Motion-Wake (Firmware+App)           — V2.0/NICE — 2-3 PT
[FR-A4]  ML Exercise Recognition (TFLite, Shadow)          — V2.0/MUST — 8-12 PT
[FR-A5]  IMU Form-Quality-Score (ROM/Tempo)                — V2.0/NICE — 3-4 PT
[FR-A6]  CV Form-Feedback über Gelenkwinkel                — V2.0/NICE — 4-6 PT
[FR-A7]  LLM Post-Session-Coaching (Opt-in)                — V3.0/NICE — 6-10 PT
[FR-A8]  Magnitude/PCA Shadow-Signal                       — V2.0/NICE — 2-3 PT
[FR-A9]  LOSO Evaluations-Harness (tools/ml)               — V2.0/MUST — 2 PT
[FR-A10] Teachable-Kalibrierungs-Presets                   — V3.0/NICE — 4-6 PT
[FR-B1]  Adaptive Ruhepausen (VBT-gesteuert)               — V1.1/NICE — 1-2 PT
[FR-B2]  Session-Export CSV/JSON                           — V1.1/MUST — 1 PT
[FR-B3]  Rep-Timeline-Sparkline                            — V1.1/NICE — 2 PT
[FR-B4]  Persönliche Rekorde & Badges                      — V2.0/NICE — 2-3 PT
[FR-B5]  History-Screen mit Trends                         — V2.0/MUST — 3 PT
[FR-B6]  Ghost-Rep-Watchdog (Ablegen/Wackeln)              — V1.1/MUST — 1-2 PT
[FR-B7]  Sensor-Platzierungs-Tutorial                      — V1.1/NICE — 1-2 PT
[FR-B8]  Audio-First / Blind-Mode                          — V2.0/NICE — 2 PT
[FR-B9]  Übungs-Profile (Ziel-Reps/Sätze)                  — V2.0/NICE — 2 PT
[FR-B10] Diagnose-/Debug-Overlay (Developer-Mode)          — V1.1/MUST — 1-2 PT
```

**Empfohlene Reihenfolge V1.1**: B10 (Diagnose zuerst → beschleunigt alles) → A2 → A1 → B6 → B2 → B1/B3/B7.

---

## Teil E — Bewusst NICHT übernommen

| Abgelehnt | Quelle | Begründung |
|-----------|--------|------------|
| Edge Impulse / proprietäre TinyML-Plattform | Q8 | Kein Flutter, Vendor-Lock-in; wir nutzen TFLite offen (A4) |
| Multi-Sensor-Setup (4 IMUs) | Q4 | FlowRep bleibt Single-Sensor; Q4 zeigt selbst: 1 Sensor genügt |
| OpenPose-basierte CV | Q10 | Veraltet/schwer für Mobile; MediaPipe/BlazePose ist überlegen |
| Flask/Web-Backend als Kern | Q3 | FlowRep ist native Flutter-App, lokale-first; kein Web-Wrapper |
| LLM als Zählquelle | Q6 | Verletzt Leitprinzip 1 (IMU autoritativ); LLM nur für Sprache |

---

## Teil F — Querverweise & nächste Schritte

- **Sensor-Fusion-Basis** für A6: [07_CV_SENSOR_FUSION](07_CV_SENSOR_FUSION.md)
- **Skelett-Overlay** für A6: [14_CV_SKELETT_OVERLAY_PLAN](14_CV_SKELETT_OVERLAY_PLAN.md)
- **Offene HW-Punkte**, die B10/B6 direkt adressieren: [13_OFFENE_PUNKTE](13_OFFENE_PUNKTE.md)
- **Release-Invarianten**: [00_UEBERSICHT](00_UEBERSICHT.md#verbotene-aktionen)

**Vorschlag als unmittelbar nächster Schritt**: Mit **FR-B10 (Diagnose-Overlay)** starten — es ist
gering-riskant, additiv und liefert das Werkzeug, um die noch offene physische HW-Validierung
(A1–A5 in Doc 13) sowie alle folgenden Signal-Features (A1, A5, A8, B6) sauber zu verifizieren.

# FlowRep 1.x/2.x — Verbesserungs-Leitfaden aus externer Recherche

> **Stand**: 24. Juli 2026 (Implementierungs-Welle)  
> **Basis**: Analyse von 8 GitHub-Repos, 1 Peer-Review-Studie (PMC), 1 Tech-Artikel (Edge Impulse)  
> **Gegen Code verifiziert**: 2026-07-24 (`main` / Product-Pfad gP, `_useNewPipeline = false`)  
> **Zweck**: Kuratierter, ticket-fähiger Backlog konkreter Verbesserungen für FlowRep **nach** 1.0  
> **Code-Status**: V1.1 + große Teile V1.2/V2/V3 **im Code** (siehe Changelog unten); physische HW-QA (Doc 13 A1–A5) weiter offen  
> **Verwandte Docs**: [00_UEBERSICHT](00_UEBERSICHT.md) · [13_OFFENE_PUNKTE](13_OFFENE_PUNKTE.md) · [12_IMPLEMENTIERUNGS_STATUS](12_IMPLEMENTIERUNGS_STATUS.md) · [07_CV_SENSOR_FUSION](07_CV_SENSOR_FUSION.md) · [14_CV_SKELETT_OVERLAY_PLAN](14_CV_SKELETT_OVERLAY_PLAN.md)

---

## 0. Wie dieses Dokument zu lesen ist

### Reihenfolge relativ zu 1.0

**Vor jedem V1.1-Feature** gilt die physische Release-QA aus [13_OFFENE_PUNKTE](13_OFFENE_PUNKTE.md) Priorität A:

> A1–A5 am Gerät (Kalibrieren → echte Curls → Satz beenden → Korrektur → Session-Ende)  
> **B10 (Diagnose-Overlay)** unterstützt diese QA — es **ersetzt** sie nicht.

Dieses Doc ist **Post-1.0-Backlog**, kein Ersatz für Doc 11/13.

### Ticket-Schema

Jeder Vorschlag ist eine **Ticket-Karte** (1:1 als GitHub-Issue nutzbar):

| Feld | Bedeutung |
|------|-----------|
| **ID** | Kanonisch `FR-A*` / `FR-B*` (siehe Teil D) |
| **Quelle** | Externes Repo/Studie *oder* `FlowRep-Kontext` |
| **Priorität** | `V1.1` · `V1.2` · `V2.0` · `V3.0` |
| **Kategorie** | `MUST` · `NICE` · `DONE` (Code da, nur Polish/QA) |
| **Code-Stand** | `Already` / `Delta` / `Greenfield` — was schon im Repo steckt |
| **Risiko** | `Niedrig` / `Mittel` / `Hoch` |
| **Machbarkeit** | Realistisch mit aktuellem Stack |
| **Aufwand** | Grobschätzung Personentage (PT) |
| **Integration** | Dateien + Einbaupunkt am **Product-Pfad** |
| **DoD** | Akzeptanzkriterien |

### Leitprinzipien (dürfen NIE verletzt werden)

Aus [00_UEBERSICHT](00_UEBERSICHT.md#verbotene-aktionen):

1. **IMU bleibt autoritativ.** Kamera/ML sind *Validatoren*, nie die Zählquelle für V1.x.
2. **`_useNewPipeline` bleibt `false`.** Neue Signalverarbeitung zuerst im Shadow-Mode.
3. **`correctedReps` wird nie in `countedReps` zurückgeschrieben.**
4. **Keine „Die KI lernt dazu“-Kommunikation** in der UI.
5. **App funktioniert ohne Kamera und ohne Cloud.** Features additiv & degradierbar.

### Quellen-Nutzung

Externe Repos liefern **Ideen und Algorithmen**, keinen Copy-Paste-Code. Lizenzen (MIT/GPL/…) und Urheberrecht prüfen, bevor Code übernommen wird. Peer-Review (Q4) und eigene Messungen schlagen anekdotische Accuracy-Claims.

### Product-Pfad (wichtig für Integration)

| Pfad | Status | Relevanz |
|------|--------|----------|
| **gP-Excursion** (`workout_engine._commitRep`, Envelope, θ-Gates) | **Product live** | Primärer Einbau für A1, A5, B6, B10 |
| New Pipeline (`PeakDetector` / `PhaseValidator` / `_emitRep`) | hinter `_useNewPipeline = false` | Nur Shadow / später; **nicht** als V1.1-Hauptintegration annehmen |

---

## 0b. Already im Code (Stand 2026-07-23)

Nicht erneut als Greenfield planen:

| Bereich | Evidence | Ticket-Implikation |
|---------|----------|--------------------|
| **Akkustand BLE + UI** | Firmware `batteryChar` (`0000fee3-…`), `readBatteryPercent()`, `connection_status_card` + Icon &lt;20 % | **FR-A2 = DONE / Polish** |
| **gP-Härtung** | θ-Floor 50, 0.70×θ, minSamples 15, Peak≥1.2×θ | **FR-B6** = zusätzliches Ablegen/Periodizitäts-Gate, nicht dieselben Gates nochmal |
| **Guided Calib + θ-Nudge** | Calib-Wizard, `nudgeDirectionAwareThreshold` nach Korrektur | **FR-A10** = Multi-Preset-UX, kein Calib von Null |
| **History-Liste** | `history_screen.dart` (Sessions) | **FR-B5** = Trends/Charts **erweitern** |
| **peakMagnitude pro Rep** | `Rep.peakMagnitude` + Drift-Spalte | **FR-A1** startet hier (Aggregation/UI, nicht „Signal erfinden“) |
| **Skelett-Overlay** | Doc 14 A–F Code | **FR-A6** baut auf Doc 14 auf |
| **protocol.yaml Battery / ControlPoint** | `BatteryLevel`, `REQUEST_BATTERY 0x03`, Low-Power-Ideen | **FR-A2/A3** an Protokoll koppeln |

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

### A1 — Velocity-Based Training (VBT) Metriken · `FR-A1`

- **Quelle**: Q1 (VBT), Q5 (Vein)
- **Priorität**: `V1.1` (light) / `V1.2` (Autoregulation) · **Kategorie**: `MUST` · **Risiko**: **Mittel** (Anzeigen = niedrig; „Satz endet bei Loss“ = mittel) · **Machbarkeit**: Hoch · **Aufwand**: 2–3 PT (light) / +1–2 PT Autoreg
- **Code-Stand**: **Delta** — `peakMagnitude` pro Rep vorhanden; Mean/Loss/UI/Persist fehlen

**Was**: Pro Rep **Peak- (und optional Mean-) Konzentrik-Velocity** aus dem **gP-Envelope-Fenster** sowie **Velocity-Loss %** über den Satz. Klar als **relative Einheit (°/s-Proxy)**, nie als lineare m/s.

**V1.1 light (empfohlen zuerst)**:
- Peak pro Rep (bestehendes `peakMagnitude` oder Fenster-Max) + Loss % in Summary anzeigen
- Optional Settings-Toggle; Persist kann V1.2 sein

**V1.2+**: Mean über Konzentrik-Phase; optionale Autoregulation „bei Loss X % Satz-Hinweis“ — **kein stilles Auto-Enden** ohne User-Consent (Product hat `autoEndSetEnabled: false`).

**Algorithmus (Product-Pfad)**:
- Bei `_commitRep` / gP-Excursion-Ende: Peak = max(|envelope|) im Fenster (heute oft schon `peakMagnitude`).
- `velocityLossPct = (peak[0] - peak[i]) / peak[0] * 100` (Referenz: erster Rep des Satzes, oder Satz-Max — im DoD festlegen).
- Mean nur wenn Phasengrenzen robust verfügbar; **nicht** an New-Pipeline `PhaseValidator` koppeln, solange `_useNewPipeline = false`.

**Integration**:
- `workout_engine.dart` — gP-Pfad `_commitRep`
- `workout_models.dart` / Drift: optionale Felder `meanVelocity`, `velocityLoss` (additiv)
- UI: Session-Summary / kleine Zeile pro Rep; Settings-Toggle

**Risiko**: Anzeige/Persist = beherrschbar. **Autoregulation und „technisches Satzende“** greifen in UX ein → separat freigeben, nicht mit light-V1.1 mischen.

**DoD (V1.1 light)**:
- [ ] Peak-Velocity (relativ) pro Rep berechnet und in Summary sichtbar.
- [ ] Velocity-Loss % pro Satz sichtbar.
- [ ] Einheit/Label klar („relativ / °/s-Proxy“, nicht m/s).
- [ ] Unit-Tests: Aggregation + Loss; Product-Pfad unverändert bzgl. Zähllogik.
- [ ] `_useNewPipeline` bleibt `false`.

**DoD (V1.2 optional)**: Mean; Settings; DB-Migration; kein Auto-End ohne Opt-in.

---

### A2 — Akkustand-Anzeige des M5StickC · `FR-A2`

- **Quelle**: Q1 (VBT)
- **Priorität**: `V1.1` · **Kategorie**: **`DONE` / Polish** · **Risiko**: Niedrig · **Machbarkeit**: Hoch · **Aufwand**: 0–0.5 PT (QA/Polish)
- **Code-Stand**: **Already** (Firmware + App)

**Was (ursprünglich)**: Batteriestand in der App — **bereits implementiert**.

**Ist-Stand (Code 2026-07-23)**:
- Firmware: `AXP2101` (nicht AXP192); spannungsbasiertes `getBatteryPercent()`; Char **`0000fee3-…`** im Gym-Tracker-Service (nicht Standard-GATT `0x180F`/`0x2A19`).
- App: `BleSensorProvider.batteryLevelCharUuid` / `readBatteryPercent()` (Control `0x03` REQUEST_BATTERY), `WorkoutUiState.batteryPercent`, `ConnectionStatusCard` mit Icon und Warnfarbe **&lt;20 %**.
- Protokoll: [protocol.yaml](../reference/protocol.yaml) `BatteryLevel`.

**Delta (optional Polish)**:
- [ ] HW-QA: Anzeige während Session plausibel (Doc 11).
- [ ] Optional: Snackbar bei &lt;15 % (zusätzlich zu Icon).
- [ ] Optional: periodisches Refresh während langer Session (heute on-demand/read).
- [ ] Docs/Tickets: **kein** separates Firmware-Greenfield mehr.

**DoD (Polish)**:
- [ ] Manueller HW-Check dokumentiert in Doc 11.
- [ ] Graceful bei fehlendem Char (falls ältere FW) — kein Crash.

---

### A3 — Stromspar-/Deep-Sleep-Strategie (BLE-seitig) · `FR-A3`

- **Quelle**: Q1 (VBT)
- **Priorität**: `V2.0` · **Kategorie**: `NICE` · **Risiko**: Mittel · **Machbarkeit**: Mittel · **Aufwand**: 2–3 PT (großteils Firmware)
- **Code-Stand**: **Delta** — ControlPoint STOP / DeviceStatus LOW_POWER in Spec; App-Idle-Disconnect unvollständig

**Was**: M5 in Deep Sleep ohne Bewegung/Verbindung; Wake per Button/IMU-Interrupt.

**Technische Details**:
- App: Idle → Disconnect nach N Minuten ohne aktiven Satz.
- Firmware: BMI270-Motion-Wake; an `protocol.yaml` / bestehende Control-Commands anbinden.
- Reconnection (P0-4) deckt Wiederaufwachen ab.

**Risiko**: Mittel — Wake-Latenz stört UX; HW-Tests Pflicht.

**DoD**:
- [ ] App Idle-Timeout konfigurierbar + Disconnect.
- [ ] Reconnect nach Wake &lt; 3 s (Doc 11).
- [ ] Kein Verlust des Product-Zählsignals während aktiver Session.

---

### A4 — ML-basierte Exercise Recognition · `FR-A4`

- **Quelle**: Q2, Q3, Q4, Q5
- **Priorität**: `V2.0` · **Kategorie**: `MUST` · **Risiko**: Mittel · **Machbarkeit**: Mittel · **Aufwand**: **15–25 PT** (Vollausbau inkl. Daten/LOSO/On-Device); Shadow-Demo 1–2 Übungen ~8–12 PT
- **Code-Stand**: **Greenfield** (+ Recorder-Muster aus CV)

**Was**: Übung aus IMU-Fenstern vorschlagen (nie still umschalten):  
`IMU-Fenster → Klassifikator → {Curl, …} + Confidence → UI „übernehmen?“`.

**Algorithmus**: Sliding Window ~2 s @ ~50 Hz; Magnitude `r` für Orientierungs-Unabhängigkeit; klassisch (RF) oder 1D-CNN → TFLite; **LOSO Pflicht** (A9).

**Integration**: `lib/domain/ml/exercise_classifier.dart`; `imu_session_recorder.dart` (opt-in, lokal); Shadow in `engine_provider` — nur Vorschlag.

**Risiko**: Mittel — braucht Daten mehrerer Personen. Ohne LOSO memoriert das Modell Nutzer.

**DoD**:
- [ ] Opt-in IMU-Recorder, lokal.
- [ ] TFLite Shadow, nur UI-Vorschlag.
- [ ] LOSO-Report im Repo.
- [ ] Zählquelle unverändert.

---

### A5 — Form-Quality-Score aus IMU · `FR-A5`

- **Quelle**: Q3, Q7, Q10
- **Priorität**: `V2.0` · **Kategorie**: `NICE` · **Risiko**: Niedrig–Mittel · **Machbarkeit**: Hoch · **Aufwand**: 3–4 PT
- **Code-Stand**: **Delta** — baut auf A1-Rep-Fenstern (gP)

**Was**: Score 0–100 pro Rep: ROM-Proxy, Tempo-Konsistenz, relativ zum **Satz-Median** (kein absolutes „richtige Form“-Urteil).

**Integration**: `workout_engine.dart` gP-Pfad; Session-Summary.

**DoD**:
- [ ] ROM-Proxy + Tempo + Score.
- [ ] Ausreißer in Summary.
- [ ] Unit-Tests Normalisierung.
- [ ] Labeling: „Konsistenz“, nicht „Form korrekt“.

---

### A6 — CV-Form-Feedback (Skelett-Erweiterung) · `FR-A6`

- **Quelle**: Q7, Q9, Q10
- **Priorität**: `V2.0` · **Kategorie**: `NICE` · **Risiko**: Mittel · **Machbarkeit**: Mittel · **Aufwand**: 4–6 PT
- **Code-Stand**: **Delta** — Doc 14 Overlay + Angle/Fusion vorhanden

**Was**: Live-Gelenkwinkel, ROM-Marker, Warnfarbe am Skelett; Cross-Check-Log gegen IMU-ROM (kein Zwang).

**Integration**: `lib/domain/vision/*`, `skeleton_painter.dart`, `fusion_pulse.dart`; optional degradiert.

**DoD**:
- [ ] Live-Winkel + ROM pro Rep aus Kamera.
- [ ] Overlay-Warnfarbe.
- [ ] Cross-Check-Log; IMU bleibt autoritativ.

---

### A7 — LLM Post-Session-Coaching · `FR-A7`

- **Quelle**: Q6
- **Priorität**: `V3.0` · **Kategorie**: `NICE` · **Risiko**: Hoch · **Machbarkeit**: Mittel · **Aufwand**: 6–10 PT
- **Code-Stand**: Greenfield

**Was**: Stufe 1 = Engine-Zahlen; Stufe 2 = LLM formuliert Sprache. LLM zählt nie. Opt-in Cloud; Offline-Regel-Fallback.

**DoD**: Opt-in + Privacy-Text; Offline-Fallback; Template-Prompt nur mit gelieferten Zahlen.

---

### A8 — Magnitude/PCA Shadow-Signal · `FR-A8`

- **Quelle**: Q2, Q4
- **Priorität**: `V2.0` · **Kategorie**: `NICE` · **Risiko**: Niedrig · **Machbarkeit**: Hoch · **Aufwand**: 2–3 PT
- **Code-Stand**: Delta (gP ist live; Magnitude-Kanal Shadow)

**Was**: `r = √(x²+y²+z²)` (+ optional PCA) als Shadow parallel zu gP loggen; Zähl-Delta dokumentieren; Live-Pfad unverändert.

**DoD**: Magnitude geloggt; Vergleichsmetrik; Live unverändert; einheitliches Shadow-Report-Format (siehe B12).

---

### A9 — LOSO Evaluations-Harness · `FR-A9`

- **Quelle**: Q4
- **Priorität**: `V2.0` · **Kategorie**: `MUST` (für jedes ML-Feature) · **Risiko**: Niedrig · **Machbarkeit**: Hoch · **Aufwand**: 2 PT
- **Code-Stand**: Greenfield (`tools/ml/`)

**Was**: Python LOSO-Eval für exportierte IMU-Sessions; Confusion-Matrix + Per-Subject-Accuracy.

**DoD**: `tools/ml/loso_eval.py` + README; optional CI-Artefakt.

---

### A10 — Teachable-Kalibrierungs-Presets · `FR-A10`

- **Quelle**: Q8, Q5
- **Priorität**: `V3.0` · **Kategorie**: `NICE` · **Risiko**: Mittel · **Machbarkeit**: Mittel · **Aufwand**: 4–6 PT
- **Code-Stand**: **Delta** — Guided Calib + Korrektur-θ-Nudge existieren

**Was (Delta, nicht Greenfield)**:
- Heute: ein gP-Profil aus Calib; θ-Nudge nach „Speichern & lernen“.
- Neu: **benannte Presets pro Übung**, wählbar/rücksetzbar; optional 3–5 Referenz-Reps → Median-θ + Dauer-Bänder als Preset-Datei in Drift.

**Nicht** nochmal den gesamten Calib-Wizard neu bauen.

**DoD**:
- [ ] Preset erzeugen/persistieren/umschalten/zurücksetzen.
- [ ] A/B Preset vs. Default dokumentiert.
- [ ] Schlechte Aufnahme darf Zählung nicht „ohne Escape“ verschlechtern.

---

## Teil B — Eigene Verbesserungsideen (FlowRep-Kontext)

### B1 — Adaptive Ruhepausen · `FR-B1`

- **Priorität**: `V1.2` (hängt an A1) · **NICE** · Risiko niedrig · 1–2 PT · **Delta**
- **Was**: Pausen-Timer (P0-2) schlägt bei hohem Velocity-Loss längere Pause vor; manuell überschreibbar.
- **DoD**: Vorschlag aus Loss; User-Override; kein Zwang.

### B2 — Session-Export CSV/JSON · `FR-B2`

- **Priorität**: `V1.1` · **MUST** · Risiko niedrig · 1 PT · **Greenfield-Service**
- **Was**: Lokaler Export (Share-Sheet): Sätze, Reps, Korrekturen, optional Velocity.
- **Privacy-DoD**: Kein Auto-Upload; Nutzer sieht was exportiert wird; Löschen der App-Daten unabhängig.
- **DoD**: Export + Share; Unit/Integration auf Query-Ebene.

### B3 — Rep-Timeline-Sparkline · `FR-B3`

- **Priorität**: `V1.2` · **NICE** · 2 PT
- **Was**: Sparkline Peaks/Rep-Marker nach Satz (didaktisch bei Fehlzählungen).
- **DoD**: Rein lesend; aus `reps`-Liste.

### B4 — PRs & Badges · `FR-B4`

- **Priorität**: `V2.0` · **NICE** · 2–3 PT
- **Was**: Meiste Reps / höchste Velocity / Serie dezent feiern.
- **DoD**: PR pro Übung; Badge in Summary.

### B5 — History Trends · `FR-B5`

- **Priorität**: `V2.0` · **MUST** · 3 PT · **Delta**
- **Already**: `history_screen.dart` listet Sessions.
- **Delta**: Volumen- und Velocity-Trends, Zeitraum-Filter, Charts (`fl_chart` o. Ä.) — **nicht** neuen Screen von Null.
- **DoD**: Trends pro Übung; Filter; lesend.

### B6 — Ghost-Rep-Watchdog · `FR-B6`

- **Priorität**: `V1.1` · **MUST** · **Risiko: Mittel** · 1–2 PT · **Delta**
- **Already**: gP-Gates (Floor, Dauer, Peak) gegen Wackeln.
- **Delta**: Erkennen **Ablegen / nicht-periodische Aktivität** (Envelope-Varianz + fehlende Periodizität) und Zählung **pausieren** — zusätzlich, nicht Ersatz der Gates.
- **Risiko**: Zu aggressiv → echte langsame Reps sterben. Pflicht: HW-Retest Curl vs. Ablegen vs. Wackeln (Doc 11/13).
- **DoD**:
  - [ ] Bei Ablegen keine neuen Reps.
  - [ ] Unit: synthetisches Rauschen / Ablegen-Signal.
  - [ ] HW-Notiz: Curl noch zählbar; Ablegen still.

### B7 — Sensor-Platzierungs-Tutorial · `FR-B7`

- **Priorität**: `V1.2` · **NICE** · 1–2 PT · **Delta**
- **Already**: Onboarding / Guided Calib erklären Platzierung teilweise.
- **Delta**: Kurzer bebilderter Flow „wo sitzt der Stick“, aus Settings wiederholbar.
- **DoD**: Erststart optional; Settings re-run.

### B8 — Audio-First / Blind-Mode · `FR-B8`

- **Priorität**: `V2.0` · **NICE** · 2 PT
- **Was**: Rep-Klick, Satzende, Pause-Ende ohne Blick aufs Handy (P1-5 + P2-3).
- **DoD**: Satz ohne Screen; respektiert Stumm.

### B9 — Übungs-Zielprofile · `FR-B9`

- **Priorität**: `V2.0` · **NICE** · 2 PT
- **Was**: z. B. 4×12; Fortschritt „Satz 2/4“.
- **DoD**: Ziele persistent; optional.

### B10 — Diagnose-/Debug-Overlay · `FR-B10`

- **Priorität**: `V1.1` · **MUST** (für HW-QA) · Risiko niedrig · 1–2 PT · **Greenfield-UI**
- **Was**: Dev-Mode: Live Envelope, θ, Peaks, Paketrate, Shadow-Delta.
- **Integration**: Overlay `home_screen`; versteckte Geste/Settings.
- **DoD**: Standard aus; kein Release-UI-Impact; beschleunigt Doc-13 A1–A5 + A1/A5/A8/B6.

---

### B11+ — Ergänzungen aus Code-Review (2026-07-23)

### B11 — BLE/Paket-Qualitäts-Indikator · `FR-B11`

- **Priorität**: `V1.2` · **NICE** · 1 PT
- **Was**: Live-Hinweis bei Jitter/Paketverlust (an P2-5 / B10 andocken).
- **DoD**: Sichtbar im Dev-Overlay; optional dezent im Product-UI.

### B12 — Einheitliches Shadow-vs-Live-Report-Format · `FR-B12`

- **Priorität**: `V1.2` · **MUST** (für A8/A4) · 1 PT
- **Was**: Ein Log-/Export-Schema für Shadow-Deltas (gP vs. Magnitude vs. ML-Vorschlag).
- **DoD**: Spec in Doc + optional JSONL-Export; B10 kann es anzeigen.

### B13 — Korrektur-Analytics (lokal) · `FR-B13`

- **Priorität**: `V1.2` · **NICE** · 1–2 PT
- **Was**: Under/Over-Count-Häufigkeit pro Übung aus `CorrectionEvent` — steuert B6/A1-Tuning, ohne Cloud.
- **DoD**: Aggregate lokal; Anzeige Dev oder History.

### B14 — Multi-Übung-Session ohne ML · `FR-B14`

- **Priorität**: `V1.2` · **NICE** · 2 PT
- **Was**: Schneller Übungswechsel + letzter θ/Preset pro Übung — billiger Nutzen als A4.
- **DoD**: Wechsel &lt; 2 Taps; Profil pro Übung geladen.

### B15 — Privacy-DoD für Exporte · `FR-B15`

- **Priorität**: mit **B2** · **MUST** · 0.5 PT
- **Was**: Klartext was in CSV/JSON steckt; kein stiller Upload; Löschpfad dokumentiert.
- **DoD**: In B2-Issue mit abhaken.

### B16 — Firmware Power-States an Spec koppeln · `FR-B16`

- **Priorität**: mit **A3** · **NICE** · (in A3 enthalten)
- **Was**: `DeviceStatus` / LOW_POWER aus protocol.yaml gegen echte FW-States prüfen und dokumentieren.

---

## Teil C — Konsolidierte Roadmap

### Gate vor Feature-Arbeit

| Gate | Quelle | Status |
|------|--------|--------|
| Physische Session A1–A5 | Doc 13 | **[ ] offen** — priorisieren |
| B10 Diagnose-Overlay | dieses Doc | empfohlen **erstes** V1.1-Ticket |

### V1.1 — Schlanke Quick Wins (~6–10 PT gesamt)

| ID | Feature | Kat. | Aufwand | Risiko | Code-Stand |
|----|---------|------|---------|--------|------------|
| **FR-B10** | Diagnose-Overlay | MUST | 1–2 PT | Niedrig | Greenfield-UI |
| **FR-B6** | Ghost-Rep-Watchdog (Ablegen) | MUST | 1–2 PT | **Mittel** | Delta zu gP-Gates |
| **FR-B2** (+B15) | Session-Export + Privacy | MUST | 1–1.5 PT | Niedrig | Greenfield |
| **FR-A1** | VBT light (Peak + Loss UI) | MUST | 2–3 PT | Niedrig* | Delta `peakMagnitude` |
| **FR-A2** | Akku Polish/QA | DONE | 0–0.5 PT | Niedrig | **Already** |

\*A1 light = nur Anzeige. Autoregulation → V1.2.

**Nicht in V1.1** (früher als „Quick Win“ zu voll): B1, B3, B7 → **V1.2**.

**Empfohlene Reihenfolge V1.1**:  
`B10 → B6 → B2(+B15) → A1 light → A2 QA abschließen`.

### V1.2 — Nach VBT/Export

| ID | Feature | Kat. | Aufwand |
|----|---------|------|---------|
| FR-B1 | Adaptive Ruhepausen | NICE | 1–2 PT |
| FR-B3 | Rep-Timeline | NICE | 2 PT |
| FR-B7 | Platzierungs-Tutorial | NICE | 1–2 PT |
| FR-B11 | BLE-Qualitäts-Indikator | NICE | 1 PT |
| FR-B12 | Shadow-Report-Format | MUST | 1 PT |
| FR-B13 | Korrektur-Analytics | NICE | 1–2 PT |
| FR-B14 | Multi-Übung ohne ML | NICE | 2 PT |
| FR-A1 | VBT Persist/Mean (optional Autoreg Opt-in) | MUST | 1–2 PT |

### V2.0 — Feature-Release (ML & Tiefe)

| ID | Feature | Kat. | Aufwand | Risiko |
|----|---------|------|---------|--------|
| FR-A4 | ML Exercise Recognition | MUST | **15–25 PT** (Voll) / 8–12 Demo | Mittel |
| FR-A9 | LOSO-Harness | MUST | 2 PT | Niedrig |
| FR-B5 | History Trends (extend) | MUST | 3 PT | Niedrig |
| FR-A5 | IMU Form-Quality | NICE | 3–4 PT | Niedrig–Mittel |
| FR-A6 | CV Form-Feedback | NICE | 4–6 PT | Mittel |
| FR-A8 | Magnitude Shadow | NICE | 2–3 PT | Niedrig |
| FR-A3 | Deep-Sleep | NICE | 2–3 PT | Mittel |
| FR-B4 | PRs & Badges | NICE | 2–3 PT | Niedrig |
| FR-B8 | Audio-First | NICE | 2 PT | Niedrig |
| FR-B9 | Zielprofile | NICE | 2 PT | Niedrig |

### V3.0 — Vision

| ID | Feature | Kat. | Aufwand | Risiko |
|----|---------|------|---------|--------|
| FR-A7 | LLM Coaching | NICE | 6–10 PT | Hoch |
| FR-A10 | Teachable-Presets (Delta zu Calib) | NICE | 4–6 PT | Mittel |

---

## Teil D — Ticket-Backlog (Copy-Paste)

> Kanonische ID = `FR-*`. Details in den Karten oben.

```
[FR-B10] Diagnose-/Debug-Overlay (Developer-Mode)          — V1.1/MUST — 1-2 PT
[FR-B6]  Ghost-Rep-Watchdog (Ablegen/nicht-periodisch)     — V1.1/MUST — 1-2 PT  [Risiko Mittel]
[FR-B2]  Session-Export CSV/JSON                           — V1.1/MUST — 1 PT
[FR-B15] Privacy-DoD Exporte (mit B2)                      — V1.1/MUST — 0.5 PT
[FR-A1]  VBT light: Peak + Velocity-Loss % UI              — V1.1/MUST — 2-3 PT
[FR-A2]  M5 Akkustand — DONE; Polish/HW-QA                 — V1.1/DONE — 0-0.5 PT

[FR-B1]  Adaptive Ruhepausen (VBT-gesteuert)               — V1.2/NICE — 1-2 PT
[FR-B3]  Rep-Timeline-Sparkline                            — V1.2/NICE — 2 PT
[FR-B7]  Sensor-Platzierungs-Tutorial                      — V1.2/NICE — 1-2 PT
[FR-B11] BLE/Paket-Qualitäts-Indikator                     — V1.2/NICE — 1 PT
[FR-B12] Shadow-vs-Live Report-Format                      — V1.2/MUST — 1 PT
[FR-B13] Korrektur-Analytics lokal                         — V1.2/NICE — 1-2 PT
[FR-B14] Multi-Übung-Session ohne ML                       — V1.2/NICE — 2 PT

[FR-A3]  Deep-Sleep + Motion-Wake (Firmware+App)           — V2.0/NICE — 2-3 PT
[FR-A4]  ML Exercise Recognition (TFLite, Shadow)          — V2.0/MUST — 15-25 PT
[FR-A5]  IMU Form-Quality-Score                            — V2.0/NICE — 3-4 PT
[FR-A6]  CV Form-Feedback Gelenkwinkel                     — V2.0/NICE — 4-6 PT
[FR-A8]  Magnitude/PCA Shadow-Signal                       — V2.0/NICE — 2-3 PT
[FR-A9]  LOSO Evaluations-Harness                          — V2.0/MUST — 2 PT
[FR-B4]  Persönliche Rekorde & Badges                      — V2.0/NICE — 2-3 PT
[FR-B5]  History Trends (extend history_screen)            — V2.0/MUST — 3 PT
[FR-B8]  Audio-First / Blind-Mode                          — V2.0/NICE — 2 PT
[FR-B9]  Übungs-Zielprofile                                — V2.0/NICE — 2 PT

[FR-A7]  LLM Post-Session-Coaching (Opt-in)                — V3.0/NICE — 6-10 PT
[FR-A10] Teachable-Presets (Delta zu Calib/Nudge)          — V3.0/NICE — 4-6 PT
```

---

## Teil E — Bewusst NICHT übernommen

| Abgelehnt | Quelle | Begründung |
|-----------|--------|------------|
| Edge Impulse / proprietäre TinyML-Plattform | Q8 | Vendor-Lock-in; TFLite offen (A4) |
| Multi-Sensor-Setup (4 IMUs) | Q4 | Single-Sensor; Q4: 1 Sensor genügt |
| OpenPose-basierte CV | Q10 | Veraltet; MediaPipe/BlazePose |
| Flask/Web-Backend als Kern | Q3 | Native Flutter, lokale-first |
| LLM als Zählquelle | Q6 | Verletzt Leitprinzip 1 |
| A2 als Firmware-Greenfield | — | **Code existiert** (fee3 + UI) |
| A1 primär über New-Pipeline PeakDetector | — | Product = gP; New-Pipeline Shadow |

---

## Teil F — Querverweise & nächste Schritte

| Thema | Doc |
|-------|-----|
| 1.0 offene HW-Gates | [13_OFFENE_PUNKTE](13_OFFENE_PUNKTE.md) A1–A5 |
| Ledger Code vs. offen | [12_IMPLEMENTIERUNGS_STATUS](12_IMPLEMENTIERUNGS_STATUS.md) |
| Sensor-Fusion / CV | [07_CV_SENSOR_FUSION](07_CV_SENSOR_FUSION.md) · [14](14_CV_SKELETT_OVERLAY_PLAN.md) |
| BLE/Battery-Protokoll | [protocol.yaml](../reference/protocol.yaml) |
| Invarianten | [00_UEBERSICHT](00_UEBERSICHT.md#verbotene-aktionen) |

**Unmittelbar**:
1. Doc-13 **A1–A5** physisch abschließen (mit oder ohne B10).  
2. **FR-B10** bauen → QA und Signal-Features entblocken.  
3. Dann **B6 → B2 → A1 light**.

---

## Changelog dieses Docs

| Datum | Änderung |
|-------|----------|
| 2026-07-22 | Erstfassung: 10 Quellen, A1–A10, B1–B10, Roadmap V1.1/V2/V3 |
| 2026-07-23 | Code-Review-Korrektur: A2 DONE; A1 gP-Pfad; Already/Delta; V1.1 schlank; B1/B3/B7 → V1.2; Risiken A1/B6/A4; B11–B16; Gate Doc 13; Product-Pfad-Tabelle |
| 2026-07-24 | **Implementierung**: B10 Diagnose-Overlay; B6 Ghost-Gate (gP-only); B2/B15 Export; A1 VBT light UI; A2 Snackbar &lt;15 %; B1 adaptive Pause; B3 Rep-Timeline; B5 History-Trends; B7 Tutorial; B8 Blind-Mode; B9 Ziele; B4 PR-Badge; A5 FormQuality; A8 Magnitude-Shadow; B12 ShadowReport; A7 RuleCoaching offline; A4 HeuristicClassifier + UI-Vorschlag; A9 `tools/ml/loso_eval.py`; A3 App-Idle-Disconnect 15 min. **Nicht** vollständig: TFLite-ML-Training, Firmware Deep-Sleep, LLM-Cloud, Multi-Subject-Daten |

### Implementierungs-Matrix (2026-07-24)

| ID | Status Code | Notes |
|----|-------------|-------|
| FR-B10 | **[x]** | Settings → Diagnose-Overlay |
| FR-B6 | **[x]** | gP-autoritativ; Unit + Settings-Toggle |
| FR-B2/B15 | **[x]** | CSV/JSON + Privacy-Text + Share |
| FR-A1 | **[x]** light | Peak/Loss UI + Summary; keine m/s |
| FR-A2 | **[x]** | Already + Snackbar &lt;15 % |
| FR-B1 | **[x]** | Adaptive Rest aus Loss |
| FR-B3 | **[x]** | `RepTimeline` |
| FR-B5 | **[x]** | Trends auf History-Screen |
| FR-B7 | **[x]** | Tutorial-Screen |
| FR-B8 | **[x]** | Blind-Mode Toggle (Haptik/Audio) |
| FR-B9 | **[x]** | Ziel Sätze×Reps in Settings |
| FR-B4 | **[x]** | PR-Chip in Summary |
| FR-A5 | **[x]** domain | FormQuality + Coaching-Hinweise |
| FR-A8 | **[x]** shadow | Magnitude shadow + report buffer |
| FR-B12 | **[x]** | `ShadowReportLine` JSONL |
| FR-A7 | **[~]** | Offline RuleCoaching only (kein LLM) |
| FR-A4 | **[~]** | Heuristic + Vorschlag-UI; kein TFLite |
| FR-A9 | **[x]** tool | `tools/ml/loso_eval.py` |
| FR-A3 | **[~]** | App Idle-Disconnect; FW Deep-Sleep offen |
| FR-A6 | **[~]** | Doc 14 Overlay already; extra Form-CV deferred |
| FR-A10 | **[ ]** | Calib/Nudge exist; Multi-Preset UX offen |

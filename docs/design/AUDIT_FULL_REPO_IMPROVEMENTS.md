# FlowRep — Full Repository Improvement Audit

> **Stand:** 2026-07-24  
> **Methode:** Code + Living Docs + HW-Session-Evidence (keine neuen HW-Messungen in diesem Audit)  
> **Constraints (unverändert):** IMU autoritativ · `_useNewPipeline = false` · `correctedReps` ≠ `countedReps` · kein Force-Push  
> **Scope:** gesamtes Repo (`app/`, `firmware/`, `docs/`, `tools/`)  
> **Ziel:** zuverlässiges Zählen, Vision sinnvoll, UI polished, ehrliche Prioritäten

---

## 0. Executive Summary

### Reifegrad (0–10)

| Dimension | Score | Kurzbegründung |
|-----------|------:|----------------|
| **Counting Reliability** | **6.0** | Product-Pfad gP mit Gates ist solid; Gate „Zählen starten“, Gyro-Bias/Rest-Anomalien, fehlende formale App-vs-Manuell-DoD und Shadow-Pipeline ungenutzt |
| **Vision Integration** | **4.5** | Scaffold + Overlay + Fusion-Stats da; getrennte Session, kein Produkt-Nutzen im Trainingsflow, Fusion zählt nicht mit |
| **UI Polish** | **5.5** | Funktionell, modular, Gym-taugliche Buttons; Home ist Feature-Liste statt „Trainingsmodus“, Diagnose dominiert Dev-Feeling |
| **Architecture** | **7.0** | Domain/Data/Presentation, Tests ~400+, Dual-Pipeline bewusst; `WorkoutEngine` + `EngineNotifier` monolitisch |
| **Release Ready** | **6.5** | RC-Tag, Features code-fertig; physische A1–A5 formal offen, Store/iOS out of scope |

### Top 10 Hebel (Impact-sortiert)

1. **Trust-UX für Zähl-Gate** — „Zählen starten“ ist der #1 Grund für 0 Reps (HW 2026-07-24); mental model + Auto-Start nach Calib/BtnA klarer machen.  
2. **Counting Reliability DoD messen** — formales App-vs-Manuell + Wiggle + Langsame Reps + Placement-Varianten; ohne Messung bleibt Tuning Ratespiel.  
3. **Pipeline-Ehrlichkeit weiter härten** — Timebase/BLE-Loss/Gyro-Bias Health-Gate vor dem Zähler (nicht nur Algorithmus).  
4. **gP Product-Pfad stabilisieren** — Refractory + θ + Excursion-Gates behalten; Adaptive Searchback für langsame Reps; Placement-Drift-Warnung.  
5. **Correction-Loop als Lernsignal maximieren** — UI schneller, Nudge-Transparenz, Session-Aggregat „Engine vs. User“.  
6. **Vision als Form-Lab positionieren** — nicht als zweiter Counter auf Home; klare Copy, optional „Übereinstimmung %“ Badge.  
7. **Gym Home UI** — Rep-first Layout, weniger Scroll, States (verbunden/kalibriert/zählend/pausiert) farblich dominant.  
8. **Shadow-DoD für New Pipeline** — Parallel-Logging, CSV-Vergleich, erst dann `_useNewPipeline` entscheiden.  
9. **Diagnose → Power-User, Default clean** — Release: große Reps, kleine Statuszeile; Diagnose nur Settings.  
10. **Firmware/Sensor Health** — stale IMU, Rest-Gyro-Anomalie (~86°/s), Battery UX bereits gut — Health-Banner ausbauen.

### Strategische Entscheidung (1 Absatz)

FlowRep ist **technisch reifer als das Produktgefühl**. Der gP-Pfad (signierte Gyro-Projektion + θ-Gates + Ghost) ist die richtige Richtung und besser als reines Magnitude-Counting; die New Pipeline hinter dem Flag ist architektonisch sauber, aber **nicht freigabereif**. Der nächste Reife-Sprung kommt **nicht** von mehr Features (Doc 15 ist weitgehend im Code), sondern von: (a) **messbarer Zähl-Zuverlässigkeit am Arm**, (b) **klarerem mental model** (wann zählt was), (c) **Gym-first UI**, (d) Vision als **optionaler Form-Validator** statt paralleler Technik-Demo. Alles andere (ML-Classifier, LLM-Coaching, Multi-Exercise-Deep-Learning) ist V2+ und darf den Product-Pfad nicht belasten.

---

## 1. Systemverständnis (Ist)

### 1.1 Architektur (textuell)

```
┌─────────────┐   BLE GATT (fee0/fee1 batches, fee3 battery, fee4 events)
│ M5StickC    │ ──────────────────────────────────────────────────────┐
│ Plus2 FW    │   BtnA → DeviceEvent 0x01                             │
│ BMI270 IMU  │                                                       │
└─────────────┘                                                       ▼
                                                          BleSensorProvider
                                                          · parse v2 (53 B)
                                                          · dedup / poll
                                                          · JitterBuffer → ~50 Hz
                                                                  │
                    ┌─────────────────────────────────────────────┤
                    ▼                                             ▼
            EngineNotifier                               CameraPoseProvider
            isCountingActive?                            flutter_pose_detection
            ghost / feedback                                      │
                    │                                             ▼
                    ▼                                    PoseRepCounter (Winkel)
            WorkoutEngine (LEGACY = PRODUCT)             FusionEngine (Stats only)
            · SignalProcessor + gP                       Skeleton overlay UI
            · θ gates, refractory, ghost
            · Correction learn (θ-nudge)
                    │
                    │  _useNewPipeline=false
                    ▼
            ExerciseEngine (SHADOW / OFF)
            SignalChain → PeakDetector → Template → Phase → Quality
                    │
                    ▼
            Drift DB · CSV · CalibrationStore · History · Export
```

### 1.2 Product Path vs. Experimental

| Pfad | Status | Zählt live? |
|------|--------|-------------|
| **gP excursion** in `WorkoutEngine._detectPeakSigned` + `_commitRep` | Product | **Ja** (nach Calib/Profile) |
| Combined magnitude `|a|+|g|·w` | Bootstrap / Fallback | Nur wenn gP/gyroMag nicht autoritativ |
| **ExerciseEngine** (`_useNewPipeline`) | Flag **false** | Nein |
| Shadow-Mode (`_shadowMode`) | optional parallel | Legacy bleibt Wahrheit |
| **PoseRepCounter + FusionEngine** | Camera session | Fusion **ändert countedReps nicht** (IMU-Home zählt) |
| ML `exercise_classifier` | Stub/heuristic | Vorschlag-UI, zählt nicht |

### 1.3 Docs vs. Code

| Behauptung | Code-Realität |
|------------|---------------|
| P0–P2 + CV-Scaffold fertig | **Ja** (Tests grün, RC `1.0.0-rc.1`) |
| A1–A5 formal erledigt | **[~]** Session partial; 4 Kurzchecks offen |
| Gyro clipping S4 | **v2 scale 0.02** in Firmware (S4-Fix) |
| Sample pacing | Firmware per-sample Interval (nicht mehr nur `delay(20)` batch) |
| Research S1 „kein Refractory live“ | **Teilweise veraltet**: `minRepIntervalSamples` in `_commitRep` existiert |
| Research S8 „nur Magnitude“ | **Product nutzt gP**, Magnitude ist Fallback |
| Doc 15 Features | Großteils implementiert; HW-Gate bleibt |

**Regel:** Code + HW-Logs schlagen ältere Research-Statuszeilen. Research bleibt wertvoll für Algorithmus-Ideen, Status-Spalten müssen re-verifiziert werden.

### 1.4 Hotspots (LOC-Orientierung)

| Datei | Rolle | Risiko |
|-------|-------|--------|
| `workout_engine.dart` (~1.5k LOC) | Zähl-Wahrheit Product | God-object, schwer zu ändern |
| `engine_provider.dart` (~1k LOC) | UI-Orchestrierung, BLE-Lifecycle | God-notifier |
| `ble_sensor_provider.dart` | Stream-Ehrlichkeit | HyperOS/poll Edge cases |
| `firmware/src/main.cpp` | Timebase, Events, Skalen | Hardware-coupled |
| `fusion_engine.dart` | Ensemble-Policy | Noch nicht product-wirksam |

---

## 2. Stärken (beibehalten)

1. **Klare Autoritätsregel IMU > Vision** — verhindert stille False Counts aus Kamera-Okklusion.  
2. **gP (signierte Projektion auf gelernte Achse)** — strukturell besser gegen Doppel-Peaks als Magnitude.  
3. **Guided Calibration 2.0 + persistiertes Profile** — Achse, Bias, θ, quality.  
4. **Product-Defaults ehrlich:** manuelles Satzende, `correctedReps` getrennt, kein Fake-„KI lernt“.  
5. **θ-Härtung:** Floor 50, 0.70×θ, minSamples≥15, Peak≥1.2×θ (Wiggle-Schutz).  
6. **GhostRepGate** mit konfigurierbarer Idle-Zeit (Default 45s) — nach zu aggressivem 5s-Verhalten korrigiert.  
7. **M5 BtnA → Start/Satzende** (fee4) + Settings für Feedback — Gym-tauglich.  
8. **JitterBuffer + Protocol v2 + Dedup** — bewusste BLE-Realitätsbehandlung.  
9. **Testkultur** — große Unit/Widget-Suite, structural tests für Product-Pfad, Simulationstools.  
10. **Living Docs + Session Evidence** — Onboarding für Menschen und Agenten ungewöhnlich gut.  
11. **Soft-fail Vision** — App ohne Kamera nutzbar.  
12. **Encryption/Secure storage Path** für Calib/DB — Privacy-bewusst für lokales Produkt.

---

## 3. Schwachstellenkatalog

### 3.1 Counting / Product Logic

#### [C-01] Zähl-Gate `isCountingActive` unsichtbar im mental model
- **Severity:** Critical (User Impact)  
- **Area:** counting · ui  
- **Evidence:** `engine_provider.dart` `_onSampleGated` only if `isCountingActive`; `COUNT_ZERO_ANALYSIS.md` 2026-07-24: ENGINE lines = 0 trotz Stream+Profile  
- **User impact:** 0 Reps trotz korrekter Calib und Bewegung  
- **Root cause:** Samples erreichen Engine erst nach explizitem Start; UI erklärt das zu schwach im Stress  
- **Current mitigation:** großer grüner Button; BtnA startet auch  
- **Better alternatives:** (1) Auto-start after successful calib; (2) persistent banner „Nicht am Zählen“; (3) armed state nach Connect+Calib mit Countdown  
- **Recommended fix:** Auto-arm after calib + unmissable state chip „BEREIT / ZÄHLT / PAUSE“  
- **Effort:** S · **Risk:** low  
- **Acceptance:** Nach Calib ohne Extra-Tap: Samples steigen in Diagnose; 8 Curls → count > 0  

#### [C-02] Formale Zähl-DoD am Gerät noch nicht geschlossen
- **Severity:** Critical (Release Trust)  
- **Area:** counting · release  
- **Evidence:** Doc 13 A1–A5 `[~]`; User „klappt besser“ ohne App/Manuell-Zahlen  
- **User impact:** Unklar ob Product wirklich ±1-Rep-ready  
- **Root cause:** Feature-Velocity > Measurement-Velocity  
- **Recommended fix:** 20-Satz Protokoll (8–12 curls, slow, partial, wiggle, re-place sensor) → Tabelle in HW session  
- **Effort:** S (Operator) · **Risk:** none  
- **Acceptance:** ≥80 % Sätze |Δ|≤1; Wiggle ≤1 false  

#### [C-03] Gyro Rest-Anomalie killt gP-Kanten
- **Severity:** High  
- **Area:** counting · firmware · ble  
- **Evidence:** `COUNT_ZERO_ANALYSIS.md`: rest gyro_mag ≈86 vs. healthy 0.4; flat accel  
- **User impact:** Keine falling edges → 0 Reps auch bei aktivem Zählen  
- **Root cause:** Bias/stale/I2C/Kalib-Drift (Hypothese; power-cycle half)  
- **Better alternatives:** Health check before counting; re-bias rest gate; reject stream if rest |gyro| > X for N seconds  
- **Recommended fix:** `SensorHealthMonitor` + Banner „Sensor unruhig — neu kalibrieren“  
- **Effort:** M · **Risk:** med (false alarms)  
- **Acceptance:** Anomalie detektiert in <5s; healthy rest passes  

#### [C-04] Dual-Pipeline-Komplexität ohne freigegebene New Pipeline
- **Severity:** Medium  
- **Area:** arch · counting  
- **Evidence:** `_useNewPipeline=false`; `ExerciseEngine` + full detection stack exists; product still `WorkoutEngine` gP  
- **User impact:** Indirekt — Wartungskosten, Docs-Verwirrung, Risiko falscher Fixes am toten Pfad  
- **Recommended fix:** Shadow-DoD script + CSV harness; bis dahin New Pipeline nur touch wenn Shadow-Arbeit  
- **Effort:** L für Gate · **Risk:** high if flipped early  

#### [C-05] Adaptive Threshold vs. Profile-Threshold Policies
- **Severity:** Medium  
- **Area:** counting  
- **Evidence:** `_adaptiveThresholdEnabled` disabled when profile `chosenSignal` set; good. Self-calib path still fragile (`calibrationReps` history)  
- **User impact:** Erstnutzer ohne Guided Calib unzuverlässiger  
- **Recommended fix:** Force Guided Calib for product; hide weak auto-calib path in UI  
- **Effort:** S  

#### [C-06] Langsame / fatigued Reps unter θ
- **Severity:** High (Training-Realität)  
- **Area:** counting  
- **Evidence:** Research S2; θ floor 50 + 0.7×θ schützt vor Wiggle, bestraft langsame End-of-set curls  
- **User impact:** Unterzählen genau wenn User am schwächsten ist  
- **Better alternatives:** Searchback half-threshold; progressive θ soften within set; duration+prominence over pure amplitude  
- **Recommended fix:** Within-set adaptive peak tracker + correction learn already nudges θ — expose „zu streng?“ after undercount corrections  
- **Effort:** M  

#### [C-07] Placement / Re-mount ohne Re-Calib
- **Severity:** High  
- **Area:** counting · calib  
- **Evidence:** gP axis from calib; strap rotation breaks projection  
- **User impact:** Plötzlich 0 oder wild counts  
- **Recommended fix:** Axis-consistency score live; prompt re-calib if projection energy low while accel shows motion  
- **Effort:** M  

### 3.2 Vision

#### [V-01] Vision ist technisch da, produktseitig isoliert
- **Severity:** High (Product Value)  
- **Area:** vision · ui  
- **Evidence:** `CameraSessionScreen` separate Route; Home IMU zählt; Fusion nur Badge/Stats  
- **User impact:** „Warum Kamera?“ unklar; kein Trainingsnutzen im Gym-Flow  
- **Recommended fix:** Product story: **Form Lab** — optional, zeigt Winkel + „IMU↔Pose Übereinstimmung“, nie still override  
- **Effort:** M  

#### [V-02] FusionEngine entscheidet, ändert aber Product-Counts nicht
- **Severity:** Medium (Honest Architecture)  
- **Area:** vision  
- **Evidence:** `fusion_engine.dart` `shouldCount` not wired into `WorkoutEngine._commitRep`  
- **User impact:** Badge wirkt wie Feature, ist aber Diagnostik  
- **Recommended fix:** Entweder (A) pure diagnostic branding, or (B) soft signal: confidence chip on each IMU rep, never veto unless user enables „streng“  
- **Effort:** S–M  

#### [V-03] Gym-Lighting / Occlusion / Framing nicht productized
- **Severity:** Medium  
- **Area:** vision  
- **Evidence:** `TrackingQualityTracker` exists; framing guide widget exists; no guided first-run camera setup in product narrative  
- **Recommended fix:** 10s setup coach: distance, full upper body, lighting  
- **Effort:** M  

#### [V-04] Performance / thermal undokumentiert am Gerät
- **Severity:** Low–Medium  
- **Area:** vision · perf  
- **Evidence:** YUV path, D5 native opt deferred; physical NPU session optional  
- **Recommended fix:** 10-min thermal test log FPS/battery  
- **Effort:** S (Operator)  

### 3.3 UI / UX

#### [U-01] Home = Feature-Scroll statt Trainings-HUD
- **Severity:** High  
- **Area:** ui  
- **Evidence:** `home_screen.dart`: connect, debug, ghost banner, suggestion, exercise, start, end set, end session, rep, history, rest, coaching…  
- **User impact:** Im Satz zu viel UI, zu wenig Fokus auf große Zahl  
- **Recommended fix:** Two modes — **Setup** vs **Active Set** (full-screen rep + thin status)  
- **Effort:** M  

#### [U-02] State-Sprache inkonsistent
- **Severity:** Medium  
- **Area:** ui  
- **Evidence:** WorkoutState names + isCountingActive + ghost paused + reconnect — parallel Konzepte  
- **Recommended fix:** Single status model: `Disconnected | Connected | Calibrating | Ready | Counting | GhostPaused | Reconnecting`  
- **Effort:** M  

#### [U-03] Diagnose/Debug standardmäßig sichtbar (debug builds)
- **Severity:** Medium (Polish)  
- **Area:** ui  
- **Evidence:** `SignalDebugView` when connected && !mock && !diagnoseOverlay  
- **User impact:** Dev-Feel in Daily Driver  
- **Recommended fix:** Collapse by default; one-line health; expand on tap  
- **Effort:** S  

#### [U-04] Ghost-Banner ohne echten Dismiss-Nutzen
- **Severity:** Low  
- **Area:** ui  
- **Evidence:** `TextButton onPressed: () {}` on ghost MaterialBanner  
- **Recommended fix:** Dismiss UI + optional „Ghost aus für diesen Satz“  
- **Effort:** S  

#### [U-05] Korrektur-Dialog gut, aber Feedback-Loop unsichtbar
- **Severity:** Medium  
- **Area:** ui · counting  
- **Evidence:** θ-nudge on confirm; no „Threshold angepasst“ toast detail  
- **Recommended fix:** After learn: short confirmation + optional delta display in diagnose  
- **Effort:** S  

#### [U-06] Kein Design-System / Marken-Polish
- **Severity:** Medium (Polished bar)  
- **Area:** ui  
- **Evidence:** Material defaults + purple splash; mixed card density  
- **Recommended fix:** Token set (type scale, spacing 4/8/16, one accent, set-mode dark)  
- **Effort:** L  

### 3.4 BLE / Firmware / Timebase

#### [F-01] BLE Rate ≠ ideal 50 Hz sample reality
- **Severity:** Medium  
- **Area:** ble · firmware  
- **Evidence:** ~11–12 batch Hz documented; JitterBuffer synthesizes 50 Hz; historical S3 concerns partially mitigated by per-sample pacing in FW  
- **User impact:** Time-constants (min samples) approx; sim may still diverge  
- **Recommended fix:** Log effective sample dt distribution; tune gates in real dt not assumed 20ms  
- **Effort:** M  

#### [F-02] Polling/Dedup kann still Frames verlieren
- **Severity:** Medium  
- **Area:** ble  
- **Evidence:** `BatchDedupTracker`, packet loss warning threshold `kPacketLossWarnThreshold`  
- **User impact:** Unterzählung bei schlechtem BLE  
- **Recommended fix:** Already warn; add set-level quality flag on summary  
- **Effort:** S  

#### [F-03] Device naming „GymTracker“ vs Product „FlowRep“
- **Severity:** Low  
- **Area:** firmware · polish  
- **Evidence:** `DEVICE_NAME "GymTracker"`  
- **Recommended fix:** Align name + BLE advertise for store story  
- **Effort:** S (requires reflash + app scan string)  

### 3.5 Architecture / Tests / Docs / Tools

#### [A-01] Monolith Engine + Notifier
- **Severity:** Medium  
- **Area:** arch  
- **Evidence:** 1.5k + 1k LOC  
- **Recommended fix:** Extract: `CountingSession`, `CalibrationFacade`, `DeviceSession`, `FeedbackCoordinator`  
- **Effort:** XL · **Do not** during reliability firefight  

#### [A-02] Test suite strong on unit, weak on HW realism
- **Severity:** High (for reliability claims)  
- **Area:** tests  
- **Evidence:** sin-excursion unit; `tool_count_sim`; few golden CSVs from real labeled sets in CI  
- **Recommended fix:** Golden CSV corpus (10–30 labeled sets) in `tools/` + CI replay  
- **Effort:** M–L  

#### [A-03] Docs drift on research status flags
- **Severity:** Low  
- **Area:** docs  
- **Evidence:** RECHERCHE_ZAEHLROBUSTHEIT S1/S8 status partially superseded by gP product  
- **Recommended fix:** Status banner „re-verify against code“ at top; link this audit  

#### [A-04] Feature-Bar über Polish-Bar (Doc 15 wave)
- **Severity:** Medium (Product focus)  
- **Area:** polish  
- **Evidence:** Metrics, export, coaching, classifier, diagnose — code heavy; formal HW DoD light  
- **Recommended fix:** Feature freeze until A1–A5 + counting metrics  

---

## 4. Deep Dive: Zuverlässiges Rep-Zählen

### 4.1 Ist-Algorithmus (Product, gP)

1. Guided Calib → `ExerciseProfile` mit `ChosenSignal.gP`, rotation axis, bias, θ.  
2. Live: `GpProjection.project(gx,gy,gz)` → signed 1D °/s.  
3. Product gP oft **abs-mode** (`_gpUseAbsProjection`) für Mount-Toleranz + `minRepIntervalSamples` gegen Phase-Doppel.  
4. Rising: value > θ; track samplesAbove + peak.  
5. Falling: value < 0.3·θ → commit only if samplesAbove ≥ 15 und peak ≥ 1.2·θ.  
6. `_commitRep`: refractory + GhostGate.  
7. Magnitude-Pfad zählt **nicht**, sobald gP autoritativ.  

Das ist **korrekt als Architektur** für Wrist-Curl.

### 4.2 Failure Mode Matrix

| Failure | Symptom | Wahrscheinliche Ursache | Mitigation |
|---------|---------|-------------------------|------------|
| Missed all | 0 | Not counting active | C-01 |
| Missed all | 0 | Gyro bias/stuck | C-03 |
| Missed slow | undercount | θ too high | C-06 searchback / learn |
| Double | overcount | abs-mode both phases; refractory too short | tune minRepInterval from calib median |
| Ghost / wiggle | false | gates too weak / ghost off | keep gates; ghost 45s |
| Placement | random | axis invalid | C-07 |
| BLE holes | undercount | loss | quality flag |
| Partial reps | policy unclear | no ROM gate on IMU alone | vision assist or user correction |

### 4.3 Alternativen (Vergleich)

| Ansatz | Vorteil | Nachteil für FlowRep | Empfehlung |
|--------|---------|----------------------|------------|
| **Current gP + gates** | Direction-aware, calibrated, shipped | Slow reps; health issues | **Keep + harden** |
| Pan-Tompkins dual adaptive + refractory | Robust online peaks | Need honest timebase | Partial: already refractory; add searchback |
| Complementary angle + ZUPT | 1 peak/rep structurally | Drift; planarity assumption; more state | Shadow experiment only |
| Full ExerciseEngine (template+phase+quality) | Richer | Unvalidated; complexity | Shadow-DoD only |
| Autocorr / MM-Fit offline | Great for calib | Offline batch | Use in calib review |
| DL few-shot | Multi-exercise dream | Data, battery, opacity | V3, not now |
| Vision primary | Intuitive angles | Gym occlusion, framing, privacy | Validator only |

### 4.4 Empfohlene Zielarchitektur Counting (12 Monate)

```
SensorHealth ──► gP Product Path (authoritative)
                      │
                      ├── Refractory from calib median
                      ├── Amplitude + duration gates
                      ├── Ghost idle gate
                      ├── Within-set adaptive searchback (opt-in)
                      └── User correction → θ/axis nudge (already)
                      
Shadow Parallel: ExerciseEngine + optional angle-complementary
Vision: agreement score only (never silent override)
```

### 4.5 Roadmap Counting

| Phase | Items | Gate |
|-------|-------|------|
| **P0** | C-01 trust UX; C-02 measure protocol; C-03 health banner; feature freeze non-counting | A1–A5 [x] |
| **P1** | Slow-rep searchback; placement energy check; golden CSV CI; set quality score | ≥80% ±1 on curl corpus |
| **P2** | Shadow ExerciseEngine DoD; multi-exercise profiles; angle secondary signal research | G7 decision |
| **P3** | Only then consider `_useNewPipeline` or multi-exercise ML class | Explicit ADR |

### 4.6 Mess- & Test-Harness

1. **Operator protocol (Doc 11 style):** 10 sets curls, 3 slow, 3 wiggle, 2 re-mount.  
2. **CSV golden:** record with `CsvSessionRecorder`, label `true_reps`.  
3. **Replay:** `tools/workout_engine_simulation.py` + Dart `tool_count_sim` on same files.  
4. **Metrics:** mean abs error, % within ±1, false positive rate on wiggle, calib fail rate.  
5. **Never** claim % accuracy without this table.

---

## 5. Deep Dive: Vision richtig einbauen

### 5.1 Ist ehrlich

- Pose detection + skeleton + angles + pose rep SM + fusion stats + front/back + soft-fail: **Code ja**.  
- Im Gym-Hauptflow **irrelevant** für countedReps.  
- User-Erwartung „Kamera zählt mit“ ist **nicht** erfüllt und soll auch nicht still erfüllt werden.

### 5.2 Product Positioning Options

| Option | Beschreibung | Empfehlung |
|--------|--------------|------------|
| **A. Form Lab** | Eigene Session: Formfarbe, Winkel, Tracking quality, optional export landmarks | **Primary** |
| **B. Agreement Badge** | Während IMU-Satz optional Kamera → „Pose bestätigt 7/10“ | Secondary, opt-in |
| **C. Camera-only counting** | Fusion `allowCameraOnly` | Lab/dev only |
| **D. Veto mode** | Camera can block IMU | **Dangerous** — reject for V1.x |

### 5.3 Fusion Policy Proposal

```
Default:
  IMU commit always authoritative.
  If camera tracking_quality high AND pose rep within ±window:
    mark rep as "confirmed" (UI only).
  If camera high quality AND no pose excursion while IMU counted:
    mark "uncertain" (UI only) — never delete rep.
  If camera low quality:
    "no opinion".

Strict mode (Settings, default off):
  Same but session summary shows disagreement rate.
```

### 5.4 UX Proposal

1. Home icon stays „Kamera-Validierung“ → rename **„Form-Check“**.  
2. On enter: 3 bullets: *zählt nicht statt IMU* · *braucht Licht/Abstand* · *optional*.  
3. Large elbow angle + form color (already partially there).  
4. End of set: „IMU 10 · Pose 9 · Übereinstimmung gut“.  
5. Never put pose count as primary numeral next to IMU without labels.

### 5.5 Tech Improvements

- Keep YUV path; measure FPS before native rewrite.  
- Improve `armConfidence` already real — use it to gate badges.  
- Occlusion: freeze last skeleton with opacity, don't invent limbs.  
- Privacy: landmark files opt-in; clear copy; auto-delete after share.  
- Future: side-view curl framing guide (2D angle most informative).

### 5.6 Vision Roadmap

| When | What |
|------|------|
| Now | Branding Form-Check; copy; agreement only |
| +30d | Optional during-set badge when camera already on |
| +60d | Disagreement → correction prompt hint (not auto) |
| +90d | Multi-exercise angle configs; not counting authority |

---

## 6. Deep Dive: UI/UX Polish

### 6.1 Journeys

**First run**
1. Connect M5 → battery visible  
2. Placement tutorial  
3. Guided calib 5 reps known count  
4. Auto-arm counting (C-01)  
5. First set → end → correction → learn  

**Daily train**
1. Auto-reconnect  
2. Profile load  
3. BtnA start → curls → BtnA end → confirm → rest timer  
4. End session summary  

**Bad count recovery**
1. Correction ±  
2. Learn  
3. If 3 undercounts: suggest re-calib / health check  

### 6.2 Top UI Issues (ranked)

1. No full-screen **Active Set** mode  
2. Counting gate not screamingly obvious  
3. Debug density on Home  
4. Parallel status concepts  
5. Ghost OK button noop  
6. Camera mental model  
7. Exercise suggestion card competes with set focus  
8. Design tokens / visual hierarchy weak  
9. History/trends not part of motivation loop  
10. Accessibility: big buttons good; contrast in banners mixed  

### 6.3 Gym-Mode Principles

- One-hand, glanceable, sweaty: **min 56dp** primary actions (already).  
- Number > everything (96–120sp during set).  
- Max 2 actions during set: End Set, Pause/Stop.  
- Haptics on rep (existing feedback) preferred over sound in gym.  
- Errors as banners, not dialogs, while counting.  

### 6.4 Two Tracks

**Minimal polish pack (1–2 weeks)**  
Active Set layout · Status chip · Collapse debug · Ghost dismiss · Form-Check rename · Correction toast  

**Ambitious redesign (optional later)**  
Design system · Motion · Onboarding reels · History insights · Dark gym theme  

---

## 7. Cross-Cutting

### Architecture
- Keep domain purity (vision doesn't mutate engine) — good.  
- Split EngineNotifier when reliability work stabilizes.  
- Avoid enabling new pipeline without harness.

### Tests
- Strength: unit gates, structural product path.  
- Gap: labeled HW CSVs in CI; integration BLE mock timing; golden gP signs.

### Firmware / BLE
- v2 scale, fee4 events, battery voltage map: mature.  
- Rename GymTracker; document advertise name in setup.  
- Continue stale IMU detection (already in FW debug).

### Data / Security
- Drift encryption path exists — verify migration on upgrade still tested.  
- Export/share: ensure no accidental landmark share without intent.

### Docs / DX
- Excellent living docs; reduce contradictory status in old research.  
- This audit should be linked from `docs/README.md` and `13_OFFENE_PUNKTE`.

### Tools
- Keep Python lab; ensure coefficients match Dart constants.  
- Webcam tool = lab, not product dependency.

### Release
- RC ok for closed beta.  
- Store listing/privacy still out of scope (C2/C4).  
- iOS not a product target yet — keep honest.

---

## 8. Was fehlt für eine polished Version?

### Definition of Done — Polished v1.x

| Bereich | DoD |
|---------|-----|
| **Reliability** | 20+ labeled curl sets: ≥80% \|Δ\|≤1; wiggle FP≤1/set; slow set documented |
| **Trust** | User always knows BEREIT/ZÄHLT/PAUSE; 0-rep mystery eliminated |
| **Onboarding** | Connect → place → calib → first counted set without docs |
| **Hardware** | Reconnect, battery, BtnA, 15-min session smoke |
| **Vision** | Clear Form-Check value; no false counting expectations |
| **UI** | Active Set HUD; debug collapsed; ghost UX fixed |
| **Observability** | Set quality + optional diagnose; CSV export for support |
| **Edge states** | Permission denied, no device, bad gyro, packet loss all have copy |
| **Perf/Battery** | Phone + M5 last full workout without thermal panic |
| **Docs** | One page „How counting works“ for humans |
| **Release hygiene** | Changelog, version, no force-push, tests green |

### Fehlt explizit (noch)

- [ ] Formale A1–A5 Abschlusszahlen  
- [ ] Sensor-Health UX  
- [ ] Active Set UI mode  
- [ ] Golden CSV CI  
- [ ] Vision product narrative  
- [ ] Shadow pipeline DoD (before any flip)  
- [ ] Design tokens / visual polish  
- [ ] Multi-exercise real validation (beyond registry)  
- [ ] Store assets / privacy final (when targeting store)

---

## 9. Priorisierte Roadmap

### 30 Tage — Reliability & Trust

| Priority | Item | Why | Effort | Depends | Success metric |
|----------|------|-----|--------|---------|----------------|
| P0 | Close A1–A5 4 checks + document | Release honesty | S | Operator | Doc 13 [x] |
| P0 | Counting state chip + auto-arm after calib | Fix 0-rep UX | S | — | No silent 0 after calib |
| P0 | Sensor health (gyro rest) banner | Fix dead gP | M | BLE samples | Anomaly caught |
| P0 | Feature freeze non-counting | Focus | — | Team | No new FR-noise |
| P1 | Labeled 20-set counting report | Ground truth | S–M | HW | Table in docs/hardware |
| P1 | Active Set minimal UI | Polish + trust | M | — | Glance test pass |
| P1 | Form-Check copy + agreement only | Vision honesty | S | — | User survey 5/5 understand |

### 60 Tage — Harden Counting

| Priority | Item | Why | Effort | Depends | Success metric |
|----------|------|-----|--------|---------|----------------|
| P1 | Slow-rep searchback / within-set adapt | Fatigue undercount | M | Metrics | Slow sets ±1 |
| P1 | Placement energy monitor | Re-mount | M | gP | Prompt re-calib |
| P1 | Golden CSV CI replay | Regression | M | Corpus | CI fails on break |
| P1 | Set quality score on summary | Trust | S | Loss+gates | Shown on end set |
| P2 | Collapse debug / design tokens light | Polish | M | — | Cleaner screenshots |

### 90 Tage — Pipeline Decision & Depth

| Priority | Item | Why | Effort | Depends | Success metric |
|----------|------|-----|--------|---------|----------------|
| P2 | Shadow ExerciseEngine DoD | Future path | L | CSVs | Diff report |
| P2 | Optional during-set vision badge | Value | M | Form-Check | Opt-in usage |
| P2 | Multi-exercise validation plan | Growth | M | Profiles | 2nd exercise ±1 |
| P3 | G7 decision `_useNewPipeline` | Architecture | L | Shadow | ADR go/no-go |

---

## 10. Quick Wins (≤ 1–2 Tage je)

1. **Status-Chip** BEREIT/ZÄHLT/GHOST auf Home.  
2. **Auto-start counting** nach erfolgreicher Calib (Settings-toggle default on).  
3. Ghost-Banner **echter Dismiss**.  
4. Camera tooltip/title → **Form-Check** + 3-Zeilen Disclaimer.  
5. Nach Correction: Snackbar **„Gespeichert — Schwelle angepasst“**.  
6. Diagnose default **collapsed** in non-settings path.  
7. Doc 13 formal abhaken sobald 4 Checks da.  
8. Link dieses Audits in `docs/README.md`.  
9. Set-Summary: zeige **Engine-Reps vs. korrigierte** klar.  
10. Wenn `!isCountingActive` und Bewegung: dezent **„Tippe Zählen starten“**.

---

## 11. Do-Not-Do List

1. **`_useNewPipeline = true` ohne Shadow-DoD** — bricht Vertrauen.  
2. **Vision silent override von IMU counts** — Gym-Okklusion = Unterzählung.  
3. **`correctedReps` → `countedReps` mergen** — Audit-Trail tot.  
4. **Threshold-Tuning ohne labeled sets** — endloses Ratespiel.  
5. **Rewrite Engine in one PR** — zu riskant.  
6. **DL/TFLite exercise classifier als Zähler** — falsche Schicht.  
7. **Mehr Features (Doc 15 style) vor Reliability-DoD** — polish debt.  
8. **Force-Push main**.  
9. **Claim „99 % Genauigkeit“** ohne Corpus — Docs/Research nicht als Marketing.  
10. **Auto-end set wieder an** ohne User-Opt-in — Product decision bewusst manual.

---

## 12. Offene Fragen an den Product Owner

1. Ist **Curl-only** für polished v1.x ok, oder muss Übung #2 (z. B. Lateral Raise) mit rein?  
2. Soll **Auto-Start Zählen** nach Calib Default sein?  
3. Ist **Form-Check** nice-to-have oder Teil der Kernstory für Beta-User?  
4. Welches Fehlerbild ist schlimmer: **Überzählen** oder **Unterzählen**? (Policy)  
5. Sollen **Partials** zählen (ROM-Policy)?  
6. Zielplattform Beta: nur dein Phone+M5, oder fremde Android-Geräte?  
7. Dürfen wir **labeled CSVs** deiner Sessions im Repo (anonym) für CI speichern?  
8. Ghost: lieber nie pausieren im Gym, oder Schutz vor Ablegen behalten?  
9. Polished UI: **minimal dark gym** oder **bright consumer fitness**?  
10. Nächstes Ziel: **geschlossene Beta** oder **Play Store** (ändert Privacy/Polish scope)?

---

## Appendix A — Code-Hotspots

| Path | Why |
|------|-----|
| `app/lib/domain/workout_engine.dart` | Product counting truth |
| `app/lib/domain/filters/gp_projection.dart` | gP math |
| `app/lib/domain/metrics/ghost_rep_gate.dart` | Idle pause |
| `app/lib/domain/exercise_engine.dart` | Future pipeline |
| `app/lib/domain/detection/*` | New pipeline pieces |
| `app/lib/domain/vision/*` | Pose + fusion |
| `app/lib/presentation/providers/engine_provider.dart` | Gating, BtnA, lifecycle |
| `app/lib/presentation/screens/home_screen.dart` | Main UX |
| `app/lib/presentation/screens/camera_session_screen.dart` | Vision UX |
| `app/lib/data/providers/ble_sensor_provider.dart` | Stream honesty |
| `app/lib/data/protocol/ble_protocol_parser.dart` | Wire format |
| `firmware/src/main.cpp` | Sample rate, events, scales |
| `docs/reference/protocol.yaml` | Contract |
| `docs/design/RECHERCHE_ZAEHLROBUSTHEIT.md` | Algo research (re-verify status) |
| `docs/hardware/sessions/2026-07-24/*` | Live failure evidence |
| `tools/workout_engine_simulation.py` | Offline proofs |

## Appendix B — Research Anchors (für Follow-ups)

- MM-Fit (UbiComp 2020) — offline peak + autocorr  
- Pan-Tompkins family — refractory + dual thresholds  
- Complementary filter curl literature (PMC8877759 et al.) — angle path  
- Survey wearable rep counting arXiv:2308.02420 — classical still strong  
- Internal: `RECHERCHE_99_PROZENT_GENAUIGKEIT.md`, `RECHERCHE_ZAEHLROBUSTHEIT.md`, Doc 15 external repos  

## Appendix C — Experiment Designs

### E1 Counting Accuracy
- 10 sets × 10 curls normal tempo, manual count video  
- Record CSV + app counted + corrected  
- Compute MAE, %±1  

### E2 Wiggle
- 30s wrist shake + 30s device on table  
- Expect 0–1 commits with ghost on  

### E3 Slow Fatigue
- 8 curls @ ~3s concentric  
- Compare vs normal θ  

### E4 Placement
- Calib → 1 set OK → rotate strap 30° → 1 set  
- Expect detection of low energy / undercount  

### E5 Vision Agreement
- Same set with camera Form-Check  
- Log IMU vs Pose counts; no product change  

---

## Appendix D — Gesamturteil

FlowRep hat die **schwierige halbe Meile** schon hinter sich: echte Hardware, ehrliche Constraints, gP statt naivem Magnitude-Count, Calib, Correction-Learn, Tests, Docs. Die **zweite halbe Meile** zur polished, vertrauenswürdigen App ist:

1. **Messen statt featureshippen**,  
2. **mental model wasserdicht** (wann zählt die App),  
3. **Sensor-Gesundheit + langsame Reps**,  
4. **Gym-HUD statt Feature-Scroll**,  
5. **Vision als Form-Check, nicht als Zähler-Mythos**.

Wenn P0 aus Abschnitt 9 erledigt ist, ist FlowRep ein glaubwürdiges **Curl-Tracking-Produkt**. Alles andere ist Verstärkung, kein Fundament.

---

*Ende des Audits. Nächster sinnvoller Schritt: Operator schließt die 4 A1–A5 Kurzchecks; parallel Quick Wins C-01/U-03/U-04/V-01 Copy umsetzen.*

---

## Appendix E — Quick Wins Implementierung (2026-07-24)

Umgesetzt und getestet (siehe `app/test/quick_wins_audit_test.dart`):

| QW | Item | Status | Evidence |
|----|------|--------|----------|
| 1 | Status-Chip BEREIT/ZÄHLT/GHOST | **done** | `counting_status_chip.dart` + Home |
| 2 | Auto-Arm nach Calib (default on) | **done** | `reloadCalibration` → `startCounting`; Settings toggle |
| 3 | Ghost-Banner echter Dismiss | **done** | `dismissGhostBanner` + `ghostBannerDismissed` |
| 4 | Form-Check Rename + 3-Zeilen Disclaimer | **done** | Camera session + Settings + Home tooltip |
| 5 | Correction Snackbar Schwelle | **done** | `confirmCorrection` → `String?` message |
| 6 | Diagnose collapsed | **done** | `SignalDebugView` ExpansionTile |
| 8 | Audit in docs/README | **done** | earlier |
| 9 | Session Summary Engine vs korrigiert | **done** | `SessionSummaryDialog` |
| 10 | „Tippe Zählen starten“ | **done** | Home when `hasCalibration && !counting` |
| 7 | Doc 13 A1–A5 formal [x] | **offen** | braucht Operator-Zahlen |

**Nicht** angefasst: `_useNewPipeline`, Vision-Counts, θ-Algorithmen.

---

## Appendix F — Agent follow-up (2026-07-24, code-only)

Implemented without physical HW:

| Item | Status | Evidence |
|------|--------|----------|
| Sensor health (gyro rest anomaly) | **done** | `sensor_health_monitor.dart` + banners; samples evaluated even when not counting |
| Placement / weak-gP while moving | **done** | `placement_energy_monitor.dart` + amber banner |
| Set quality score | **done** | `set_quality_score.dart`; summary + last-set label |
| Active Set HUD | **done** | `home_screen` splits setup vs counting |
| Tests | **done** | `sensor_health_and_quality_test.dart` |

Still operator-only: formal A1–A5 numbers, labeled 20-set corpus, Shadow G7.

---

## Appendix G — Slow-rep searchback shadow (2026-07-24)

**Lightest algorithmic next step** after code-only trust UX.

| | |
|--|--|
| **What** | When product gP rejects an excursion (`peak < 1.2×θ` or short), a relaxed rule (`peak ≥ 0.85×θ`, samples ≥ 10) may flag a **shadow** slow-rep |
| **What not** | Never calls `_commitRep`; no change to live `countedReps` |
| **Why** | Measure undercount risk on slow/fatigued curls before promoting searchback to product |
| **Code** | `domain/metrics/slow_rep_shadow.dart`, hook in `WorkoutEngine._detectPeakSigned` |
| **UI** | Diagnose overlay: `slowShadow=N` |
| **Tests** | `app/test/slow_rep_shadow_test.dart` |
| **Promote to live?** | Only after labeled HW sets show shadow ≈ true missed reps and low false shadow on wiggles |

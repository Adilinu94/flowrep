# FlowRep 1.0 — Implementierungsstatus (Living Tracker)

> **Stand**: 2026-07-23  
> **Commit-Basis**: siehe `git log` / `origin/main`  
> **Zweck**: ehrlicher Ledger — erledigt vs. offen. Kein „alles grün“ ohne Evidence.

Siehe auch: [00_UEBERSICHT](00_UEBERSICHT.md) · [10_RELEASE](10_RELEASE_VORBEREITUNG.md) · [11_HARDWARE_QA](11_HARDWARE_QA_CHECKLISTE.md) · [13_OFFENE_PUNKTE](13_OFFENE_PUNKTE.md) · [15_POST_1.0_BACKLOG](15_VERBESSERUNGEN_EXTERNE_REPOS.md) · [HW_VALIDATION](../hardware/sessions/2026-07-23/HW_VALIDATION.md)

---

## Legende

| Symbol | Bedeutung |
|--------|-----------|
| `[x]` | im Code + Tests (ggf. HW-Evidence) |
| `[~]` | Code da, volle Geräte-Bewegung noch offen |
| `[ ]` | offen / nicht freigegeben |

---

## P0 — Release-Blocker

| ID | Feature | Code | Unit/Widget | HW E2E | Notes |
|----|---------|------|-------------|--------|-------|
| P0-1 | Korrektur-UI (+/−, Speichern & lernen) | [x] | [x] | [~] | `CorrectionDialog`; `confirmCorrection` → `CorrectionEvent` + θ-nudge |
| P0-2 | Pausen-Timer 90s | [x] | [x] | [~] | nach Korrektur |
| P0-3 | Session-Beenden + Summary | [x] | [x] | [~] | „Training beenden“ |
| P0-4 | BLE Reconnection | [x] | [x] | [x] | BT off/on 2026-07-23 |
| P0-5 | Foreground Service | [x] | — | [x] | Screen-Lock 20s, Batches weiter |

---

## P1 — Qualität

| ID | Feature | Status |
|----|---------|--------|
| P1-1 | Global Error Handler | [x] |
| P1-2 | App-Lifecycle | [x] |
| P1-3 | Settings-Screen | [x] |
| P1-4 | iOS-Konfiguration | [x] (plist; Geräte-iOS separat) |
| P1-5 | Sound-Asset | [x] |
| P1-6 | App-Icon + Splash | [x] |
| P1-7 | Widget-Tests | [x] (≥10) |
| P1-8 | CI/CD | [x] |

---

## P2 — Polish

| ID | Feature | Status |
|----|---------|--------|
| P2-1 … P2-7 | Dark Mode … Logging | [x] (siehe 00_UEBERSICHT) |

---

## Produkt: manuelles Satzende + Lernen (User-Feedback 2026-07-23)

| Check | Status | Evidence |
|-------|--------|----------|
| `autoEndSetEnabled: false` in Product (`main.dart`) | [x] | Engine endet Satz **nicht** nach Stille |
| UI „Satz beenden“ | [x] | `home_screen.dart` → `endSetManually` |
| Nach Satzende Korrektur-Dialog (echte Reps) | [x] | `showCorrectionForLastSet` on `completedSet` |
| `countedReps` unverändert; nur `correctedReps` | [x] | Spec + `correction_test.dart` |
| CorrectionEvent persistiert | [x] | Drift `saveCorrection` |
| Rule-based Lernen (θ-nudge + Profile save) | [x] | `_learnFromCorrection` / `nudgeDirectionAwareThreshold` |
| Keine Copy „Die KI lernt dazu“ | [x] | „Speichern & lernen“ / Dankestext |
| Auto-„Satz abgeschlossen“ | [x] abgeschaltet | Timeout-Pfad nur wenn `autoEndSetEnabled` |

---

## Engine / Zählqualität (gP)

| Check | Status | Notes |
|-------|--------|-------|
| gP-Profil autoritativ (`ChosenSignal.gP`) | [x] | Combined-Sentinel 999 gegen 1.2g-Fallback |
| θ-Floor + Ratio | [x] | `max(50, theta×0.70)` (Härtung gegen Wackeln) |
| Excursion-Dauer-Gate | [x] | `_minGpSamplesAbove` ≥ 15 (~300 ms @50 Hz) |
| Peak-Amplitude-Gate in Excursion | [x] | Peak ≥ 1.2×θ |
| Kurze/kleine Wiggles zählen nicht | [x] Unit | `tool_count_sim_test.dart` |
| Echte Curl-Form zählt | [x] Unit | sin-Excursion ~800 ms, Peak ≥100 °/s |
| HW: Wackeln vs. Curl am Arm | [~] | physisch offen / User-Retest |
| `_useNewPipeline` | **false** | G7 — nicht freigeben ohne Shadow-DoD |

---

## CV-Track (optional, nicht release-blockierend)

| ID | Status |
|----|--------|
| CV-01 … CV-06 + UI | [x] Code/Docs; Geräte-Webcam/Emulator manuell optional |
| CV-07 Skelett-Overlay | [x] Code A–F: Painter, Session, E1–E7/E9/E10; E8 out; Geräte-QA [~] |
| D2 Pose-Confidence | [x] `armConfidence`/`primaryElbow` → fusion; kein Live-Placeholder `0.8` |
| D1 NPU soft-fail | [x] Code; physische Live-Session [~] |
| D5 YUV path | [~] yuv420 an Detector; native RGB-Opt deferred |
| D6 Skelett-Overlay | [x] Code; physisch optional — Doc 14 |

---

## Builds / Qualitätstore

| Check | Status | Stand |
|-------|--------|-------|
| `flutter analyze lib` | [x] | 0 issues (2026-07-23, optional-goal final) |
| `flutter test` | [x] | 405 green (CV-07 skeleton + E9 file sink + no-pose frames) |
| `flutter build apk --release` | [x] | ~108 MB; TFLite AGP9-Workaround |
| Force-Push / Test-Abschwächung | verboten | siehe 00_UEBERSICHT |

---

## Offene 1.0-Punkte (ehrlich)

> Vollständige Liste mit Prioritäten A–D: **[13_OFFENE_PUNKTE.md](13_OFFENE_PUNKTE.md)**.  
> Session 2026-07-24: [HW_SESSION_A1_A5.md](../hardware/sessions/2026-07-24/HW_SESSION_A1_A5.md).

1. **[~]** Volle physische Session — Calib/Zählen/BtnA-Satzende belegt; **noch** Learn + Training beenden + Curl-Zahlen notieren  
2. **[~]** Wiggle am Gerät — Unit + Ghost 45s; **noch** 5–10 s bewusster Wackel-Test  
3. **[~]** G5/G6 am Gerät (Motion); G7 Pipeline **false**  
4. Optional: CV physisch (Preview/Pose [x] Session; Webcam nicht nötig)  
5. Store/Admin: C1/C2/C4 out of scope; **C3** `v1.0.0-rc.1` erledigt

---

## Post-1.0 Backlog (Doc 15) — nicht 1.0-DoD

> Details + Matrix: **[15_VERBESSERUNGEN_EXTERNE_REPOS.md](15_VERBESSERUNGEN_EXTERNE_REPOS.md)**.

| Phase | Fokus | Code 2026-07-24 |
|-------|--------|-----------------|
| **V1.1** | B10, B6, B2, A1 light, A2 | **[x]** implementiert |
| **V1.2** | B1/B3/B7, Shadow, … | **[x]** größtenteils |
| **V2.0** | History-Trends, A5/A8/A9, A4 heuristic | **[~]** Trends+domain; TFLite offen |
| **V3.0** | LLM / Teachable-Presets | **[~]** RuleCoaching offline; A10 offen |

**Gate:** physische Doc-13 A1–A5 **[~]** (4 Kurzchecks) — Feature-Code blockiert Release nicht.

---

## Changelog dieses Trackers

| Datum | Änderung |
|-------|----------|
| 2026-07-24 | Audit follow-up: SensorHealth, Placement, SetQuality, Active-Set HUD — App. F |
| 2026-07-24 | Audit Quick Wins (Status-Chip, Auto-Arm, Form-Check, Ghost dismiss, …) — `AUDIT_FULL_REPO_IMPROVEMENTS.md` App. E |
| 2026-07-24 | A1–A5 Session partial; BtnA/Ghost/Kamera; Rest-Checkliste 4 Punkte |
| 2026-07-23 | Post-1.0 Abschnitt Doc 15 (V1.1 schlank, A2 DONE, Already) |
| 2026-07-23 | Optional-goal final: 375 tests, C3 tag, B*/D* living status |
| 2026-07-23 | CV-07: 401+ tests; no-pose stream + FileLandmarkSink; CHANGELOG entry |
| 2026-07-23 | D2 echte Confidence + Tests; D1/D5 Status |
| 2026-07-23 | Tracker angelegt aus 00 + HW_VALIDATION + Product-Fixes (manual end, learn, gP harden) |
| 2026-07-23 | gP-Härtung: floor 50, 0.70×θ, minSamples 15, peak≥1.2×θ; Tests `tool_count_sim` + `product_path_structural`; Suite 369 grün (`08f98c6`) |

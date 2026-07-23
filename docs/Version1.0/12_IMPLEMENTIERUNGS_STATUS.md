# FlowRep 1.0 — Implementierungsstatus (Living Tracker)

> **Stand**: 2026-07-23  
> **Commit-Basis**: siehe `git log` / `origin/main`  
> **Zweck**: ehrlicher Ledger — erledigt vs. offen. Kein „alles grün“ ohne Evidence.

Siehe auch: [00_UEBERSICHT](00_UEBERSICHT.md) · [10_RELEASE](10_RELEASE_VORBEREITUNG.md) · [11_HARDWARE_QA](11_HARDWARE_QA_CHECKLISTE.md) · [HW_VALIDATION](HW_VALIDATION_2026-07-23.md)

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

---

## Builds / Qualitätstore

| Check | Status | Stand |
|-------|--------|-------|
| `flutter analyze lib` | [x] | 0 issues (2026-07-23) |
| `flutter test` | [x] | grün (siehe CI / lokale Runs) |
| `flutter build apk --release` | [x] | ~108 MB; TFLite AGP9-Workaround |
| Force-Push / Test-Abschwächung | verboten | siehe 00_UEBERSICHT |

---

## Offene 1.0-Punkte (ehrlich)

1. **[ ]** Volle physische Session: Kalibrieren → Zählen (Curls) → **Satz beenden** → echte Reps eingeben → Training beenden  
2. **[~]** Wiggle-Resistenz am Gerät (Unit grün; User meldete Rest-Wackeln → weitere Gates gelandet, HW-Retest)  
3. **[ ]** Phase E–H Hardware-Protokoll (Zähl-DoD G5/G6, Shadow G7) — siehe Doc 11  
4. Optional: CSV-Export Kalibrier-Puffer, Webcam-Live-Session

---

## Changelog dieses Trackers

| Datum | Änderung |
|-------|----------|
| 2026-07-23 | Tracker angelegt aus 00 + HW_VALIDATION + Product-Fixes (manual end, learn, gP harden) |
| 2026-07-23 | gP-Härtung: floor 50, 0.70×θ, minSamples 15, peak≥1.2×θ; Tests `tool_count_sim` + `product_path_structural`; Suite 369 grün (`08f98c6`) |

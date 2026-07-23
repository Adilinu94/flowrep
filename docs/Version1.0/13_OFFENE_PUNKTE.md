# FlowRep 1.0 — Offene Punkte (konsolidiert)

> **Stand**: 2026-07-23 (optional-goal final)  
> **Git**: `main` = `origin/main`; RC-Tag `v1.0.0-rc.1`  
> **Zweck**: eine Seite für „was ist fertig / was steht noch aus“ aus dem gesamten Ordner `docs/Version1.0/`.  
> **Quellen**: 00, 10, 11, 12, HW_VALIDATION, 01–09 (Implementierungspläne), Product-Code-Stand.  
> **Dieses Ziel**: alle Optionals außer C1/C2/C4; B5 bleibt off; Motion-B* ehrlich env-deferred.

---

## 0. Repo / Commit-Status (diese Session)

| Check | Status |
|-------|--------|
| Feature-Code (P0–P2, CV-Scaffold, manual set end, correction learn, gP harden) | **committed + pushed** |
| Living Tracker 10 / 11 / 12 | **committed + pushed** |
| Untracked nur: `data/`, `app/android/build/`, `*.log` | **bewusst nicht im Repo** (gitignore / Artefakte) |
| Force-Push | verboten — nicht genutzt |
| `_useNewPipeline` | bleibt **`false`** |

**Kein ausstehender Code-Commit** für die 1.0-Codepfade, die in 00/12 als erledigt markiert sind. Offen ist vor allem **physische Validierung + Store-Admin**.

---

## 1. Priorität A — Release-Blocker (physisch am Gerät)

Ohne diese Schritte kein Store-/RC-„fertig“. Code+UI sind da; Evidence fehlt.

| # | Punkt | Doc-Ref | Status |
|---|--------|---------|--------|
| A1 | **Volle Session**: Kalibrieren → Zählen (echte Curls) → **Satz beenden** → echte Reps im Korrektur-Dialog → **Training beenden** | 00 DoD, 11 Kern-Pfad, 12 §Offen, HW_VALIDATION | **[ ] offen** |
| A2 | **Zählen E1**: 8–12 Curls → Anzeige plausibel | 11 E1 | **[ ]** |
| A3 | **Wackeln E2**: Alltags-/Wackelbewegung → keine wilden Falsch-Reps | 11 E2, 10 §5.4, 12 Wiggle HW | **[ ]** (Unit grün; User-HW-Retest nach Härtung) |
| A4 | **E3–E5**: Satz beenden → Korrektur („Speichern & lernen“) → Session-Ende/Summary | 11 E3–E5 | **[ ]** |
| A5 | Pre-Release-Smoke §5 Punkte 3–4 grün | 10_RELEASE | **[ ]** → blockiert finalen RC |

### Empfohlener manueller Ablauf (Adi + Phone + M5)

1. App installieren (Debug-APK), BLE verbinden.  
2. Guided Calib durchlaufen (Profil gP speichern).  
3. **Zählen starten** → 8–12 echte Bizeps-Curls.  
4. **Nicht** auf Auto-Ende warten → **„Satz beenden“**.  
5. Im Dialog echte Anzahl einstellen → **„Speichern & lernen“**.  
6. Optional Pause / zweiter Satz.  
7. **„Training beenden“** → Summary prüfen.  
8. Kurz wackeln (kein Curl) und prüfen: Zähler bleibt stabil.  
9. Ergebnis in `11_HARDWARE_QA_CHECKLISTE.md` und hier abhaken + kurzer Log/Screenshot-Hinweis.

---

## 2. Priorität B — Hardware-QA Rest (nicht immer Store-Blocker)

> Env-Probe 2026-07-23: Phone online (`55j7xkiffixsyhxg`), App installiert, kurzer Launch/HOME ohne FATAL; **kein M5/Serial**, **keine Operator-Körperbewegung**. Evidence: `docs/hardware/sessions/2026-07-23/OPTIONAL_HW_ENV_PROBE.md`.

| # | Punkt | Doc-Ref | Status |
|---|--------|---------|--------|
| B1 | C2/C3 optionale Signal-Tests (Drehen/Dummy) | 11 C | **[~]** env-defer: braucht Stream + Handbewegung (Probe: kein M5) |
| B2 | Re-Calib nach Clean-Install dokumentieren | 11 D | **[~]** env-defer: interaktiver Clean-Install + Wizard |
| B3 | App-Hintergrund lang / Lifecycle HW | 11 F | **[~]** Code+Unit; kurzer HOME/Resume-Smoke ohne Crash; Langzeit-HW offen |
| B4 | G5/G6 Curl- vs. Wiggle-DoD am Gerät | 11 G | **[~]** env-defer: Armbewegung + M5 fehlen |
| B5 | G7: `_useNewPipeline = true` freigeben | 11 G, 00 Verbote | **[ ]** — **nicht** ohne Shadow-DoD (bleibt `false`) |
| B6 | G8 Langzeit-Session / Drift | 11 G | **[~]** env-defer: lange Session + Motion |
| B7 | 15‑min Session ohne Crash-Logs | 11 H | **[~]** nur Kurz-Launch-Smoke; 15‑min nicht gelaufen |
| B8 | Volle Gym-Session ohne Tool-Hilfe | 11 H | **[~]** env-defer: menschliche Gym-Session |
| B9 | Guided Calib 5-Reps physisch vollständig (Wizard UI ok) | HW_VALIDATION | **[~]** Wizard Code [x]; physische 5-Reps env-defer |

---

## 3. Priorität C — Release-Admin / Plattform

| # | Punkt | Doc-Ref | Status |
|---|--------|---------|--------|
| C1 | iOS Archive / Geräte-Build | 10 §3 | **[ ]** **out of scope** (dieses Ziel); Labor ohne iOS-Gerät |
| C2 | Play Console / Signing | 10 §3 | **[ ]** **out of scope**; außerhalb Code |
| C3 | Semver-Tag / Changelog-Release | 10 §7 | **[x]** `app` version `1.0.0-rc.1+1`; `CHANGELOG.md`; annotated tag `v1.0.0-rc.1` |
| C4 | Store-Listing / Privacy-Text final | 10 §7 | **[ ]** **out of scope**; DSGVO-Settings im Code vorhanden |

---

## 4. Priorität D — CV-Track (optional, **nicht** 1.0-Release-Blocker)

Code-Scaffold und Unit-Tests sind grün; manuelle Geräte-/Webcam-Checks bleiben teilweise offen.

| # | Punkt | Doc-Ref | Status |
|---|--------|---------|--------|
| D1 | Live-Kamera-Anbindung Pose Detector (NPU) auf Gerät | 05/06, soft-fail | **[x]** Code: `NpuPoseDetector` + Image-Stream + soft-fail; **[~]** physische NPU-Session am Gerät optional |
| D2 | Echte Pose-Confidence (statt Placeholder) | 07, mapper | **[x]** `PoseFrameMapper.armConfidence` / `primaryElbow` aus Landmark-Visibility; Live-UI ohne `0.8`-Placeholder; Unit + structural |
| D3 | Manuelle Webcam-Session (Python-Tool) | 08 Checkliste | **[x]** headless 25 Frames (Pipeline OK, pose_frames=0 ohne Person); pure logic 4/4; MediaPipe Tasks + `--headless/--max-frames` |
| D4 | Android-Emulator Kamera-Checkliste (Doc 09) | 09 | **[~]** env-defer: kein AVD konfiguriert; Soft-fail 0-Kamera Unit grün |
| D5 | Native YUV→RGB Performance | 06 TODO(cv-opt) | **[~]** deferred: Dart-Pfad sendet bereits `yuv420`-Planes an Detector (kein RGB-Zwischenweg); native Opt nur bei FPS-Mangel |
| D6 | **Skelett-Overlay** + E1–E7, E9, E10 (ohne E8 Blur) | [14_CV_SKELETT_OVERLAY_PLAN](14_CV_SKELETT_OVERLAY_PLAN.md) | **[x]** Code A–F; Unit/Widget grün; **[~]** physische Kamera-Session optional; **E8 out** |

---

## 5. Was **fertig** ist (Kurz — nicht erneut bauen)

Aus 00 / 12 / HW_VALIDATION / Code:

| Bereich | Status |
|---------|--------|
| P0-1 … P0-5 (Korrektur, Rest-Timer, Session-Ende, Reconnect, FGS) | Code + Unit/Widget; HW teilweise [~] |
| P1-1 … P1-8 | [x] |
| P2-1 … P2-7 | [x] |
| CV-01…06 + UI Soft-fail | [x] Code/Docs |
| `autoEndSetEnabled: false` + UI „Satz beenden“ | [x] Product |
| CorrectionEvent + `correctedReps` (countedReps unverändert) | [x] |
| Rule-based Lernen (θ-nudge + Profil persist) | [x] |
| gP-Härtung (floor 50, 0.70×θ, Dauer, Peak≥1.2×θ) | [x] + Unit |
| BLE Connect/Stream, Screen-Lock FGS, BT-Reconnect, Dark Mode | [x] HW 2026-07-23 |
| Calib-Profil gP θ≈87.2 q≈0.95 | [x] Session-Analyse |
| `flutter analyze lib` 0 / `flutter test` grün / Release-APK | [x] |
| Gyro-Gate / keine TODO(hardware) | [x] |

---

## 6. Datei-Index `docs/Version1.0/`

| Datei | Rolle | Living? |
|-------|-------|---------|
| `00_UEBERSICHT.md` | Überblick, Reihenfolge, DoD, Verbote | ja (Header/DoD) |
| `01`–`03` | Feature-Implementierungspläne P0–P2 | Spec (Code erledigt) |
| `04`–`09` | CV-Pläne / Setup | Spec + optionale Manuell-Checks |
| `10_RELEASE_VORBEREITUNG.md` | Release-Gates | **living** |
| `11_HARDWARE_QA_CHECKLISTE.md` | Phone+M5 QA | **living** |
| `12_IMPLEMENTIERUNGS_STATUS.md` | Ledger Code vs. offen | **living** |
| `13_OFFENE_PUNKTE.md` | **Diese Datei** — konsolidiert | **living** |
| `14_CV_SKELETT_OVERLAY_PLAN.md` | Skelett-Overlay MVP + 10 Ergänzungen | Plan |
| `../hardware/sessions/2026-07-23/HW_VALIDATION.md` | Geräte-Evidence Snapshot | archiviert/session |

---

## 7. Definition „1.0 Release fertig“

1. **A1–A5** physisch abgehakt und in Doc 11 + hier dokumentiert.  
2. `flutter test` + `analyze` grün (bereits).  
3. Release-APK + Tag (C3).  
4. G7 **nicht** erzwingen — Shadow-Pipeline bleibt aus bis eigene DoD.  
5. CV D* optional, blockiert Release nicht.

---

## Changelog

| Datum | Änderung |
|-------|----------|
| 2026-07-23 | B* env-probe + ehrliche Deferrals; D3 headless Webcam; D4 kein AVD |
| 2026-07-23 | C3: Semver `1.0.0-rc.1+1`, CHANGELOG, tag `v1.0.0-rc.1`; C1/C2/C4 out of scope |
| 2026-07-23 | D2: echte Landmark-Confidence live; D1 Code soft-fail [x]; D5 yuv420-Pfad / deferred native |
| 2026-07-23 | D6 **Code DONE**: SkeletonPainter, Session-Wire, E1–E7/E9/E10; E8 out; analyze 0 |
| 2026-07-23 | D6: Plan Scope = MVP + E1–E7/E9/E10 in Phasen A–F; **E8 gestrichen** |
| 2026-07-23 | D6: Plan Skelett-Overlay (`14_CV_SKELETT_OVERLAY_PLAN.md`) angelegt |
| 2026-07-23 | Erste Konsolidierung aus 00/10/11/12/HW + CV-Docs; Git-Parity bestätigt |

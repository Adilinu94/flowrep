# FlowRep 1.0 — Offene Punkte (konsolidiert)

> **Stand**: 2026-07-23  
> **Git**: `main` = `origin/main` (siehe `git rev-parse HEAD origin/main`)  
> **Zweck**: eine Seite für „was ist fertig / was steht noch aus“ aus dem gesamten Ordner `docs/Version1.0/`.  
> **Quellen**: 00, 10, 11, 12, HW_VALIDATION, 01–09 (Implementierungspläne), Product-Code-Stand.

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

| # | Punkt | Doc-Ref | Status |
|---|--------|---------|--------|
| B1 | C2/C3 optionale Signal-Tests (Drehen/Dummy) | 11 C | **[ ]** optional |
| B2 | Re-Calib nach Clean-Install dokumentieren | 11 D | **[ ]** optional |
| B3 | App-Hintergrund lang / Lifecycle HW | 11 F | **[~]** Code da |
| B4 | G5/G6 Curl- vs. Wiggle-DoD am Gerät | 11 G | **[ ]** |
| B5 | G7: `_useNewPipeline = true` freigeben | 11 G, 00 Verbote | **[ ]** — **nicht** ohne Shadow-DoD |
| B6 | G8 Langzeit-Session / Drift | 11 G | **[ ]** |
| B7 | 15‑min Session ohne Crash-Logs | 11 H | **[ ]** |
| B8 | Volle Gym-Session ohne Tool-Hilfe | 11 H | **[ ]** |
| B9 | Guided Calib 5-Reps physisch vollständig (Wizard UI ok) | HW_VALIDATION | **[~]** partial |

---

## 3. Priorität C — Release-Admin / Plattform

| # | Punkt | Doc-Ref | Status |
|---|--------|---------|--------|
| C1 | iOS Archive / Geräte-Build | 10 §3 | **[ ]** Labor ohne iOS-Gerät |
| C2 | Play Console / Signing | 10 §3 | **[ ]** außerhalb Code |
| C3 | Semver-Tag / Changelog-Release | 10 §7 | **[ ]** |
| C4 | Store-Listing / Privacy-Text final | 10 §7 | **[ ]** (DSGVO-Settings im Code vorhanden) |

---

## 4. Priorität D — CV-Track (optional, **nicht** 1.0-Release-Blocker)

Code-Scaffold und Unit-Tests sind grün; manuelle Geräte-/Webcam-Checks bleiben offen.

| # | Punkt | Doc-Ref | Status |
|---|--------|---------|--------|
| D1 | Live-Kamera-Anbindung Pose Detector (NPU) auf Gerät | 05/06 TODO(cv-06), 00 CV-03 | **[~]** optional |
| D2 | Echte Pose-Confidence (statt Placeholder) | 07 TODO | **[~]** optional |
| D3 | Manuelle Webcam-Session (Python-Tool) | 08 Checkliste | **[ ]** optional |
| D4 | Android-Emulator Kamera-Checkliste (Doc 09) | 09 | **[ ]** optional Setup |
| D5 | Native YUV→RGB Performance | 06 TODO(cv-opt) | **[ ]** later |

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
| `HW_VALIDATION_2026-07-23.md` | Geräte-Evidence Snapshot | archiviert/session |

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
| 2026-07-23 | Erste Konsolidierung aus 00/10/11/12/HW + CV-Docs; Git-Parity bestätigt |

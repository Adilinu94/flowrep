# FlowRep 1.0 — Release-Vorbereitung

> **Stand**: 2026-07-23  
> **Regel**: Checkbox nur mit Evidence. Kein Force-Push. Kein `_useNewPipeline = true` ohne G7.

Verwandt: [12_IMPLEMENTIERUNGS_STATUS](12_IMPLEMENTIERUNGS_STATUS.md) · [11_HARDWARE_QA](11_HARDWARE_QA_CHECKLISTE.md) · [00_UEBERSICHT](00_UEBERSICHT.md)

---

## 1. Feature-Freeze Check

| Bereich | Status |
|---------|--------|
| P0-1 … P0-5 | [x] Code + Tests; HW teilweise [~] |
| P1-1 … P1-8 | [x] |
| P2-1 … P2-7 | [x] |
| CV-Track | [x] optional; Soft-fail ohne Kamera |
| Manuelles Satzende + Korrektur-Lernen | [x] Product-Default |

---

## 2. Verbotene Aktionen (Release-Gate)

- [x] `_useNewPipeline` bleibt `false` (struktureller Test vorhanden)
- [x] `correctedReps` wird nicht in `countedReps` zurückgeschrieben
- [x] Keine UI-Copy „Die KI lernt dazu“
- [x] Keine abgeschwächten/gelöschten Regressionstests
- [x] Kein Force-Push auf `main`

---

## 3. Build & Analyse

| Schritt | Status | Evidence |
|---------|--------|----------|
| `flutter analyze lib` → 0 | [x] | 2026-07-23 |
| `flutter test` → grün | [x] | 356+; bei jeder Änderung re-run |
| `flutter build apk --debug` | [x] | installiert auf 55j7xkiffixsyhxg |
| `flutter build apk --release` | [x] | ~108.6 MB |
| iOS Archive | [ ] | optional / Gerät fehlt im Labor |
| Play Console / Signing | [ ] | außerhalb Code-Scope |

### Android / TFLite (bekannt)

- Exclude duplicate TFLite packages  
- `minSdk ≥ 31` für pose_detection  
- `jniLibs.pickFirsts` für `.so`

---

## 4. Produkt-Default-Flags

| Flag | Erwartet | Datei |
|------|----------|-------|
| `autoEndSetEnabled` | `false` | `app/lib/main.dart` |
| `_useNewPipeline` | `false` | `workout_engine.dart` |
| Satzende | manuell „Satz beenden“ | `home_screen.dart` |

---

## 5. Pre-Release Hardware Smoke (Minimal)

Kopiert aus Doc 11 — muss **einmal** grün sein vor Store:

1. [x] BLE Connect + Stream  
2. [x] Kalib-Profil speichern (gP) — Session 2026-07-23  
3. [ ] Satz: Curls zählen → Satz beenden → Korrektur → Training beenden  
4. [ ] Wackeln erzeugt keine wilden Falsch-Reps  
5. [x] Screen-Lock Stream  
6. [x] BLE Reconnect  

**Release-Blocker physisch:** Punkte 3–4.

---

## 6. Docs & Repo-Hygiene

| Item | Status |
|------|--------|
| Living Tracker 10/11/12 | [x] angelegt 2026-07-23 |
| 00_UEBERSICHT DoD aktuell | [x] |
| HW_VALIDATION verlinkt | [x] |
| Secrets / `data/` device dumps | [x] gitignored — nicht committen |
| `origin/main` = lokale Feature-Commits | [x] nach Push |

---

## 7. Release-Kandidaten-Checkliste (final)

- [ ] Alle Punkte §5 physisch grün  
- [x] Unit-Suite grün  
- [x] Analyze 0  
- [x] Release-APK gebaut  
- [ ] Changelog / Version-Tag (semver) gesetzt  
- [ ] Store-Listing / Privacy-Text (DSGVO Settings vorhanden)  

**Aktueller RC-Status:** **Code-ready, HW-session-path open** — kein Store-Push bis §5.3–5.4.

---

## Changelog

| Datum | Änderung |
|-------|----------|
| 2026-07-23 | Release-Tracker angelegt; Product-Flags und offener HW-Pfad dokumentiert |

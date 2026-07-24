# FlowRep

BLE/IMU-basiertes automatisches Wiederholungszählen für Krafttraining.  
**Hardware:** M5StickC Plus2 · **App:** Flutter (Android) · **Firmware:** PlatformIO / ESP32

## Aktueller Stand (2026-07-24)

| Bereich | Status |
|---------|--------|
| App P0–P2 + CV + Trust-UX + Settings-Persistenz | Code auf `main` / `origin/main` |
| BLE + IMU Streaming | Hardware-verifiziert |
| Guided Calibration 2.0 (gP-Profil) | Hardware-Session OK |
| Manuelles „Satz beenden“ + Korrektur-Lernen | Product-Default |
| Audit Quick Wins + Follow-ups | Status-Chip, Auto-Arm, Health/Placement/Quality, Shadow, Dual-BLE, Agreement-Badge, Prefs |
| Volle Gym-Session formal (A1–A5) | **[~]** noch 4 Kurzchecks — siehe HW-Plan |
| Shadow / `_useNewPipeline` | bleibt **false** |
| RC-Tag | `v1.0.0-rc.1` |

**Living Docs**

| Doc | Zweck |
|-----|--------|
| [`docs/Version1.0/13_OFFENE_PUNKTE.md`](docs/Version1.0/13_OFFENE_PUNKTE.md) | Was noch offen ist |
| [`docs/hardware/PLAN_HW_TEST_AKTUELL.md`](docs/hardware/PLAN_HW_TEST_AKTUELL.md) | **HW-Testplan P0–P3** |
| [`docs/README.md`](docs/README.md) | Doku-Karte |
| [`CHANGELOG.md`](CHANGELOG.md) | Unreleased + RC |

## Repo-Struktur

```
/app        Flutter-App (domain / data / presentation)
/firmware   PlatformIO M5StickC Plus2
/docs       Dokumentation (siehe docs/README.md)
/tools      Python-Simulation / Hilfsskripte
```

Lokal **nicht** im Git (gitignore): `data/` (Device-Pulls), `*.log`, `app/build/`, `app/android/build/`, `_backup_app/`.

## Setup

- Flutter: `cd app && flutter pub get && flutter test`
- Firmware: `cd firmware && pio run -t upload`
- Mensch-Setup: [`docs/reference/SETUP_ANLEITUNG.md`](docs/reference/SETUP_ANLEITUNG.md) · [`docs/reference/ANLEITUNG_FUER_ADI.md`](docs/reference/ANLEITUNG_FUER_ADI.md)

## Für KI / Contributor

1. [`docs/README.md`](docs/README.md) — Karte der Doku  
2. [`docs/Version1.0/13_OFFENE_PUNKTE.md`](docs/Version1.0/13_OFFENE_PUNKTE.md) — was noch offen ist  
3. [`docs/hardware/PLAN_HW_TEST_AKTUELL.md`](docs/hardware/PLAN_HW_TEST_AKTUELL.md) — physische Tests  
4. [`docs/reference/protocol.yaml`](docs/reference/protocol.yaml) — BLE-Wire-Format  
5. Code: `app/lib/domain/workout_engine.dart` (Klassenkommentar lesen vor Threshold-Änderungen)

### Verbote

- Kein Force-Push auf `main`
- `_useNewPipeline = true` nur nach Shadow-DoD
- `correctedReps` nicht in `countedReps` zurückschreiben
- Keine Device-Dumps / Secure-Storage-Pulls committen (`data/`)

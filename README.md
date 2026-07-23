# FlowRep

BLE/IMU-basiertes automatisches Wiederholungszählen für Krafttraining.  
**Hardware:** M5StickC Plus2 · **App:** Flutter (Android) · **Firmware:** PlatformIO / ESP32

## Aktueller Stand (2026-07-23)

| Bereich | Status |
|---------|--------|
| App P0–P2 + CV-Scaffold | Code + Unit/Widget-Tests grün |
| BLE + IMU Streaming | Hardware-verifiziert |
| Guided Calibration 2.0 (gP-Profil) | Hardware-Session OK |
| Manuelles „Satz beenden“ + Korrektur-Lernen | Product-Default |
| Volle Gym-Session (Curls → Korrektur → Ende) | **noch manuell am Gerät** |
| Shadow / `_useNewPipeline` | bleibt **false** |

**Living Docs:** [`docs/Version1.0/13_OFFENE_PUNKTE.md`](docs/Version1.0/13_OFFENE_PUNKTE.md) · Index: [`docs/README.md`](docs/README.md)

## Repo-Struktur

```
/app        Flutter-App (domain / data / presentation)
/firmware   PlatformIO M5StickC Plus2
/docs       Dokumentation (siehe docs/README.md)
/tools      Python-Simulation / Hilfsskripte
```

## Setup

- Flutter: `cd app && flutter pub get && flutter test`
- Firmware: `cd firmware && pio run -t upload`
- Mensch-Setup: [`docs/reference/SETUP_ANLEITUNG.md`](docs/reference/SETUP_ANLEITUNG.md) · [`docs/reference/ANLEITUNG_FUER_ADI.md`](docs/reference/ANLEITUNG_FUER_ADI.md)

## Für KI / Contributor

1. [`docs/README.md`](docs/README.md) — Karte der Doku  
2. [`docs/Version1.0/13_OFFENE_PUNKTE.md`](docs/Version1.0/13_OFFENE_PUNKTE.md) — was noch offen ist  
3. [`docs/reference/protocol.yaml`](docs/reference/protocol.yaml) — BLE-Wire-Format  
4. [`docs/reference/GYM_TRACKER_ARCHITEKTUR.md`](docs/reference/GYM_TRACKER_ARCHITEKTUR.md) — Architektur  
5. Code: `app/lib/domain/workout_engine.dart` (Klassenkommentar lesen vor Threshold-Änderungen)

### Verbote

- Kein Force-Push auf `main`
- `_useNewPipeline = true` nur nach Shadow-DoD
- `correctedReps` nicht in `countedReps` zurückschreiben

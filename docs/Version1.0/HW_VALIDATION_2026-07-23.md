# Hardware-Validierung 2026-07-23

> Automatisierte Session mit verbundenem Xiaomi 21081111RG + M5StickC (COM3).

## Geräte

| Gerät | Status |
|--------|--------|
| Phone | `55j7xkiffixsyhxg` · Android 14 · model 21081111RG |
| M5StickC | USB COM3 · Firmware booted · MPU6886 @0x68 WHO_AM_I=0x19 |

## Builds

| Build | Ergebnis |
|--------|----------|
| `flutter analyze lib` | **0 issues** |
| `flutter test` | **354+ tests green** |
| `flutter build apk --debug` | OK (~238 MB) after TFLite AGP9 fix |
| `flutter build apk --release` | OK (108.6 MB) |
| `adb install -r app-debug.apk` | **Success** |

### Android Build-Fixes (CV / AGP 9)

- Exclude `tensorflow-lite-api` + `tensorflow-lite-gpu` (duplicate package namespace)
- `minSdk = max(flutter.minSdk, 31)` for `flutter_pose_detection`
- `packaging.jniLibs.pickFirsts` for duplicate `.so`

## App-Launch + BLE

| Check | Ergebnis | Evidence |
|--------|----------|----------|
| App startet | ✅ | MainActivity focused, UI dump shows FlowRep |
| UI Home | ✅ | Getrennt → Gerät verbinden; Kamera / Settings / Verlauf icons |
| BLE Connect | ✅ | UI: `Verbunden (BLE)`; log: NOTIFY + read batches |
| IMU stream | ✅ | `NOTIFY received`, batches climbing (20→1000+), ~12 Hz read loop |
| Trennen | ✅ | UI shows Trennen when connected |
| Firmware serial | ✅ | `FlowRep firmware booted`, I2C RTC+MPU6886 |

Log excerpt (device):

```
[FlowRep:I] NOTIFY received! HyperOS notification block lifted?
[FlowRep:D] read() took 95ms, rate=12.5 Hz, batches=20
…
content-desc="Verbunden (BLE)"
content-desc="Zustand: calibrating"
content-desc="Trennen"
```

## Manuell / noch offen (braucht Bewegung + User)

| Check | Status | Hinweis |
|--------|--------|---------|
| Guided Calib 2.0 | ⚠️ partial | Auto-connect reached `calibrating`; full wizard needs user reps |
| Zählen + Korrektur-Dialog | ⏳ manuell | P0 UI vorhanden, physische Curls nötig |
| Session beenden | ⏳ manuell | Button + Summary implementiert |
| Screen-Lock + FGS | ⏳ manuell | FGS verdrahtet; 30s lock test by user |
| BLE Drop + Reconnect UI | ⏳ manuell | Code + unit tests; hardware drop not automated |
| Dark Mode | ⏳ manuell | themeMode.system in app |
| Kamera-Session UI | ✅ code | Screen + badge installed; runtime camera permission on device |

## TODO(hardware)

- Nur verbleibend: `workout_engine.dart` Gyro-Gate in active (bewusst offen laut DoD-Ausnahme)

## Fazit

Installierbare Debug- **und** Release-APKs bauen, App startet, **BLE + IMU-Streaming live verifiziert**. Vollständige Satz-/Korrektur-/Lock-Pfade erfordern kurze manuelle Gym-Session am Gerät.

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
| `flutter test` | **356+ tests green** (inkl. Gyro-Gate) |
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
| IMU stream | ✅ | `NOTIFY received`, batches climbing, ~11 Hz read loop |
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

## Session-2 (nach Gyro-Gate + erweiterte Checks)

| Check | Status | Evidence |
|--------|--------|----------|
| BLE Connect + Stream | ✅ | `Verbunden (BLE)`, Batches: 244+, Rate 10.9 Hz, MTU 517 |
| Screen-Lock 20s (FGS) | ✅ | batches 650 → 935 während/nach Lock; Stream blieb aktiv |
| Dark Mode (`cmd uimode night yes`) | ✅ | themeMode.system; Labels lesbar (Screenshot `data/flowrep_dark.png`) |
| BLE Drop (BT off 8s) + Re-Enable | ✅ | Nach `svc bluetooth enable`: wieder `Verbunden (BLE)`, Batches steigen |
| Guided Calib UI | ✅ partial | Wizard öffnet „Ruhephase“; volle 5-Reps brauchen physische Curls |
| Zählen + Korrektur-Dialog | ⏳ manuell | P0 UI vorhanden; physische Bewegung nötig |
| Session beenden | ⏳ manuell | Button + Summary implementiert |
| Gyro-Gate (`\|gyro\| < 15°/s`) | ✅ code+unit | Baseline friert in `active` bei Bewegung; Test grün |

## Code (Session-2)

- `workout_engine.dart`: Gyro-Gate aktiv — Baseline-EMA nur bei Ruhe in `active`
- `kGyroRestThresholdDegPerSec = 15.0` aus `engine_constants.dart`
- Unit-Test: `gyro-gate: baseline must NOT drift in active while |gyro| >= 15°/s`
- Keine `TODO(hardware)` mehr im Code

## Fazit

Installierbare APKs, App startet, **BLE + IMU live**, **Screen-Lock behält Stream**, **BT-Drop reconnect**, **Dark Mode**, **Gyro-Gate**.  
Volle Gym-Session (5-Rep-Calib → Zählen → Korrektur → Ende) bleibt der einzige manuelle Schritt am Gerät (physische Bewegung).

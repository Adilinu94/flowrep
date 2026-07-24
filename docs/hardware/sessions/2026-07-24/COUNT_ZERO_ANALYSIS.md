# Analyse: 0 Wiederholungen — 2026-07-24

## Evidence

- Device: 55j7xkiffixsyhxg, App com.flowrep.flowrep (fresh debug APK install)
- Profile loaded: `signal=gP theta≈80–87 q=0.90–0.95 axis=true` (OK)
- BLE stream live: ~11.6 Hz batches, totalSamples > 12k
- **ENGINE log lines: 0** in full session logcat
- **gP rep lines: 0**
- DIAG gyro_mag: min 33.5, max 202.7, **avg ~86**; at rest later **stuck ~86** with flat accel
- Compare 2026-07-23 rest: `gyro_mag=0.4` (healthy)

## Root causes (ranked)

### 1. Engine never received samples (PRIMARY)

`EngineNotifier._onSampleGated` only forwards IMU to `WorkoutEngine` when
`isCountingActive == true` (user tapped **Zählen starten**).

Zero `ENGINE #…` lines means processSample was never called → reps stay 0
regardless of curls / calibration quality.

### 2. Gyro quality degraded (SECONDARY — blocks counting even if started)

Rest today ≈ 86 °/s gyro magnitude vs 0.4 °/s yesterday. gP counting needs
rising/falling edges on |g_p| relative to θ≈56 (0.7×80, floor 50). Flat or
bias-dominated gyro → no falling edge → no reps.

### 3. Not a profile-load failure

Profile load succeeded twice with gP + axis.

## Operator fix sequence

1. Home: button must say **Zählen stoppen** (red) while counting.
2. Overlay: `samples=` must increase every ~1s.
3. During curl: `|gP|` should spike well above θ then fall.
4. If gyro rest stays ~86: power-cycle M5, reconnect, short re-calib rest.
5. Only then re-test 8–12 curls.

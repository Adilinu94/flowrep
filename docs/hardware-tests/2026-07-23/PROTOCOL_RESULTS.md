# Hardware-Test Ergebnisse — 2026-07-23

**Session-Ende:** unterbrochen nach Phase D (vor E)  
**Basis-Commit vor Session:** `ccda100`  
**Code-Fixes dieser Session:** siehe Commit (calib-load + compileSdk + ENGINE-Diag)  
**Firmware env:** m5stick-c-plus2  
**COM:** COM3 (CH9102)  
**Phone:** 21081111RG (Android 14, amber_eea) — adb `55j7xkiffixsyhxg`  
**Stick MAC (esptool):** `4c:c3:82:9c:7b:44`  
**Tester:** KI + Adi  
**App:** BleSensorProvider (Debug), `compileSdk = 36`, Version 0.1.0  

---

## Fortschritt (Übersicht)

| Phase | Status | Kurz |
|-------|--------|------|
| A Firmware & Boot | ✅ PASS | Flash OK, IMU OK |
| B BLE & Rate | ✅ PASS | MTU 517, ~11.7 Hz, Parse 0 |
| C Signal | ✅ grob | Ruhe mag≈1g; C2 optional offen |
| D Kalibrierung | ⚠️ teilweise | Wizard durch, Load-Bug gefunden+gefixt; **Re-Calib nach Reinstall fehlt** |
| E Zählung Legacy | ⬜ offen | Sätze E1–E6 nicht gelaufen |
| F Robustheit | ⬜ offen | |
| G Shadow | ⬜ offen | Code: `enableShadowMode` nach Load mit Achse |
| H Gate | ⬜ offen | `_useNewPipeline` bleibt **false** |

**DoD bisher:** G1 ✅ · G2 ✅ · G3 grob ✅ · G4–G8 offen

---

## Phase A — Firmware & Boot

| # | Ergebnis | Notizen |
|---|----------|---------|
| A1 pio run | ✅ | RAM 12%, Flash 58.4% |
| A2 upload COM3 | ✅ | ESP32-PICO-V3-02 |
| A3 Serial boot | ✅ | `serial_boot.log` |
| A4 Display | ✅ Firmware „Bereit“ | |
| A5 Hash | ccda100 + lokale Fixes | |

```
FlowRep firmware booted
I2C: 0x51 RTC, 0x68 MPU6886 WHO_AM_I=0x19 OK
IMU init: OK mag=1.002
```

**Hinweis:** Diese Unit = **MPU6886 @ 0x68** (nicht BMI270 @ 0x69).

---

## Phase B — BLE & Datenrate

| # | Ergebnis | Notizen |
|---|----------|---------|
| B1 flutter run | ✅ | compileSdk 36; vibration pub-cache Patch 33→34 |
| B2 Verbinden | ✅ | „Verbunden (BLE)“ |
| B3–B7 | ✅ | Rate ~11–13 Hz, MTU ~517, Parse-Fehler 0, samples steigen |
| B8 JitterBuffer | ⏳ | nicht einzeln gemessen; Rate stabil |

UI (Adi): **MTU ~517, Rate ~11–13 Hz, Parse 0, samples steigt.**

---

## Phase C — Signal

| # | Ergebnis | Notizen |
|---|----------|---------|
| C1 Ruhe | ✅ | Serial mag 0.997–1.010, gyro≈0 |
| C2 Drehen | ⏳ | optional |
| C3 Dummy | ⏭ | optional |
| C4 Settling 5s | Hinweis | vor Zählung einhalten |

---

## Phase D — Kalibrierung

| # | Ergebnis | Notizen |
|---|----------|---------|
| D1–D4 Wizard | ✅ Adi durch | Log: calibrating→active, Gyro-Peaks ~100°/s |
| D5 Speichern | ✅ Secure Storage | |
| D6 Reload | ❌ dann Fix | Bug unten |

### Bug (Hardware 2026-07-23) — im Code behoben

`EngineNotifier._loadCalibration` rief `applyCalibration` **ohne** `chosenSignal` / Interval / Prominence.

- theta ≈ **36.7 °/s** (gP) landete in `_peakThreshold` (combined)
- `_gpThreshold` blieb null → **Zählung tot**
- Beweis: `threshold=36.73` bei `combined≈1–6`, `above=false` trotz Gyro 100+

**Fix:** `app/lib/presentation/providers/engine_provider.dart`  
+ ENGINE-Diag: `app/lib/domain/workout_engine.dart` (sig / gpT / reps)  
+ `compileSdk = 36` in `app/android/app/build.gradle.kts`

**Reinstall:** Xiaomi blockierte einmal Install; danach `adb install -r` Success.  
Secure Storage ggf. leer → **nächste Session: Guided Calib wiederholen**, dann Phase E.

---

## Phase E–H

Nicht gestartet. Plan: `docs/hardware-tests/PLAN_HARDWARE_VALIDIERUNG.md`

### Nächste Session — Checkliste

1. Handy USB + Stick COM3, `flutter run` / installierte Debug-APK  
2. Verbinden, Debug: Rate ~12 Hz, Parse 0  
3. **Neu kalibrieren** (Guided 2.0)  
4. Log prüfen: `Loaded profile: signal=… theta=…` und ENGINE `sig=gP gpT=…`  
5. Phase E: 6 Curl-Sätze Real vs App  
6. F Alltag, G Shadow-Stats, H Gate-Doc  
7. **Nicht** `_useNewPipeline = true` ohne G1–G8

---

## Artefakte in diesem Ordner

| Datei | Inhalt |
|-------|--------|
| `serial_boot.log` | Boot + IMU init |
| `serial_ble_session.log` | IMU real Stream (Auszug) |
| `logcat_calib.txt` | App-Logs inkl. ENGINE während Calib |
| `logcat_session.txt` | älter / teils Rauschen |
| `PROTOCOL_RESULTS.md` | dieses File |
| `../PLAN_HARDWARE_VALIDIERUNG.md` | Gesamtplan A–H |
| `../SESSION_HANDOFF.md` | Kurz-Handoff zum Fortsetzen |

---

## Gate-Entscheidung

**pending** — `_useNewPipeline` bleibt **false**.

# Recherche: M5-Tasten → Start/Stop Zählung + Feedback

> Stand: 2026-07-24  
> Kontext: User will per M5-Taste Zählung starten/stoppen; Phone vibriert/ton.

---

## 1. Hardware (M5StickC Plus2)

| Taste | API (M5Unified / M5StickCPlus2) | Hinweis |
|-------|----------------------------------|---------|
| **BtnA** | `M5.BtnA.wasPressed()` / `wasClicked()` | Haupt-Taste vorne (HOME/Button A) |
| **BtnB** | `M5.BtnB.wasPressed()` | Seite |
| **BtnPWR** | `M5.BtnPWR.wasClicked()` / `wasHold()` | Power; nur click/hold über PMIC |

In `loop()` immer `M5.update()` vor dem Button-Poll.  
Firmware nutzt bereits `M5.update()` — **kein Button-Handling** bislang.

---

## 2. Ist-Zustand FlowRep BLE

| Richtung | Mechanismus | Status |
|----------|-------------|--------|
| App → Stick | ControlPoint **Write** `fee2` | 0x01 Start Stream, 0x02 Stop, 0x03 Battery, 0x04 Dummy |
| Stick → App | SensorData Notify `fee1`, Battery `fee3` | IMU + Akku |
| Stick → App Events | **fehlt** | Keine Button-Characteristic |

`protocol.yaml` kennt **DeviceStatus** (IDLE/STREAMING/…) — in der live Firmware **nicht** als Char implementiert.  
Buttons sind **nicht** spezifiziert.

---

## 3. Empfohlene Architektur

```
M5 BtnA wasClicked
    → Firmware BLE Notify EventChar (fee4)  payload: 1 byte event_id
    → App hört Notify
    → startCounting() / stopCounting()
    → FeedbackService (Vibration + Sound)  ← bereits vorhanden
```

### Event-IDs (Vorschlag)

| ID | Name | App-Aktion |
|----|------|------------|
| 0x01 | COUNT_START | `startCounting()` + Haptik/Sound |
| 0x02 | COUNT_STOP | `stopCounting()` oder `endSetManually()` (Produktentscheid) |
| 0x03 | COUNT_TOGGLE | optional statt 01/02 |
| 0x04 | END_SET | optional: Satz beenden |

### Tasten-Mapping (Vorschlag UX)

| Taste | Aktion |
|-------|--------|
| **BtnA** kurz | Toggle Zählen Start/Stop (einfachste UX mit einer Taste) |
| **BtnB** kurz | Satz beenden (wenn zählt) |
| **BtnPWR** | **nicht** für Training (Power/Sleep) |

Feedback: App-seitig nach Event — Phone vibriert/ton; Stick kann Display „COUNT ON/OFF“ zeigen.

---

## 4. BLE-Protokoll-Erweiterung (Draft)

Neue Characteristic:

```
UUID: 0000fee4-0000-1000-8000-00805f9b34fb
Name: DeviceEvent
Properties: notify (+ optional read last)
Payload: 1 byte event_id
```

App (`ble_sensor_provider.dart`):

- Char abonnieren (`setNotifyValue` — **Achtung HyperOS**: Sensor-Data nutzt absichtlich Read-Polling; Events sollten Notify versuchen, mit Read-Fallback oder dediziertem Poll der Event-Char wenn Notify blockiert).
- Stream `deviceEvents` → EngineNotifier.

**HyperOS-Risiko:** App kommentiert, dass Notifications für SensorData problematisch sind. Für **seltene Button-Events** (nicht 12 Hz) ist Notify oft zuverlässiger als für High-Rate IMU. Trotzdem: Fallback `lastValueStream` + periodisches `read()` der Event-Char oder Event im Sensor-Batch-Header (1 Status-Byte) — robuster, aber Protokoll-Change pro Sample.

**Robustere Alternative (weniger GATT-Risiko):**

- Button-Event als **seltenes Control-ähnliches Notify** auf fee4  
- oder 1 Bit im bestehenden Batch (verschmutzt Sensor-Pfad)

Empfehlung: **fee4 Notify**, bei 0 Events in App nach 2s Read-Probe; Product-Test auf HyperOS.

---

## 5. Aufwand

| Arbeit | PT |
|--------|-----|
| Firmware: Btn poll + Notify fee4 | 0.5–1 |
| protocol.yaml + UUIDs App | 0.25 |
| App: Event-Stream → start/stop + Feedback | 0.5–1 |
| Settings: „M5-Taste steuert Zählen“ Toggle | 0.25 |
| HW-Test HyperOS Notify | 0.5 |

**Gesamt ~2–3 PT**, abhängig Notify-Stabilität.

---

## 6. Ghost-Pause (separat, App-only — umgesetzt parallel)

- Vorher: ~**5 s** Idle → Pause (zu aggressiv für Satz-Pausen).
- Neu: Default **45 s**, Settings **30 / 45 / 90 / Aus**.
- Kein Firmware-Change.

---

## 7. Entscheidungen (User 2026-07-24) — umgesetzt

1. **BtnA = Toggle-Pfad** — ja  
2. Stop = **Satz beenden** (+ Korrektur-Dialog)  
3. Feedback: **Vib und Sound einzeln** in Settings wählbar (Master „BtnA steuert Zählen“)

Siehe: `docs/Version1.0/16_M5_BUTTON_COUNT_CONTROL.md`

---

## 8. Quellen

- M5 StickC Plus2 Button docs (M5Unified BtnA/B/PWR)
- `firmware/src/main.cpp` — kein Button-Code, ControlPoint Write-only
- `docs/reference/protocol.yaml` — ControlPoint 0x01–0x03, DeviceStatus spezifiziert aber unvollständig in FW
- `FeedbackService` — `onRepCounted` / Haptik+Audio bereit

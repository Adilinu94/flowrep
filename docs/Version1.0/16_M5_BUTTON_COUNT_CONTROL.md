# M5-Tasten-Steuerung (Zählen Start / Satz beenden)

> **Stand**: 2026-07-24  
> **Status**: implementiert (Firmware + App) — erfordert **Firmware-Flash** auf dem Stick  
> **Entscheidungen (User)**:
> 1. BtnA = primäre Taste (Start / Stop-Pfad)  
> 2. Stop-Pfad = **Satz beenden** (nicht nur Zählen stoppen)  
> 3. Feedback (Vibration / Sound) in Settings **einzeln wählbar**

---

## UX

| Zustand App | BtnA (kurz / wasClicked) | Phone-Feedback |
|-------------|--------------------------|----------------|
| Zählen **aus** | `startCounting()` | optional Vib + Ton |
| Zählen **an** | `endSetManually()` → Korrektur-Dialog | optional Vib + Ton |

Settings:

- **BtnA steuert Zählen** (Master on/off)  
- **Tasten-Feedback: Vibration** (on/off)  
- **Tasten-Feedback: Sound** (on/off)  

Kombinationen: nur Vib, nur Sound, beides, keins.

---

## Protokoll (BLE)

Characteristic **DeviceEvent** `0000fee4-…`:

| Byte | Name | Bedeutung |
|------|------|-----------|
| 0 | `seq` | 1–255, +1 pro Event (0 = noch kein Event) |
| 1 | `event_id` | `0x01` = `COUNT_PRIMARY` (BtnA) |

Properties: **READ + NOTIFY**.  
App pollt alle 250 ms (HyperOS-sicher) und akzeptiert Notify falls verfügbar.

Kanonisch: `docs/reference/protocol.yaml` → `DeviceEvent`.

---

## Code-Pfade

| Schicht | Datei |
|---------|--------|
| Firmware | `firmware/src/main.cpp` — `pollButtons()`, `sendDeviceEvent()` |
| Domain | `app/lib/domain/device_event.dart` |
| BLE | `app/lib/data/providers/ble_sensor_provider.dart` — fee4 poll/notify |
| Provider | `app/lib/presentation/providers/engine_provider.dart` — `_onDeviceEvent` |
| Feedback | `app/lib/presentation/services/feedback_service.dart` — `onDeviceButton` |
| Settings | `app/lib/presentation/screens/settings_screen.dart` |

Ältere Firmware ohne fee4: App loggt „DeviceEvent char missing“ und deaktiviert Tasten-Steuerung still.

---

## Flash-Hinweis

App allein reicht nicht — Stick braucht den neuen Firmware-Build:

```bash
cd firmware
pio run -t upload
```

---

## Manueller Test

1. Firmware flashen, App installieren, verbinden.  
2. Settings: BtnA an, Vib/Sound nach Wunsch.  
3. BtnA → Zählen startet + Feedback.  
4. Curls, BtnA → Satz beenden + Korrektur-Dialog + Feedback.  
5. Master-Toggle aus → BtnA wirkungslos.

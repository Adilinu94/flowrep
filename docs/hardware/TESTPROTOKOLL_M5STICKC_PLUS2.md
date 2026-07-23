# Hardware-Testprotokoll – M5StickC Plus2 (FlowRep)

**Zweck:** Erster Systemtest der Firmware auf echter Hardware. Das Protokoll validiert Schritt für Schritt, ob BLE-Werbung, GATT-Verbindung, MTU-Verhandlung, IMU-Datenstrom und Akku-Abfrage wie spezifiziert funktionieren.

**Voraussetzungen**

- M5StickC Plus2 per USB-C an den Computer angeschlossen
- Firmware erfolgreich mit `pio run --target upload` geflasht
- Android-Handy mit installierter FlowRep-App oder ein BLE-Scanner (z. B. nRF Connect)
- Serial Monitor bereit: `pio device monitor --baud 115200`

---

## 1. Gerät bootet und zeigt Status an

| # | Schritt | Erwartet | Ergebnis | Notizen |
|---|---|---|---|---|
| 1.1 | M5StickC Plus2 einschalten / Reset | Display zeigt "Gym Tracker" → "Bereit" | ☐ OK / ☐ NOK | |
| 1.2 | Serial Monitor öffnen | Ausgabe "FlowRep firmware booted" | ☐ OK / ☐ NOK | |
| 1.3 | I2C-Scan im Log prüfen | BMI270 an 0x69 erkannt, CHIP_ID 0x24 | ☐ OK / ☐ NOK | Wichtig: M5StickC Plus2, nicht Plus |
| 1.4 | IMU-Init im Log prüfen | "IMU init: OK (valid gravity vector)" | ☐ OK / ☐ NOK | Falls FAIL: Display zeigt "IMU FAIL!" |
| 1.5 | Display-Status nach Boot | "Bereit" oder Status-Text sichtbar | ☐ OK / ☐ NOK | |

**Fehlerbehebung**

- **IMU FAIL!**: I2C-Adresse prüfen (0x68 vs. 0x69), Kabel wechseln, `Wire.setClock(100000)` aktivieren.
- **Kein Serial-Output**: Baudrate 115200 prüfen, USB-Treiber (CP210x/CH340) installieren.

---

## 2. BLE-Werbung und Verbindung

| # | Schritt | Erwartet | Ergebnis | Notizen |
|---|---|---|---|---|
| 2.1 | Handy-BLE-Scan starten | Gerät "GymTracker" sichtbar | ☐ OK / ☐ NOK | |
| 2.2 | Service-UUID prüfen | `0000fee0-0000-1000-8000-00805f9b34fb` in Werbung | ☐ OK / ☐ NOK | Optional mit nRF Connect |
| 2.3 | FlowRep-App: "Gerät verbinden" tippen | Verbindungsaufbau ohne Fehler | ☐ OK / ☐ NOK | |
| 2.4 | App-Status zeigt "Verbunden (BLE)" | Status-Text wechselt | ☐ OK / ☐ NOK | |
| 2.5 | Firmware-Display zeigt "Verbunden" | Display aktualisiert | ☐ OK / ☐ NOK | |
| 2.6 | Serial Log: `BLE: client connected, auto-starting stream` | Zeile erscheint | ☐ OK / ☐ NOK | |

**Fehlerbehebung**

- **Gerät nicht sichtbar**: Bluetooth am Handy aktiv? M5StickC Plus2 neu starten.
- **Verbindung bricht sofort ab**: Pairing/Bonding löschen, App neu installieren.

---

## 3. MTU-Verhandlung

| # | Schritt | Erwartet | Ergebnis | Notizen |
|---|---|---|---|---|
| 3.1 | App zeigt MTU an | `MTU: 517` | ☐ OK / ☐ NOK | Firmware setzt `NimBLEDevice::setMTU(517)` |
| 3.2 | App zeigt keine MTU-Fehler | Kein `StateError` mit MTU < 185 | ☐ OK / ☐ NOK | |
| 3.3 | Serial Log: `requestMtu(185) returned: 517` | Oder ähnliche Bestätigung | ☐ OK / ☐ NOK | HyperOS ignoriert Client-MTU |

**Fehlerbehebung**

- **MTU zu klein (< 55)**: `NimBLEDevice::setMTU(517)` in `firmware/src/main.cpp` prüfen.
- **MTU-Fehler in App**: `BleSensorProvider.requiredMtu` und Firmware-Seite abstimmen.

---

## 4. IMU-Datenstrom validieren

### 4.1 Dummy-Stream (isoliert BLE-Pfad)

| # | Schritt | Erwartet | Ergebnis | Notizen |
|---|---|---|---|---|
| 4.1.1 | In App: "Dummy Stream"-Button drücken | Firmware sendet konstante Werte (ax=100, ay=200, az=300) | ☐ OK / ☐ NOK | Isoliert IMU vs. BLE |
| 4.1.2 | App zeigt konstante Accel-Magnitude ~0.374 g | `sqrt(0.1² + 0.2² + 0.3²)` | ☐ OK / ☐ NOK | |
| 4.1.3 | Serial Log: `BLE: DUMMY batch sent` | Periodisch sichtbar | ☐ OK / ☐ NOK | |
| 4.1.4 | App zeigt Rate > 0 Hz | Batches-Zähler steigt | ☐ OK / ☐ NOK | |

### 4.2 Echter IMU-Datenstrom

| # | Schritt | Erwartet | Ergebnis | Notizen |
|---|---|---|---|---|
| 4.2.1 | Dummy-Stream ausschalten / App neu verbinden | Echte IMU-Daten fließen | ☐ OK / ☐ NOK | |
| 4.2.2 | Ruheposition: Accel-Magnitude ≈ 1.0 g | Wert im App-Diag-Log oder UI | ☐ OK / ☐ NOK | Gravitation |
| 4.2.3 | Ruheposition: Gyro-Magnitude ≈ 0 °/s | Keine Rotation | ☐ OK / ☐ NOK | |
| 4.2.4 | Gerät bewegen: Accel/Gyro-Werte ändern sich | Live-Reaktion in App/Log | ☐ OK / ☐ NOK | |
| 4.2.5 | Serial Log: `IMU: a=(...)` zeigt sich ändernde Werte | ~1 Hz Dump | ☐ OK / ☐ NOK | |
| 4.2.6 | App-Rate liegt im erwarteten Bereich | ~20–30 Hz bei read()-Polling | ☐ OK / ☐ NOK | HyperOS blockiert Notifications |

**Fehlerbehebung**

- **Keine Daten trotz Verbindung**: `subscr` auf Display prüfen. Bei 0: CCCD-Problem. App verwendet read()-Polling, daher Notifications nicht nötig.
- **Konstante Werte bei Bewegung**: IMU stale? Display zeigt `STALE:`? I2C-Bus prüfen.
- **Rate zu niedrig**: `ConnectionPriority.high` prüfen, Handy-BLE-Stack/Modell wechseln.

---

## 5. Akku-Abfrage

| # | Schritt | Erwartet | Ergebnis | Notizen |
|---|---|---|---|---|
| 5.1 | App zeigt Akkustand an | Wert zwischen 0 % und 100 % | ☐ OK / ☐ NOK | |
| 5.2 | Akku-Abfrage wiederholen | Wert bleibt plausibel (±5 %) | ☐ OK / ☐ NOK | |
| 5.3 | Serial Log: Spannungsbasierte Berechnung | `getBatteryPercent()` basiert auf 3300–4200 mV | ☐ OK / ☐ NOK | |

**Fehlerbehebung**

- **Akku 0 % / unplausibel**: `M5.Power.getBatteryVoltage()` im Log prüfen. Manche M5StickC-Plus2-Revisionen liefern ungenaue Werte.

---

## 6. Workout-Engine-Test (erste echte Bewegung)

| # | Schritt | Erwartet | Ergebnis | Notizen |
|---|---|---|---|---|
| 6.1 | Kalibrierungsdialog starten | UI zeigt Countdown | ☐ OK / ☐ NOK | |
| 6.2 | 10 gleichmäßige Bizeps-Curls ausführen | Kalibrierung schließt ab, Schwellenwert angezeigt | ☐ OK / ☐ NOK | |
| 6.3 | Danach einen Satz ausführen | Zähler erhöht sich mit jeder Wiederholung | ☐ OK / ☐ NOK | |
| 6.4 | 4 Sekunden Pause | Status wechselt zu "paused" | ☐ OK / ☐ NOK | |

**Fehlerbehebung**

- **Kalibrierung schließt nicht ab**: Gyro-Validierung prüfen (`_minGyroPeakDegPerS = 50.0`). Schneller/langsamer curlen.
- **Zählt nicht**: Threshold im UI prüfen, CSV-Aufnahme starten und offline analysieren.

---

## 7. Zusammenfassung und Sign-Off

| Bereich | Status | Tester | Datum |
|---|---|---|---|
| Boot & IMU-Init | ☐ OK / ☐ NOK | | |
| BLE-Werbung & Verbindung | ☐ OK / ☐ NOK | | |
| MTU-Verhandlung | ☐ OK / ☐ NOK | | |
| IMU-Datenstrom (Dummy) | ☐ OK / ☐ NOK | | |
| IMU-Datenstrom (echt) | ☐ OK / ☐ NOK | | |
| Akku-Abfrage | ☐ OK / ☐ NOK | | |
| Workout-Engine | ☐ OK / ☐ NOK | | |

**Gesamtergebnis:** ☐ Bestanden ☐ Nicht bestanden

**Auffälligkeiten / Blocker:**

---

## Anhang: Wichtige UUIDs und Befehle

| Element | Wert |
|---|---|
| Gerätename | `GymTracker` |
| Service UUID | `0000fee0-0000-1000-8000-00805f9b34fb` |
| SensorData Char | `0000fee1-0000-1000-8000-00805f9b34fb` |
| ControlPoint Char | `0000fee2-0000-1000-8000-00805f9b34fb` |
| Battery Char | `0000fee3-0000-1000-8000-00805f9b34fb` |
| START_STREAM | `0x01` |
| STOP_STREAM | `0x02` |
| REQUEST_BATTERY | `0x03` |
| TOGGLE_DUMMY_STREAM | `0x04` |

## Anhang: Nützliche Kommandos

```bash
# Firmware flashen
cd firmware && pio run --target upload

# Serial Monitor öffnen
pio device monitor --baud 115200

# App im Mock-Modus starten (keine Hardware nötig)
cd app && flutter run -d chrome

# App auf Android starten
cd app && flutter run
```

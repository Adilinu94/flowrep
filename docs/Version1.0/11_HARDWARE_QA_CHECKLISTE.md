# Hardware-QA-Checkliste — FlowRep 1.0

> **Voraussetzung**: Alle P0-Features implementiert. Release-APK gebaut (Doc 10).
> **Ziel**: Manuelle Validierung auf echtem M5StickC Plus2 + Android-Handy.
> **Wer**: Adi führt die Tests aus. KI wertet Logs/CSVs aus.
> **Dauer**: ~30-45 Minuten.

---

## 0. Test-Aufbau

### 0.1 Benötigte Hardware

| Gerät | Zweck |
|-------|-------|
| M5StickC Plus2 | BLE-Sensor (IMU am Oberarm) |
| Android-Handy (HyperOS/Xiaomi) | FlowRep-App |
| USB-C Kabel | M5StickC laden / Serial-Monitor |
| Oberarm-Bandage / Tape | Sensor am Bizeps befestigen |

### 0.2 Vorbereitung

```bash
# 1. M5StickC Plus2 flashen (falls nötig)
cd flowrep/firmware
pio run --target upload

# 2. Serial Monitor starten (für Debugging)
pio device monitor --baud 115200

# 3. Release-APK auf Handy installieren
adb install flowrep/app/build/app/outputs/flutter-apk/app-release.apk
```

### 0.3 Sensor-Positionierung

```
    ┌─────────────┐
    │  M5StickC   │  ← Display zeigt nach außen
    │  Plus2      │
    └──────┬──────┘
           │  ← USB-C zeigt nach UNTEN (Richtung Ellenbogen)
           │
    ═══════╪═══════  ← Oberarm (Bizeps)
           │
```

**WICHTIG**: Die Positionierung beeinflusst die Gyro-Achse.
Die Kalibrierung erkennt die optimale Achse automatisch.

---

## 1. Testfall: Verbindung aufbauen

| # | Schritt | Erwartet | OK? |
|---|---------|----------|-----|
| 1.1 | M5StickC einschalten | Display: "GymTracker" → "Bereit" | ☐ |
| 1.2 | App starten | HomeScreen erscheint | ☐ |
| 1.3 | "Verbinden" tippen | Status: "Verbinde..." | ☐ |
| 1.4 | Warten (max 10s) | Status: "Verbunden" + Batterie-% | ☐ |
| 1.5 | Serial-Monitor prüfen | "BLE: client connected" | ☐ |

**Fehlerbehebung**:
- Gerät nicht gefunden → Bluetooth aus/an, Standort-Permission prüfen
- Verbindung bricht ab → Pairing löschen, App neu starten

---

## 2. Testfall: Kalibrierung

| # | Schritt | Erwartet | OK? |
|---|---------|----------|-----|
| 2.1 | Nach Verbindung: Onboarding-Banner sichtbar | "Kalibrierung starten" Button | ☐ |
| 2.2 | "Kalibrierung starten" tippen | CalibrationWizard öffnet | ☐ |
| 2.3 | Anweisung lesen, "Start" tippen | Countdown 3-2-1 | ☐ |
| 2.4 | 5 langsame Bicep Curls machen | Fortschritt: 1/5, 2/5, ... 5/5 | ☐ |
| 2.5 | Kalibrierung abgeschlossen | "Kalibrierung erfolgreich" + Peaks-Anzeige | ☐ |
| 2.6 | Zurück zum HomeScreen | Übung ausgewählt, Kalibrierung aktiv | ☐ |

**Kriterien**:
- Mindestens 3 von 5 Reps müssen erkannt werden
- Schwellenwert muss plausibel sein (nicht 0, nicht >1000)
- Rotation-Achse muss bestimmt sein (X, Y, oder Z)

---

## 3. Testfall: Zählung (Kernfunktionalität)

| # | Schritt | Erwartet | OK? |
|---|---------|----------|-----|
| 3.1 | "Zählung starten" Button tippen | Button wird zu "Stoppen", Zählung aktiv | ☐ |
| 3.2 | 10 langsame Bicep Curls | Rep-Counter zeigt: 1, 2, 3, ... 10 | ☐ |
| 3.3 | 5 Sekunden pausieren | Keine Falsch-Reps | ☐ |
| 3.4 | 5 schnelle Curls | Reps werden gezählt (evtl. ±1 Toleranz) | ☐ |
| 3.5 | Arm ruhig halten | Keine Falsch-Reps | ☐ |
| 3.6 | Gehen (ohne Curls) | Keine Falsch-Reps | ☐ |

**Bewertung**:
| Ergebnis | Bewertung |
|----------|-----------|
| 10/10 korrekt | ✅ Perfekt |
| 9/10 oder 11/10 | ✅ Akzeptabel (±1 Toleranz) |
| 8/10 oder 12/10 | ⚠️ Grenzwertig — Kalibrierung wiederholen |
| <8/10 oder >12/10 | ❌ FAIL — Pipeline-Debug nötig |

---

## 4. Testfall: Korrektur-UI (P0-1)

| # | Schritt | Erwartet | OK? |
|---|---------|----------|-----|
| 4.1 | Nach ~10 Reps: Satzende abwarten | Set-Erkennung (Pause > 3s) | ☐ |
| 4.2 | Korrektur-Dialog erscheint | "Satz beendet: X Reps" + /− Buttons | ☐ |
| 4.3 | "+1" tippen | Reps erhöhen sich um 1 | ☐ |
| 4.4 | "−1" tippen | Reps verringern sich um 1 | ☐ |
| 4.5 | "Bestätigen" tippen | Dialog schließt, Nachricht: "Danke, das hilft uns die Erkennung zu verbessern." | ☐ |
| 4.6 | Pausen-Timer startet | 90s Countdown sichtbar | ☐ |

**VERBOTEN**: Die Nachricht darf NICHT "Die KI lernt dazu" lauten!

---

## 5. Testfall: Pausen-Timer (P0-2)

| # | Schritt | Erwartet | OK? |
|---|---------|----------|-----|
| 5.1 | Nach Korrektur-Bestätigung | Timer zeigt 90, 89, 88, ... | ☐ |
| 5.2 | Timer bei 0 angekommen | Vibration + Signalton | ☐ |
| 5.3 | "Pause überspringen" tippen | Timer stoppt sofort | ☐ |
| 5.4 | Nächster Satz starten | Zählung beginnt bei 0 | ☐ |

---

## 6. Testfall: Session-Beenden (P0-3)

| # | Schritt | Erwartet | OK? |
|---|---------|----------|-----|
| 6.1 | "Session beenden" / Zurück-Button | Bestätigungs-Dialog: "Session beenden?" | ☐ |
| 6.2 | "Ja, beenden" tippen | Zusammenfassung erscheint | ☐ |
| 6.3 | Zusammenfassung prüfen | Gesamt-Reps, Sätze, Dauer sichtbar | ☐ |
| 6.4 | "Fertig" tippen | Zurück zum HomeScreen, Zählung gestoppt | ☐ |
| 6.5 | History-Screen öffnen | Session ist in der Liste | ☐ |

---

## 7. Testfall: BLE-Reconnection (P0-4)

| # | Schritt | Erwartet | OK? |
|---|---------|----------|-----|
| 7.1 | Während Zählung: M5StickC ausschalten | App zeigt "Verbindung verloren" | ☐ |
| 7.2 | 5 Sekunden warten | Status: "Verbinde erneut..." | ☐ |
| 7.3 | M5StickC einschalten | Auto-Reconnect innerhalb 10-30s | ☐ |
| 7.4 | Verbindung wiederhergestellt | Status: "Verbunden", Zählung läuft weiter | ☐ |
| 7.5 | Rep-Counter prüfen | Keine Reps verloren, keine Falsch-Reps | ☐ |

**Kriterium**: Reconnect muss OHNE Benutzerinteraktion funktionieren.

---

## 8. Testfall: Foreground Service (P0-5)

| # | Schritt | Erwartet | OK? |
|---|---------|----------|-----|
| 8.1 | Zählung starten | Notification erscheint: "FlowRep zählt" | ☐ |
| 8.2 | Bildschirm sperren (Power-Button) | Zählung läuft weiter (Vibration bei Rep) | ☐ |
| 8.3 | 30 Sekunden warten | Weitere Reps werden gezählt | ☐ |
| 8.4 | Bildschirm entsperren | Rep-Counter zeigt korrekte Anzahl | ☐ |
| 8.5 | App aus Recent-Apps wischen | Zählung läuft weiter (Foreground Service) | ☐ |

**KRITISCH**: Ohne Foreground Service killt Android die BLE-Verbindung nach ~30s im Hintergrund.

---

## 9. Testfall: Dark Mode (P2-1)

| # | Schritt | Erwartet | OK? |
|---|---------|----------|-----|
| 9.1 | System auf Dark Mode umstellen | App folgt automatisch | ☐ |
| 9.2 | HomeScreen prüfen | Text lesbar, Kontrast ausreichend | ☐ |
| 9.3 | Korrektur-Dialog prüfen | Buttons sichtbar, Text lesbar | ☐ |
| 9.4 | CalibrationWizard prüfen | Fortschritt sichtbar | ☐ |
| 9.5 | History-Screen prüfen | Einträge lesbar | ☐ |

---

## 10. Testfall: CV-Integration (optional)

> **Nur wenn CV implementiert ist (Phase 4)**

| # | Schritt | Erwartet | OK? |
|---|---------|----------|-----|
| 10.1 | Kamera-Permission erlauben | Kamera-Preview erscheint | ☐ |
| 10.2 | Bicep Curl vor Kamera | Skelett-Overlay sichtbar | ☐ |
| 10.3 | 10 Curls mit Kamera | Kamera-Rep-Counter zählt mit | ☐ |
| 10.4 | Fusion-Statistik prüfen | IMU+Kamera einig → ✅ | ☐ |
| 10.5 | Kamera zuhalten (Okklusion) | IMU zählt weiter, Kamera pausiert | ☐ |

---

## 11. Zusammenfassung & Go/No-Go

### Bewertungsschema

| Testfall | Gewicht | Bestanden? |
|----------|---------|-----------|
| 1. Verbindung | Pflicht | ☐ |
| 2. Kalibrierung | Pflicht | ☐ |
| 3. Zählung | Pflicht | ☐ |
| 4. Korrektur-UI | Pflicht | ☐ |
| 5. Pausen-Timer | Pflicht | ☐ |
| 6. Session-Beenden | Pflicht | ☐ |
| 7. BLE-Reconnection | Pflicht | ☐ |
| 8. Foreground Service | Pflicht | ☐ |
| 9. Dark Mode | Empfehlung | ☐ |
| 10. CV-Integration | Optional | ☐ |

### Go/No-Go Entscheidung

- **GO**: Alle Pflicht-Tests (1-8) bestanden
- **BEDINGTES GO**: Pflicht 1-6 bestanden, 7 oder 8 mit Einschränkungen
- **NO-GO**: Einer der Tests 1-6 nicht bestanden

### Unterschrift

| | Name | Datum | Ergebnis |
|---|------|-------|----------|
| Tester | Adi | _________ | GO / NO-GO |

---

## 12. Bekannte Einschränkungen (1.0)

| Einschränkung | Grund | Workaround |
|---------------|-------|-----------|
| Nur Bicep Curls | Nur eine Übung kalibriert | Weitere in 1.1 |
| Nur Android | iOS-BLE-Setup fehlt | iOS in 1.1 |
| Shadow-Pipeline inaktiv | `_useNewPipeline = false` | Manuell aktivieren nach Gate |
| Kein ML/Adaptive | V1 ist regelbasiert | ML in 2.0 |
| Kein Cloud-Sync | Nur lokale DB | Export via CSV |

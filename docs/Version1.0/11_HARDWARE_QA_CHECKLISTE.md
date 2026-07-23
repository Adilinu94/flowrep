# FlowRep 1.0 — Hardware-QA-Checkliste

> **Stand**: 2026-07-23  
> **Geräte-Referenz**: Xiaomi 21081111RG (`55j7xkiffixsyhxg`) + M5StickC Plus2 (COM3, MPU6886)  
> **Detail-Logs**: `docs/hardware/sessions/2026-07-23/`, `../hardware/sessions/2026-07-23/HW_VALIDATION.md`, `CALIB_SESSION_ANALYSIS.md`  
> **Konsolidierte Offene Punkte**: [13_OFFENE_PUNKTE.md](13_OFFENE_PUNKTE.md)

Markiere nur mit Evidence (Log, Screenshot, Unit-Test-Name). Keine Annahmen.

---

## A — Firmware & Boot

- [x] PlatformIO Build + Upload COM3
- [x] Serial: `FlowRep firmware booted`, IMU WHO_AM_I OK
- [x] Display „Bereit“ (Firmware)

## B — BLE & Stream

- [x] App: „Verbunden (BLE)“
- [x] NOTIFY / Batches steigen (~11 Hz)
- [x] MTU ~517, Parse-Fehler 0
- [x] Trennen UI

## C — Signal

- [x] Ruhe: mag ≈ 1 g, gyro niedrig (~2 °/s in Calib-DIAG)
- [~] Gezielte Curl-Peaks 50–200 °/s (in Calib-Session gesehen)
- [ ] Optionale Dreh-/Dummy-Tests (C2/C3 Protokoll)

## D — Kalibrierung (Guided 2.0)

- [x] Wizard öffnet (Ruhephase / Briefing / 5 s Countdown + Vibration)
- [x] Rest-Gate handheld still (Code + Unit)
- [x] Profil gespeichert: signal=**gP**, theta≈**87.2**, q≈**0.95**, Achse true  
  Evidence: `CALIB_SESSION_ANALYSIS.md` / logcat Loaded profile
- [ ] Re-Calib nach Clean-Install nochmals dokumentiert (optional)

## E — Zählung (Legacy / Product-Pfad)

> Product: `autoEndSetEnabled: false` — Satz endet **nur** über „Satz beenden“.

- [ ] E1: Zählen starten, 8–12 echte Curls → Anzeige plausibel
- [ ] E2: bewusstes Wackeln / Alltagsbewegung → **keine** oder minimale Falsch-Reps
- [ ] E3: „Satz beenden“ tippen → Korrektur-Dialog mit System-Count
- [ ] E4: echte Reps eingeben → „Speichern & lernen“ → `correctedReps` / nächste Session θ-nudge
- [ ] E5: „Training beenden“ → Summary / Persistenz
- [x] Unit: Curl-Form zählt, kurzes Wackeln zählt nicht (`tool_count_sim_test.dart`)
- [x] Unit: `autoEndSetEnabled false` + `endSetManually` (`tool_count_sim_test.dart`)

## F — Robustheit

- [x] Screen-Lock ≥20 s → Stream bleibt (FGS; Batches 650→935)
- [x] BLE Drop (BT off) → Reconnect
- [~] App-Hintergrund / Lifecycle (Code P1-2; langes HW optional)
- [x] Gyro-Gate: Baseline friert bei Bewegung in `active` (Unit)

## G — Shadow / Pipeline-Gate

- [x] Shadow aktivierbar wenn Achse im Profil (`enableShadowMode`)
- [ ] G5/G6: Curl-DoD vs. Wiggle-DoD am Gerät (physisch)
- [ ] G7: `_useNewPipeline = true` **nur** nach Shadow-DoD — aktuell **false**, nicht freigeben
- [ ] G8: Langzeit-Session / Drift

## H — Release-HW-Smoke (vor Store)

- [x] Debug-APK installierbar
- [x] Release-APK buildbar
- [x] Dark Mode lesbar (`uimode night`)
- [ ] Volle Gym-Session einmal ohne Tool-Hilfe (Adi)
- [ ] Keine Crash-Logs in 15‑min Session

---

## Offener Kern-Pfad (DoD)

```
[ ] Kalibrieren → [ ] Zählen (Curls) → [ ] Satz beenden → [ ] Korrigieren → [ ] Beenden
```

Code+UI für alle Schritte vorhanden; **Bewegungs-E2E am Arm** ist der verbleibende Gate.

---

## Changelog

| Datum | Änderung |
|-------|----------|
| 2026-07-23 | Checkliste aus HW_VALIDATION + Protocol + Calib-Analyse + Product-Manual-End |

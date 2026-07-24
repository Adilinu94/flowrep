# FlowRep 1.0 — Hardware-QA-Checkliste

> **Stand**: 2026-07-24  
> **Geräte-Referenz**: Xiaomi 21081111RG (`55j7xkiffixsyhxg`) + M5StickC Plus2  
> **Detail-Logs**: `docs/hardware/sessions/2026-07-23/`, `2026-07-24/` (A1–A5 partial), `HW_VALIDATION.md`  
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
- [~] Optionale Dreh-/Dummy-Tests (C2/C3) — env-defer 2026-07-23 (kein M5/Motion im Agent-Lauf; siehe OPTIONAL_HW_ENV_PROBE.md)

## D — Kalibrierung (Guided 2.0)

- [x] Wizard öffnet (Ruhephase / Briefing / 5 s Countdown + Vibration)
- [x] Rest-Gate handheld still (Code + Unit)
- [x] Profil gespeichert: signal=**gP**, theta≈**87.2**, q≈**0.95**, Achse true  
  Evidence: `CALIB_SESSION_ANALYSIS.md` / logcat Loaded profile
- [~] Re-Calib nach Clean-Install — env-defer (interaktiv; OPTIONAL_HW_ENV_PROBE.md)

## E — Zählung (Legacy / Product-Pfad)

> Product: `autoEndSetEnabled: false` — Satz endet **nur** über „Satz beenden“ (UI oder M5 BtnA).

- [~] E1: Zählen starten + Curls am Gerät (2026-07-24 „klappt besser“); **noch**: 8–12 mit App/Manuell-Zahl notieren — siehe `sessions/2026-07-24/HW_SESSION_A1_A5.md`
- [~] E2: Ghost Idle Default 45 s (kurze Pause ok); **noch**: bewusstes Wackeln 5–10 s notieren
- [~] E3: Satz beenden → Dialog (BtnA User-ok 2026-07-24); UI-Button gleichwertig
- [ ] E4: echte Reps → „Speichern & lernen“ (einmalig bestätigen)
- [ ] E5: „Training beenden“ → Summary (einmalig bestätigen)
- [x] M5 BtnA: Start Zählen / Satz beenden (User 2026-07-24)
- [x] Unit: Curl-Form zählt, kurzes Wackeln zählt nicht (`tool_count_sim_test.dart`)
- [x] Unit: `autoEndSetEnabled false` + `endSetManually` (`tool_count_sim_test.dart`)

## F — Robustheit

- [x] Screen-Lock ≥20 s → Stream bleibt (FGS; Batches 650→935)
- [x] BLE Drop (BT off) → Reconnect
- [~] App-Hintergrund / Lifecycle (Code P1-2; Kurz-Smoke HOME/Resume 2026-07-23 ohne FATAL; Langzeit optional)
- [x] Gyro-Gate: Baseline friert bei Bewegung in `active` (Unit)

## G — Shadow / Pipeline-Gate

- [x] Shadow aktivierbar wenn Achse im Profil (`enableShadowMode`)
- [~] G5/G6: Curl-DoD vs. Wiggle-DoD am Gerät — env-defer (Motion/M5)
- [ ] G7: `_useNewPipeline = true` **nur** nach Shadow-DoD — aktuell **false**, nicht freigeben
- [~] G8: Langzeit-Session / Drift — env-defer

## H — Release-HW-Smoke (vor Store)

- [x] Debug-APK installierbar
- [x] Release-APK buildbar
- [x] Dark Mode lesbar (`uimode night`)
- [~] Volle Gym-Session einmal ohne Tool-Hilfe — env-defer (menschlich)
- [~] Keine Crash-Logs in 15‑min Session — nur Kurz-Launch-Smoke; 15‑min offen

---

## Offener Kern-Pfad (DoD)

```
[x] Verbinden → [x] Kalibrieren → [~] Zählen (Curls) → [~] Satz beenden → [ ] Korrigieren/Lernen → [ ] Training beenden
```

Code+UI+BtnA da. **Rest:** ein sauberer Satz mit Zahlen + Learn + Summary + kurzer Wackel-Test  
→ `docs/hardware/sessions/2026-07-24/HW_SESSION_A1_A5.md`.

---

## Changelog

| Datum | Änderung |
|-------|----------|
| 2026-07-24 | Session A1–A5 partial: Calib/Zählen/BtnA/Ghost/Kamera; E1–E3 [~], E4–E5 [ ] |
| 2026-07-23 | Optional-B Env-Probe: Phone/App OK, M5/Motion fehlen → ehrliche [~] |
| 2026-07-23 | Checkliste aus HW_VALIDATION + Protocol + Calib-Analyse + Product-Manual-End |

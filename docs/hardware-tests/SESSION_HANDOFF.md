# Handoff Hardware-Validierung

**Stand:** 2026-07-23 (Session abgebrochen vor Phase E)  
**Repo-Basis:** war `ccda100` + Fixes dieser Session (calib-load, compileSdk, Diag)

## Erledigt

- Firmware gebaut/geflasht (COM3), Boot OK (MPU6886)
- App Debug auf 21081111RG, BLE verbunden
- G1/G2: Rate ~11.7 Hz, MTU 517, Parse 0
- Guided Calib einmal durchgelaufen
- **Bug:** Profile-Load ohne `chosenSignal` → Zählung tot → **gefixt**
- Plan + Tagesprotokoll unter `docs/hardware-tests/`

## Offen (nächste Session)

1. Re-Calib (Profil nach Reinstall evtl. weg)
2. Phase E: 6 Curl-Sätze Real vs App
3. F Robustheit, G Shadow, H Gate
4. Optional: vibration-Plugin dauerhaft (pub-cache-Patch oder upgrade auf 3.x) — aktuell nur lokal 33→34
5. Token-Rotation: falls früher PAT im Chat: auf GitHub revoken

## Nicht tun

- `_useNewPipeline = true` ohne Gate G1–G8
- Legacy löschen vor Gate

## Einstieg

```
docs/hardware-tests/PLAN_HARDWARE_VALIDIERUNG.md
docs/hardware-tests/2026-07-23/PROTOCOL_RESULTS.md
```

Hardware: Stick USB COM3, Handy adb, `app/` Debug-Build.

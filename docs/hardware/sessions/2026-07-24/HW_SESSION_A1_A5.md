# HW-Session A1–A5 — 2026-07-24

> Operator: Adi · Agent: Grok · Gerät: Xiaomi 21081111RG (`55j7xkiffixsyhxg`) + M5StickC Plus2  
> App: Debug-APK aus `main` (u. a. `618e3bb` CV-Switch, `2f26b00` BtnA, `db2f382` Ghost 45s)  
> Firmware: geflasht 2026-07-24 (DeviceEvent fee4 / BtnA)  
> Webcam: **nicht** verwendet

Markierung nur mit Evidence (User-Aussage, Logcat, Commit). Keine Annahmen als „fertig“.

---

## Session-Chronologie (Evidence)

| Zeit / Phase | Event | Evidence |
|--------------|--------|----------|
| Start | Phone online, App alt `0.1.0` | adb `versionName=0.1.0` |
| Fix | Frisches Debug-APK installiert | adb install Success |
| Connect | Verbunden, Akku 44 % | User |
| Calib | Guided Calib durch | User + logcat `Loaded profile: signal=gP theta≈80–87 axis=true` |
| Zählen 0 | Engine bekam keine Samples | logcat: **0× ENGINE**, User „immer 0“ |
| Diagnose | Zählen-Button / Samples-Gate | Analyse `COUNT_ZERO_ANALYSIS.md` |
| Zählen ok | „klappt jetzt besser“ | User |
| Ghost zu früh | Pause zwischen Reps → Pause | User; Fix Default **45 s** + Settings (`db2f382`) |
| BtnA | Start Zählen / Satz beenden | User: „Ja hat gklappt“; FW flash + App `2f26b00` |
| Kamera | Sich selbst sehen; Front/Back fehlte | User; Switch `618e3bb` installiert |

---

## A1–A5 Scorecard (ehrlich)

| ID | DoD | Status | Was belegt | Was fehlt für [x] |
|----|-----|--------|------------|-------------------|
| **A1** | Volle Session: Calib → Curl-Zählen → Satz beenden → Korrektur → Training beenden | **[~]** | Calib, Zählen aktiv, BtnA=Start + Satz beenden | Explizit: Summary nach „Training beenden“; eine notierte Curl-Anzahl |
| **A2** | 8–12 Curls, Anzeige plausibel | **[~]** | Zählen funktioniert am Gerät | Ein Satz mit manueller vs. App-Zahl (z. B. 10/10 oder 10/9) |
| **A3** | Wackeln → keine wilden Falsch-Reps | **[~]** | Unit grün; Ghost-Fix (kurze Pause ≠ Freeze) | 10 s bewusst wackeln/ablegen, Ergebnis notieren |
| **A4** | Satz beenden → Speichern & lernen → Session-Ende | **[~]** | BtnA → Satz beenden (User ok) | Einmal „Speichern & lernen“ + „Training beenden“ bestätigt |
| **A5** | Pre-Release-Smoke §5 (3–4) | **[~]** | Install, Connect, Calib, Count-Pfad, kein Crash in Session | Kurzer Durchlauf ohne Agent-Hilfe als „Gym-Smoke“ |

**Kern-Pfad (visual):**

```
[x] Verbinden  [x] Calib  [~] Zählen(Curls)  [~] Satz beenden  [ ] Korrigieren+Lernen  [ ] Training beenden
```

---

## Zusatz (nicht A1–A5, Session-Nutzen)

| Feature | Status |
|---------|--------|
| Diagnose-Overlay | [x] genutzt |
| Ghost Idle Settings 30/45/90/Aus | [x] Code + APK |
| M5 BtnA Start / Satzende | [x] User bestätigt |
| Kamera Preview + Pose | [x] User sieht sich |
| Front/Rück-Umschaltung | [x] Code+APK (`618e3bb`) |
| IMU autoritativ | [x] unverändert |

---

## Rest-Checkliste (≈ 3 Minuten, einmalig)

Bitte nur abhaken und hier oder in Doc 13 melden:

1. [ ] **A2:** 8–12 Curls, notieren: `App=__  Manuell=__`  
2. [ ] **A4:** Satz beenden → echte Zahl → **Speichern & lernen**  
3. [ ] **A1/A5:** **Training beenden** → Summary sichtbar  
4. [ ] **A3:** 5–10 s wackeln/ablegen → Falsch-Reps: `0 / wenige / viele`  

Wenn 1–4 ok → A1–A5 auf **[x]** setzen und Session schließen.

---

## Related files

- `COUNT_ZERO_ANALYSIS.md` — 0-Rep-Root-Cause  
- `RESEARCH_M5_BUTTONS_COUNTING.md` / Doc 16 — BtnA  
- logcat: `logcat_count_debug.txt`, `logcat_live12s.txt`

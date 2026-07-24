# FlowRep — Aktueller Hardware-Testplan

> **Stand**: 2026-07-24 (nach Code-Welle Audit/Settings; `main` u. a. Settings-Persistenz, Agreement-Badge, Dual-BLE)  
> **Ziel**: einmal klar sagen, **was am Gerät noch zu testen ist**, in welcher Reihenfolge, und was schon erledigt ist.  
> **Living Tracker**: [11_HARDWARE_QA_CHECKLISTE](../Version1.0/11_HARDWARE_QA_CHECKLISTE.md) · [13_OFFENE_PUNKTE](../Version1.0/13_OFFENE_PUNKTE.md)  
> **Letzte Session**: [sessions/2026-07-24/HW_SESSION_A1_A5.md](sessions/2026-07-24/HW_SESSION_A1_A5.md)

---

## 0. Kurzfassung

| Priorität | Was | Dauer (ca.) | Blockiert Release? |
|-----------|-----|-------------|---------------------|
| **P0** | 4 Kurzchecks A1–A5 formal abschließen | **≈ 5–10 Min** | **Ja** |
| **P1** | Neue Code-Features am Gerät smoke’n (Trust-UX, Prefs, BLE-Name) | ≈ 15–20 Min | Nein (aber stark empfohlen vor „fertig“) |
| **P2** | Robustheit / Gym-Session / Shadow-DoD | 30–90 Min | Nein (V1.1 / Pipeline-Gate) |
| **P3** | Store-Admin, iOS, optional CV-NPU | außerhalb Code | Store-Admin ja; iOS out-of-scope Labor |

**Kern-DoD-Pfad (Product):**

```
[x] BLE verbinden
[x] Guided Calib (gP)
[~] 8–12 Curls zählen (App vs. Manuell notieren)
[~] Satz beenden (UI oder BtnA)
[ ] Korrektur → „Speichern & lernen“
[ ] Training beenden → Session-Summary
[~] Kurz wackeln → keine wilden Falsch-Reps
```

Sobald die **vier P0-Checks** grün und notiert sind → A1–A5 auf **[x]** in Doc 11/13 und Session schließen.

---

## 1. Setup (einmal vor der Session)

### Geräte

| Item | Soll |
|------|------|
| Phone | Android (Labor: Xiaomi 21081111RG / `55j7xkiffixsyhxg` oder aktuell) |
| Stick | M5StickC Plus2, geladen |
| Firmware | Mind. DeviceEvent `fee4` (BtnA); optional Re-Flash mit `DEVICE_NAME "FlowRep"` |
| App | **Frisches Debug-APK** von aktuellem `main` installieren (nicht alte 0.1.0) |

### Build / Install (typisch)

```text
# Firmware (optional Re-Flash für Name FlowRep)
cd firmware && pio run -t upload

# App
cd app && flutter install   # oder build apk + adb install -r
```

### Vor dem Zählen prüfen

1. BLE: App findet **FlowRep** und/oder **GymTracker** (Dual-Scan).  
2. Status: verbunden, Akku-Anzeige.  
3. Settings: **Auto-Arm nach Calib** = an (Default).  
4. Ghost-Pause: Default **45 s** (nicht 0/Aus für den P0-Test).  
5. `_useNewPipeline` bleibt **false** — nicht umschalten.  
6. Diagnose optional aufklappen für `health=` / `place=` / `slowShadow=`.

---

## 2. P0 — Release-Blocker (≈ 5–10 Min) — **jetzt**

> Ein sauberer Durchlauf. Zahlen **aufschreiben** (dieses Doc, Session-Notiz oder Doc 13).

### P0.1 — Connect + Calib (meist schon ok, 1× bestätigen)

| Schritt | Erwartung | Notiz |
|---------|-----------|--------|
| Verbinden | „Verbunden“, Batches steigen | |
| Guided Calib | Wizard fertig, Profil gP geladen | |
| Auto-Arm | Nach Calib: Zählen startet **automatisch** (oder Chip ZÄHLT) | |

### P0.2 — Zählen E1 / A2

| Schritt | Erwartung | Notiz |
|---------|-----------|--------|
| 8–12 normale Curls (Armband-Lage wie trainiert) | Anzeige steigt plausibel | **App = ___** |
| Parallel manuell mitzählen | ±1 ok für Go | **Manuell = ___** |

### P0.3 — Satzende + Lernen E3–E4 / A4

| Schritt | Erwartung | Notiz |
|---------|-----------|--------|
| „Satz beenden“ **oder** M5 **BtnA** | Korrektur-Dialog | UI / BtnA: ___ |
| Echte Rep-Zahl setzen falls nötig | Dialog speichert | |
| **„Speichern & lernen“** | Snackbar z. B. Schwelle angepasst / gespeichert | [ ] |

### P0.4 — Session-Ende E5 / A1

| Schritt | Erwartung | Notiz |
|---------|-----------|--------|
| **Training beenden** | Session-Summary | [ ] |
| Summary | Engine (raw) vs. korrigiert erkennbar; Quality falls da | [ ] |

### P0.5 — Wackeln E2 / A3

| Schritt | Erwartung | Notiz |
|---------|-----------|--------|
| 5–10 s bewusst wackeln / Stick ablegen (nicht curl-ähnlich) | Keine wilden Falsch-Reps | **0 / wenige / viele:** ___ |
| Kurze Pause *zwischen* echten Curls (2–3 s) | Ghost friert **nicht** ein (45 s Idle) | [ ] |

### P0 Go-Kriterium

- [ ] App/Manuell notiert (P0.2)  
- [ ] Speichern & lernen einmal bestätigt (P0.3)  
- [ ] Training beenden + Summary (P0.4)  
- [ ] Wackel-Ergebnis notiert (P0.5)  

→ Dann: Doc 13 A1–A5 **[x]**, Doc 11 E1–E5 **[x]**, `10_RELEASE` §5 Punkte 3–4 **[x]**.

---

## 3. P1 — Code-seitige Features am Gerät (≈ 15–20 Min)

Nach P0 oder in derselben Session. Kein Release-Hard-Block, aber Vertrauen vor „1.0 fertig“.

### 3.1 Trust-UX (Audit follow-up)

| Test | Wie | Pass |
|------|-----|------|
| Status-Chip | BEREIT / ZÄHLT / GHOST sichtbar | [ ] |
| Active-Set HUD | Während Zählen: große Reps, wenig Setup-Clutter | [ ] |
| Sensor-Health | Stick ungewöhnlich / hoher Gyro-Ruhe → roter Banner (falls reproduzierbar) | [ ] / n.a. |
| Placement | Falsche Lage + Bewegung → gelber Re-Calib-Hinweis (falls reproduzierbar) | [ ] / n.a. |
| Set Quality | Nach Satzende / Summary Score-Label | [ ] |

### 3.2 Settings-Persistenz

| Test | Wie | Pass |
|------|-----|------|
| Toggle speichern | z. B. Auto-Arm **aus**, Rest 60 s, VBT aus | [ ] |
| App kill + neu starten | Werte noch da | [ ] |
| Übungsziel | Settings 5×8 setzen → kill → wieder da | [ ] |
| Auto-Arm wieder **an** | für Normalbetrieb | [ ] |

### 3.3 BLE-Name (Dual-Scan)

| Test | Wie | Pass |
|------|-----|------|
| Ungeflashter Stick | Advertise **GymTracker** → App verbindet trotzdem | [ ] / n.a. |
| Nach Re-Flash | Advertise **FlowRep** → App verbindet | [ ] / optional |

### 3.4 Form-Check / Vision (optional, ehrlich)

| Test | Wie | Pass |
|------|-----|------|
| Form-Check öffnen | Preview + Pose, Front/Rück | [x] Session 07-24 |
| IMU zählt weiter autoritativ | Kamera ändert den Haupt-Zähler nicht still | [ ] |
| Agreement-Badge | Nur wenn Kamera-Pref an **und** Fusion-Daten — „Pose bestätigt X/Y“; kein Override | [ ] |
| Disclaimer | Copy: zählt nicht statt IMU | [ ] |

### 3.5 Diagnose / Shadow (Beobachtung)

| Test | Wie | Pass |
|------|-----|------|
| Diagnose-Zeile | `health=` / `place=` / `slowShadow=` sichtbar | [ ] |
| Slow-Rep Shadow | Sehr langsame Curls: `slowShadow` kann steigen, **Live-Count unverändert** (kein Searchback live) | [ ] |

### 3.6 M5 BtnA Feedback

| Test | Wie | Pass |
|------|-----|------|
| BtnA Start / Satzende | wie P0 | [x] 07-24 |
| Settings: Button-Haptic/Audio aus | kein Phone-Buzz/Klick | [ ] |

---

## 4. P2 — Robustheit & Pipeline (nicht Release-Blocker 1.0)

### 4.1 Kurz-Robustheit (empfohlen, ≈ 20–30 Min)

| ID | Test | Pass |
|----|------|------|
| B2 | Clean-Install → Re-Calib Wizard komplett | [ ] |
| F | Screen-Lock ≥20 s Stream bleibt | [x] früher |
| F | BT aus → Reconnect | [x] früher |
| B3 | App 2–5 Min Hintergrund → Resume, Stream ok | [ ] |
| B7 | 15 Min Session ohne Crash (logcat) | [ ] |

### 4.2 Zähl-Qualität (Daten sammeln)

| Test | Ziel | Pass |
|------|------|------|
| 3× Sätze 8–12 Curls | App vs. Manuell Tabelle | [ ] |
| 1× langsame Curls | Unterzählung? `slowShadow` notieren | [ ] |
| 1× Ablegen 30 s | Ghost pausiert, keine Flut an Reps | [ ] |

Beispiel-Tabelle:

| Satz | Manuell | App | Delta | Notes |
|------|---------|-----|-------|--------|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |

### 4.3 Shadow / New Pipeline — **nicht freigeben**

| ID | Aktion | Status |
|----|--------|--------|
| B5 / G7 | `_useNewPipeline = true` | **Verboten** ohne Shadow G5/G6 DoD |
| G5/G6 | Parallel-Diff Curl vs. Wiggle am Arm | offen, wenn Shadow-Modus aktiv genutzt wird |
| G8 | Langzeit / Drift | offen |

### 4.4 Volle Gym-Session (B8)

Ein Training **ohne** Agent/ADB-Hilfe: Connect → Calib → mehrere Sätze → Learn → Ende.  
Notizen: Crashes, 0-Rep-Fallen, Ghost zu aggressiv, Akku, Usability.

---

## 5. P3 — Außerhalb / optional

| ID | Thema | Labor-Status |
|----|--------|--------------|
| C1 | iOS Archive | out of scope (kein iOS-Gerät) |
| C2 | Play Console / Signing | Admin |
| C4 | Store Listing / Privacy final | Admin |
| D* | NPU live / Webcam | optional; Code soft-fail |
| Firmware-Name | Re-Flash `FlowRep` | optional; Dual-Scan deckt GymTracker ab |

---

## 6. Was **nicht** testen / nicht umstellen

1. **`_useNewPipeline = true`** ohne Shadow-DoD.  
2. Vision als **Ersatz** für IMU-Zählung.  
3. `correctedReps` in `countedReps` mergen (Audit-Trail).  
4. Threshold „nach Gefühl“ ohne notierte Sätze.  
5. Force-Push / random Firmware-Experimente ohne Serial-Backup.

---

## 7. Session-Protokoll (Vorlage zum Ausfüllen)

```text
Datum: ________
Phone: ________   M5 Firmware: GymTracker / FlowRep (____)
App-Commit / APK: ________

P0.2 App=____  Manuell=____
P0.3 Speichern & lernen: ja / nein
P0.4 Training beenden + Summary: ja / nein
P0.5 Wackeln: 0 / wenige / viele   Notes: ________

P1 Prefs nach Kill: ok / fail
P1 BLE Name: GymTracker / FlowRep / beide
P1 slowShadow beobachtet: ____

Probleme / Screenshots:
-
```

Evidence ablegen unter:  
`docs/hardware/sessions/YYYY-MM-DD/`  
(z. B. `HW_SESSION_NOTES.md`, kurze logcat-Excerpts — **keine** riesigen Roh-Dumps committen).

---

## 8. Empfohlene Reihenfolge heute

```
1. Frisches APK installieren
2. P0 komplett (5–10 Min)  ← Blocker
3. P1 Prefs + Trust-Chips + optional Form-Check (15 Min)
4. Optional: ein zweiter Curl-Satz + slowShadow beobachten
5. Docs 11/13 abhaken + Session-Notiz
6. P2 nur wenn Zeit / vor „final release feeling“
```

---

## 9. Verweise

| Doc | Inhalt |
|-----|--------|
| [11_HARDWARE_QA_CHECKLISTE](../Version1.0/11_HARDWARE_QA_CHECKLISTE.md) | Living Checkboxen A–H |
| [13_OFFENE_PUNKTE](../Version1.0/13_OFFENE_PUNKTE.md) | A/B/C Prioritäten |
| [10_RELEASE_VORBEREITUNG](../Version1.0/10_RELEASE_VORBEREITUNG.md) | §5 Smoke |
| [PLAN_HARDWARE_VALIDIERUNG](PLAN_HARDWARE_VALIDIERUNG.md) | Älterer Phasenplan A–H (Detail) |
| [sessions/2026-07-24/HW_SESSION_A1_A5.md](sessions/2026-07-24/HW_SESSION_A1_A5.md) | Letzte Partial-Evidence |
| [AUDIT_FULL_REPO](../design/AUDIT_FULL_REPO_IMPROVEMENTS.md) | Code-Audits / Do-Not-Do |

---

## Changelog dieses Plans

| Datum | Änderung |
|-------|----------|
| 2026-07-24 | Neu: konsolidierter aktueller Plan (P0–P3) inkl. Post-Audit-Features (Prefs, Dual-BLE, Agreement, Shadow) |

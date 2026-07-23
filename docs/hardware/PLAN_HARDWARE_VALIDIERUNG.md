# Hardware-Testplan FlowRep

**Status:** Aktiv — Session 2026-07-23 pausiert nach Phase D  
**Stand:** 2026-07-23 (Basis: `main` ab `ccda100` + Calib-Load-Fix)  
**Letzte Ergebnisse:** `docs/hardware/sessions/2026-07-23/PROTOCOL_RESULTS.md`  
**Handoff:** `docs/hardware/sessions/(archiviert — siehe docs/README.md)`  
**Zweck:** Alles, was für Pipeline-Gate und Produktqualität auf echtem Gerät nötig ist — nicht nur „Gerät blinkt“.

---

## 0. Ziel & Erfolgskriterien

### Gesamtziel

1. **Datenpfad grün** (Firmware → BLE → Parser → Engine-Samples)
2. **Zählqualität messbar** (Legacy-Pfad, aktuell produktiv)
3. **Shadow-Pipeline bewerten** (neue Engine vs. Legacy auf denselben Samples)
4. **Gate-Entscheidung** dokumentieren: darf `_useNewPipeline = true` werden?

### Harte DoD (Go / No-Go)

| ID | Kriterium | Pass |
|----|-----------|------|
| G1 | Batch-Rate stabil | ~10–13 Hz Batches, Engine-Samples ~45–55 Hz nach JitterBuffer |
| G2 | Keine Parse-Fehler | 0 Parse-Errors über ≥5 min Stream |
| G3 | JitterBuffer | `dropRate < 5 %`, `underrunRate < 10 %` im ruhigen Satz |
| G4 | Kalibrierung | Guided Calib 2.0 schließt ab, Profil speichert Achse/Bias/θ |
| G5 | Zählung (Curls) | über ≥5 Sätze à 8–12 Reps: \|gezählt − real\| ≤ 1 pro Satz **oder** Korrekturrate &lt; 15 % der Sätze |
| G6 | Alltagsbewegung | ohne Curl: ≤ 1 Falschrep / 60 s (Gehen, Tippen, Arm schwenken) |
| G7 | Shadow | bei G5-Sätzen: `Δ = \|legacy − new\|` dokumentiert; Gate nur wenn Δ≈0 **oder** new klar besser und manuell verifiziert |
| G8 | Stabilität | Disconnect/Reconnect + 3 Sätze ohne Crash, State wieder sinnvoll |

**Gate für `_useNewPipeline = true`:** G1–G6 + G7 (new ≥ legacy auf denselben CSVs) + G8.

---

## 1. Rollen: KI vs. Adi

| Aufgabe | KI | Adi |
|---------|----|-----|
| Firmware bauen/flashen, Serial-Log | ✅ | USB anschließen, Gerät an |
| App bauen/installieren (`flutter run`) | ✅ | USB-Debugging / Install erlauben |
| BLE verbinden, Curls machen | Anleitung + Log-Auswertung | **Physisch bewegen, zählen** |
| Manuelle Ground Truth (Reps laut) | Protokoll vorgeben | **laut mitzählen / notieren** |
| CSV teilen / Datei holen | auswerten | Teilen-Button / Datei freigeben falls nötig |
| Shadow-Stats, Logs, Rate | ✅ auslesen/auswerten | — |
| Ergebnis in Doc committen | ✅ nach Freigabe | Review |

Ohne Adi: **keine** Bewegungstests. Alles andere (Flash, Build, Analyse) kann die KI führen, sobald Gerät/Handy bereit sind.

---

## 2. Voraussetzungen (einmalig vor Phase A)

### Hardware

- [ ] M5StickC Plus2 geladen, USB-C → PC (typisch **COM3**, CH9102)
- [ ] Android-Handy (z. B. HyperOS/Xiaomi), Bluetooth an, Standort an falls nötig
- [ ] Handy USB → PC (Debugging) **oder** APK manuell installieren

### Software (PC)

- [ ] Repo `main` aktuell (`git pull`)
- [ ] PlatformIO, Flutter, Geräte-Treiber
- [ ] Commit-Hash notieren (Test gehört zu **einem** Build)

### App-Konfiguration für Tests

- [ ] `main.dart`: `BleSensorProvider` (nicht Mock)
- [ ] Debug-Build (CSV-Aufnahme + Diags)
- [ ] Shadow: `enableShadowMode()` **nach** Kalibrierung mit `rotationAxis`/`gyroBias` (sonst keine neue Pipeline)

### Artefakt-Ordner pro Testdatum

```
docs/hardware/sessions/YYYY-MM-DD/
  PROTOCOL_RESULTS.md      # Checklisten + Zahlen
  serial_boot.log
  logcat_session.txt       # optional
  csv/                     # Rohaufnahmen
  shadow_summary.md
```

---

## 3. Phasen im Überblick

```
A  Firmware & Boot          (~15 min)
B  BLE & Datenrate          (~20 min)
C  Signal-Plausibilität     (~15 min)
D  Kalibrierung             (~20 min)
E  Zählung Legacy (Kern)    (~45–60 min)  ← kritisch
F  Robustheit / Alltag      (~20 min)
G  Shadow-Pipeline          (~30 min)     ← Gate
H  Auswertung & Entscheidung(~20 min)
```

Gesamt **ca. 2,5–3,5 h** reine Testzeit (mit Pausen/Neuflashen eher ein Halbtag).

---

## 4. Phase A — Firmware & Boot

**Zweck:** Gerät = Protocol v2, IMU OK.

| # | Schritt | Erwartung | Wer |
|---|---------|-----------|-----|
| A1 | `pio run` im `firmware/` | SUCCESS | KI |
| A2 | `pio run -t upload` (Gerät an, COM) | Upload OK | KI + Adi USB |
| A3 | `pio device monitor -b 115200` | Boot-Log, BMI270, kein `IMU FAIL` | KI |
| A4 | Display | „Bereit“ / Gym Tracker | Adi |
| A5 | Hash/Version notieren | Commit + Build-Zeit | KI |

**Fail → Stop.** Kein App-Test ohne grünes A.

*Referenz:* `docs/hardware/TESTPROTOKOLL_M5STICKC_PLUS2.md` Abschnitte 1–2 (Re-Verify nach App-Änderungen).

---

## 5. Phase B — BLE-Verbindung & Rate

**Zweck:** App sieht echte Samples, kein Parser-Tod.

| # | Schritt | Erwartung | Messung |
|---|---------|-----------|---------|
| B1 | `flutter run` (Debug) | App startet | — |
| B2 | Verbinden | „Verbunden“, Display „Verbunden“ | — |
| B3 | Serial: auto-start stream | `client connected` / stream | Serial |
| B4 | MTU | ~517 (HyperOS-Quirk OK) | UI-Diag |
| B5 | Sample-Zähler 60 s | steigt monoton | `diagEngineSampleCount` / UI |
| B6 | Batch-Rate | ~11–13 Hz | BLE-Diag / Log |
| B7 | Protocol | v2, 53 Byte, keine Parse-Errors | Log |
| B8 | JitterBuffer 60 s Ruhe/leichte Bewegung | drops & underruns loggen | `dropRate`, `underrunRate` |

**Pass:** G1, G2, grob G3 (Ruhe).

**Stolper:** Install-Sperre Xiaomi → USB-Installation erlauben; Gerät aus = kein COM.

---

## 6. Phase C — Signal-Plausibilität (ohne Zähl-DoD)

| # | Szene | Erwartung |
|---|--------|-----------|
| C1 | Stick ruhig flach | Accel-Mag ≈ 1.0 g, Gyro ≈ 0 |
| C2 | Langsam drehen | Gyro ändert sich, kein Clipping-Dauerplateau bei harten Swings |
| C3 | Dummy-Stream (falls Button noch da) | konstante Werte, isoliert BLE |
| C4 | 5 s nach Connect warten | `isSettled` (250 Samples ≈ 5 s) — **nicht** vorher zählen erwarten |

Optional: CSV 30 s Ruhe + 30 s Bewegung → Offline-Plot (`tools/dsp_lab_phase2_real_data.py` o. ä.).

---

## 7. Phase D — Kalibrierung (Guided 2.0)

**Zweck:** Achse/Bias/θ real, Voraussetzung für g_p + Shadow.

| # | Schritt | Erwartung |
|---|---------|-----------|
| D1 | Wizard starten | Stufen klar (Ruhe → … → Known-Count) |
| D2 | Ruhe-Phase | Gate besteht (wenig Bewegung) |
| D3 | Known-Count / Tap falls nötig | Profil entsteht |
| D4 | Nach Abschluss | `rotationAxis`, `gyroBias`, Threshold gesetzt; App speichert |
| D5 | Reconnect | Profil bleibt (kein „immer Idle“ / Wake-Bug) |
| D6 | CSV während Calib | Datei speichern für Offline |

**Fail-Hinweise:** zu wenig Gyro-Peak → kräftiger curlen; Wizard hängt → Log + Stufe notieren.

---

## 8. Phase E — Zählung Legacy (Hauptmessung)

**Das ist der Kern.** Protokoll pro Satz (vgl. `docs/09_TESTPROTOKOLL_TEMPLATE.md`):

### Setup

- Übung: **nur Bizeps-Curl** (V1)
- Montage: immer gleiche Position (z. B. Handgelenk, gleiche Orientierung)
- Nach Connect: **≥5 s warten** (Settling)
- Pro Satz: CSV an (Debug), manuell mitzählen
- Shadow: wenn möglich schon an (Phase G parallel), Legacy bleibt autoritativ

### Sätze (Minimum)

| Satz | Protokoll | Real (Adi) | App | Diff | CSV-Name | Notizen |
|------|-----------|------------|-----|------|----------|---------|
| E1 | 10 langsame Curls, sauber | | | | | |
| E2 | 10 normale Tempi | | | | | |
| E3 | 10 schnelle | | | | | |
| E4 | 8 mit Pausen zwischen Reps | | | | | |
| E5 | 12 mit Ermüdung / unsauber | | | | | |
| E6 | 10 nach 4 s Pause (neuer Satz) | | | | | Set-Ende? |

### Auswertung E

- Pro Satz: `Δ = |App − Real|`
- Pass G5 wenn ≥4/6 Sätze mit Δ≤1 **oder** Korrektur-Sätze &lt;15 %
- Typfehler getrennt notieren:
  - **Unterzählung** (echte Curl verpasst)
  - **Überzählung** (Doppelhump / Zittern)
  - **Falschstart** (Alltag → nächste Phase)

Historischer Bug (2026-07-18): *Alltag zählt, echte Curls nicht* — E + F müssen das gezielt widerlegen.

---

## 9. Phase F — Robustheit & Alltagsbewegung

| # | Test | Pass |
|---|------|------|
| F1 | 60 s gehen, Arm baumeln, **keine** Curls | ≤1 Falschrep (G6) |
| F2 | Handy bedienen, Stick am Arm | ≤1 Falschrep |
| F3 | BLE Disconnect (Bluetooth aus 10 s) → wieder an | reconnect, State OK, weiterzählbar nach Calib-Profil (G8) |
| F4 | App kurz Background → zurück | Stream/Zähler nicht tot |
| F5 | 3 Sätze hintereinander mit Satzpausen | paused/resting sinnvoll, History/Feedback falls aktiv |

---

## 10. Phase G — Shadow-Pipeline (Gate)

**Voraussetzung:** Kalibrierung mit Achse/Bias; `enableShadowMode()` aktiv; `_useNewPipeline` bleibt **false**.

| # | Schritt | Messung |
|---|---------|---------|
| G1 | Shadow an nach erfolgreicher Calib | Log: Shadow enabled |
| G2 | Sätze E1–E5 wiederholen **oder** dieselben CSVs offline durch beide Engines | `shadowStats`: legacy vs new |
| G3 | Pro Satz | `(legacy, new, Δ)` + Real |
| G4 | Jitter während Shadow-Sätzen | drop/underrun |
| G5 | Fälle mit Δ≠0 | CSV speichern, Root-Cause (Peak? Template? Settling? PhaseValidator?) |

### Gate-Regel (explizit)

```
IF G1–G6 (Legacy) bestanden
AND median(|new − real|) ≤ median(|legacy − real|)
AND keine systematische Alltags-Überzählung der New-Pipeline
THEN Empfehlung: _useNewPipeline = true in separatem Commit
ELSE: New-Pipeline-Bugs fixen, erneut nur G (nicht alles von vorn)
```

**Nicht** Flag flippen in derselben Session ohne dokumentiertes G-Ergebnis.

---

## 11. Phase H — Auswertung & Dokumentation

1. `docs/hardware/sessions/YYYY-MM-DD/PROTOCOL_RESULTS.md` ausfüllen
2. CSV-Index + Shadow-Tabelle
3. Kurzes Verdict:
   - Datenpfad: OK/NOK
   - Legacy-Zählung: OK/NOK
   - Shadow: ready / not ready
   - Nächster Code-Schritt (konkret)
4. Optional: Commit nur Docs (keine Produkt-Flags ohne Gate)
5. STATUS/Handoff einen Absatz updaten

---

## 12. Was wir **nicht** in diesem Plan mischen

| Thema | Warum raus |
|-------|------------|
| Token-Rotation | Security, parallel |
| Legacy-Code löschen | erst nach Gate |
| Template end-to-end verdrahten | Code-Arbeit; Hardware kann Fehlen zeigen |
| Multi-Übung / ML | out of V1-Scope |
| Store-Release / iOS | nicht nötig |

---

## 13. Session-Ablauf (praktisch)

### Session 1 (Pipeline-Plumbing) — ~45 min

**A + B + C**  
Ende: „Samples fließen, Rate/Jitter OK.“

### Session 2 (Zählen) — ~90 min

**D + E + F**  
Ende: G5/G6 Zahlen, CSV-Satz.

### Session 3 (Shadow-Gate) — ~60 min

**G + H**  
Ende: Go/No-Go für `_useNewPipeline`.

Zwischen Sessions: Gerät laden, gleiche Montage, gleicher Commit wenn möglich.

---

## 14. Checkliste „Start jetzt“ (Adi)

1. M5Stick **an** + USB am PC
2. Handy USB-Debugging / Bluetooth an
3. Kurz bestätigen: „Gerät an, COM sollte da sein“
4. Optional: Debug-Toggle für Shadow in UI (aktuell API `enableShadowMode()` — ggf. 1 Zeile in Provider für Tests)

Dann: **Phase A** (COM prüfen → flash falls nötig → Serial → App).

---

## 15. Risiken

| Risiko | Mitigation |
|--------|------------|
| Settling 5 s vergisst man | UI/Ansage „5 s warten“ vor Satz 1 |
| Shadow ohne Achse = no-op | Calib-Gate vor G |
| HyperOS BLE-Jank | drop/underrun messen, nicht nur „fühlt sich an“ |
| Ground Truth ungenau | lautes Mitzählen + Video optional |
| Zwei Engines, eine UI | nur Legacy-Zahl in UI; Shadow nur Log/Stats |

---

## 16. Verwandte Dokumente

- `docs/hardware/TESTPROTOKOLL_M5STICKC_PLUS2.md` — Boot/BLE/IMU-Grundprotokoll
- `docs/09_TESTPROTOKOLL_TEMPLATE.md` — Nutzer-/Satz-Template
- `docs/reference/protocol.yaml` — Wire-Format v2
- `docs/SPEC_CRITICAL_STEPS.md` — Status-Matrix Pipeline (Shadow-Gate)
- `app/lib/domain/workout_engine.dart` — `enableShadowMode()`, `shadowStats`

---

## Kurzfassung

Acht Phasen **A–H**: zuerst **Strom & Rate**, dann **Kalibrierung**, dann **echte Curl-Sätze mit manuellem Mitzählen + CSV**, dann **Alltag/Reconnect**, dann **Shadow-Vergleich**, dann **schriftliches Gate** für die neue Pipeline. Ohne G5–G7 kein `_useNewPipeline = true`.


# KONZEPT: Guided Calibration 2.0 — Recherche & detaillierter Plan (2026-07-16)

> **Rev 2 (2026-07-16, Review eingearbeitet):** (1) K5 aktualisiert — Baseline-Freeze ist seit Commit `3907706` implementiert; (2) neue Sektionen **§4 Architektur (Controller/Engine-Grenze mit Sequenzdiagramm)** und **§5 Neue Dependencies**; (3) Implementierungsplan mit **MVP-Priorisierung (V0/V1/V2/V3)** statt flacher Paketliste; (4) **Migrationsstrategie** für gespeicherte Legacy-Kalibrierungen; (5) **Multi-Exercise**-Keying im `ExerciseProfile` von Anfang an; (6) **Offline-Kalibrierung aus CSV** als risikoarme Vorstufe V0; (7) Performance- und Sample-Raten-Anmerkungen (Sweep, Tap-Lag); (8) Quellen-Authority differenziert (§10).

**Auftrag von Adi:** Die Guided Calibration funktioniert nicht zufriedenstellend — entweder werden viel zu viele oder zu wenige Reps erkannt; die optimalen Einstellungen sind schwer zu finden. Adis eigene Ideen: (a) per Button-Tippen jede gemachte Rep markieren, (b) die App führt stufig ("mach 1 Rep, dann 5, dann 10") und lernt daraus. Auftrag: gründlich recherchieren und einen detaillierten Plan erstellen.

**Methodik:** Code-Verifikation der bestehenden Kalibrierung (Fundstellen mit Datei:Zeile), Web-Recherche zu Kalibrierungs-/Personalisierungs-Ansätzen (Wearable-HAR, assistierte Annotation, Template-Matching, Metronom-Protokolle, Few-Shot-Adaption). Anschluss an `RECHERCHE_ZAEHLROBUSTHEIT_2026-07-16.md` (P0–P3) — dieses Konzept ist so entworfen, dass es **auch vor P0** (ehrliche Zeitbasis) schon deutlich robuster ist, von P0 aber profitiert.

---

## 1. Warum die aktuelle Guided Calibration fragil ist (Root-Cause-Analyse, code-verifiziert)

| # | Root Cause | Beleg | Konsequenz |
|---|---|---|---|
| K1 | **Henne-Ei-Problem:** Die Kalibrierung benutzt selbst eine Peak-Detection mit hartkodierten Parametern (`_minPeakHeight = 1.2`, `_minPeakDistanceSamples = 12`), um die Parameter der Peak-Detection zu finden. Diese Startparameter sind weder an Person noch Signal angepasst | `workout_engine.dart:197-201` | Doppel-Hub-Nutzer → zu viele Peaks; ruhige/langsame Nutzer → zu wenige Peaks. Exakt Adis Beobachtung |
| K2 | **Zählung ohne Wahrheit:** Kalibrierung ist "fertig", sobald 10 Peaks gefunden wurden — bei Überzählung also schon nach z. B. 5 echten Reps. Der Nutzer erfährt nie, was das System gezählt hat; es gibt keinen Review-Schritt | `calibrationTargetReps = 10`, Z.200 | Schwellen werden aus einem Gemisch aus echten Peaks + Echo-Buckeln gelernt; Fehler unsichtbar |
| K3 | **Eine einzelne fragile Statistik:** Threshold = 30. Perzentil der Peak-Höhen, danach `excursion × 0.5`, geclampet [0,10, 2,0]. Keine Robustheit (Median/MAD), kein Streuungs-Check | Z.199, Z.452-462 | Ausreißer und schwankende Rep-Qualität vergiften den Schwellenwert lautlos |
| K4 | **Kein Tempo-Lernen:** Kalibriert wird nur im gerade aktuellen Tempo. Da der Threshold gyro-dominiert ist (~≥114 °/s, s. RECHERCHE_ZAEHLROBUSTHEIT S2), verpasst er später langsamere Reps systematisch | gyroWeight/Threshold-Pfad | "Zu wenig erkannt" im Normalbetrieb trotz erfolgreicher Kalibrierung |
| K5 | ✅ **Teilweise behoben (2026-07-16, Commit `3907706`):** Die EMA-Baseline ist jetzt während `guidedCalibration` eingefroren (`_state != WorkoutState.guidedCalibration` in der Update-Bedingung, `workout_engine.dart:235-236`); laut Commit-Message setzt `startGuidedCalibration()` die Baseline bereits aus dem beruhigten Ruhe-Signal (3 s Ruhe + 5 s Countdown). **Verbleibend offen:** Es gibt kein explizites Qualitäts-Gate, das die Ruhe *verifiziert* (Stillstands-Check mit klaren Kriterien + Gyro-Bias- + Rausch-Schätzung) — wird durch Stufe 0 adressiert | Z.235-236, Commit `3907706` | Kontamination gestoppt; Ruhe-Qualität weiterhin Vertrauenssache |
| K6 | **Sample-basierte Konstanten** (12 Samples Mindestabstand) unter realer Burst-Zufuhr ohne ehrliche Zeitbasis (S3) | Z.198 + `ble_protocol_parser.dart:54` | Mindestabstand real bedeutungslos; Kalibrierung erbt das Pipeline-Problem |
| K7 | **Kein Feedback-Kanal:** Der Nutzer kann weder "falsch" sagen noch einzelne Phasen wiederholen; Abbruch = alles weg | UI/State-Machine | Frustration, Trial-and-Error mit unbekanntem Fehlergrund |

**Kernaussage:** Das eigentliche Defizit ist nicht "der falsche Perzentil-Wert", sondern das **Fehlen einer Wahrheit**. Solange die Kalibrierung ihre eigenen Detektionen als Ground Truth benutzt, kann sie ihre Fehler nicht erkennen. Beide Ideen von Adi liefern genau diese Wahrheit — der Button liefert Rep-Grenzen (starke Wahrheit), die Stufenführung liefert bekannte Anzahlen (ebenfalls starke Wahrheit, einfacher in der UX). Sie sind komplementär und werden unten kombiniert.

---

## 2. Recherche: Was sagt der Stand der Technik zu Kalibrierung?

### 2.1 "Kurz kalibrieren mit selbst gezählter Wahrheit" ist publizierte Praxis

Luu et al. 2022 (Step-Count-Personalisierung, PMC9183122, S-Authority) empfehlen explizit einen **Hybrid**: generelles Default-Modell für alle, plus kurze Selbst-Kalibrierung pro Nutzer — wörtlich: *"a short calibration process at the beginning for each subject … the subject counts his/her steps to provide feedback for the general models. Importantly, subjects could do this on their own."* Personalisierung nur dort, wo das Default-Modell versagt. Das ist exakt Adis Idee (b) — Nutzer macht bekannte Anzahl, System lernt daraus — und sie ist klinisch validiert (98–99 % personalisiert vs. 96–99 % generell; Ausreißer-Nutzer profitieren am stärksten, +10–41 %).

**Übertrag auf FlowRep:** Default-Parameter (Prior) + kurze geführte Kalibrierung mit bekannter Anzahl; Profil-Update statt Komplett-Ersatz.

### 2.2 Wenige Beispiele reichen — aber nur mit Prior (Regularisierung)

arXiv:2606.04798 (2026, S): Few-Shot-/One-Shot-Nutzeradaption für Wearable-HAR. Zentrale Befunde: (1) schon **3 s Kalibrierungsdaten** ("one shot") verbessern messbar (+2,8 bis +33 pp Makro-F1); (2) **rein empirische** Schätzung aus sehr wenigen Beispielen ist instabil und kann **schlechter** sein als gar keine Kalibrierung — Bayesianisches Update gegen einen **Prior** (Default-/Vorgänger-Parameter) ist der stabile Weg; (3) mit mehr Beispielen (≈16 Shots) darf der Prior-Einfluss sinken.

**Übertrag:** Nie wieder Threshold **nur** aus den aktuellen 10 Peaks (K3). Stattdessen: `neuerWert = gewichtete Mischung(alterWert/Default, Messwert)`, Gewicht wächst mit Anzahl und Konsistenz der Kalibrierungs-Reps. Das macht auch "Schnell-Rekalibrierung" mit nur 5 Reps sicher.

### 2.3 Assistierte Annotation: System schlägt vor, Mensch bestätigt (SAAT-Muster)

SAAT (Frontiers in Computer Science, 2025, A): Annotationstools für Wearable-Daten arbeiten am effizientesten so, dass das System **Segmentierungs- und Label-Vorschläge** macht und der Mensch nur bestätigt oder korrigiert (Klick statt Suche). Nachweislich schneller und weniger fehleranfällig als reine Handarbeit.

**Übertrag (Review-Phase):** Nach jeder Kalibrierungs-Stufe zeigt die App das Signal mit den **erkannten Rep-Markierungen**. Der Nutzer bestätigt ("ja, 5") oder korrigiert (Minus/Plus auf einzelnen Markern). Erst danach wird gelernt und persistiert. Verwandelt K2 von "blindem Vertrauen" in **verifizierte Kalibrierung** — und erzeugt nebenbei gelabelte CSVs (Ground Truth für `tools/dsp_lab_phase2_real_data.py`, P0.6).

### 2.4 Template-Matching mit persönlichem Template (Alternative/Ergänzung zur Schwelle)

Smart-surface/CSZ2016 (simpleskin.org, Übungs-Zählung): Pro Übung wird ein **Template** gebaut — alle Wiederholungen auf Median-Länge skaliert und gemittelt — und der Datenstrom per **DTW-Matching** (gleitendes Fenster) mit dem Template verglichen; die Match-Kurve wird mit **Hysterese-Schwellen** gepeakt. Zählgenauigkeit 80–100 % je Nutzer/Übung (Ø 89,9 %), user-unabhängig getestet. Industrie-Beleg für dasselbe Prinzip: Bowflex-ST560-Dumbbell zählt Curls produktreif über Gyro-/Bewegungsprofil statt nackter Accel-Schwelle (simplexitypd.com).

⚠️ **Authority-Hinweis:** Beide Quellen sind NA-geratet (Konferenz-PDF ohne Peer-Review-Nachweis bzw. Firmen-Blog). Der Template-Pfad ist daher **nicht Teil des Kernkonzepts**, sondern als optionale V3-Ergänzung eingeplant und vor produktivem Einsatz an eigenen CSV-Daten zu validieren (§6, §10).

**Übertrag:** Aus Phase A/B kann automatisch ein **persönliches Rep-Template** (Median-Rep) entstehen. Live kann die App neben dem Schwellen-Pfad einen **Ähnlichkeits-Pfad** rechnen (normalisierte Kreuzkorrelation des letzten Fensters mit dem Template; DTW optional später). Rep = Match-Peak mit Hysterese + Refractory. Robust gegen Amplituden-Drift (Ermüdung), weil es **Form** statt Höhe vergleicht — adressiert K4 ergänzend.

### 2.5 Metronom-Kadenz als Kalibrierungs-Stütze (Fallback, nicht Default)

Widerstands-Studien kontrollieren das Tempo standardmäßig per Metronom (z. B. 60 bpm: 1 s konzentrisch + 1 s exzentrisch, J. Strength & Conditioning Research 2012). Tempo-Review Wilk et al. 2021 (PMC8310485, S): reale Kontraktionsdauern reichen von explosiv bis **≥10 s** (Notation 2/0/1/0 … 5/0/10/0) — Beleg, dass eine Kalibrierung, die nur ein Tempo kennt, strukturell lückenhaft ist (K4).

**Übertrag:** (1) Pflicht-Lernphase mit **langsamen** Reps (siehe Plan, Stufe C). (2) Optionaler **Metronom-Modus** als Fallback (V2): Wenn die Erkennung in Stufe B zweimal scheitert, bietet die App "Führe mich im Takt" an (Ton/Sprache "hoch … runter", ~60 bpm). Mit bekannter Kadenz wird Detektion nahezu trivial (Autokorrelation bei bekanntem Lag; Zeitfenster um Cue-Zeiten) — die Kalibrierung kann nicht mehr "kollabieren", und das System lernt trotzdem die persönliche Amplitude/Achse. Garmin nutzt Metronom + Rep-Counting in Konsumentengeräten — UX-Präzedenzfall vorhanden.

### 2.6 Button-Ground-Truth funktioniert — aber Taps sind systematisch zu spät

Annotations-Literatur (EMG-Ground-Truth-Studie, CFS Journal 2024 [NA-Authority]; Best Practices Roggen et al., Pervasive 2010 [A]): zwischen Ereignis und manueller Markierung liegt eine **Reaktions-Verzögerung**, die systematisch und personentypisch ist; Ground Truth soll nicht ungeprüft "nachjustiert" werden, aber die Verzögerung muss charakterisiert/kompensiert werden.

**Übertrag (Adis Idee a, "Tap-to-Tag"):** Tippen bei abgeschlossener Rep (untere Position) liefert Rep-Grenzen als starke Wahrheit — **aber** Tap ≠ Rep-Ende im Signal (≈150–400 ms später, plus Tipp-Gewohnheit). Lösung: Tap wird im Suchfenster **rückwärts** auf das nächste Signal-Landmark ausgerichtet (lokales Minimum des Winkels bzw. Gyro-Nulldurchgang Richtung Ruhe), Median-Lag geschätzt und abgezogen. Taps bleiben **optional** (nicht jeder will tippen); wenn vorhanden, sind sie die stärkste Kalibrierungs-Wahrheit überhaupt (voll bestimmte Segmentierung) und später im Training ein Feedback-Kanal für Online-Adaption + gelabelte CSVs.

**Auflösungs-Hinweis:** Bei der aktuellen effektiven Abtastrate (~20 Hz, Bursts) ist ein Landmark nur auf **±50 ms** lokalisierbar — gegenüber dem 150–400-ms-Lag eine Unsicherheit von ~10–30 %, für die Lag-Korrektur ausreichend. Nach P0 (ehrliche 50-Hz-Zeitbasis) verbessert sich dies auf **±20 ms** automatisch.

### 2.7 UX-Referenz: Teachable-Machine-Schleife

Googles Teachable Machine (Apache 2.0, ai4k12.org/Google Creative Lab): Sammeln → sofort Testen → bei schlechtem Ergebnis gezielt Nachbeispiele geben → erneut Testen. Die Stärke ist nicht der Algorithmus, sondern die **sofort sichtbare Konsequenz** jeder Eingabe.

**Übertrag:** Jede Kalibrierungs-Stufe endet mit sichtbarem Ergebnis ("5/5 erkannt ✓" + Marker-Review). Der Nutzer erlebt, *dass* und *was* das System gelernt hat — Vertrauen statt Blackbox. Fehlschläge sind erlaubt und kosten nichts ("Wiederholen"-Button pro Phase, kein Gesamt-Reset).

---

## 3. Konzept: Guided Calibration 2.0 ("Lernen mit Wahrheit")

**Leitidee:** Die Kalibrierung ratet nicht mehr an der eigenen Detektion, sondern bekommt die Wahrheit in drei aufsteigend starken Formen — **bekannte Anzahl** (immer), **Tap-Grenzen** (optional), **Nutzer-Review** (immer) — und optimiert ihre Parameter so, dass sie diese Wahrheit reproduziert. Adis Ideen (a) und (b) sind darin vereint: (b) ist das Grundgerüst, (a) der optionale Turbo und Dauer-Feedback-Kanal.

### Ablauf (4 Pflicht-Stufen + 1 optionale)

```
Stufe 0  Ruhe (5 s still stehen)              → Baseline, Rauschboden, Gyro-Bias
Stufe A  "Mach genau 1 Rep"                    → Achse (PCA), Template-Seed, Pipeline-Check
Stufe B  "Mach genau 5 Reps in DEINEM Tempo"   → Known-Count-Optimierung (Hauptlernschritt)
Stufe C  "Mach 3 langsame Reps (~4–6 s)"       → Tempo-Robustheit (Fix K4)
Stufe D  Review & Verifikation                 → Nutzer bestätigt/korrigiert → Persistieren
(optional, jederzeit in B–D: Tap-Button pro fertiger Rep)   [V2]
```

#### Stufe 0 — Ruhe & Setup (5 s)
- Anzeige: "Steh still, Arm hängen lassen." Live-Check: `|gyro| < 15 °/s`, Varianz Accel klein.
- Lernt: `baseline`, Rausch-σ (npk-Init für duale Schwellen), **Gyro-Bias** (ZUPT-Anker aus RECHERCHE_ZAEHLROBUSTHEIT §2.1).
- Baut auf dem implementierten Baseline-Freeze (Commit `3907706`, K5) auf und ersetzt die implizite Ruhe-Annahme durch ein **explizites Qualitäts-Gate**: Ruhe wird gemessen und verifiziert, nicht nur angenommen.
- Qualitäts-Gate: Es müssen überhaupt Samples ankommen (**ENG-Check** — macht das offene "0 Reps"-Problem aus HANDOFF_AN_NAECHSTE_KI sofort sichtbar, mit klarer Fehlermeldung statt stillem Scheitern) und Ruhe muss erreicht werden.

#### Stufe A — "Genau 1 Rep" (bekannte Anzahl N=1)
- Anweisung: "Führe genau EINE Wiederholung aus, in deinem normalen Tempo. Danach still stehen."
- Da N=1 **bekannt** ist, ist die Segmentierung trivial: das Bewegungsfenster zwischen Ruhe und Ruhe IST die Rep.
- Lernt: **Rotationsachse** `a` (PCA auf die 3D-Gyro-Kovarianz des Fensters → projiziertes, vorzeichenbehaftetes `g_p`, s. RECHERCHE_ZAEHLROBUSTHEIT P2; Implementierung ohne Package, §5), Rep-Dauer `T₀`, Winkel-Exkursion `θ₀` (integriertes `g_p`), **Template-Seed** (resampelter Verlauf; Template-Nutzung selbst ist V3, §2.4), Peak-Höhen aller Kandidaten-Kanäle.
- Gate: Kein Bewegungsfenster gefunden → **spezifische** Meldung ("Keine Bewegung erkannt — Sensor sitzt locker / Verbindung?"), nicht generisches "Fehler".

#### Stufe B — "Genau 5 Reps, dein Tempo" (Haupt-Lernschritt, N=5)
- Anweisung: "Mache genau 5 Wiederholungen in deinem normalen Trainingstempo." Optional (V2): großer Tap-Button ("Tippe bei jeder fertigen Wiederholung").
- **Known-Count-Optimierung** (der Kern, ersetzt K1/K3):
  1. Kandidaten-Signale: `g_p` (aus Stufe A), combined, |gyro|.
  2. Sweep: Für jedes Signal und ein kompaktes Parametergitter (Schwelle θ ∈ [0,1 … max] in 20 Schritten; Refractory ∈ [0,35–0,75]·T₀; Prominenz ∈ {aus, 0,2·median}) zähle die Detektionen über das Aufnahme-Fenster.
  3. Zielfunktion: **count == 5** (hart), danach Regularität maximieren: minimale Variationskoeffizient der Intervalle (CV = σ/μ der Rep-Abstände), danach höchste Margin (θ möglichst weit über Rauschboden).
  4. Mit Taps (V2): stattdessen/zusätzlich Alignment-Score — jedes Tap-Intervall muss genau 1 Detektion enthalten.
- **Performance-Hinweis:** Der Sweep ist bewusst lightweight: ~360 Konfigurationen × ~10²–10³ Samples ≈ 10⁴–10⁵ Operationen → auf dem Handy **< 1 ms**, einmalig am Stufenende (kein Echtzeit-Anspruch). Kein Optimierungsbedarf.
- Lernt: θ (als `median − k·MAD` der validierten Peaks, k aus Optimierung), `minRepInterval = 0,5–0,55 · median(T)`, Prominenz-Minimum, Intervall-Statistik.
- Gates: Optimierung ohne Lösung → 1× Wiederholung mit Hinweis ("ruhiger absetzen"); 2× gescheitert → **Metronom-Fallback** (V2, §2.5). In V1 ohne Metronom: erneute Wiederholung mit Hinweistext.

#### Stufe C — "3 langsame Reps" (Tempo-Robustheit, N=3)
- Anweisung: "Jetzt 3 Wiederholungen, bewusst langsam — etwa 4–6 Sekunden pro Wiederholung."
- Prüft/nachjustiert: die aus B gewählten Parameter müssen **auch hier 3/3** zählen. Wenn nicht: θ schrittweise senken (bzw. auf prominenzbasiertes Kriterium wechseln), bis beide Stufen gleichzeitig korrekt zählen — θ wird damit **tempo-robust konservativ** statt tempo-overfittet (direkter Fix für K4/S2). Gyro-Nebenbedingung (≥50 °/s) darf für langsame Reps nicht hart sein → weich machen (nur noch Plausibilisierung über Vorzeichenwechsel von `g_p`).
- Widerspruch (kein θ zählt beide Stufen korrekt) → Hinweis + Review mit beiden Signalen; Nutzer entscheidet, welche Stufe wiederholt wird.

#### Stufe D — Review & Persistenz (SAAT-Muster, Pflicht)
- Bildschirm: Signalverlauf von B und C mit eingezeichneten Rep-Markierungen (Rendering via CustomPainter, §5); große Anzeige "Erkannt: 5 + 3. Stimmt das?" Plus/Minus-Korrektur pro Marker; danach ggf. Re-Optimierung mit der korrigierten Anzahl (One-Shot-Reopt, kein neues Training nötig).
- **Persistenz als `ExerciseProfile`** (ersetzt die heutigen zwei Einzelwerte; **von Anfang an per `exerciseId` gekeyed**, §6 Migration): {Rotationsachse `a`, `medianT/MAD_T`, θ, `minRepInterval`, Prominenz-Min, Gyro-Bias, `spk/npk`-Init, Qualitätsscore, Zeitstempel}. Template-Feld im Modell vorgesehen, Nutzung erst V3.
- **Bayesianisches Blending** (s. 2.2): bei Rekalibrierung `profil_neu = (1−w)·profil_alt + w·messwert`, `w` aus Anzahl und Konsistenz (z. B. w=0,5 bei konsistenter 8-Rep-Kalibrierung, w=0,25 bei wackeliger). Eine schlechte Rekalibrierung kann das Profil nie mehr ruinieren (K3-Weichei).

### Tap-to-Tag im Detail (Adis Idee a) — V2
- **Während Kalibrierung:** optionaler großer Button; jeder Tap = "Rep fertig". Taps werden lag-korrigiert (rückwärts auf Landmark ausrichten, Median-Lag abziehen, s. 2.6 inkl. Auflösungs-Hinweis) und liefern die stärkste Segmentierungs-Wahrheit: Die Optimierung muss nicht einmal sweepen — die Rep-Grenzen sind gegeben; Parameter lernen = Statistik über gegebene Segmente.
- **Während des Trainings (später):** derselbe Button als "Feedback-Tap". Jeder Tap wird mit der Detektion abgeglichen (Tap ohne Detektion = verpasste Rep → `npk/spk`-Schwellen adaptieren à la Pan-Tompkins; Detektion ohne Tap = Kandidat für False Positive → Log). Erzeugt fortlaufend gelabelte Daten (CSV) und senkt die Korrekturrate ohne neue Kalibrierung.
- **Risiko Ablenkung:** Tap ist immer optional; Default-Flow kommt ohne aus (bekannte Anzahl reicht).

### Was sich algorithmisch ändert (Mapping auf Code)
| Alt (heute) | Neu (2.0) |
|---|---|
| Hardcoded `_minPeakHeight=1.2`, `_minPeakDistanceSamples=12` (Samples!) | Alle Konstanten in **Sekunden/Prominenz**, gelernt aus Stufe A/B; Sample-Konstanten nur nach P0-Resampling |
| 30. Perzentil der Peak-Höhen | `median − k·MAD`, `k` aus Known-Count-Optimierung; Streuungs-Gate |
| Eine Zähl-Statistik, keine Verifikation | Known-Count-Sweep + Review-Phase (Nutzer-Wahrheit) |
| Threshold einmalig, Overwrite | `ExerciseProfile` (per `exerciseId` gekeyed) + Bayesianisches Blending, Schnell-Rekal mit 5 Reps möglich |
| Gyro ≥ 50 °/s hart am Peak-Index | Vorzeichenwechsel von `g_p` (weich), tempo-robust aus Stufe C |
| Baseline läuft während Kalibrierung weiter | ✅ **Bereits behoben** (Commit `3907706`); Stufe 0 ergänzt Ruhe-Qualitäts-Gate |
| Zwei Einzelwerte im Store | Versionierter Store mit Migration v1→v2 (§6) |

---

## 4. Architektur: Grenze zwischen WorkoutEngine und CalibrationController

**Entscheidung (Variante "Engine behält den State"):** Die `WorkoutEngine` bleibt der **einzige Eigentümer** von `WorkoutState` — inklusive `guidedCalibration`. Der `CalibrationController` ist ein Domain-Service **ohne eigenen Workout-State**: Er besitzt die **Stufen-Logik** (0/A/B/C/D), den Fenster-Recorder, den Optimierer und die Statistik, aber keine Ahnung von `idle/active/paused`. Die Engine delegiert im State `guidedCalibration` jedes Sample an den Controller und übernimmt das fertige `ExerciseProfile` am Ende über den bereits vorhandenen `applyCalibration()`-Pfad (Commit `3aecd27`).

**Begründung:** Eine einzige State-Machine (keine parallelen Wahrheiten); Controller ist rein und isoliert testbar (Dart + Python-Portierung); der bestehende Engine-Alt-Pfad kann hinter einer Flag verbleiben und schrittweise abgelöst werden (Regression: 15/15 Tests bleiben grün).

### Sequenzdiagramm (Sample- und Kontrollfluss)

```
BLE Provider        WorkoutEngine            CalibrationController        UI (Flow)        CalibrationStore
     │                    │                          │                      │                   │
     │ samples            │                          │                      │                   │
     ├───────────────────>│ processSample()          │                      │                   │
     │                    │ state==guidedCalibration │                      │                   │
     │                    ├─────────────────────────>│ onSample(s)          │                   │
     │                    │                          │── Stufen-Events ────>│ (Fortschritt,     │
     │                    │                          │   (stageAdvanced,    │  Live-Signal)     │
     │                    │                          │    qualityGateFail)  │                   │
     │                    │                          │                      │                   │
     │                    │                          │<── Nutzer-Aktion ────┤ (Stufe beenden,   │
     │                    │                          │  (finishStage(),     │  Tap, Korrektur,  │
     │                    │                          │   addTap(),          │  Bestätigen)      │
     │                    │                          │   correctCount(n))   │                   │
     │                    │                          │                      │                   │
     │                    │                          │── Review-Daten ─────>│ (Signal + Marker) │
     │                    │                          │                      │                   │
     │                    │ profile (Stufe D ✓)      │ finalize()           │                   │
     │                    │<─────────────────────────│  → ExerciseProfile   │                   │
     │                    │ applyCalibration(profile)│                      │                   │
     │                    ├─────────────────────────────────────────────────────────────────────>│ save(profile)
     │                    │ hasValidCalibration=true │                      │                   │
```

### Verantwortlichkeiten

| Komponente | Verantwortung | Nicht verantwortlich |
|---|---|---|
| `WorkoutEngine` | `WorkoutState`-Transitions, Live-Zählung, Konsum des Profils (θ, Refractory, `g_p`-Projektion), `applyCalibration()` | Stufen-Logik, Optimierung, Review-Daten |
| `CalibrationController` | Stufen 0/A/B/C/D, Fenster-Aufzeichnung, Known-Count-Optimierung, Statistik (median/MAD/CV), Qualitäts-Gates, Review-Daten-Aufbereitung, Blending | Workout-States, Persistenz, UI |
| `CalibrationStore` | Persistenz, **Versionierung + Migration v1→v2**, Keying per `exerciseId` | Logik |
| UI (Calibration-Flow) | Rendering (CustomPainter-Chart), Nutzer-Eingaben (Weiter, Tap, Korrektur), Fehlermeldungen | Jede Signalverarbeitung |

---

## 5. Neue Dependencies & Infrastruktur

| Feature | Benötigte Infrastruktur | Entscheidungsvorschlag | Wann |
|---|---|---|---|
| PCA / Rotationsachse (Stufe A) | Eigenvektorzerlegung | **Kein Package.** Nur 3×3-Kovarianz des Gyro-Fensters → Jacobi-Eigenzerlegung, ~60 Zeilen reines Dart, exakt testbar. Kein `ml_linalg` nötig | V1 |
| Signal-Visualisierung (Review, Stufe D) | Chart | **V1: `CustomPainter`** (Polyline + Marker, keine Dependency). `fl_chart` nur nachrüsten, wenn Zoom/Sonstiges nötig wird | V1 |
| Metronom (Fallback) | Audio/TTS | **V2-Entscheidung:** einfacher Beep (System-Sound/audioplayers) vs. Sprache (`flutter_tts`). V1 kommt ohne Metronom aus (Wiederhol-Hinweis statt Fallback) | V2 |
| Ähnlichkeits-Pfad (Template, §2.4) | NCC/DTW | **V3.** Zuerst normalisierte Kreuzkorrelation (O(n·m), trivial); DTW nur falls nötig, dann mit Sakoe-Chiba-Band (begrenzt O(n·b)) — Performance bei 50 Hz beachten | V3 |
| Tap-Pfad | — | Keine neue Dependency (Button-Event + Timestamp in den Sample-Stream) | V2 |

**Fazit: V1 (MVP) benötigt null neue Packages.**

---

## 6. Implementierungsplan (MVP-priorisiert)

**Reihenfolge & Abhängigkeiten:** Unabhängig von P0 startbar (Known-Count + Review sind robust gegenüber der fiktiven Zeitbasis, weil Anzahl statt Absolut-Timing zählt). P0.5 (Baseline-Freeze) ist **bereits umgesetzt** (Commit `3907706`, K5). Profitiert weiterhin von P0.3 (Resampling) für exakte Zeitkonstanten.

### V0 — Optionaler Vorläufer: Offline-Kalibrierung aus CSV (~1–2 Tage, risikoarm)

Bevor irgendeine UI gebaut wird, kann der gesamte Known-Count-Ansatz **offline** validiert werden:

1. Nutzer nimmt mit dem bestehenden `CsvSessionRecorder` Sätze mit **bekannter Anzahl** auf (z. B. 5 normale + 3 langsame Reps) und teilt die CSV.
2. Der Known-Count-Optimierer (Paket 1, Python) läuft in `tools/dsp_lab_phase2_real_data.py` gegen diese echten Daten.
3. Ergebnis: validierte Parameter + Beleg, dass der Ansatz an echter Hardware trägt — **bevor** der on-device Flow existiert. Optional: Profil-Import (JSON) in die App.

Das reduziert das Gesamtrisiko massiv und liefert nebenbei die lange fehlenden echten CSVs (P0.6).

### V1 — MVP: Known-Count + Review (ohne Tap, ohne Metronom, ohne Template-Nutzung) (~5–8 Tage)

| # | Arbeitspaket | Inhalt | Berührte Dateien | Größe |
|---|---|---|---|---|
| 1 | **Simulations-First** (ADR-022-Pflicht) | `tools/workout_engine_simulation.py` um Personas erweitern: Doppel-Hub-Nutzer, schwacher Nutzer, langsamer Nutzer, inkonsistenter Nutzer; Known-Count-Optimierer in Python. **Abnahme:** alle Personas → korrekte Parameter & 5/5 bzw. 3/3; injizierte Zählfehler werden im (simulierten) Review-Schritt gefangen | `tools/workout_engine_simulation.py` | M |
| 2 | Domain: `CalibrationController` | Neuer Domain-Service gemäß §4: Stufen 0/A/B/C/D (ohne Tap/Metronom), Fenster-Recorder, Optimierer (Sweep + Zielfunktion; lightweight, <1 ms — einmalig am Stufenende), Robust-Statistik (median/MAD/CV), Qualitäts-Gates, PCA 3×3 (§5), Blending | `app/lib/domain/calibration_controller.dart` (neu) | M |
| 3 | Domain: `ExerciseProfile` + Store-Migration | Profil-Modell **per `exerciseId` gekeyed** (V1: nur `bicep_curl`, Modell vorbereitet), Store-Struktur `{version: 2, profiles: Map<...>}`, **Migration v1→v2** (s. unten) | `app/lib/data/security/calibration_store.dart`, neues Modell | S |
| 4 | Engine-Anbindung | Engine delegiert Samples im State `guidedCalibration` an den Controller (§4); konsumiert Profil via `applyCalibration()` (Commit `3aecd27`); Alt-Pfad hinter Flag; Regression 15/15 Tests grün | `workout_engine.dart` | M |
| 5 | UI: Kalibrierungs-Flow inkl. Review | Stufen-Screens (Anweisung + Live-Signal), **Review-Screen** (CustomPainter-Chart + Marker + Bestätigen/Korrigieren), konkrete Fehlermeldungen, Wiederholen pro Stufe | `app/lib/presentation/screens/` (neu: `calibration_flow*.dart`) | M–L |
| 6 | Tests | Unit: Optimierer (Count-Match, CV-Tiebreak), Statistik, Blending, PCA, **Migration v1→v2**; Flow-Tests; Regression | `app/test/` | M |

**Explizit NICHT in V1:** Tap-Button, Metronom, Template-/Ähnlichkeits-Zählpfad, Online-Adaption.

### V2 — Wahrheiten verstärken (~4–6 Tage)

- **Tap-to-Tag** in Kalibrierung (§3, Lag-Korrektur inkl. ±50-ms-Hinweis §2.6) + **Feedback-Tap im Training** (V1-scope: nur loggen, keine Adaption — liefert fortlaufend Ground Truth).
- **Metronom-Fallback** für Stufe B (Audio-Entscheidung §5).
- Ground-Truth-CSV-Export mit Labels (Szenen, Rep-Grenzen) über `CsvSessionRecorder` → `tools/dsp_lab_phase2_real_data.py`.

### V3 — Später (bewusst zurückgestellt, §10 Authority)

- Template-/Ähnlichkeits-Zählpfad (NCC → ggf. DTW mit Sakoe-Chiba-Band) — vor produktivem Einsatz an eigenen CSVs validieren (NA-Quellen, §2.4).
- Online-Adaption aus Feedback-Taps (Pan-Tompkins-`spk/npk`-Update).
- Multi-Exercise-UI (Modell ist ab V1 vorbereitet).

### Migrationsstrategie (Legacy-Kalibrierungen)

Es existieren bereits gespeicherte Kalibrierungen im alten Format (zwei Einzelwerte `peakThreshold`, `minThresholdAboveBaseline` in `flutter_secure_storage`; im E2E-Test vom 2026-07-16 sichtbar, z. B. Schwelle 6,07).

1. `CalibrationStore.load()` erkennt das alte Format an fehlendem `version`-Feld.
2. Auto-Migration: Legacy-Werte werden in ein minimales `ExerciseProfile` gewrapt (`exerciseId: 'bicep_curl'`, neue Felder = Defaults/Priors, `qualityScore: low`, `migratedFrom: 1`).
3. Migrierte Profile sind funktional, aber die App **empfiehlt aktiv eine Rekalibrierung** ("Kalibrierung aus älterer Version — jetzt 2 Minuten neu kalibrieren für bessere Genauigkeit?").
4. Altes Format wird nie zurückgeschrieben; nach erstem Speichern liegt nur noch v2 vor.

### Multi-Exercise-Statement

`ExerciseProfile` ist von Anfang an **per `exerciseId` gekeyed** (`Map<String, ExerciseProfile>` im Store). V1 implementiert ausschließlich `bicep_curl` — Modell, Store und Migration sind aber so angelegt, dass Übung #2 später "ein Profil hinzufügen" ist statt "Pipeline umbauen" (vgl. RECHERCHE_99 §2.4).

---

## 7. Erfolgskriterien & Metriken

1. **Kalibrierungs-Erfolg:** ≥ 9/10 Erstversuche enden mit verifiziertem Profil (Review bestätigt ohne Korrektur).
2. **Zählgenauigkeit nach Kalibrierung:** MAE ≤ 0,5 Reps über 10 Validierungssätze (10–15 Reps), davon ≥ 3 Sätze in bewusst langsamem Tempo (Stufe-C-Vertrag: langsame Reps ≥ 90 % Recall — Fix K4 nachweisbar).
3. **Tempo-Robustheit:** gleicher Satz in 2 Tempos (normal/langsam) → Count-Differenz ≤ 1.
4. **Korrekturrate** (bestehendes Kriterium): < 15 %, gemessen über Review- + Feedback-Taps.
5. **Robustheit Rekalibrierung:** 5 absichtlich schlechte Rekalibs hintereinander → Profil driftet dank Blending ≤ 20 % vom verifizierten Referenz-Profil.
6. **Migration:** Legacy-Profil (v1) lädt fehlerfrei, wird automatisch gemigriert, Rekalibrierungs-Empfehlung erscheint, kein Crash/Reset (Unit-Test + manueller Check mit Bestandsdaten).

## 8. Risiken & Gegenmaßnahmen

| Risiko | Gegenmaßnahme |
|---|---|
| Nutzer führt Kalibrierungs-Reps schlampig aus | Streuungs-Gate (MAD/median > 30 % → "uneinheitliche Wiederholungen", Wiederholung der Stufe), Review-Phase, Metronom-Fallback (V2) |
| Taps lenken vom Training ab / werden vergessen | Taps strikt optional (V2); Known-Count funktioniert ohne; Taps nur als Turbo/Feedback |
| Metronom verändert die natürliche Bewegung | Nur Fallback (V2), nicht Default; gelernt wird trotzdem die persönliche Amplitude/Achse |
| Overfitting an eine Session | Blending mit Prior (2.2), Schnell-Rekalibrierung jederzeit, Feedback-Taps für Online-Adaption (V3) |
| Bekannte Anzahl wird falsch ausgeführt (Nutzer zählt sich selbst falsch) | Review-Phase zeigt Marker — Diskrepanz wird sichtbar und korrigierbar, bevor gelernt wird |
| Burst-Zeitbasis (S3) verzerrt `T₀`-Schätzung | Anzahl- statt Zeit-Logik dominiert; nach P0.3 Zeitkonstanten in Sekunden final korrekt |
| **Performance des Sweeps auf dem Gerät** | Bewusst lightweight: ~10⁴–10⁵ Ops, < 1 ms, einmalig am Stufenende (§3 Stufe B); kein Risiko, dokumentiert |
| **Migration alter Store-Daten** schlägt fehl / Datenverlust | Versionierung + Auto-Wrap (§6), altes Format bleibt beim ersten Laden unangetastet bis erfolgreiche Migration, Unit-Tests |
| **Vorzeitige Multi-Exercise-Generalisierung** | Modell generisch (Keying), UI/Flows V1 strikt single-exercise; keine generelle Übungslogik vor Übung #2 |
| Template-Pfad beruht auf NA-Quellen (§2.4) | Nicht Teil von V1/V2; V3 nur nach Validierung an eigenen CSVs; ADR-023 dokumentiert Quellenlage |

## 9. Offene Entscheidungen für Adi

1. **V0 (Offline-Kalibrierung aus CSV) zuerst?** Empfehlung: ja — validiert den ganzen Ansatz an echten Daten, bevor UI entsteht.
2. **Tap-Button in V2: Standard sichtbar oder opt-in?** Empfehlung: sichtbar mit "überspringen".
3. **Metronom-Fallback mit Sprachansage oder nur Ton?** Entscheidung erst in V2 nötig (§5).
4. **Review-Screen Pflicht bei jeder Kalibrierung oder nur bei Auffälligkeit?** Empfehlung: Pflicht (Kern des Konzepts), dauert < 10 s.
5. **Feedback-Tap im Training:** V2 nur loggen (Empfehlung) oder sofort adaptieren? Empfehlung: erst loggen, Adaption (V3) nach Auswertung der Logs.
6. **Charting:** CustomPainter (Empfehlung, keine Dependency) oder direkt `fl_chart`?

---

## 10. Quellen (mit differenzierter Authority)

**Kernkonzept stützt sich auf S/A-Quellen:** Known-Count-Selbstkalibrierung (Luu et al. 2022, S), Few-Shot mit Prior/Blending (arXiv:2606.04798, S), Review/assistierte Annotation (SAAT, A), Metronom-/Tempo-Begründungen (JSCR 2012, A; Wilk 2021, S), Annotation-Best-Practices (Roggen 2010, A), Teachable-Machine-UX (S).

**Schwächer abgesicherte Einzelbausteine (NA-Quellen) — bewusst NICHT im V1-Kern:** Template-Matching/DTW (Smart-surface CSZ2016, NA; Bowflex-Blog, NA) → V3, vorher an eigenen CSVs validieren; konkrete Tap-Lag-Größen 150–400 ms (CFS Journal 2024, NA) → als plausible Größenordnung behandelt, Lag-Korrektur misst den Lag ohnehin empirisch pro Nutzer (Median über Taps). **ADR-023 soll diese Unterscheidung explizit festhalten.**

| Quelle | Verwendet für | Authority |
|---|---|---|
| Luu et al. 2022 — pmc.ncbi.nlm.nih.gov/articles/PMC9183122 | Hybrid: Default + kurze Selbst-Kalibrierung mit nutzer-gezählter Wahrheit | S |
| arXiv:2606.04798 (2026) — Uncertainty-Aware Few-Shot User Adaptation | One-Shot reicht; Bayesianisches Update gegen Prior; Regularisierung | S |
| SAAT — frontiersin.org/journals/computer-science (2025, Günthermann) | System schlägt vor, Mensch bestätigt/korrigiert (Review-Muster) | A |
| Smart-surface/CSZ2016 — simpleskin.org/papers/CSZ2016.pdf | Persönliches Template, DTW-Match + Hysterese (V3) | NA |
| J. Strength & Conditioning Research 2012 — journals.lww.com/nsca-jscr | Metronom-Kadenz (60 bpm) als Standard-Protokoll | A |
| Wilk et al. 2021 — pmc.ncbi.nlm.nih.gov/articles/PMC8310485 | Tempo-Klassifikation → Pflicht-Tempo-Robustheit | S |
| EMG-Annotation (CFS Journal 2024) — cfs.kpu.edu.rs | Reaktions-Verzögerung bei manueller Markierung | NA |
| Roggen et al. 2010 — collaborative-ai.org/publications/roggen10_pervasive.pdf | Best Practices Ground Truth/Annotation | A |
| Teachable Machine — ai4k12.org/teachable-machine (+ Google Creative Lab Repo) | UX-Schleife Sammeln→Testen→Nachlernen | S (Repo) |
| Garmin Forerunner Manual — www8.garmin.com | Konsumenten-Präzedenz: Metronom + Rep-Counting | A |
| Bowflex ST560 — simplexitypd.com/blog/why-you-need-a-gyro-to-measure-position | Industrie-Beleg Gyro-Profil (V3-Plausibilität) | NA |
| Repo-intern: `RECHERCHE_ZAEHLROBUSTHEIT_2026-07-16.md`, `RECHERCHE_99_PROZENT_GENAUIGKEIT_2026-07-14.md`, `Umbauplan Flowrep/`, Commits `3907706`, `3aecd27` | P0-Pipeline, Pan-Tompkins-Transfer, MM-Fit-Rezept, ExerciseProfile, Baseline-Freeze, applyCalibration | — |

*Alle Code-Fundstellen (K1–K7) in dieser Sitzung direkt verifiziert; K5-Fix anhand Commit `3907706` und `workout_engine.dart:235-236` verifiziert.*

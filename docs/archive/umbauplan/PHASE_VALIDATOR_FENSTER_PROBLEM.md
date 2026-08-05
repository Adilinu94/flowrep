# PhaseValidator/DSP-Fenster-Problem — Diagnose, Recherche und Umsetzungsplan

**Datum:** 2026-08-04
**Session:** Claude (Session: e14e4950)
**Branch:** `fix-phase-validator-window`
**Status:** **Umgesetzt.** Parallel zu dieser Recherche hat Claude-38f650c4 einen Fix implementiert und auf diesen Branch gepusht (Commit `1000004`, vor dieser Doku in der Historie) — unabhängig verifiziert, siehe Nachtrag direkt unter diesem Kopf. Alles ab Abschnitt 11 beschreibt die eigene Empfehlung *vor* Kenntnis dieser Implementierung; als Kontext/Alternativvergleich stehengelassen, nicht mehr der aktuelle Handlungsplan.
**Bezieht sich auf:** Problem 2 aus dem Session-Handover vom 2026-08-03 (Claude-7e4b2c91), baut direkt auf Commit `bfa2669` auf

---

## Nachtrag (2026-08-04, nach Kollisions-Fund): Bereits umgesetzt und unabhängig verifiziert

Beim Kollisionscheck vor dem eigenen Push (Bauplan Punkt 6: `git fetch` + `git ls-remote` unmittelbar vor Push) zeigte sich, dass `origin/fix-phase-validator-window` inzwischen existierte: Claude-38f650c4 hatte parallel denselben Branch mit einer echten Implementierung gepusht (Commit `1000004`, `fix(detection): PhaseValidator-Fenster vor Validierung vervollstaendigen`). Diese Session startete offenbar vom selben ursprünglichen 2026-08-03-Handover wie diese hier, aber ohne den `bfa2669`-Fund (kein Verweis auf "nur dokumentieren" oder die drei Lösungsrichtungen in ihrem Eintrag) — ob Adi ihr separat grünes Licht gegeben hat oder sie auf Basis des ursprünglichen "Next Move" ohne Kenntnis der Zwischenzeit-Entscheidung weitergearbeitet hat, ist mir nicht bekannt.

**Der tatsächliche Ansatz** (`app/lib/domain/detection/rep_counter.dart`, gelesen und geprüft): einfacher als der externe Plan und meine eigene Empfehlung. Kein Umbau an `PeakDetector`/`PeakEvent` nötig — der komplette Pending-Zustand (`_pendingPeak`, `_pendingWindow`, `_pendingStartMin`, `_pendingExtraSamples`) lebt in `RepCounter` selbst. Dadurch ist das Zuordnungsproblem aus Abschnitt 3 strukturell ausgeschlossen, nicht nur vermieden — es gibt keine zweite Datenquelle, die dem falschen Peak zugeordnet werden könnte. Bei Kollision (neuer Peak trifft ein, während der alte noch offen ist) wird der alte sofort mit dem bis dahin gesammelten Fenster finalisiert, dann der neue gestartet — kein Datenverlust. Abschlussbedingung ist adaptiv (Rückkehr über den ursprünglichen Fenster-Tiefpunkt, oder Timeout bei 120 Samples), nicht fix — deckt sich mit meiner Empfehlung aus Abschnitt 6/7. Template-Matching läuft auf dem finalisierten (ggf. erweiterten) Fenster, nicht mehr auf dem schmalen — beantwortet die offene Frage aus Abschnitt 13 von selbst.

**Eigene Verifikation (nicht nur der Commit-Message geglaubt):**
- `flutter test` gegen die 4 Ziel-Dateien: **42/42 grün**, bestätigt exakt die Behauptung im Commit.
- `flutter analyze lib/domain/detection/`: keine Findings, bestätigt.
- Commit behauptet "477 Tests, 4 rot". Eigene volle Suite zeigt **455 Tests, 8 rot**. Vier davon sind der bekannte Cluster (ROM-Gate ×2, `p1_assets_structural_test.dart`, `reconnect_test.dart`). Die anderen vier — `drift_encryption_migration_test.dart`, `error_handler_test.dart`, `p2_polish_test.dart`, `widgets/home_screen_test.dart`, alle Ladefehler (Compile-Time) — waren mir neu. Gegenprobe: `rep_counter.dart` per `git checkout 28533ae --` auf den unveränderten `main`-Stand zurückgesetzt, dieselben vier Dateien erneut getestet — identischer Fehlschlag. Damit belegt: vorbestehend, nichts mit diesem Fix zu tun (vermutlich Umgebungsabhängigkeit, u. a. ein nicht überall verlinkter SQLite3-Cipher-Build laut einer älteren STATUS_FORTSCHRITT-Notiz). `rep_counter.dart` danach wiederhergestellt.

**Einordnung:** Der Fix ist solide und tut, was er soll. Die Abweichung in der Testzahl ist keine Qualitätsfrage des Fixes, sondern ein separates, vorbestehendes Thema, das getrennt angeschaut werden könnte.

---


## 0. TL;DR

- **Problem:** 4 Szenarien in `dsp_verification_test.dart` + 3 in `exercise_engine_pipeline_test.dart` schlagen fehl.
- **Root Cause:** Kein Validator-Bug, kein Policy-Bug. `PeakDetector` schließt sein Detektionsfenster strukturell zu früh (vor Ende der exzentrischen Phase); `PhaseValidator` bekommt ein unvollständiges Fenster und verwirft zurecht.
- **Warum der erste Fix-Versuch scheiterte:** Zuordnungsproblem, nicht Timing-Problem — ein nachträglich vervollständigtes Fenster wurde dem falschen Peak zugeordnet.
- **Eigene Empfehlung (vor Kollisions-Fund):** Pending-Slot-Architektur in `RepCounter`, Zählung bleibt zurückgehalten bis das Fenster vollständig ist. Exit-Bedingung adaptiv (Vorbild: `DirectionalGpShadow`), nicht fest. Als Kontext/Alternativvergleich stehengelassen (Abschnitt 11/12) — siehe Nachtrag unten, warum das nicht mehr der Handlungsplan ist.
- **Tatsächlich umgesetzt:** Claude-38f650c4 hat parallel eine noch einfachere Variante gebaut und gepusht (Commit `1000004`) — Pending-Slot komplett innerhalb von `RepCounter`, kein Cross-Object-Handover nötig. Unabhängig verifiziert: 42/42 Ziel-Tests grün, `flutter analyze` sauber. Eine Abweichung in der Commit-Message aufgeklärt (siehe Nachtrag).
- **Wichtigster Kontext-Fund:** Die komplette betroffene Pipeline läuft **nirgends live** (`_useNewPipeline = false`, strukturell erzwungen). Kein Produktionsrisiko, unabhängig vom Ausgang.
- **Status:** Umgesetzt und unabhängig verifiziert. Merge-Zeitpunkt liegt bei Adi (kein Merge nach main durch diese Session).

---
## 1. Ausgangslage

### 1.1 Problem 1 vs. Problem 2
Kurz zur Einordnung: Problem 1 (Handover-Rep-Verlust in `WorkoutEngine`) ist gelöst und auf `origin` gepusht (Branch `fix-live-gp-authority-coupling`, Commits `4656f4b`/`e382117`). Dieses Dokument behandelt ausschließlich **Problem 2**: den vorbestehenden Testfehler-Cluster rund um `PhaseValidator`/`PeakDetector`.

### 1.2 Wie dieser Thread entstand
Das Session-Handover vom 2026-08-03 (Claude-7e4b2c91) hinterließ als "Next Move": debuggen, warum ein Mechanismus namens `takeCompletedPhaseWindow` die 4 dsp-Szenarien nicht grün machte.

Beim Einstieg in diese Session (2026-08-04) zeigte sich: `flowrep-main` hatte einen neueren Stand als das Handover-Dokument. Die Arbeit war dort direkt fortgesetzt worden (in der geteilten Kopie, nicht in einer eigenen Session-Kopie) und mündete in Commit `bfa2669` (2026-08-03, 17:48, auf Branch `phase4-tracker-integration`) — mit einer vollständigen, tatsächlich gemessenen Diagnose und Adis Entscheidung "nur dokumentieren".

---

## 2. Diagnose (aus `bfa2669`, real gemessen)

### 2.1 Mechanismus
`PeakDetector.process()` (`app/lib/domain/detection/peak_detector.dart`) schließt sein Detektionsfenster, sobald das Signal unter `θ × fallingRatio (0.5)` fällt UND das für `fallingDebounce` (4) Samples in Folge anhält. Das ist für präzises Peak-**Timing** richtig (Pan-Tompkins-Prinzip), bedeutet aber: zum Zeitpunkt des Fenster-Abschlusses ist erst ein kleiner Teil der exzentrischen (negativen) Halbwelle im Fenster — der Rest liegt schlicht noch in der Zukunft.

### 2.2 Messwerte

| Fenster | Positiv/Negativ | Ratio | `PhaseValidator`-Urteil (Policy 0.15–0.85) |
|---|---|---|---|
| Abgeschnitten (27 Samples, wie real geliefert) | 24 / 3 | 0.89 | außerhalb → **verworfen** |
| Vollständiger Sinus (50 Samples) | 25 / 24 | 0.51 | innerhalb → **gültig** |

### 2.3 Konsequenz für die Policy-Frage
Die 0.15/0.85-Grenzen (Commit `c956607`, 2026-07-25, Policy "Überzählen > Unterzählen") sind **korrekt**. Sie machen nur einen vorbestehenden Fensterdefekt zum ersten Mal sichtbar — mit den alten Grenzen (0.05/0.99) rutschte 0.89 noch knapp durch. Der Defekt selbst ist älter als die Policy-Änderung.

---
## 3. Warum der erste Fix-Versuch scheiterte

### 3.1 Der Ansatz
Ursprünglich (Handover 2026-08-03): `PeakDetector` sollte nachträglich, über mehrere Frames hinweg, ein vollständiges Fenster sammeln (`takeCompletedPhaseWindow`), das `RepCounter` pro Frame abfragt und für die Validierung bevorzugt gegenüber dem schmalen Fenster verwendet.

### 3.2 Das tatsächliche Ergebnis
Implementiert, getestet, wieder verworfen (alles dokumentiert in `bfa2669`, nichts davon ist im Repo). Root Cause des Scheiterns:

> **Zuordnungsproblem, nicht Timing-Problem.** Peak N wird im selben Frame bestätigt, in dem Peak N−1s Fenster fertig wird. Das fertige Fenster gehört zu Peak N−1 — wird aber der Validierung von Peak N zugeordnet, weil beide Ereignisse im selben Frame zusammentreffen.

Wichtige Präzisierung gegenüber "die Entscheidung fällt, bevor das Fenster fertig ist" (so hat es ein zweiter, unabhängiger Lösungsvorschlag formuliert — siehe Abschnitt 10): Das Fenster IST rechtzeitig fertig, es landet nur beim falschen Empfänger.

---

## 4. Drei dokumentierte Lösungsrichtungen (aus `bfa2669`)

| # | Ansatz | Bewertung |
|---|---|---|
| 1 | **Verzögerte Bestätigung.** `RepCounter` hält eine erkannte Rep als "pending", bis die Gegenphase gelaufen ist, bevor sie zählt. 0.15/0.85 bleibt unangetastet. | Größter Umbau, aber einzige Variante, die den Defekt wirklich behebt. |
| 2 | **Ringpuffer im Validator.** Weniger invasiv, aber dasselbe Zuordnungsproblem in Teilen — bereits getestet und gescheitert. | Kein Ausweg. |
| 3 | **Policy zurück auf 0.05/0.99.** Suite sofort grün. | Laut `bfa2669`: "keine Lösung, nur Rücknahme der Sichtbarkeit" — revidiert die Produktentscheidung und lässt den Fensterdefekt bestehen. |

Damit bleibt Option 1 als einzige echte Lösung.

---
## 5. Recherche dieser Session: Der Umbau ist kleiner als angenommen

Geprüft anhand des echten Codes, nicht Vermutung:

- **`WorkoutStateMachine.handleEvent(RepCounted)`** (`app/lib/domain/state/workout_state_machine.dart`) reagiert nur auf ein bereits entschiedenes Event — setzt `_lastRepAt`, bleibt in `active`. Keine strukturelle Änderung nötig; das Event feuert einfach zeitversetzt.
- **`OnlineAdapter.onRepConfirmed()`** (`app/lib/domain/detection/online_adapter.dart`) ist ein reiner EMA-Statistik-Tracker, komplett entkoppelt von der Zähl-Entscheidung selbst. Auch hier: nur der Aufrufzeitpunkt verschiebt sich.
- Der eigentliche Umbau bleibt auf **`RepCounter.process()`** (`app/lib/domain/detection/rep_counter.dart`) beschränkt — aktuell strikt synchron: ein Frame rein, eine Entscheidung raus, kein Pending-Zustand.

---

## 6. Recherche dieser Session: Vorhandenes Muster im eigenen Code

`app/lib/domain/metrics/directional_gp_shadow.dart` — Shadow-only-Beobachter für die (separate) Legacy-gP-Pipeline, Zweck: Mount-Mismatch-Erkennung. Implementiert praktisch exakt das Muster, das Option 1 braucht:

```
ready → primary → awaitingReturn → ready
              (opposite als Sonderfall für Fehlmontage-Erkennung)
```

- Zählung passiert am Ende von **primary** (konzentrisch): reiner Samples-über-Schwelle- (`_minSamplesAbove=15`) + Peak-Amplitude-Check (`_peakOverThreshold=1.2`).
- Der volle Zyklus läuft in `awaitingReturn` weiter (`_cycleWindow`), für Template-Matching — **blockiert die Zählung nicht**.
- Exit aus `awaitingReturn` ist **adaptiv**, kein fixer Sample-Count:
  - Rückschwung unter `-θ × 0.3` mit anschließender Rückkehr in Schwellennähe, **oder**
  - 10 Samples am Stück nahe Null (`_minSettleSamples`) auch ohne klaren Rückschwung, **oder**
  - Timeout bei 250 Samples / 5s (`_maxAwaitReturnSamples`) als Notbremse, nicht als Regelfall.

Shadow-only, zählt nicht den Produkt-Counter — aber das Zustandsmuster ist real im Repo, getestet, und unabhängig vom aktuellen Problem entstanden.

---
## 7. Recherche dieser Session: Zahlencheck gegen echte Testdaten

`app/test/dsp_verification_test.dart` definiert Rep-Dauern über die Szenarien hinweg:

| Szenario | Dauer/Rep | Bei 50 Hz |
|---|---|---|
| 1 (perfekt) | 50 Samples | 1,0 s |
| 4 (langsam) | 100 Samples | 2,0 s |
| 5 (schnell) | 30 Samples | 0,6 s |

Ein fixes Wartefenster von ~25 Samples (wie im 2026-08-03-Handover grob geschätzt, oder ~10–30 Samples in einem zweiten, unabhängigen Vorschlag — Abschnitt 10) wäre für Szenario 4 zu kurz: die exzentrische Hälfte allein kann dort ~50 Samples brauchen. Ein festes kurzes Fenster würde exakt bei den langsamen Reps wieder zu früh abschneiden — derselbe Fehlermechanismus wie jetzt, nur verschoben statt behoben. Das adaptive Settle/Timeout-Verfahren aus Abschnitt 6 deckt 30–100 Samples komfortabel ab (Timeout liegt bei 250).

---

## 8. Externe Recherche

### 8.1 Pan-Tompkins hat dieses Problem nicht
Das Original-Verfahren (Namensgeber für `PeakDetector`s Docstring) behandelt unsichere Entscheidungen ausschließlich rückwärtsgewandt:
- **Search-back:** bei verpassten Peaks wird rückwärts in bereits durchlaufenen Daten gesucht, nie vorwärts gewartet.
- **T-Wave-Discrimination:** eine mögliche T-Welle wird von einem echten QRS-Komplex unterschieden, indem die Steigung des Kandidaten mit der des zuletzt bestätigten Peaks verglichen wird — wieder ein Vergleich mit der Vergangenheit.

Der QRS-Komplex ist ein in sich abgeschlossener Spike; er braucht nie ein Warten auf zukünftige Samples. Das Zukunfts-Problem bei uns entsteht nicht aus der Peak-Detection (sauber Pan-Tompkins-inspiriert), sondern aus `PhaseValidator`s Anforderung "beide Phasen im selben Fenster" — eine Anforderung, die Pan-Tompkins nie hatte. Für die Hälfte der Pipeline stimmt der Docstring-Verweis; für den Rest gibt es kein Pan-Tompkins-Rezept zum Nachschlagen.

### 8.2 Industriemuster bestätigt den Ansatz
Ein US-Patent zu Rep-Counting an Kabelzug-Trainingsgeräten ("Repetition phase detection") beschreibt exakt das Muster aus Abschnitt 6 als Standard: der Rep-Zähler inkrementiert regulär am Ende der konzentrischen Phase, während die exzentrische bzw. Ruhephase als separater Zustand weiterläuft. "Count auf primary, validieren/verfeinern danach" ist also kein Improvisieren, sondern verbreitete Praxis.

---
## 9. Kritischer Kontext-Fund: Die betroffene Pipeline läuft nirgends live

In `app/lib/domain/workout_engine.dart` (~Z. 94–110):

```dart
// === NEUE PIPELINE (KRITISCHER SCHRITT 3: Facade-Pattern) ===
// Feature-Flag: solang false, läuft der Legacy-Pfad unverändert weiter.
bool _useNewPipeline = false;

/// Shadow-Mode: Beide Pfade laufen parallel, Legacy bleibt autoritativ.
bool _shadowMode = false;
```

Beide Flags stehen fest auf `false`, zusätzlich abgesichert durch Structural-Tests (`app/test/product_path_structural_test.dart`, `app/test/vision/cv_structural_test.dart`), die das Nicht-Umschalten erzwingen. Bestätigt auch in `docs/Version1.0/13_OFFENE_PUNKTE.md`, B5: "G7: `_useNewPipeline = true` freigeben — nicht ohne Shadow-DoD (bleibt false)."

**Die komplette `ExerciseEngine`-Pipeline** (`PeakDetector` → `TemplateMatcher` → `PhaseValidator` → `QualityScorer` → `RepCounter`) — also alles, was in diesem Dokument behandelt wird — **ist diese "neue Pipeline"**. Sie läuft aktuell nirgends live. Der Legacy-Pfad (`_processSampleLegacy`, gP-basierte signed-gyro-projection-Zählung) bleibt autoritativ, bis eine eigene Shadow-DoD (G7) das ändert.

**Konsequenz:** Das ändert nichts an der fachlichen Sorgfalt, die dieses Problem verdient — aber nichts, was hier passiert oder nicht passiert, kann etwas live Laufendes beeinflussen. Kein Hotfix, sondern Qualitätsarbeit an einer noch nicht aktivierten Pipeline.

---
## 10. Zweiter Umsetzungsvorschlag (extern) — Bewertung

Adi legte parallel einen sechsstufigen Umsetzungsplan einer anderen KI-Instanz vor (Schritt 0: Freigabe abwarten; Schritt 1: Pflichtlektüre; Schritt 2: Pending-Slot-Architektur; Schritt 3: `PeakDetector`-Erweiterung; Schritt 4: `RepCounter`-Umbau; Schritt 5: Verifikation ohne Flutter-Zugriff via Python-Port; Schritt 6: Abschluss/Push). Kerndiagnose und Kern-Design (einzelner Pending-Slot statt komplexer Zuordnungslogik) sind richtig — das Design vermeidet implizit genau das Zuordnungsproblem aus Abschnitt 3, auch ohne das explizit zu benennen.

Vier Korrekturen dazu:

1. **Root-Cause-Begründung präzisieren.** "Entscheidung fällt vor Fenster-Fertigstellung" ⇒ tatsächlich "Fenster wird dem falschen Peak zugeordnet" (Abschnitt 3.2). Sollte als Code-Kommentar an der Pending-Slot-Stelle stehen, sonst geht der Grund fürs Vermeiden der komplizierteren Zuordnungslogik in einer späteren Session verloren.
2. **Kollisions-Timing explizit spezifizieren.** Der Plan lässt offen, was mit `PeakDetector`s internem Akkumulator passiert, wenn Peak N+1 bestätigt wird, während er noch für Peak N läuft. Muss vor der Implementierung feststehen: der Kollisionsfall aus Schritt 2 muss im selben Frame feuern, in dem `PeakDetector` den Akkumulator neu belegen würde — sonst können kurzzeitig zwei Peaks um einen Slot konkurrieren (dieselbe Fehlerklasse wie in Abschnitt 3, nur eine Ebene tiefer).
3. **Adaptive statt feste Wartezeit.** Siehe Abschnitt 7 — Vorbild ist `DirectionalGpShadow`s Settle/Timeout-Logik, nicht ein geschätzter fixer Sample-Bereich.
4. **Schritt 5 (Python-Verifikation) entfällt.** Diese Session hat echten `flutter test`-Zugriff auf Adis Maschine via Desktop Commander. Zusätzlich dokumentiert `workout_engine.dart` selbst einen Präzedenzfall (Kommentar bei `_awaitingSettleAfterCalibration`): ein Bug, den weder diese noch eine frühere Session per Python/Dart-Rekonstruktion fand — erst der echte `flutter test` zeigte ihn. Verifikation läuft direkt gegen die echte Suite.

---
## 11. Empfohlene Architektur (Synthese)

*Historisch — beschreibt die eigene Synthese vor dem Kollisions-Fund. Tatsächlich umgesetzt wurde die einfachere Variante aus dem Nachtrag oben; stehengelassen als Alternativvergleich.*

- `RepCounter` bekommt einen einzelnen Pending-Slot (kein Array, keine Zuordnungslogik über mehrere Peaks) — Zählung eines Peaks bleibt zurückgehalten, bis sein Fenster vollständig ist.
- `PeakDetector`s Fenster-Akkumulator wird explizit an genau diesen einen ausstehenden Peak gebunden. Trifft ein neuer Peak ein, während der alte noch offen ist: alten Peak sofort mit seinem eigenen (schmalen) Fenster nachträglich validieren — Fallback, geht nichts verloren, keine Zuordnungs-Verwechslung möglich, weil zu jedem Zeitpunkt maximal ein Kandidat existiert.
- Exit-Bedingung für "Fenster vollständig": adaptiv nach `DirectionalGpShadow`-Vorbild (Rückschwung+Settle, oder Settle allein, oder Timeout als Notbremse) — kein fixer Sample-Count.
- Zählung bleibt **pending, nicht optimistisch**: kein Zählen-und-Zurücknehmen. Ein optimistischer Zähler würde die "Überzählen > Unterzählen"-Policy auch nur für den kurzen Moment zwischen Anzeige und Bestätigung verletzen.
- `WorkoutStateMachine` und `OnlineAdapter` bleiben strukturell unverändert (Abschnitt 5).
- 0.15/0.85-Policy in `PhaseValidator` bleibt unangetastet.

---

## 12. Nächste Schritte (bei Freigabe durch Adi)

*Historisch — obsolet durch die bereits erfolgte Umsetzung (Nachtrag oben). Stehengelassen, um den ursprünglichen Gedankengang nachvollziehbar zu halten.*

1. Explizite Freigabe von Adi einholen — noch nicht erteilt (`bfa2669`: "nur dokumentieren"). **Dieser Schritt ist der Blocker, nicht Zeit oder Unklarheit.**
2. `PeakDetector` erweitern: Fenster-Akkumulator gebunden an genau einen offenen Peak, mit definiertem Verhalten bei Kollision (Punkt 2 aus Abschnitt 10).
3. `RepCounter.process()` umbauen: Pending-Slot-Logik, adaptive Exit-Bedingung (Abschnitt 6/11), Template-Match-Zeitpunkt separat entscheiden (bleibt sofort, oder wandert auf das volle Fenster wie bei `DirectionalGpShadow` — noch offen, siehe Abschnitt 13).
4. Gegen die 4 dsp- + 3 pipeline-Testfälle verifizieren via echtem `flutter test` (kein Python-Zwischenschritt).
5. Sicherstellen, dass die zuvor grünen Tests (`phase_validator_test.dart`, `rep_counter_test.dart`, weitere `exercise_engine_pipeline_test.dart`-Fälle) grün bleiben.
6. `flutter analyze` sauber.
7. Vor Push: `git branch -r` + letzte Commits auf Kollisionen prüfen.
8. Commit (mehrzeilig, deutsch, ehrlich was verifiziert wurde), STATUS_FORTSCHRITT-Eintrag, Push auf `fix-phase-validator-window`. Kein Merge nach `main`.

---
## 13. Offene Fragen für Adi

- **UX-Delay:** Peak passiert, Zähler tickt erst ~0,3–1 s später (variabel, je nach Rückschwung). Fühlt sich das in einer künftigen Live-Ansicht richtig an, oder braucht es ein sofortiges Zwischenfeedback (z. B. kurzes Pulsieren beim Peak, Zahl erst beim Bestätigen)? Rein produktseitig, keine technische Frage.
- **Template-Matching-Zeitpunkt:** ~~Offen~~ — durch die tatsächliche Umsetzung beantwortet: läuft auf dem finalisierten (ggf. erweiterten) Fenster, nicht auf dem schmalen. Siehe Nachtrag oben.
- **Zeithorizont:** Da nichts live läuft (Abschnitt 9), gibt es keinen Zeitdruck von der Produktseite. Priorisierung gegenüber anderen offenen Punkten (z. B. `docs/Version1.0/13_OFFENE_PUNKTE.md` §1 A1–A5, Hardware-Release-Blocker) liegt bei Adi.

---

## 14. Referenzen

**Code:**
- `app/lib/domain/detection/peak_detector.dart`
- `app/lib/domain/detection/phase_validator.dart`
- `app/lib/domain/detection/rep_counter.dart`
- `app/lib/domain/detection/online_adapter.dart`
- `app/lib/domain/state/workout_state_machine.dart`
- `app/lib/domain/metrics/directional_gp_shadow.dart`
- `app/lib/domain/workout_engine.dart` (Z. ~94–110, `_useNewPipeline`/`_shadowMode`)

**Tests:**
- `app/test/dsp_verification_test.dart` (Szenarien 1/3/4/7 rot)
- `app/test/exercise_engine_pipeline_test.dart` (3 Fälle rot)
- `app/test/phase_validator_test.dart` (Regressionsschutz 0.15/0.85 — muss grün bleiben)
- `app/test/product_path_structural_test.dart`, `app/test/vision/cv_structural_test.dart` (erzwingen `_useNewPipeline = false`)

**Docs:**
- `docs/Version1.0/13_OFFENE_PUNKTE.md` (B5/G7)
- `docs/archive/umbauplan/STATUS_FORTSCHRITT.md` (Einträge Claude-7e4b2c91, 2026-08-03, und dieser Session)

**Commits:**
- `bfa2669` — vollständige Diagnose, "nur dokumentieren"-Entscheidung
- `c956607` (2026-07-25) — Policy-Verschärfung 0.05/0.99 → 0.15/0.85
- `4656f4b`/`e382117` — Problem 1, zum Vergleich (gelöst, gepusht, nicht Teil dieses Dokuments)

**Extern:**
- Pan-Tompkins-Algorithmus: Search-back-/T-Wave-Discrimination-Mechanik (u. a. MDPI, MATLAB File Exchange)
- US-Patent "Repetition phase detection" (Kabelzug-Rep-Counting, Zählung am Ende der konzentrischen Phase)

---

*Ende des Dokuments. Nichts hieraus ist implementiert. Umsetzung wartet auf Freigabe.*

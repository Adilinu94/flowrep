# AUDIT: PhaseValidator-Fenster-Fix — Plan-Review und Implementierungs-Befunde (2026-08-05)

**Kontext:** Problem 2 (siehe `STATUS_FORTSCHRITT.md`, Session 7e4b2c91, Commit `bfa2669` auf `phase4-tracker-integration`) wurde in einer Multi-Agenten-Runde weiterbearbeitet: zwei unabhängige Plan-Entwürfe für Richtung 1 ("verzögerte Bestätigung"), gegenseitige Reviews, und parallel dazu eine echte, gepushte Implementierung (Commit `1000004`, Session 38f650c4, mit Flutter-Zugriff auf Adis Maschine, Branch `fix-phase-validator-window`). Dieses Dokument fasst zusammen, was sich aus dem Plan-Vergleich ergab, und — wichtiger — was ein Code-Audit der tatsächlich gepushten Implementierung ergeben hat.

**Methodik:** Kein Flutter/Dart-SDK in dieser Sandbox verfügbar (wiederkehrendes Muster in der Session-Historie dieses Projekts). Alle Befunde in diesem Dokument beruhen auf direkter Code-Lektüre und manueller Ausführungspfad-Verfolgung (Zeile für Zeile durchgespielt), NICHT auf echtem `flutter test`. Wo die reale Test-Suite bereits gelaufen ist (Commit `1000004`, 42/42 grün auf den vier relevanten Dateien), ist das explizit als solches gekennzeichnet.

---

## Zusammenfassung

Die gepushte Implementierung (`1000004`) löst das ursprüngliche Zuordnungsproblem sauberer als beide vorab diskutierten Pläne und ist gegen die reale Test-Suite grün. Ein Code-Audit hat zwei neue, von den Tests nicht erfasste Bugs in der Metadaten-Weitergabe an `ExerciseEngine` gefunden (Abschnitt 3). Beide betreffen nicht den Rep-Count selbst; ein minimaler Fix ist vorgeschlagen (Abschnitt 4) und **inzwischen umgesetzt** (Commit `01d2e9c`) — Details, eine Präzisierung und ein zusätzlicher Befund dazu in Abschnitt 7. Ein weiterer, unabhängig davon gefundener Befund (Template/Kalibrierungs-Formkonsistenz statt Metadaten) ist ebenfalls in Abschnitt 7 dokumentiert — offen, nicht angewendet.

---

## 1. Plan-Review: zwei unabhängige Entwürfe für Richtung 1

Zwei Plan-Entwürfe (Schritt-0–6-Format) wurden gegeneinander und gegen den Code geprüft, bevor die tatsächliche Implementierung bekannt wurde:

| Punkt | Befund |
|---|---|
| Ursache laut `bfa2669` | Zuordnungsproblem (Peak N wird im selben Frame bestätigt, in dem Peak N−1s Fenster fertig wird), **nicht** simple Verspätung. Ein Plan-Entwurf hatte das als Verspätung beschrieben — im Review korrigiert, gegen `bfa2669` verifiziert. |
| Risikolage | `_useNewPipeline`/`_shadowMode` beide `false` (`workout_engine.dart:96,110`), doppelt abgesichert durch `product_path_structural_test.dart` und `cv_structural_test.dart:84`, zusätzlich in `13_OFFENE_PUNKTE.md` (B5/G7: "nicht ohne Shadow-DoD") als Produktpolitik verankert. **Präzisierung:** `enableShadowMode()` wird trotzdem automatisch beim Laden eines Kalibrierungsprofils mit gültiger Achse/Bias aufgerufen (`engine_provider.dart:~1397`) — die Pipeline läuft für kalibrierte Nutzer im Hintergrund mit (nur nicht zählend). Kein User-Risiko, aber relevant für die Shadow-Diff-Qualität. |
| Feste Verzögerung (z. B. 25 Samples) | Zu knapp für langsame Reps (Szenario 4, 100 Samples/Rep), per Python-Portierung empirisch bestätigt (Ratio beim 200-Sample-Stresstest nur 0,79, knapp unter der 0,85-Grenze). |
| Übernahme von `directional_gp_shadow.dart`-Konstanten (`_rearmRatio=0.3`, `_minSettleSamples=10`, `_maxAwaitReturnSamples=250`) | Keine dokumentierte Tuning-Begründung gefunden (`DIRECTIONAL_GP_SHADOW_ROLLOUT_2026-07-27.md` durchsucht, kein Treffer) — andere Schwellen-Quelle (statisch vs. `PeakDetector`s adaptives SPK/NPK). Reine Übernahme wäre unbegründet gewesen. |
| `_awaitingSettleAfterCalibration`-Präzedenzfall | Verifiziert real: mehrere frühere Python/Dart-Verifikationen in diesem Projekt waren nachweislich "verfrüht" — erst echter `flutter test` fand den tatsächlichen Fehler. Relativiert, wie viel Vertrauen reine Code-Lektüre bzw. Python-Simulation verdient. |

**Ergebnis:** Beide Pläne wurden nicht in der geplanten Form umgesetzt — Commit `1000004` wählt eine andere, einfachere Architektur (Abschnitt 2).

---

## 2. Implementierungs-Audit: Commit `1000004`

**Architektur:** Fenster-Erweiterung läuft vollständig in `RepCounter` (`_pendingPeak`/`_pendingWindow`, `rep_counter.dart:92-97`). `PeakDetector`/`PeakEvent` bleiben unangetastet — kein Cross-Object-Handover. Das vermeidet das Zuordnungsproblem aus `bfa2669` strukturell, ohne die in beiden Plänen diskutierte Synchronisation zwischen zwei unabhängigen Akkumulatoren.

**Kollisionsbehandlung** (`rep_counter.dart:118-130`): Trifft ein neuer Peak ein, während der alte noch aussteht, wird der alte sofort mit seinem bisherigen (ggf. teilweise erweiterten) Fenster abgeschlossen, bevor der neue übernommen wird. Eindeutig, da nie mehr als ein Kandidat existiert.

**Exit-Bedingung** (`_pendingComplete()`, `rep_counter.dart:159-165`): signalbasiert — Fenster gilt als vollständig, wenn es unter sein eigenes Startminimum gefallen und wieder auf ≥0 zurückgekehrt ist, oder nach 120 zusätzlichen Samples (Sicherheits-Cap). Reine Hüllkurven-Peaks (kein negativer Anteil) entscheiden weiterhin sofort. Robuster als eine feste oder proportionale (z. B. "2× bisheriges Fenster") Verzögerung, da keine Symmetrie zwischen konzentrischer und exzentrischer Phase unterstellt wird.

**TemplateMatcher** bekommt jetzt dasselbe (ggf. erweiterte) Fenster wie `PhaseValidator` (`_decide()`, `rep_counter.dart:181`) statt wie vorher nur das trunkierte — beantwortet eine zuvor offen diskutierte Frage.

**Reale Verifikation:** 42/42 grün auf `dsp_verification_test.dart`, `exercise_engine_pipeline_test.dart`, `phase_validator_test.dart`, `rep_counter_test.dart`; volle Suite exakt auf den erwarteten vorbestehenden Rest-Cluster reduziert; `flutter analyze` ohne neue Findings in `lib/`. `phase_validator.dart` (0,15/0,85-Policy) unverändert.

---

## 3. Zwei neue Befunde (🟡 Fix angewendet, noch nicht real getestet — siehe Abschnitt 7 — ursprünglich durch die Tests nicht erfasst)

Die Commit-Message räumt selbst ein: *"eine verzögerte statt sofortige Entscheidung ist für diese Tests unsichtbar"* — genau in dieser Lücke liegen beide folgenden Befunde. Kein Rep-Count ist falsch, kein Test schlägt fehl.

### Befund A — Systematische Dauer-Verfälschung (jede Rep mit exzentrischer Phase)

`ExerciseEngine._onRepCounted()` liest `_repCounter.peakDetector.lastPeakDurationSamples` (`exercise_engine.dart:246`). Dieser Wert ist in `PeakDetector` als `_window.length` definiert (`peak_detector.dart:162`) — also **immer** die ursprüngliche, trunkierte Fensterlänge zum Detektionszeitpunkt. `RepCounter._decide()` verwendet für `QualityScorer.score()` aber das tatsächliche, ggf. erweiterte `window.length` (`rep_counter.dart:205`).

**Konsequenz:** Für jede Rep mit exzentrischer Phase (nach diesem Fix: die meisten normalen Reps) meldet `OnlineAdapter.onRepConfirmed()` eine systematisch zu kurze Dauer. Die adaptive Erwartungswert-Baseline (`QualityScorer.updateExpectations()`) driftet dadurch schleichend Richtung "zu kurz" — mit potenziellem Effekt auf künftiges Scoring. Vor diesem Fix nicht beobachtbar, weil Reps mit exzentrischer Phase kaum je gezählt wurden.

`prominence` ist davon **nicht** betroffen (ändert sich nicht durch Fenster-Erweiterung).

### Befund B — Falsche Metadaten im Kollisionsfall

Im Kollisionsfall (`rep_counter.dart:118-127`) läuft `peakDetector.process(frame)` für den **neuen** Peak N+1 zuerst — das überschreibt `_lastPeakDurationSamples`/`_lastPeakProminence` in `PeakDetector` mit N+1s Werten (`peak_detector.dart:161-163`), **bevor** `_finalizePending()` für den **alten** Peak N das Ergebnis zurückgibt. `ExerciseEngine` meldet dann N als gezählt, aber mit N+1s Dauer **und** Prominenz an `OnlineAdapter`.

`RepResult` selbst (`repNumber`/`qualityScore`/`correlation`) bleibt korrekt — `_decide()` verwendet für diese Felder direkt die übergebenen `PeakEvent`/`MatchResult`-Objekte, nicht den mutablen `PeakDetector`-Zustand.

---

## 4. Vorgeschlagener Fix (historisch — inzwischen umgesetzt, siehe Abschnitt 7)

*Ursprünglicher Vorschlag, unverändert stehengelassen als Nachvollzug der Herleitung.*

Geprüft auf Nebenwirkungen: `lastPeakDurationSamples`/`lastPeakProminence` werden nirgends außer `exercise_engine.dart` und `peak_detector.dart` selbst referenziert; `RepResult` hat keine `==`/`toString`-Overrides; kein Test konstruiert `RepResult` direkt.

1. `rep_counter.dart`: `RepResult` um zwei nullable Felder erweitern (`durationSamples`, `prominence`), befüllt in der "REP GEZÄHLT"-Rückgabe (aktuell Zeile 221-226) mit exakt den Werten, die Zeile 205/219 bereits berechnen — keine neue Logik, nur zusätzliche Speicherung.
2. `exercise_engine.dart:246-247`: von `_repCounter.peakDetector.lastPeakDurationSamples`/`.lastPeakProminence` auf `result.durationSamples!`/`result.prominence!` umstellen.

Löst A und B gleichzeitig, zwei Dateien, keine Änderung an `PeakDetector` nötig — konsistent mit der "alles bleibt in `RepCounter`"-Philosophie von `1000004`.

---

## 5. Risikoeinordnung

Nicht dringend: `_useNewPipeline=false` bleibt in Kraft, nichts davon zählt live. Aber nicht folgenlos: Für kalibrierte Nutzer läuft die Pipeline im Shadow-Mode mit (Abschnitt 1) — Befund A/B verfälschen dort leise die Adaptations-/Scoring-Diagnostik, die für die spätere Rep-Diff-=-0-Freigabe (B5/G7) relevant ist. Mit dem Fix (`01d2e9c`) adressiert, siehe Abschnitt 7 für den Verifikationsstand.

---

## 6. Referenzen

- `docs/archive/umbauplan/STATUS_FORTSCHRITT.md` — Session-Historie, u. a. Commit `bfa2669` (Session 7e4b2c91, ursprüngliche Diagnose) und der Eintrag zu diesem Audit.
- `docs/Version1.0/13_OFFENE_PUNKTE.md` — B5/G7 (`_useNewPipeline`-Freigabe-Bedingungen).
- `docs/design/DIRECTIONAL_GP_SHADOW_ROLLOUT_2026-07-27.md` — geprüft als möglicher Präzedenzfall für Schwellenwerte, keine übertragbare Tuning-Begründung gefunden.
- `docs/archive/umbauplan/PHASE_VALIDATOR_FENSTER_PROBLEM.md` (Session e14e4950) — unabhängiger, tieferer Plan-Review und eigene Re-Verifikation von `1000004`.
- Commit `1000004` (`fix-phase-validator-window`) — auditierte Implementierung.
- Commit `01d2e9c` — Umsetzung der in Abschnitt 4 vorgeschlagenen Fixes A+B (siehe Abschnitt 7).

---

**Status:** Befunde dokumentiert, Fix vorgeschlagen und **umgesetzt** (`01d2e9c`). Noch offen: echter `flutter test`-Lauf gegen die vier Zieldateien — Details und ein zusätzlicher Befund in Abschnitt 7.

---

## 7. Nachtrag (2026-08-05, Claude-edbf16cb, claude.ai-Sandbox, kein Flutter-Zugriff)

Review dieses Audits gegen den echten Diff geprüft statt nur gelesen. Beim anschließenden Kollisionscheck (vor dem Schreiben dieser Ergänzung) zeigte sich, dass der Branch sich seit der Erst-Review bereits weiterbewegt hatte (`01d2e9c`, `6654650`) — die folgenden Punkte sind gegen den *aktuellen* Stand geprüft, ein ursprünglich mitgebrachter Befund (fehlende zweite Fundstelle) war dadurch bereits überholt.

**Der in Abschnitt 4 vorgeschlagene Fix ist umgesetzt, vollständig:** Commit `01d2e9c` (Session 38f650c4) hat unabhängig auch die zweite, im Audit-Text nicht genannte Fundstelle erfasst (`RepEvent`-Konstruktion, vormals `exercise_engine.dart:264-265`), nicht nur `onRepConfirmed()` (246-247). Gegengeprüft: `grep -n "lastPeakDurationSamples\|lastPeakProminence" app/lib/domain/exercise_engine.dart` liefert keine Treffer mehr.

**Aber `01d2e9c` ist selbst nicht mit echtem `flutter test` verifiziert.** Laut eigener Commit-Message verlor die Session mitten in der Umsetzung den Flutter-Zugriff, nur Code-Lektüre. Session `e14e4950` (Commit `6654650`) hat `1000004` real gegengetestet und dabei eine echte Abweichung zur Commit-Message gefunden (477/4 behauptet, 455/8 tatsächlich — vier zusätzliche, als vorbestehend bestätigt) — Präzedenzfall dafür, dass "beim Lesen korrekt" hier nachweislich nicht immer mit "real getestet" übereinstimmt. `01d2e9c` liegt zeitlich nach dieser Verifikation (19:19 vs. 07:37 Uhr) und wurde von ihr nicht erfasst. Sollte vor Vertrauen denselben echten Testlauf bekommen wie `1000004`.

**Neuer Befund, bislang nur in `01d2e9c`s Commit-Message erwähnt, hier konsolidiert:** `RepCounter._trackForAdaptation()` führt eine eigene rollierende Mittelwertbildung (`_recentDurations`/`_recentProminences`, letzte 10 Reps) und ruft darüber `qualityScorer.updateExpectations()` auf. `ExerciseEngine._onRepCounted()` ruft dieselbe Methode ein zweites Mal auf, mit Werten aus dem separaten `OnlineAdapter`-EMA — und das immer *danach*, da `_onRepCounted()` erst nach `RepCounter.process()` läuft. Effekt: `RepCounter`s eigene Rolling-Average-Logik wird bei jeder gezählten Rep sofort überschrieben, bevor sie je wirksam wird. Kein Bug (QualityScorer bekommt sinnvolle Werte, nur vom anderen Pfad) — aber in der Wirkung toter Code, der beim isolierten Lesen von `RepCounter` fälschlich als die aktive Anpassungslogik erscheint. Vorbestehend (nicht durch `01d2e9c` verursacht), nicht Teil des hier vorgeschlagenen Fixes.

**Verwandtes Dokument:** `docs/archive/umbauplan/PHASE_VALIDATOR_FENSTER_PROBLEM.md` (Session `e14e4950`) deckt einen Großteil derselben Recherche ab (DirectionalGpShadow-Muster, Pan-Tompkins, `_useNewPipeline`-Fund, externe Bewertung) mit eigenem Empfehlungsabschnitt — hier nicht dupliziert, nur referenziert.

---

**Ergänzung (2026-08-05, Claude-e14e4950, claude.ai-Sandbox — Desktop Commander war ab diesem Punkt auch für diese Session nicht mehr verfügbar):** Kollisionspfad (Befund B) zusätzlich per Kontrollfluss nachverfolgt, nicht nur per grep-Abwesenheit der alten Referenzen: `_finalizePending()` erfasst `peak`/`window` in lokale Variablen, *bevor* `_startPending()` für den neuen Peak `_pendingPeak`/`_pendingWindow` überschreibt (`rep_counter.dart:126-131`) — der alte Peak nutzt dadurch nie den mutablen `PeakDetector`-Zustand, unabhängig davon, was `peakDetector.process(frame)` zwischenzeitlich in dessen `_lastPeakDurationSamples`/`_lastPeakProminence` geschrieben hat. Alle drei Rückgabepfade in `process()` (Kollision, sofortige Hüllkurve, reguläre Vervollständigung) laufen durch denselben `_decide()`-Rückgabepunkt, der `durationSamples`/`prominence` immer gemeinsam setzt (`rep_counter.dart:241-242`); `RepResult.none` und alle Ablehnungs-Rückgaben lassen beide Felder `null` — sicher, weil `ExerciseEngine._onRepCounted()` ausschließlich bei `repCounted == true` liest (`exercise_engine.dart:226`), dem einzigen Pfad, der die Felder auch setzt. Keine neue Erkenntnis, eine tiefere Bestätigung der bestehenden — der offene Punkt bleibt derselbe: echter `flutter test`-Lauf gegen `01d2e9c` steht weiterhin aus, auch diese Session konnte ihn nicht liefern.

---

**Ergänzung (2026-08-06, Claude-93e3aa2c, claude.ai-Sandbox, kein Flutter-Zugriff):** Anderer Befund als A/B/die Kollisionsbestätigung oben — betrifft Formkonsistenz, nicht Metadaten-Weitergabe. Von den bisherigen drei Durchgängen an diesem Dokument (Erstaudit, Abschnitt-7-Nachtrag, Kollisionspfad-Bestätigung) nicht erfasst.

Abschnitt 2s Aussage *"TemplateMatcher bekommt jetzt dasselbe (ggf. erweiterte) Fenster wie PhaseValidator ... beantwortet eine zuvor offen diskutierte Frage"* ist nur die halbe Antwort. `RepCounter._decide()` übergibt `TemplateMatcher.match()` tatsächlich das erweiterte `window` (`rep_counter.dart:181`) — aber `TemplateExtractor.extract()`, die Kalibrierung, die das Template überhaupt erst erzeugt, sammelt weiterhin ausschließlich aus `PeakEvent.window` (`template_extractor.dart`, Docstring-Zeile 9, auf diesem Branch unverändert seit vor `1000004`), also der ursprünglichen, trunkierten Form. `template_matcher.dart` selbst ist ebenfalls unverändert; beide Seiten resamplen linear auf `templateLength` (64 Samples) vor der NCC-Berechnung.

**Konsequenz:** Ein kalibriertes Template repräsentiert nach dem Resampling überwiegend die konzentrische Phase (für die Referenz-Rep aus Fund 5/`STATUS_FORTSCHRITT.md`: ~89 % positiv, ~11 % negativ). Das jetzt erweiterte Laufzeit-Fenster repräsentiert nach demselben Resampling einen annähernd symmetrischen Zyklus (~50/50). Strukturell unterschiedliche Kurvenformen nach dem Resampling — die NCC-Korrelation zwischen beiden dürfte für sonst valide Reps niedriger ausfallen als vor `1000004`, sobald ein echtes Template aktiv ist. Wie bei Befund A/B unsichtbar in `dsp_verification_test.dart` (`hasTemplate` bleibt in allen sieben Szenarien `false`, `noTemplate=true` verhindert jede Ablehnung unabhängig von der tatsächlichen Korrelation) — greift erst nach echter Kalibrierung.

**Vorgeschlagener Fix (nicht angewendet):** Minimal — `rep_counter.dart:181` von `templateMatcher.match(window)` zurück auf `templateMatcher.match(peak.window)`. TemplateMatcher bekommt wieder das ursprüngliche, trunkierte Fenster wie vor `1000004`, konsistent mit dem, woraus Templates gelernt werden; `PhaseValidator`/`QualityScorer` bleiben unberührt auf dem erweiterten `window`. Eine Zeile. Alternative, größer und eine Produktentscheidung statt Bugfix: `TemplateExtractor` ebenfalls auf das erweiterte Fenster umstellen (würde die Kalibrierungs-Pipeline berühren, nicht nur `RepCounter`) — dafür Templates, die echte Wiederholungsformen statt nur die konzentrische Phase abbilden.

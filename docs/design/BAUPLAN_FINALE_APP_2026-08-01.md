# Bauplan: FlowRep zur fertigen App (2026-08-01)

**Für:** eine ausführende KI-Session (weniger erfahren als die, die diesen Plan
geschrieben hat). Lies dieses ganze Dokument, bevor du irgendetwas anfasst.
**Ziel von Adi (wörtlich, Chat 2026-08-01):** Übungsauswahlbibliothek
(erweiterbar), sauber designte Übungs-Tracker-Seite mit Kalibrierung,
KG-Eingabe, Start-Knopf, Wiederholungszählung, Korrektur-Möglichkeit — und die
App soll aus Korrekturen lernen. App ist erstmal nur für Adi selbst gedacht
(kein Multi-User).

**Wichtigster Fund, der diesen Plan von einem "baue alles neu"-Plan
unterscheidet:** das meiste existiert bereits im Code, echt verifiziert (nicht
nur behauptet — siehe Teil 1). Dieser Plan ist bewusst **kein** Neubau-Plan.
Wenn du an einer Stelle denkst "das wäre doch einfacher, wenn ich das von
Grund auf neu baue" — stopp, lies Teil 1 nochmal, du übersiehst wahrscheinlich
etwas, das schon da ist.

---

## Teil 0: Pflichtlektüre und Arbeitsweise — VOR jedem Code

Dieses Projekt hat eine eigene, bereits etablierte Arbeitsweise für
KI-Sessions. Sie existiert, weil frühere Sessions (inklusive der, die diesen
Plan schreibt) wiederholt dieselben Fehler gemacht haben. Ignoriere sie nicht.

1. **Lies zuerst** `docs/Umbauplan Flowrep/STATUS_FORTSCHRITT.md` (Ende der
   Datei, letzte ~5 Einträge) und `docs/Version1.0/13_OFFENE_PUNKTE.md`
   komplett. Beide sind "living" Dokumente — der Stand von jetzt kann falsch
   sein, sobald du das hier liest. **Führe als aller ersten Schritt
   `git fetch origin --prune` aus und vergleiche gegen `origin/main`.** Dieses
   Repo wird von mehreren parallelen KI-Sessions UND von Adi selbst bearbeitet
   — der Stand ändert sich teils innerhalb von Minuten. Nicht davon ausgehen,
   dass das, was hier steht, noch exakt stimmt.
2. **Nie direkt auf `main` committen.** Für jede Phase unten (1–6) einen
   eigenen Branch, ASCII-only benannt (keine Umlaute — verursacht
   Encoding-Probleme in PowerShell-Git-Operationen). Branch von frischem
   `origin/main`, nicht von einem alten lokalen Stand.
3. **Git-Identität:** `git config user.email "claude@anthropic.local"` und
   `git config user.name "Claude (Session: <random-hex>)"` — die Kennung
   zufällig generieren (z. B. `python3 -c "import uuid; print(uuid.uuid4().hex[:8])"`),
   nicht Datum+Buchstabe.
4. **Commit-Messages:** mehrzeilig, in eine temporäre Datei schreiben, dann
   `git commit -F .commitmsg.txt` — Here-Strings/`-m` mit mehrzeiligem Text
   sind in diesem Environment wiederholt hängen geblieben.
5. **"Fertig" heißt: echtes `flutter analyze` + `flutter test`, nicht
   Code-Lektüre.** Falls du in einer Sandbox ohne Flutter-Toolchain arbeitest
   (kein `flutter`/`dart` Befehl verfügbar): das ist ein bekannter,
   akzeptierter Zustand in diesem Projekt — schreibe den Code sorgfältig,
   sag aber explizit und ehrlich "nicht mit echtem flutter test verifiziert"
   in Commit-Message UND Status-Update. Behaupte NIE Verifikation, die nicht
   stattgefunden hat — das hat in diesem Projekt schon mehrfach zu echten,
   stillen Bugs geführt (Beispiele: eine Merge-Commit-Message behauptete,
   `home_screen.dart` sei aktualisiert worden — der tatsächliche Diff war
   leer; ein anderer Merge bestand einen eigenen Regressionstest nicht, weil
   niemand ihn nach dem Merge erneut laufen ließ).
6. **Vor jedem Merge/jeder größeren Änderung: prüfen, ob eine parallele
   Branch dasselbe Problem schon (anders) gelöst hat.** `git branch -r` und
   die Commit-Messages der letzten Tage lesen. Dieses Projekt hatte mehrfach
   zwei parallele, unwissentlich widersprüchliche Lösungen für dasselbe
   Problem — vermeidbar durch einen kurzen Blick vorher.
7. **Windows/PowerShell-Toolchain** (falls du über Desktop Commander auf
   Adis echtem Rechner arbeitest, `C:\Users\adini\Desktop\flowrep-main`):
   die Umgebungsvariable "ProgramFiles(x86)" auf "C:\Program Files (x86)"
   setzen, bevor du einen `flutter`-Befehl ausführst — vor JEDEM
   `flutter`-Befehl voranstellen — fehlt die Variable, bricht der Befehl
   still ab. `dart run build_runner build --delete-conflicting-outputs` aus
   `app/` laufen lassen, bevor `flutter analyze`/`test`, wenn Drift-generierte
   Dateien veraltet sein könnten.

---

## Teil 1: Ist-Stand — NICHT neu bauen

Verifiziert am echten main-Code (`969865a`), nicht aus Dokumentation
übernommen:

| Feature | Datei(en) | Status |
|---|---|---|
| Korrektur-UI (+/− Zähler nach einem Satz) | `correction_dialog.dart`, `engine_provider.dart` | **Fertig, echt.** `applyCorrectionDelta()`, `confirmCorrection()` |
| **Regelbasiertes Lernen aus Korrekturen** | `engine_provider.dart::_learnFromCorrection()` (Zeile ~410) | **Fertig, echt geprüft (Code gelesen, nicht nur Doku).** Über-/Unterzählung → θ wird um einen geclampten Faktor (1.05–1.25 bzw. 0.80–0.95) angepasst, **sofort im Speicher UND persistiert** in `CalibrationStore` fürs nächste Mal. Rauschband ±5 % (keine Anpassung bei kleiner Abweichung). Eigene Code-Regel beachten: **"never claim 'KI lernt' in UI copy"** — das gilt auch für jeden Text, den du neu schreibst. |
| Übungsauswahl-Widget | `exercise_selector_card.dart` | **Fertig, bewusst erweiterbar gebaut** (Kommentar im Code: "V1: nur Bizeps-Curl, Architektur für V2 offen"). Iteriert automatisch über `kExerciseCatalog` — sobald der Katalog mehr Einträge hat (Phase 1 unten), zeigt dieses Widget sie ohne eigene Änderung an. |
| Kalibrierungs-Assistent | `calibration_wizard_screen.dart`, `calibration_controller.dart` | Fertig, mehrfach diese Projekt-Historie überarbeitet und getestet — das ist unabhängig von der Zeile direkt darunter. |
| `isMultiJoint` steuert `knownSetCount` | `exercise_registry.dart`, `calibration_wizard_screen.dart` Zeile ~82 | **NICHT auf main — nur auf dem unmerged Branch `feat/exercise-biomechanical-priors`.** `git show origin/main:app/lib/domain/calibration_controller.dart \| grep -c isMultiJoint` = 0, echt geprüft. Diese Zeile war in einer früheren Version dieses Plans fälschlich als "Fertig" markiert — Fehler beim Schreiben dieses Plans selbst, gefunden von einer anderen Session. Kommt mit Phase 1 rein, siehe dort. |
| Verlauf / Session-Zusammenfassung | `history_screen.dart`, `session_summary_dialog.dart` | Fertig. |
| `autoArmAfterCalib` | `engine_provider.dart` (Zeile ~129, ~1419) | Fertig, **umschaltbare, persistierte Einstellung** (Default: an). Automatischer Zählstart nach Kalibrierung. Für Phase 2 unten relevant — siehe dort. |
| Rest-Timer, Settings-Persistenz, Sensor-Health-Banner, Set-Quality-Score | diverse | Fertig laut `docs/Version1.0/13_OFFENE_PUNKTE.md` §5. |
| M5-Hardware-Taste (BtnA: Start Zählen / Satz beenden) | Firmware + `engine_provider.dart` | Fertig. Das ist die physische Taste am Gerät, NICHT dasselbe wie der in Phase 2 gebaute In-App-Start-Knopf — beide sollen nebeneinander funktionieren, nicht kollidieren. |
| DSP-Pipeline (Butterworth/Pan-Tompkins/TemplateMatcher) | `domain/dsp/*`, `domain/counting/*` | Gebaut, aber **`_useNewPipeline` bleibt `false`** — bewusst noch nicht live. Für diesen Bauplan **nicht anfassen**, außerhalb des Scopes. |

**Was das bedeutet:** deine Arbeit in diesem Plan ist Integration und wenige
echte Neubauten (Teil 3, 4), nicht "die App bauen".

---

## Teil 2: Bekannte, noch ungelöste Widersprüche — zuerst lesen, dann entscheiden

Bevor du mit Phase 1 anfängst, hier zwei Dinge, die WÄHREND der Recherche zu
diesem Plan gefunden wurden und die du nicht stillschweigend ignorieren
solltest:

**A) Übungskatalog: vier unabhängige, sich teils überholende Branches — main
selbst hat noch 6 Übungen, nicht 5.** Eine frühere Version dieses Abschnitts
behauptete, main hätte bei Commit `969865a` schon 4 neue Übungen (Bench Press
raus). **Das war falsch** — echt nachgeprüft:
`git show 969865a:docs/design/EXERCISE_BIOMECHANICAL_PRIORS_2026-07-28.md`
enthält Horizontal Bench Press noch 3-mal. `969865a` ist weiterhin
`origin/main`s aktueller Stand (Stand dieser Korrektur). Der Fehler kam
daher, dass der Inhalt des eigenen, später korrigierten Branches mit dem
main-Commit verwechselt wurde, auf dem dieser Branch aufbaut — nicht dasselbe.

Vollständige, echt geprüfte Lage (jede Zeile per `git log`/`git show`
nachvollzogen, nicht aus Erinnerung):

| Branch | Typ | Basis | Übungsanzahl | Status |
|---|---|---|---|---|
| `feat/exercise-biomechanical-priors` (`71a5802`) | Code | `969865a` (=main) | 6 (inkl. Bench Press) | **Wird gebraucht** — einzige Code-Umsetzung des Katalogs. Muss noch um Bench Press gekürzt werden. |
| `docs-fix-4-exercises-not-5` (`ca7dd37`) | Docs | `969865a` (=main) | 4 + Bizeps-Curl, mit Erklärtext warum Bench Press raus ist | **Aktuellste, korrekte Docs-Version — auf frischem main aufgebaut.** Diese verwenden, nicht die zwei folgenden. |
| `docs-hammer-strength-exercises` (`ae67359`, `abaf39c`) | Docs | `fb06712` (ein Commit VOR `969865a`) | 4, aber auf veralteter Struktur (Addendum-Stil statt der direkt in main integrierten Abschnitte 2/3/4.1/5) | **Überholt.** Baut auf einem main-Stand auf, der die spätere direkte Umstrukturierung (Abschnitte 2-5) nicht enthält. Nicht mergen — würde die aktuelle main-Struktur zerstören. Kann gelöscht/ignoriert werden. |
| `docs-exercise-priors-addendum` (`869577f`) | Docs | `cfb5c3f` (weit vor `969865a`) | betrifft die Übungsauswahl gar nicht — reine Statistik-Begründung (Abschnitt 8, arXiv 2606.04798, Eigenwert-Signal) | **Überholt, aber ungefährlich.** Geprüft: der Inhalt ist bereits in main vorhanden (`grep -c "2606.04798\|varianzAnteil" origin/main:...` = 7 Treffer) — eine andere Session hat ihn beim Umbau auf main mit mit-integriert. Nichts geht verloren, wenn dieser Branch ignoriert/gelöscht wird. Nicht mergen (Basis zu alt, würde main-Struktur zerstören).

**Kurz:** von den vier Branches wird nur einer gebraucht, um main zu
aktualisieren (`docs-fix-4-exercises-not-5`), plus der Code-Branch mit einer
kleinen Korrektur. Die anderen zwei Docs-Branches sind Sackgassen derselben
Autorin/desselben Autors zu unterschiedlichen Zeitpunkten — nicht raten,
welcher der "richtige" ist, sondern wie oben an der Basis (`git merge-base
origin/main origin/<branch>`) ablesen, welcher auf dem aktuellsten main
aufbaut.

**B) Start-Verhalten: expliziter Knopf vs. Auto-Start.** Adis eigener,
älterer Branch `feature-exercise-selection-start-button` (22.07., Commit
`fb10ce9`) wollte: kein automatisches Zählen, stattdessen expliziter
Start-Knopf mit Countdown. Der aktuelle main-Code hat stattdessen
`autoArmAfterCalib` (automatischer Start nach Kalibrierung, Default an) als
etablierte, funktionierende Lösung bekommen. **Das ist kein Bug, sondern eine
seit Adis Branch parallel gewachsene, andere Lösung für denselben Bedarf.**
Adis Branch selbst lässt sich nicht mehr sauber mergen (main hat sich seit
dem 22.07. zu stark verändert — echte Konflikte, geprüft). Phase 2 unten
löst das NICHT durch Git-Merge, sondern durch Neubau des expliziten
Start-Knopfs gegen den aktuellen Code, mit `autoArmAfterCalib` als weiterhin
bestehende (aber dann nicht mehr Default-mäßig aktive) Alternative.

---

## Phase 1: Übungskatalog vereinheitlichen

**Ziel:** main hat einen konsistenten, korrekten 5-Übungen-Katalog. Aktuell
hat main-Code nur `bicep_curl`.

**Schritte:**

1. `git fetch origin --prune`. Neuen Branch `fix-exercise-catalog-5` von
   frischem `origin/main`.
2. `git merge origin/feat/exercise-biomechanical-priors` in diesen Branch
   (Code, 6 Übungen). Danach `git merge origin/docs-fix-4-exercises-not-5`
   (Docs, korrekt 4+1, siehe Teil 2.A-Tabelle) — **nicht** die beiden anderen
   Docs-Branches (`docs-hammer-strength-exercises`,
   `docs-exercise-priors-addendum`) anfassen, die sind laut Teil 2.A
   überholt. Konflikte sind bei beiden Merges möglich (unabhängig
   entstanden) — selbst auflösen, nicht raten welche Seite gewinnt, sondern
   anhand von Teil 2.A entscheiden.
3. Nach dem Merge: Katalog-Zähler in Code und Docs müssen jetzt
   übereinstimmen (beide 4 neue + Bizeps-Curl = 5, Horizontal Bench Press in
   keinem von beiden mehr als aktive Übung). In
   `app/lib/domain/exercises/exercise_registry.dart`: den Katalog-Eintrag
   für Horizontal Bench Press (`id: 'hs_bench_press'` o. ä.) vollständig
   entfernen. Ergebnis: 5 Einträge (`bicep_curl`, `hs_lat_pulldown`,
   `hs_incline_press`, `hs_row`, `scott_curl`).
4. In `calibration_wizard_screen.dart` und überall sonst, wo `hs_bench_press`
   referenziert sein könnte (`grep -rn "hs_bench_press\|bench_press" app/lib`):
   entfernen.
5. **Konkrete Namen verwenden, nicht raten:** die exakten IDs/Feldnamen stehen
   im Commit `71a5802` und in `docs/design/EXERCISE_BIOMECHANICAL_PRIORS_2026-07-28.md`
   Abschnitt 8.4 — dort nachschlagen, nicht neu erfinden.
6. `dart run build_runner build --delete-conflicting-outputs` (falls Drift
   von der Änderung betroffen ist — vermutlich nicht, da `ExerciseMetadata`
   kein Drift-Table ist, aber prüfen).
7. **Verifikation:** `flutter analyze` (0 neue Probleme ggü. vorher),
   `flutter test` (alle grün, inkl. `exercise_registry_test.dart` — die 14
   bestehenden Tests dürfen nicht kaputtgehen, und die neuen Katalog-Einträge
   sollten mindestens einen einfachen "Katalog hat 5 Einträge, jeder mit
   plausiblen Feldern"-Test bekommen, falls der noch fehlt).
8. Commit, push. **Nicht selbst nach main mergen** — für Adi/nächste Session
   sichtbar lassen.

---

## Phase 2: Expliziter Start-Knopf mit Countdown

**Ziel:** nach erfolgreicher Kalibrierung erscheint ein Start-Knopf; erst nach
Antippen (und einem kurzen Countdown) beginnt die Zählung. Vorher wird
nichts gezählt, auch nicht bei Bewegung.

**Wichtig, bevor du anfängst:** das ist der Schritt in diesem ganzen Plan mit
dem höchsten Risiko für den Fehler "im Code geändert, aber nie wirklich
aufgerufen" — genau das ist in diesem Projekt bereits zweimal real passiert
(siehe Teil 0, Punkt 5). Sei hier besonders explizit, nicht knapp.

**Schritte:**

1. Branch `feat-explicit-start-button` von frischem `origin/main` (baut auf
   Phase 1 auf, falls die noch nicht gemergt ist: von `fix-exercise-catalog-5`
   branchen statt von main, und das im Commit vermerken).
2. In `home_screen.dart::_buildSetupBody` (Zeile ~255): nach erfolgreicher
   Kalibrierungsprüfung (`hasValidCalibration` — der exakte Getter-/Feldname
   steht in `engine_provider.dart`, dort nachschlagen) einen neuen,
   deutlich sichtbaren Button "Start" (oder "Satz starten") einfügen, der nur
   aktiv/sichtbar ist, wenn kalibriert.
3. Beim Antippen: 3-Sekunden-Countdown anzeigen (einfacher `Timer.periodic`
   oder `AnimatedCounter`-Widget — kein neues Package nötig, Flutter-Bordmittel
   reichen). Nach Ablauf: **denselben Aufruf verwenden, den
   `_autoArmAfterCalibration()` heute nach Kalibrierung automatisch macht**
   (in `engine_provider.dart` Zeile ~1419 nachschauen, welche Methode das
   konkret ist — vermutlich `startCounting()` oder ähnlich benannt). Nicht
   eine zweite, eigene Zählstart-Logik schreiben — es gibt bereits eine, die
   wiederverwenden.
4. **Verifikationsschritt, der nicht übersprungen werden darf:** nach dem
   Schreiben des Codes, in derselben Session, den Pfad manuell nachverfolgen:
   Button-`onPressed` → Countdown-Callback → welcher Provider-Methodenaufruf
   → welche Zeile in `workout_engine.dart` setzt den State tatsächlich auf
   `active`? Wenn du diese Kette nicht lückenlos im Code nachweisen kannst,
   ist der Knopf vermutlich nur optisch da, ohne Wirkung — genau der bereits
   zweimal aufgetretene Fehler in diesem Projekt.
5. `autoArmAfterCalib`: **nicht entfernen.** Stattdessen den Standardwert auf
   `false` setzen (in `UserPrefsStore`/`engine_provider.dart`, wo der Default
   `true` aktuell gesetzt ist) — der explizite Knopf wird der neue
   Standardweg, automatisches Starten bleibt als Einstellung für später
   verfügbar, falls Adi es doch mal so will. Bestehende Nutzer/Profile:
   dieser Default gilt nur für neu erstellte Prefs, nicht rückwirkend
   überschreiben (bestehende `UserPrefsStore`-Werte respektieren — prüfen wie
   dort mit Migration von Default-Werten umgegangen wird, bevor du das
   änderst).
6. Widget-Test für den neuen Button (mindestens: Button unsichtbar/deaktiviert
   ohne Kalibrierung, sichtbar mit Kalibrierung, Countdown läuft, danach wird
   die Zählstart-Methode aufgerufen — mit Mock/Spy auf den Provider, nicht
   nur "Button existiert").
7. Verifikation wie in Phase 1 (`flutter analyze` + `flutter test`).
8. Commit, push, nicht selbst mergen.

---

## Phase 3: Gewicht (KG) eintragen

**Ziel:** vor oder während eines Satzes kann Adi das verwendete Gewicht in kg
eintragen; es wird pro Satz gespeichert (nicht pro Übung oder pro Session) —
das erlaubt Pyramiden-/Dropsätze mit unterschiedlichem Gewicht pro Satz, was
in der Realität normal ist.

**Das ist der einzige echte Neubau in diesem Plan — alles andere ist
Integration bestehender Teile.**

**Datenmodell-Entscheidung (bereits getroffen, nicht neu diskutieren):**
Gewicht gehört als nullable Spalte in die bestehende `ExerciseSets`-Tabelle
(`drift_database.dart`, dieselbe Tabelle wie `countedReps`/`correctedReps`)
— nicht als neue eigene Tabelle. Ein Satz hat ein Gewicht, das passt exakt
zur bestehenden Granularität.

**Schritte:**

1. Branch `feat-weight-entry` von frischem `origin/main` (oder von der
   vorigen Phase, falls die noch offen ist).
2. In `drift_database.dart`: `RealColumn get weightKg => real().nullable()();`
   zur `ExerciseSets`-Tabelle hinzufügen (Zeile ~82, direkt neben
   `correctedReps`, gleicher Stil).
3. **Schema-Migration, nicht überspringen:** `schemaVersion` in der
   `AppDatabase`-Klasse um 1 erhöhen; in `onUpgrade` (oder wo die
   Migrationslogik aktuell lebt — im selben File suchen, es gibt dort
   bereits mindestens eine frühere Migration als Vorlage) einen Schritt
   `m.addColumn(exerciseSets, exerciseSets.weightKg)` für den Sprung von der
   alten auf die neue Version ergänzen. Das ist eine reine
   Spalten-Hinzufügung (nullable, kein Datentransfer, kein Verschlüsseln) —
   deutlich risikoärmer als die Verschlüsselungs-Migration, die dieses
   Projekt früher schon gebaut hat, aber trotzdem: **echt testen, nicht
   annehmen.** Ein Test, der eine DB auf altem Schema anlegt, die Migration
   laufen lässt, und prüft dass bestehende Zeilen erhalten bleiben und
   `weightKg` dort `null` ist (nicht 0, nicht Fehler).
4. `dart run build_runner build --delete-conflicting-outputs` (Pflicht nach
   Drift-Schema-Änderung).
5. `workout_models.dart::ExerciseSet`: `final double? weightKg;` Feld
   ergänzen, `copyWith` entsprechend erweitern (gleiches Muster wie
   `correctedReps` dort, als Vorlage nehmen).
6. `engine_provider.dart`: eine Methode `setWeightForCurrentSet(double? kg)`
   o. ä., die das Gewicht am aktuellen (noch nicht abgeschlossenen) Satz
   setzt, analog zu `applyCorrectionDelta` vom Muster her aber ohne die
   Lern-Logik (Gewicht beeinflusst NICHT die Zählschwelle — bewusst getrennt
   halten, das eine ist Bewegungserkennung, das andere reine Protokollierung).
7. UI in `home_screen.dart::_buildSetupBody`: ein einfaches Zahlenfeld
   ("Gewicht (kg)", optional, leer lassen erlaubt — nicht jede Übung
   braucht zwingend ein Gewicht, z. B. Bodyweight-Varianten). Numerische
   Tastatur (`TextInputType.numberWithOptions(decimal: true)`), keine
   Validierung über "ist eine Zahl" hinaus nötig — Adi ist der einzige
   Nutzer, keine Fremdeingaben abzusichern.
8. In `history_screen.dart` und `session_summary_dialog.dart`: Gewicht mit
   anzeigen, wo Wiederholungen schon angezeigt werden (gleiche Zeile/Karte,
   z. B. "12 Wdh. · 20 kg"). Kein neues Layout-Konzept — an bestehende
   Darstellung anhängen.
9. In `export_service.dart`: `weightKg` zur CSV-Spaltenliste hinzufügen
   (gleiche Stelle wie `correctedReps`, Zeile ~36/47/58 — dort ist bereits
   das Muster für "neue Spalte in Export aufnehmen" zu sehen).
10. Tests: Modell-Test für `ExerciseSet.copyWith` mit Gewicht, Repository-Test
    fürs Speichern/Laden, der Migrations-Test aus Schritt 3, ein einfacher
    Widget-Test fürs Eingabefeld.
11. Verifikation, Commit, Push wie oben.

---

## Phase 4: Alles zur Tracker-Seite zusammenführen

**Ziel:** der von Adi beschriebene Ablauf funktioniert lückenlos auf einer
Seite: Übung wählen → falls nicht kalibriert, zum Assistenten → Gewicht
eintragen → Start-Knopf mit Countdown → Zählung läuft → nach Satzende:
Korrektur möglich (bereits vorhanden) → nächster Satz oder Training beenden.

**Das ist überwiegend Verdrahtung, kein neuer Code** — Phase 1–3 liefern die
Bausteine, Phase 4 stellt sicher, dass sie in der richtigen Reihenfolge
sichtbar sind und ineinandergreifen.

**Schritte:**

1. Branch von main (nach Merge der Phasen 1–3, oder von der letzten offenen
   Phase — Reihenfolge mit Adi/STATUS_FORTSCHRITT.md abstimmen, nicht selbst
   entscheiden welche Phase zuerst gemerged wird).
2. `home_screen.dart::_buildSetupBody` durchgehen und die Reihenfolge der
   angezeigten Elemente explizit prüfen: `ExerciseSelectorCard` → Kalibrierungs-
   Status/Hinweis (falls nicht kalibriert: Button zum Assistenten, kein
   Start-Knopf sichtbar) → Gewichtsfeld → Start-Knopf. Falls die aktuelle
   Reihenfolge im Widget-Baum davon abweicht: anpassen. Kein Redesign der
   Optik nötig (Adi hat kein spezifisches visuelles Design vorgegeben,
   „sauber designt" heißt hier: konsistent mit dem Rest der App, nicht neu
   erfunden) — `frontend-design`-Skill lesen, falls doch ein visueller
   Feinschliff gewünscht ist, aber das ist NICHT der Kern dieser Phase.
3. Manuell (im Code nachvollziehen, nicht nur "sollte funktionieren"
   annehmen) den kompletten Zustandsübergang durchgehen: keine Kalibrierung
   vorhanden → Assistent abgeschlossen → zurück auf Tracker-Seite mit jetzt
   sichtbarem Start-Knopf → Countdown → Zählung → Satz beenden → Korrektur-
   Dialog (falls Zahl nicht stimmt) → gespeichert, θ ggf. angepasst →
   nächster Satz zeigt wieder Start-Knopf (nicht wieder Kalibrierung, außer
   Übung gewechselt).
4. Integrationstest (Widget-Test über mehrere Schritte hinweg, nicht nur
   Einzelkomponenten) für genau diesen Ablauf, so weit das ohne echte
   BLE-Hardware geht (Mock-Engine/Mock-Repository verwenden, wie es
   bestehende Tests in diesem Projekt bereits tun — als Vorlage nehmen).
5. Verifikation, Commit, Push.

---

## Phase 5: Lernschleife verifizieren (kein neuer Code, nur Prüfung + Härtung)

**Ziel:** sicherstellen, dass „die App lernt aus Korrekturen" nicht nur im
Code plausibel aussieht, sondern nachweislich funktioniert — über mehrere
Sessions hinweg, nicht nur innerhalb einer.

1. Test schreiben (falls nicht schon vorhanden — prüfen, `_learnFromCorrection`
   könnte schon Unit-Tests haben): Profil mit bekanntem θ laden → Korrektur
   mit Überzählung simulieren → prüfen, dass θ steigt, geclampt bleibt
   (30–250) UND dass beim erneuten Laden desselben Profils (neue
   `CalibrationStore`-Instanz, simuliert „nächste Session") der neue Wert da
   ist, nicht der alte.
2. Rauschband (±5 %) und Clamping (Faktor 1.05–1.25 bzw. 0.80–0.95, θ
   30–250) explizit testen, nicht nur den Regelfall.
3. `migratedFrom != 0`-Fall testen: bei einem migrierten Legacy-Profil darf
   `_learnFromCorrection` laut vorhandenem Code-Kommentar **nicht**
   persistieren (nur die In-Memory-Anpassung) — sicherstellen, dass das
   wirklich so ist und nicht versehentlich doch geschrieben wird.
4. **UI-Text-Audit:** jeden Text, der in Phase 2–4 neu geschrieben wurde,
   gegen die bestehende Regel "never claim 'KI lernt' in UI copy" prüfen.
   Die existierende Snackbar-Formulierung ("Gespeichert — Schwelle
   angepasst") als Vorbild für Tonfall nehmen: sachlich, nicht
   übertreibend.
5. Kein neuer Mechanismus nötig — falls beim Testen ein echter Bug auffällt
   (nicht nur fehlende Tests), reparieren und im Status-Dokument klar von
   „Test ergänzt" unterscheiden.

---

## Phase 6: Physische Verifikation (braucht Adi + echtes Gerät)

**Das kann keine Sandbox-KI-Session allein abschließen.** Aus
`docs/Version1.0/13_OFFENE_PUNKTE.md` §1, angepasst um die neuen Schritte
aus diesem Plan:

1. Übung wählen (aus jetzt 5, nicht nur Bizeps-Curl) → Kalibrierung
   durchlaufen → Gewicht eintragen → Start-Knopf mit Countdown → 8–12
   Wiederholungen → Anzeige mit tatsächlicher Zahl vergleichen.
2. Bewusst 5–10 Sekunden wackeln/Gerät ablegen — keine wilden Falsch-Reps.
3. Satz beenden → falls Zahl falsch: korrigieren → Snackbar-Bestätigung
   sehen.
4. **Neu, aus diesem Plan:** eine zweite Übung derselben Kategorie
   kalibrieren (z. B. Row nach Bizeps-Curl) und prüfen, dass beide Profile
   unabhängig gespeichert bleiben (Wechsel zurück zu Bizeps-Curl darf nicht
   die Row-Kalibrierung zeigen oder überschreiben).
5. Zweite Session (App neu starten oder zumindest Provider neu laden):
   prüfen, dass eine frühere Korrektur tatsächlich nachwirkt (θ hat sich
   sichtbar verschoben, z. B. weniger Über-/Unterzählung als in Session 1
   bei ähnlicher Ausführung).
6. Ergebnis in `docs/Version1.0/13_OFFENE_PUNKTE.md` eintragen — dieses Doc
   ist der etablierte Ort dafür, nicht ein neues Dokument dafür anlegen.

---

## Reihenfolge-Zusammenfassung

Phase 1 → Phase 2 und Phase 3 können parallel laufen (unabhängig
voneinander, beide bauen nur auf Phase 1 auf) → Phase 4 braucht 1–3 fertig →
Phase 5 kann parallel zu Phase 4 laufen → Phase 6 ganz zum Schluss, mit Adi.

**Nach jeder Phase:** `STATUS_FORTSCHRITT.md`-Eintrag mit Session-Kennung,
was gemacht wurde, ob echt verifiziert oder nicht, und explizit was als
Nächstes offen ist — genau wie es dieses Projekt für jede bisherige Phase
schon gehandhabt hat.

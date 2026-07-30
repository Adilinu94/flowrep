# Handoff: Direction-Aware Counting Fix (2026-07-26)

An die übernehmende KI: Du hast vollen Repo-Zugriff und volle Entscheidungsfreiheit,
wie du das umsetzt. Dieses Dokument gibt dir den Kontext, den ich (Claude, vorherige
Session) gesammelt habe, und benennt ehrlich, wo ich selbst nicht weitergekommen bin
oder nichts verifizieren konnte. Nimm meine Empfehlung als Ausgangspunkt, nicht als
Vorgabe — triff deine eigene technische Entscheidung.

## 1. Das Problem (Kern)

`docs/design/IMU_REP_COUNTER_VERIFICATION_2026-07-26.md` weist nach (und ich habe es
unabhängig durch eigene Codeausführung reproduziert, nicht nur gelesen): Der aktuell
LIVE laufende Zählpfad für Guided-Calibration-2.0-Profile
(`WorkoutEngine.applyCalibration`, `case ChosenSignal.gP:`,
`app/lib/domain/workout_engine.dart` ~Zeile 1625) setzt `_gpUseAbsProjection = true`.
Das bedeutet: `_detectPeakSigned` zählt auf `|g_p|` statt auf signiertem `g_p`. Eine
Rep mit ausreichend starker konzentrischer UND exzentrischer Phase (jede Phase für
sich `longEnough && strongEnough`) wird dadurch **zweimal** gezählt. Simulation:
`double_bump`-Persona zählt 20 statt 10. Das ist kein Rand-Fall — laut Code-Kommentar
in `quality_scorer.dart`/dem Verifikationsbericht hat JEDE Rep in reiner Magnitude
zwei Buckel (konzentrisch+exzentrisch); nur das Vorzeichen trennt sie. Historie:
Commit `2cbeaae` (23.07.) hat `abs()` bewusst eingeführt, um Montage-Kipp-Toleranz zu
bekommen und sich auf die 0.7s-Refraktärzeit verlassen, um den Doppelbuckel
einzufangen — das reicht bei realistischem Tempo nachweislich nicht.

## 2. Adis Design-Vorgabe (Chat, 2026-07-26 — wortgetreu meine Zusammenfassung)

Explizit **kein** einfacher `abs→signed`-Flip. Stattdessen:

1. Kalibrierung speichert Hauptrichtung + typisches signiertes Bewegungsmuster.
2. Live zählt nur die kalibrierte Hauptbewegung; die Gegenbewegung (Rückphase) kann
   nie selbst eine Wiederholung auslösen. Kein Fallback auf `abs()` oder den
   kombinierten Pfad bei Unsicherheit — das würde das Überzählen-Risiko wieder öffnen.
3. Phasen-Automat verhindert Doppelzählung strukturell: bereit → Hauptbewegung →
   Rückkehr/Stillstand abwarten → bereit.
4. Montageänderung wird **nicht** an einer einzelnen Gegenexkursion erkannt (normal
   bei jedem Curl!), sondern an einem **stabilen Muster über mehrere Bewegungen**.
5. Erst bei stabilem Muster: Zählen pausieren + "Sensorposition scheint geändert,
   bitte neu kalibrieren" anzeigen.
6. Zweistufig: erst Shadow (läuft mit, beeinflusst `countedReps` nicht), erst danach
   produktiv — und zwar erst nachdem Doppelbuckel, Wiggle, langsame Reps und
   absichtliches Verdrehen des Sensors mit ECHTEN Hardware-Daten geprüft wurden.

## 3. Aktueller Stand: DREI unabhängige, unfertige Branches für dasselbe Problem

Das ist selbst Teil des Problems — offenbar arbeiten mehrere Sessions parallel daran,
ohne voneinander zu wissen. Keiner der drei ist gemerged, kein PR ist offen.

**`fix/direction-aware-counting-shadow`** (meiner). Shadow-only, inline in
`WorkoutEngine` (`_DirPhase`-Enum, `_detectDirectionAwareShadow`,
`_correlatesWithTemplate`, `_recordCycle`). Mismatch-Erkennung: 5-Zyklen-Fenster,
braucht 4 von 5 "Gegenseite qualifiziert ohne Hauptseite" um zu flaggen. CI grün
(`Static analysis`/`Run unit tests`: beide `success`). Dokumentiert in
`docs/design/DIRECTION_AWARE_SHADOW_COUNTING_2026-07-26.md`.

**`p0-directional-gp-shadow`**. Ebenfalls Shadow-only, aber sauberer architektiert:
eigene Klasse `DirectionalGpShadow` in `app/lib/domain/metrics/directional_gp_shadow.dart`
(passt zur bestehenden Konvention — `GhostRepGate`, `SensorHealthMonitor` sind auch
eigene Klassen dort), nutzt `TemplateMatcher` direkt statt eigener NCC-Rechnung.
Zusätzlich: prüft `gyroMagnitude` (Gesamt-Rotation aus allen 3 Achsen) gegen die
Achsen-Projektion, um Fehlausrichtung auch auf einer GANZ ANDEREN Achse zu erkennen,
nicht nur Vorzeichenumkehr auf derselben Achse — das kann weder mein noch der dritte
Branch. Habe ich noch NICHT auf CI-Ergebnis geprüft.

**`feat/p0-signed-gp-profile-counting`**. **WICHTIG: Dieser macht die Änderung
LIVE, nicht Shadow** — `_gpUseAbsProjection = true` → `false` direkt im
`ChosenSignal.gP`-Zweig, wirkt sofort auf `countedReps`. Das widerspricht Punkt 6
oben (Stufe 1 vor Stufe 2). Zusätzlich ein eigener, einfacherer Mismatch-Mechanismus:
Gegenrichtungs-Exkursion zählen (`_oppositeDirectionExcursions`), bei JEDEM
erfolgreichen `_commitRep` auf 0 zurückgesetzt, `needsRecalibration = true` bei 2
Treffern in Folge OHNE zwischenzeitlichen Commit.

## 4. Empirischer Vergleich (von mir durchgeführt — Python-Portierungen aller drei
Mismatch-Mechanismen, gegen identische 5 Szenarien: `clean`, `weak`, `double_bump`,
invertierte Montage, echte Alltagsbewegung aus `docs/archive/umbauplan/
STATUS_FORTSCHRITT.md:261`, wörtliches Adi-Zitat vom 18.07.: "Wenn den M5 nur beege
oder etwas drehe werden reps gezählt.")

| Szenario | Meiner (Fenster) | `DirectionalGpShadow` (gyroMagnitude) | `needsRecalibration` (Reset-bei-Commit) |
|---|---|---|---|
| double_bump | 10, kein Flag | 10, kein Flag | 10, kein Flag |
| clean | 10, kein Flag | 10, kein Flag | 10, kein Flag |
| weak | 10, kein Flag | 10, kein Flag | 10, kein Flag |
| invertierte Montage | 0, **Flag=True** | 0, **Flag=False** ✗ | 0, **Flag=True** |
| Alltagsbewegung | 0, kein Flag | 0, **Flag=True** ✗ | 0, kein Flag |

**Befund**: `DirectionalGpShadow`s gyroMagnitude-Heuristik verpasst den Kernfall (eine
invertierte Achse hat weiterhin STARKE Projektion, nur negatives Vorzeichen — "schwache
Projektion trotz Rotation" testet die falsche Dimension dafür) UND schlägt bei
zufälliger Alltagsbewegung falschen Alarm (zufällige Achsrichtung projiziert per
Geometrie oft ebenfalls schwach auf eine feste Achse, ganz ohne Montageproblem). Der
einfachere Reset-bei-Commit-Mechanismus aus dem Live-Branch trifft beide kritischen
Fälle korrekt, mit weniger State als meiner.

Portierungen liegen NICHT im Repo (nur in meiner Sandbox) — falls du das nachvollziehen
willst, musst du sie neu bauen. Ausgangspunkt: `tools/workout_engine_simulation.py`
hat bereits `GpEngineSim`/`DirShadow`/`PERSONA_PROFILES`/`make_incidental_movement`
zum Wiederverwenden (auf meinem Branch; auf `main` fehlt `DirShadow`).

## 5. Meine Empfehlung (Ausgangspunkt, keine Vorgabe)

Synthese statt Auswahl: (a) Kernmechanismus = der einfachere Reset-bei-Commit-Ansatz
aus `feat/p0-signed-gp-profile-counting`, aber **als Shadow umgesetzt**
(`_gpUseAbsProjection` unverändert lassen); (b) Architektur = eigene Klasse in
`domain/metrics/` wie bei `p0-directional-gp-shadow`; (c) Korrelation = `TemplateMatcher`
direkt wiederverwenden; (d) `DirectionalGpShadow`s gyroMagnitude-Idee NICHT so
übernehmen wie sie ist — falsifiziert. Falls "Rotation auf anderer Achse" als
zusätzliches Signal gewünscht ist, braucht das eigene, an echten Daten kalibrierte
Schwellen, nicht die aktuellen (`weakProjectionRatio=0.35` etc.).

## 6. Was ich NICHT verifizieren konnte (ehrlich, nicht verschwiegen)

- **Kein `flutter test` gelaufen** in meiner Sandbox möglich (kein Flutter/Dart-SDK,
  `pub.dev` nicht im Netzwerk-Allowlist). Alles oben ist Python-Portierung + manuelle
  Prüfung + für meinen eigenen Branch: echtes CI (`app-ci.yml`) grün. Für die anderen
  beiden Branches habe ich CI-Status NICHT geprüft (unklar ob überhaupt gelaufen).
- **Ungeklärte Diskrepanz in meiner eigenen Python-Portierung**: Ein älterer,
  in echtem CI grün gelaufener Dart-Test (`workout_engine_test.dart`, "ROM-Gate:
  prominenceMin omitted...", peak=140/`prominenceMin`=0, erwartet `closeTo(5,1)`)
  liefert in meiner Python-Portierung `0` statt `~5` — in sowohl abs- als auch
  signed-Modus. Trace zeigt `samples_above=13 < 15` (Mindestwert) am Ende der
  Exkursion. Ursache nicht gefunden. Betrifft die 5 Szenarien oben nicht direkt (alle
  bei peak=220, klarer Abstand), relativiert aber generell, wie weit man sich auf
  meine Python-Verifikation statt auf echtes `flutter test` verlassen sollte.
- **Mein eigener Korrelations-/Template-Mismatch-Zweig** (`weakCorrelation` in
  meinem Branch) wurde in KEINEM der 5 Szenarien tatsächlich ausgelöst/geprüft —
  unverifiziert, nicht widerlegt.
- **"Rotation auf einer komplett anderen Achse als Montageproblem"** ist in KEINEM
  der drei Branches nachweislich korrekt abgedeckt (siehe Tabelle) — falls das ein
  echtes Ziel ist, ist das noch offen.
- Ich habe geprüft, dass `p0-directional-gp-shadow` und `feat/p0-signed-gp-profile-
  counting` jeweils bei `main`@`027270b` (mein ROM-Gate-Merge) abzweigen — beide
  sollten also konfliktfrei gegen den aktuellen `main`-Stand zu vergleichen sein,
  ich habe aber keinen tatsächlichen Merge/Rebase probiert.

## 7. Konkret zu tun

1. Entscheiden: eine der drei Branches weiterführen, oder Synthese neu aufsetzen.
2. Falls Synthese: Mismatch-Logik aus `feat/p0-signed-gp-profile-counting` als
   SHADOW (nicht `_gpUseAbsProjection` anfassen), Architektur/TemplateMatcher-Reuse
   aus `p0-directional-gp-shadow`.
3. Übrige, nicht gewählte Branches: mit Adi klären, ob löschen oder als Referenz
   behalten — nicht meine Entscheidung.
4. Wenn möglich: echtes `flutter test` laufen lassen (in dieser Sandbox nicht
   möglich) — das würde auch Punkt 6 (Python-Diskrepanz) endlich auflösen.
5. Stufe 2 (produktiv schalten, `_gpUseAbsProjection` wirklich abschalten, UI-Hinweis
   "Sensorposition scheint geändert") bleibt so oder so hinter echten HW-Daten
   (Doppelbuckel, Wiggle, langsame Reps, absichtliches Verdrehen) — siehe
   `docs/reference/ESKALATIONS_PLAYBOOK.md`.

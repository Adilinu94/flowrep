# Übungs-Vorwissen für Guided Calibration (2026-07-28)

**Status:** Planung, noch nicht umgesetzt.
**Entscheidungsgrundlage:** Produktentscheidung von Adi (Chat, 2026-07-28) — bewusst
gegen meine eigene vorherige Einschätzung ("erst beobachten, dann entscheiden"),
siehe Chat-Verlauf desselben Tages.
**Ersetzt/überholt:** Widerspricht `UMBAUPLAN_MULTI_EXERCISE_2026-07-28.md`
Abschnitt 3 ("`id` wird NICHT aus dem Namen abgeleitet", freier Text) und
Abschnitt 7 ("Übungs-Icons/-Kategorien/-Typen... reicht fürs Erste",
"Unterschiedliche Kalibrierungs-Varianten je Übungstyp" explizit NICHT Teil des
Umbaus). Dieses Dokument ersetzt diese beiden Stellen — siehe Abschnitt 6 unten
für die konkrete Änderung an der Datei selbst.

---

## 1. Entscheidung

Statt freien Textnamen: **Auswahl aus 5 vordefinierten Übungen**, jede mit
recherchiertem biomechanischem Profil. Ziele (von Adi vorgegeben): bessere
Guided-Calibration-Ergebnisse, genauere Anweisungen an den Nutzer.

## 2. Die 5 Übungen — konkret von Adi vorgegeben (2026-07-28, zweite Runde)

Ersetzt die erste, selbst vorgeschlagene Auswahl (Trizeps-Extension/Seitheben/
Schulterdrücken/Latzug) vollständig. Bizeps-Curl bleibt zusätzlich bestehen
(bereits produktiv, nicht Teil dieser 5) — macht 6 Übungen im Katalog insgesamt.

| Übung | Gelenk(e) | Bewegungsmuster | Maschinen-Typ |
|---|---|---|---|
| Bizeps-Curl (bestehend) | Ellbogen (Flexion) | Zug, eingelenkig | Freihantel |
| Hammer Strength Iso-Lateral Front Lat Pulldown | Schulter + Ellbogen | Zug, mehrgelenkig, vertikal, Untergriff | konvergierend/divergierend |
| Hammer Strength Iso-Lateral Incline Press | Schulter + Ellbogen | Druck, mehrgelenkig, steil nach oben-vorne | konvergierend/divergierend |
| Hammer Strength Iso-Lateral Row | Schulter + Ellbogen | Zug, mehrgelenkig, horizontal, brustgestützt | konvergierend/divergierend |
| Scott Curls / Preacher Curls | Ellbogen (Flexion) | Zug, eingelenkig, Oberarm fixiert | Freihantel/Kabel/Maschine |
| Hammer Strength Iso-Lateral Horizontal Bench Press | Schulter + Ellbogen | Druck, mehrgelenkig, horizontal | konvergierend/divergierend |

**Neue Kategorie, die die erste Fassung nicht hatte:** vier der 5 sind
Hammer-Strength-Maschinen mit **konvergierender/divergierender, iso-lateraler**
Armführung — jede Seite bewegt sich unabhängig, aber entlang einer vom
Maschinen-Hebelmechanismus fest vorgegebenen Bahn (Life Fitness/Hammer
Strength, offizielle Produktseiten). Das unterscheidet sich grundlegend von
freier Hantel-/Kabelzugbewegung: die Bahn ist nicht durch Gelenkbiomechanik und
individuelle Technik bestimmt, sondern durch die Maschine selbst erzwungen —
vermutlich konsistenter von Rep zu Rep und zwischen Nutzern, trotz
Mehrgelenkigkeit. Unverifizierte Erwartung, siehe Abschnitt 4.4.

## 3. Biomechanisches Profil je Übung (recherchiert, mit Quellen)

Recherchiert für Genauigkeit der ROM-/Tempo-Angaben; individuelle Streuung
zwischen Nutzern bleibt trotzdem groß — diese Werte sind **Startwerte für
Plausibilisierung**, kein Ersatz für die empirische Known-Count-Sweep-Kalibrierung.

**Statistische Begründung, warum das bei nur 8 Kalibrierungs-Reps überhaupt
etwas bringt** (`knownSetCount=5` + `slowSetCount=3`, verifiziert in
`calibration_controller.dart` Zeile 128–129): Burzer et al., "Uncertainty-Aware
(Un)Supervised Few-Shot User Adaptation for On-Device Personalized Human
Activity Recognition" (arXiv:2606.04798, Juni 2026) — sensorbasierte
Aktivitätserkennung, on-device, Few-Shot-Nutzerkalibrierung, methodisch nah an
unserem Problem. Tabelle 2 des Papers zeigt konkret: bei extrem wenigen
Kalibrierungsdaten ("1 shot", 3 Sekunden) liegt rein empirische
Prototyp-Schätzung auf dem HHAR-Datensatz bei **-2,65** Prozentpunkten relativ
zur Zero-Shot-Baseline (schlechter als gar keine Personalisierung!), während die
Bayesian-Prior-Kombination durchgehend über alle 4 getesteten Datensätze
gewinnt. Zwei Einschränkungen, um das nicht zu überziehen: (a) der Effekt nimmt
laut Paper selbst mit mehr Shots ab (Richtung 16 Shots konvergieren die
Verfahren) — 8 Reps sind nicht der extremste "1-Shot"-Fall, in dem die
dramatischsten Zahlen gemessen wurden; (b) es ist ein Multi-Klassen-
Aktivitätserkennungs-Paper mit Bayesian-Schätzung im Embedding-Raum, nicht
unser einfacheres Achsen-/Schwellenwert-Problem — das allgemeine Prinzip
(Prior+Stichprobe schlägt reine Stichprobe bei wenigen Samples) überträgt sich,
die konkreten Prozentpunkte nicht.

**Bewusste Scoping-Entscheidung:** Das Paper selbst kombiniert Prior und
Stichprobe rechnerisch (Bayesian Shrinkage). Das wäre die konsequentere
Umsetzung dieser Erkenntnis, ist aber ein deutlich größerer Eingriff in die
Zählmathematik als eine reine Plausibilisierung. Diese Planung entscheidet sich
bewusst für die konservativere Variante (Abschnitt 4.3: nur flaggen, nie
automatisch verrechnen) — passend zum sonst im Projekt durchgehend gelebten
Shadow-erst-Prinzip (siehe `DIRECTIONAL_GP_SHADOW_ROLLOUT_2026-07-27.md`).
Rechnerische Kombination bleibt ein möglicher späterer Schritt, kein Teil
dieser Planung.

### Bizeps-Curl (bereits produktiv, hier als Referenz)
- 1 Gelenk (Ellbogen), reine Flexion/Extension.
- ROM ≈ 110–160° je nach Quelle/Variante (GVSU-Biomechanik-Thesis: 156–157° bei
  Standard-Curl; Exosuit-Studie: 107–115° gemessen).
- Unterarm/Handgelenk dreht praktisch starr mit — für einen handgelenkgetragenen
  Sensor die sauberste der 5 Übungen: eine dominante Rotationsachse.
- Tempo in bisherigen Simulationen (`PERSONA_PROFILES`): ~1.2–1.6s/Rep.
- Signal: rotationsdominant, gP-Projektion passt gut (bestätigt durch Produktivbetrieb).

### Hammer Strength Iso-Lateral Front Lat Pulldown
- Mehrgelenkig: Schulteradduktion + Ellbogenflexion, sitzend, **Untergriff**
  (Life Fitness/Hammer Strength, offizielle Produktbeschreibung) — anders als
  der generische Latzug (meist Obergriff), das ändert die Ruheposition des
  Unterarms/Handgelenks im Raum gegenüber einem Standard-Latzug.
- Konvergierende/divergierende Armbahn: die Griffe bewegen sich beim Ziehen
  aufeinander zu, beim Loslassen auseinander — maschinengeführte Bahn, nicht
  frei.
- Herstellerbeschreibung nennt explizit "natürlichen, ergonomischen
  Bewegungspfad", ausgelegt für kontrollierte Zugbewegungen.
- Signal: vermutlich weiterhin Mischung aus Rotation und Translation wie beim
  generischen Latzug (Hand bleibt am Griff, Hauptbewegung an Schulter+Ellbogen),
  aber durch die feste Maschinenbahn potenziell konsistenter als am freien
  Kabelzug — unverifiziert (Abschnitt 4.4).

### Hammer Strength Iso-Lateral Incline Press
- Mehrgelenkig: Schulterabduktion/-flexion + Ellbogenextension, sitzend.
- Herstellerbeschreibung: liegt bewegungstechnisch zwischen Schulterdrücken und
  Incline Press, Bahn ähnelt einem "Frontal-Military-Press" — steiler/mehr
  nach oben-vorne als ein klassischer Incline Press.
- Griffe zwischen neutralem und Obergriff positioniert (Herstellerangabe).
- Konvergierend/divergierend wie die anderen Hammer-Strength-Maschinen.
- Signal: Druckbewegung, ähnlich Schulterdrücken-Charakteristik aus der ersten
  Dokumentfassung, aber steilere/andere Bahnrichtung — eigene Beobachtung nötig.

### Hammer Strength Iso-Lateral Row
- Mehrgelenkig: Schulter-Retraktion + Ellbogenflexion, **horizontal** (im
  Gegensatz zum vertikalen Lat Pulldown), sitzend mit **Brustpolster**
  (chest-supported) und geneigtem Sitz (Herstellerangabe: Sitz und Brustpolster
  eigens auf optimales Rückenengagement ausgelegt).
- Konvergierend/divergierende Zugbahn.
- Brustpolster stützt den Oberkörper — vermutlich weniger Rumpf-/
  Ausweichbewegung als bei einem freien Rudern, ähnlich der
  Momentum-Reduktion bei Scott Curls unten.
- Signal: horizontale Zugbewegung, andere Ebene als Lat Pulldown und Bizeps-Curl.

### Scott Curls / Preacher Curls
- **Eingelenkig wie der Standard-Curl** (reine Ellbogenflexion) — aber der
  **Oberarm liegt fixiert auf einem geneigten Polster** (Scott-/Curlbank,
  typisch 45–60°), nur der Unterarm bewegt sich (modusX, alle 4 dort
  beschriebenen Varianten — Kurzhantel, Langhantel, SZ-Stange, Kabelzug —
  betonen das übereinstimmend: Oberarm/Ellbogen bleiben unbewegt).
- Ausgangsposition des Arms im Raum unterscheidet sich vom hängenden
  Standard-Curl (durch die geneigte Bank), die ROM bezieht sich auf den Winkel
  zwischen Unter- und Oberarm (fast gestreckt → fast senkrecht), nicht auf eine
  absolute Armposition.
- Explizit **weniger Schwung/Körpereinsatz möglich** — die Bank verhindert das
  mechanisch (Quelle nennt das als Hauptzweck der Übung sowie als häufigen
  Fehler, wenn versucht). Vermutlich saubereres Signal als beim Standard-Curl:
  weniger Störbewegung durch Restkörper.
- Handgelenk soll laut Quelle eine "natürliche Verlängerung" des Unterarms
  bleiben (kein Abknicken) — bestätigt dieselbe starre Handgelenk-Unterarm-
  Kopplung wie beim Standard-Curl, nur mit anderer Ruhelage im Raum.
- Varianten: ein- oder beidarmig, mehrere Geräte (SZ-Stange, Langhantel,
  Kurzhantel, Kabelzug, Bizepsmaschine) — Bewegungsprinzip bei allen identisch.
- Signal: rotationsdominant wie Bizeps-Curl, aber andere Achsen-Ruhelage im
  Raum — guter zweiter Testfall neben double_bump, ob das System zwei
  Curl-Varianten anhand der Ruhelage sauber trennt statt zu verwechseln.

### Hammer Strength Iso-Lateral Horizontal Bench Press
- Mehrgelenkig: Schulterhorizontaladduktion + Ellbogenextension, **horizontal**
  (Gegenstück zur Incline Press oben), sitzend mit **5°-geneigtem Sitz** für
  Positionierung "wie auf einer echten Flachbank" (Herstellerangabe).
- Konvergierend/divergierende Druckbahn — Herstellerbeschreibung betont
  explizit den Unterschied zur Langhantel: "eine Langhantel zwingt beide Arme
  als eine Einheit, hier bewegt sich jeder Arm unabhängig."
- Signal: Druckbewegung wie Incline Press, aber horizontal statt steil-nach-
  oben — eigene Bahnrichtung, dritte Druckvariante neben Incline Press.

## 4. Wie das in die Architektur passt

### 4.1 Datenmodell (ändert Umbauplan Abschnitt 3)

Die geplante `Exercises`-Tabelle braucht eine zusätzliche Spalte:

```dart
class Exercises extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get templateId => text()(); // NEU: 'bicep_curl' | 'hs_lat_pulldown'
                                          //      | 'hs_incline_press' | 'hs_row'
                                          //      | 'scott_curl' | 'hs_bench_press'
  DateTimeColumn get createdAt => dateTime()();
}
```

`templateId` referenziert eines der 5 biomechanischen Profile (Abschnitt 3), fest
verdrahtet im Code (kein Nutzer-Freitext für den Typ selbst). `displayName` bleibt
frei editierbar (z.B. "Latzug eng" statt "Latzug") — das war schon im Umbauplan so
vorgesehen und ändert sich nicht. Anlegen wird aus einem Textfeld eine Auswahl aus
5 Karten/Optionen (ersetzt Umbauplan Abschnitt 5.2).

### 4.2 Datenstruktur: bestehende `ExerciseMetadata` erweitern, keine neue Klasse

**Korrektur (2026-07-28, zweite Überarbeitung):** `app/lib/domain/exercises/
exercise_registry.dart` hat bereits eine `ExerciseMetadata`-Klasse mit `id`,
`displayName`, `muscleGroup`, `description`, `requiresCalibration` — mit
14 eigenen Tests (`exercise_registry_test.dart`), aber im Katalog bislang nur
mit `bicep_curl` befüllt. Das ist praktisch schon die richtige Stelle für die
biomechanischen Zusatzfelder — eine separate `ExerciseBiomechanicalTemplate`-
Klasse (frühere Fassung dieses Abschnitts) wäre unnötige Parallelstruktur
gewesen:

```dart
class ExerciseMetadata {
  final String id;
  final String displayName;
  final String muscleGroup;
  final String description;
  final bool requiresCalibration;
  // NEU, fuer diese Planung:
  final String jointDescription;       // z.B. "Ellbogen (Flexion)"
  final bool isMultiJoint;
  final (double, double) expectedRomDegrees;
  final (double, double) expectedTempoSecPerRep;
  final String instructionText;        // siehe Abschnitt 5
}
```

`ExerciseRegistry.blendProfile()`/`ExerciseProfile.blendWith()` existieren
ebenfalls bereits (lineares Blending zwischen zwei kalibrierten Profilen,
gewichtet) — dienen heute einem anderen Zweck (alte vs. neue Kalibrierung
derselben Übung mischen), aber dieselbe Mechanik wäre direkt wiederverwendbar,
falls aus der in Abschnitt 3 diskutierten Bayesian-Kombination (Prior gegen
Empirie) doch einmal mehr als reine Plausibilisierung werden soll — günstiger
als ursprünglich in Abschnitt 3 eingeschätzt.

### 4.3 Einsatz in Guided Calibration 2.0 — vier konkrete Stellen

1. **Plausibilisierung nach dem Known-Count-Sweep**: gefundene Tempo-/ROM-Werte
   gegen `expectedRomDegrees`/`expectedTempoSecPerRep` des gewählten Templates
   vergleichen. Bei starker Abweichung (Faktor 2+ o.ä., genaue Schwelle braucht
   eigene Kalibrierung mit echten Daten) einen Hinweis zeigen — **nicht** die
   Kalibrierung blockieren, nur ehrlich flaggen ("Das gemessene Tempo passt nicht
   ganz zum Erwartungswert für Hammer Strength Row — trotzdem übernehmen?").
2. **Zweites, übungsunabhängiges Signal — Achsen-Eindeutigkeit**: `_axisAnalysis`
   berechnet über `_jacobiEigen3` bereits `varianzAnteil` (größter Eigenwert /
   Summe aller drei Eigenwerte, `_AxisResult`, Zeile 707) — komplett kostenlos,
   kein neuer Rechenschritt. Ein niedriger Wert heißt: die gemessene Bewegung war
   nicht eindeutig einachsig, unabhängig davon ob ROM/Tempo zum Profil passen.
   Für die Hammer-Strength-Maschinen (oben als konvergierend/divergierend statt
   frei rotierend eingeschätzt) ein zweites, orthogonales Warnsignal. Genauer wäre "größter vs. zweitgrößter
   Eigenwert" statt "größter/Summe" — der ist aktuell NICHT exponiert, bräuchte
   einen zusätzlichen (immer noch billigen) Schritt. Start mit `varianzAnteil`,
   da bereits vorhanden; Wechsel zur präziseren Metrik bleibt offen.
3. **`isMultiJoint` steuert `knownSetCount` statt nur Nachprüfung**: mehrgelenkige
   Übungen (die 4 Hammer-Strength-Maschinen) bekommen mehr Kalibrierungs-Reps (z.B. 8
   statt 5) — mehr Rohdaten für die unveränderte `_axisAnalysis`, kein Eingriff
   in die Achsen-Mathematik selbst. Mildert direkt das Problem aus Abschnitt 3
   (mehr Shots → geringere Prior-Abhängigkeit, laut Burzer et al. selbst).
   Schließt einen Kreis mit Punkt 2: bleibt `varianzAnteil` trotz erhöhter
   Rep-Zahl niedrig, ist das ein stärkeres Signal als eine niedrige Rep-Zahl allein.
4. **Bessere Startwerte statt generischer Defaults**: `expectedDurationSamples`
   für den (noch nicht produktiven) `QualityScorer` aus `expectedTempoSecPerRep`
   seeden, statt eines festen generischen Werts.
5. **Instruktionstext**: `CalibrationWizardScreen._phaseHint` (aktuell komplett
   übungs-unabhängig — geprüft, dort steht heute nur generischer Workflow-Text
   wie "Aufzeichnung läuft. Danach Weiter tippen.") um einen zusätzlichen,
   übungsspezifischen Satz aus `instructionText` ergänzen, in der Briefing-Phase
   angezeigt.

## 4.4 Validierungsplan (vor Produktivschaltung)

Die ROM-/Tempo-Werte in Abschnitt 3 sind Literaturwerte auf Gelenkebene — nicht
dasselbe wie das, was der M5StickC am Handgelenk tatsächlich als gP-Signal
zeigt. Diese Übersetzung ist unverifiziert. Deshalb, passend zum in ADR-022
(`docs/archive/umbauplan/02_ARCHITECTURE_DECISION_RECORDS.md`) verankerten
Grundsatz "erst simulieren/beobachten, dann scharf schalten" — dort konkret zu
Testmethodik, hier sinngemäß übertragen: die erste echte Kalibrierung jeder
neuen Übung (v.a. die 4 Hammer-Strength-Maschinen) manuell gegen diese Erwartungswerte
und gegen `varianzAnteil` prüfen, bevor das Plausibilisierungs-Flag für diese
Übung scharf geschaltet wird. Bis dahin: Template vorhanden, Warnung deaktiviert.

## 5. Beispiel-Instruktionstexte (Entwurf, nicht final)

- **Bizeps-Curl**: „Sensor am Handgelenk. Ellbogen am Körper, Unterarm rauf und
  runter — der Ellbogen bleibt der feste Punkt."
- **Hammer Strength Front Lat Pulldown**: „Sensor am Handgelenk. Griff im
  Untergriff kontrolliert zur Brust ziehen, dann kontrolliert zurück — die
  Maschine führt die Bahn, du musst sie nicht erzwingen."
- **Hammer Strength Incline Press**: „Sensor am Handgelenk. Griffe nach
  schräg oben drücken, bis die Arme fast gestreckt sind, dann kontrolliert
  zurück."
- **Hammer Strength Row**: „Sensor am Handgelenk. Brust am Polster, Griffe
  waagerecht zum Körper ziehen, Schulterblätter zusammenziehen."
- **Scott Curls / Preacher Curls**: „Sensor am Handgelenk. Oberarm bleibt
  fest auf dem Polster liegen, nur der Unterarm bewegt sich — kein Schwung
  aus dem Körper."
- **Hammer Strength Horizontal Bench Press**: „Sensor am Handgelenk. Griffe
  gerade nach vorne drücken, bis die Arme fast gestreckt sind, dann
  kontrolliert zurück."

## 6. Änderung an `UMBAUPLAN_MULTI_EXERCISE_2026-07-28.md`

Zwei Stellen brauchen eine Ergänzung (nicht stillschweigend überschrieben,
sondern mit Verweis hierher — siehe Abschnitt „Ersetzt/überholt" oben in dieser
Datei als Vorlage für den Stil):
- Abschnitt 3 ("`id` wird NICHT aus dem Namen abgeleitet"): weiterhin richtig für
  die generierte `id`, aber `templateId` kommt als Pflichtfeld dazu.
- Abschnitt 7, dritter Punkt: der Satz „nicht als selbstverständlich
  vorausgesetzt" bleibt inhaltlich richtig (die empirische Known-Count-Sweep-
  Kalibrierung bleibt die eigentliche Quelle der Wahrheit) — aber die Prämisse
  „keine Kalibrierungs-Varianten je Übungstyp" gilt ab jetzt nicht mehr.

## 7. Bewusst NICHT Teil dieser Planung

- Keine automatische Übungserkennung aus dem Bewegungsmuster (das existiert
  bereits separat, als Shadow-Vorschlag, in `domain/ml/exercise_classifier.dart`
  — unabhängig von dieser Planung, nicht hier mit hineinmischen).
- Keine harte Ablehnung einer Kalibrierung bei Abweichung vom Profil — nur
  Hinweis, nie Blockade (siehe 4.3, Punkt 1).
- Keine rechnerische Prior+Stichprobe-Kombination (Bayesian Shrinkage) —
  Prior bleibt reine Plausibilisierung, verändert das Kalibrierungsergebnis
  selbst nicht (siehe Abschnitt 3, "Bewusste Scoping-Entscheidung").
- Keine weiteren Übungen über die 5 hinaus in dieser Runde.
- Keine Änderung an `_axisAnalysis`/Known-Count-Sweep selbst — die bleibt
  generisch, die Profile sind zusätzliche Plausibilisierung, kein Ersatz.

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

## 2. Die 5 Übungen — Auswahl und Begründung

`kExerciseCatalog` (`exercise_registry.dart`) hatte bereits `shoulder_press` und
`lateral_raise` als V2-Kommentare vorgesehen. Dazu Latzug (von Adi genannt) und
Trizeps-Extension als bewusstes Gegenstück zum Curl (gleiches Gelenk, entgegen-
gesetzte Bewegungsrichtung — guter Testfall, ob zwei Ellbogen-Übungen sauber
unterschieden werden). Fünf Übungen, drei Bewegungsmuster, bewusst nicht
beliebig — jede zusätzliche Übung braucht eigene Recherche und Beobachtung,
mehr wäre für den Start unnötiger Umfang:

| Übung | Gelenk(e) | Bewegungsmuster |
|---|---|---|
| Bizeps-Curl (bestehend) | Ellbogen (Flexion) | Zug, eingelenkig |
| Trizeps-Extension | Ellbogen (Extension) | Druck, eingelenkig — Gegenstück zum Curl |
| Seitheben | Schulter (Abduktion) | Zug, nahezu eingelenkig |
| Schulterdrücken | Schulter + Ellbogen | Druck, mehrgelenkig, vertikal |
| Latzug | Schulter + Ellbogen + Skapula | Zug, mehrgelenkig, kombiniert |

## 3. Biomechanisches Profil je Übung (recherchiert, mit Quellen)

Recherchiert für Genauigkeit der ROM-/Tempo-Angaben; individuelle Streuung
zwischen Nutzern bleibt trotzdem groß — diese Werte sind **Startwerte für
Plausibilisierung**, kein Ersatz für die empirische Known-Count-Sweep-Kalibrierung.

### Bizeps-Curl (bereits produktiv, hier als Referenz)
- 1 Gelenk (Ellbogen), reine Flexion/Extension.
- ROM ≈ 110–160° je nach Quelle/Variante (GVSU-Biomechanik-Thesis: 156–157° bei
  Standard-Curl; Exosuit-Studie: 107–115° gemessen).
- Unterarm/Handgelenk dreht praktisch starr mit — für einen handgelenkgetragenen
  Sensor die sauberste der 5 Übungen: eine dominante Rotationsachse.
- Tempo in bisherigen Simulationen (`PERSONA_PROFILES`): ~1.2–1.6s/Rep.
- Signal: rotationsdominant, gP-Projektion passt gut (bestätigt durch Produktivbetrieb).

### Trizeps-Extension
- 1 Gelenk (Ellbogen), Extension statt Flexion — biomechanisch das Gegenteil
  des Curls, ähnliche ROM-Größenordnung, je nach Ausführung (Overhead-Extension
  vs. Kickback) etwas kleiner.
- Handgelenk-Charakteristik wie beim Curl: rotiert praktisch starr mit.
- Signal: rotationsdominant wie Curl, aber Vorzeichen/Ruhelage unterscheiden sich.
- Guter erster Testfall für "zwei ähnliche Übungen sauber unterscheiden", ohne
  gleich die Komplexität eines mehrgelenkigen Musters mitzubringen.

### Seitheben
- Schulter-Abduktion, für die Hauptbewegung nahezu eingelenkig — Bewegung findet
  in der Scapularebene statt, ca. 35° vor der reinen Frontalebene (Muscle & Motion,
  anatomische Analyse), ROM bis etwa Schulterhöhe (~90°).
- Explizit in der Literatur (ATHLEAN-X, Technikanleitungen) als **langsam,
  kontrolliert** auszuführen beschrieben — "Handgelenk über dem Ellbogen halten",
  das Handgelenk bewegt sich relativ zum Unterarm kaum, der GANZE Arm rotiert um
  die Schulter. Für den Sensor: anderer Hebelarm/Abstand zum Rotationszentrum als
  beim Curl, aber weiterhin rotationsdominant.
- Erwartung: langsameres Tempo als Curl → falls das bestehende
  `_minGpSamplesAbove`/Refraktärzeit-Timing zu eng auf Curl-Tempo kalibriert ist,
  hier zuerst beobachten (siehe Audit C-06, langsame Reps).

### Schulterdrücken
- Mehrgelenkig: Schulterabduktion/-flexion + Ellbogenextension gemeinsam, vertikale/
  Über-Kopf-Bahn (Vertical-Push-Literatur: ab ~80–90° Schulterflexion wird die
  Skapula aktiv mitbewegt).
- Handgelenk bewegt sich mit dem Oberarm mit, aber die Bewegungsrichtung ist
  vertikal statt der Bogenform des Curls — andere Signalform, nicht nur andere Achse.
- Ähnlich komplex wie Latzug, aber vertikal statt horizontal/ziehend — guter
  zweiter mehrgelenkiger Testfall mit anderer Bewegungsrichtung.

### Latzug
- Mehrgelenkig und am komplexesten: Schulteradduktion + horizontale
  Schulterabduktion + Ellbogenflexion + Skapula-Retraktion gleichzeitig (NASM-
  Biomechanik-Blog; Strength & Conditioning Journal, komparative Analyse).
- Hand bleibt relativ fest am Griff — die Hauptbewegung passiert an Schulter und
  Ellbogen zusammen, **nicht primär am Handgelenk selbst**.
- Literatur nennt explizit ein kontrolliertes Tempo von 2–4s pro Phase, spürbar
  langsamer als ein typischer Curl.
- Signal: vermutlich weniger eindeutig rotationsdominant als bei den anderen 4 —
  wahrscheinlich eine Mischung aus Rotation und linearer Translation der Hand
  entlang des Griffwegs. Das bestätigt (nicht nur vermutet) die im
  Umbauplan-Dokument offen benannte Sorge, ob die PCA-Achsenfindung hier
  genauso zuverlässig eine Achse findet wie beim Curl.

## 4. Wie das in die Architektur passt

### 4.1 Datenmodell (ändert Umbauplan Abschnitt 3)

Die geplante `Exercises`-Tabelle braucht eine zusätzliche Spalte:

```dart
class Exercises extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get templateId => text()(); // NEU: 'bicep_curl' | 'triceps_extension'
                                          //      | 'lateral_raise' | 'shoulder_press'
                                          //      | 'lat_pulldown'
  DateTimeColumn get createdAt => dateTime()();
}
```

`templateId` referenziert eines der 5 biomechanischen Profile (Abschnitt 3), fest
verdrahtet im Code (kein Nutzer-Freitext für den Typ selbst). `displayName` bleibt
frei editierbar (z.B. "Latzug eng" statt "Latzug") — das war schon im Umbauplan so
vorgesehen und ändert sich nicht. Anlegen wird aus einem Textfeld eine Auswahl aus
5 Karten/Optionen (ersetzt Umbauplan Abschnitt 5.2).

### 4.2 Neue Datenstruktur: biomechanisches Profil

```dart
class ExerciseBiomechanicalTemplate {
  final String templateId;
  final String jointDescription;      // z.B. "Ellbogen (Flexion)"
  final bool isMultiJoint;
  final (double, double) expectedRomDegrees;
  final (double, double) expectedTempoSecPerRep;
  final String instructionText;       // siehe Abschnitt 5
}
```

Rein statische Konstanten (wie `kExerciseCatalog` heute), keine neue Tabelle nötig.

### 4.3 Einsatz in Guided Calibration 2.0 — drei konkrete Stellen

1. **Plausibilisierung nach dem Known-Count-Sweep**: gefundene Tempo-/ROM-Werte
   gegen `expectedRomDegrees`/`expectedTempoSecPerRep` des gewählten Templates
   vergleichen. Bei starker Abweichung (Faktor 2+ o.ä., genaue Schwelle braucht
   eigene Kalibrierung mit echten Daten) einen Hinweis zeigen — **nicht** die
   Kalibrierung blockieren, nur ehrlich flaggen ("Das gemessene Tempo passt nicht
   ganz zum Erwartungswert für Latzug — trotzdem übernehmen?").
2. **Bessere Startwerte statt generischer Defaults**: `expectedDurationSamples`
   für den (noch nicht produktiven) `QualityScorer` aus `expectedTempoSecPerRep`
   seeden, statt eines festen generischen Werts.
3. **Instruktionstext**: `CalibrationWizardScreen._phaseHint` (aktuell komplett
   übungs-unabhängig — geprüft, dort steht heute nur generischer Workflow-Text
   wie "Aufzeichnung läuft. Danach Weiter tippen.") um einen zusätzlichen,
   übungsspezifischen Satz aus `instructionText` ergänzen, in der Briefing-Phase
   angezeigt.

## 5. Beispiel-Instruktionstexte (Entwurf, nicht final)

- **Bizeps-Curl**: „Sensor am Handgelenk. Ellbogen am Körper, Unterarm rauf und
  runter — der Ellbogen bleibt der feste Punkt."
- **Trizeps-Extension**: „Sensor am Handgelenk. Oberarm ruhig halten, nur den
  Unterarm strecken und wieder beugen."
- **Seitheben**: „Sensor am Handgelenk. Arm seitlich bis Schulterhöhe heben,
  langsam und kontrolliert — nicht schwungvoll."
- **Schulterdrücken**: „Sensor am Handgelenk. Gewicht gerade nach oben drücken,
  bis der Arm fast gestreckt ist, dann kontrolliert zurück."
- **Latzug**: „Sensor am Handgelenk. Stange kontrolliert zur Brust ziehen —
  diese Übung ist für die Kalibrierung anspruchsvoller als die anderen, bitte bei
  Problemen einmal neu kalibrieren, bevor du das Ergebnis anzweifelst."

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
- Keine weiteren Übungen über die 5 hinaus in dieser Runde.
- Keine Änderung an `_axisAnalysis`/Known-Count-Sweep selbst — die bleibt
  generisch, die Profile sind zusätzliche Plausibilisierung, kein Ersatz.

# Kanonisches Datenmodell-Referenzblatt

**Zweck:** Einzige autoritative Übersicht aller Domain-Klassen. Bei Abweichung zwischen dieser Datei und einer Prosa-Beschreibung im Architekturdokument gilt diese Datei, da sie speziell zum schnellen Nachschlagen ohne Kontext-Rekonstruktion gedacht ist.

## `WorkoutSession`

| Feld | Typ | Pflicht | Beschreibung |
|---|---|---|---|
| `id` | `String` (UUID) | ja | Eindeutige ID |
| `startedAt` | `DateTime` | ja | Beginn der Session |
| `endedAt` | `DateTime?` | nein | Ende — null solange Session läuft |
| `sets` | `List<ExerciseSet>` | ja | Alle Sätze dieser Session |

## `ExerciseSet`

| Feld | Typ | Pflicht | Beschreibung |
|---|---|---|---|
| `id` | `String` (UUID) | ja | Eindeutige ID |
| `exerciseId` | `String` | ja | Referenz auf die Übung (siehe Übungsliste in `00_ENTSCHEIDUNGEN_ERFORDERLICH.md`) |
| `countedReps` | `int` | ja | Von der Engine automatisch gezählte Wiederholungen |
| `correctedReps` | `int?` | nein | Falls vom Nutzer korrigiert — null, wenn keine Korrektur erfolgte |
| `endedAt` | `DateTime` | ja | Zeitpunkt des Satzendes |
| `reps` | `List<Rep>` | ja | Einzelne erkannte Wiederholungen |

## `Rep`

| Feld | Typ | Pflicht | Beschreibung |
|---|---|---|---|
| `timestamp` | `DateTime` | ja | Erkennungszeitpunkt |
| `peakMagnitude` | `double` | ja | Signalstärke des erkannten Peaks (zu Diagnosezwecken) |

## `CorrectionEvent`

| Feld | Typ | Pflicht | Beschreibung |
|---|---|---|---|
| `id` | `String` (UUID) | ja | Eindeutige ID |
| `setId` | `String` | ja | Referenz auf `ExerciseSet.id` |
| `systemCount` | `int` | ja | Von der Engine gezählter Wert vor Korrektur |
| `userCorrectedCount` | `int` | ja | Vom Nutzer eingegebener korrigierter Wert |
| `timestamp` | `DateTime` | ja | Zeitpunkt der Korrektur |

**Wichtig:** `CorrectionEvent` wird als eigenständiges Objekt gespeichert, nicht nur als überschriebenes Feld in `ExerciseSet` — der ursprüngliche `systemCount` muss erhalten bleiben, da er später als Trainingssignal für ML-Stufen (Phase 5) dient.

## `IWorkoutRepository` (Interface — Domain-Layer)

```dart
abstract class IWorkoutRepository {
  Future<void> saveSession(WorkoutSession session);
  Future<List<WorkoutSession>> getHistory();
  Future<void> saveCorrection(CorrectionEvent event);
  Future<void> deleteAllUserData(); // DSGVO-Löschrecht, siehe ADR-010
}
```

**Konkrete Implementierung:** `DriftWorkoutRepository` (siehe ADR-006 — finale Wahl Drift statt Isar).

**Verbindliche Regel:** Kein Code außerhalb der konkreten Implementierungsklasse darf einen Drift- oder sonstigen datenbankspezifischen Import enthalten. Prüfbar über: `grep -r "package:drift" lib/domain/` — muss leer sein.

## Beziehungen (Kurzform)

```
WorkoutSession 1---* ExerciseSet 1---* Rep
                          |
                          1
                          |
                          * CorrectionEvent (referenziert per setId, kein direktes Objekt-Feld)
```

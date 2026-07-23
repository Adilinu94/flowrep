# Glossar — Verbindliche Begriffsdefinitionen

**Zweck:** Verhindert, dass über mehrere KI-Sessions hinweg leicht unterschiedliche Bedeutungen für denselben Begriff entstehen. Bei jedem Konflikt zwischen dieser Datei und einer anderen Dokumentation gilt: **diese Datei hat Vorrang**, bis sie bewusst per ADR geändert wird.

## Konvention

- **Domain-Klassen** (Code) werden auf Englisch benannt.
- **UI-Texte und mündliche/schriftliche Kommunikation** verwenden Deutsch.
- Dieses Glossar verbindet beide Ebenen explizit, damit keine Übersetzungslücke entsteht.

## Kernbegriffe

| Begriff (Deutsch) | Code-Entsprechung | Definition | Abgrenzung |
|---|---|---|---|
| Wiederholung / Rep | `Rep` | Eine einzelne, vollständige Bewegung einer Übung (z. B. ein Bizeps-Curl von unten nach oben und zurück) | Nicht zu verwechseln mit "Peak" (ein einzelner erkannter Ausschlag im Sensorsignal — im Idealfall 1:1 zu einer Rep, aber nicht immer, siehe Doppel-Peak-Problem in der Workout-Engine-Doku) |
| Satz / Set | `ExerciseSet` | Eine zusammenhängende Folge von Wiederholungen derselben Übung ohne Unterbrechung durch eine Pause | Wird umgangssprachlich manchmal "Set" genannt — im Code immer `ExerciseSet`, nie `Set` (Namenskollision mit Darts `Set<T>`-Typ) |
| Trainingseinheit / Session / Workout | `WorkoutSession` | Die gesamte App-Nutzung von der ersten erkannten Bewegung bis zum manuellen oder automatischen Sessionende | "Workout" und "Session" werden in der bisherigen Dokumentation synonym verwendet — ab jetzt einheitlich `WorkoutSession` |
| Kalibrierung | *(kein eigenes Feld — Zustand `calibrating` in `WorkoutState`)* | Die ersten 2–3 Wiederholungen des allerersten Satzes, die gleichzeitig gezählt UND zur Schwellenwert-Verfeinerung genutzt werden | **Kein separater, "leerer" Kalibrierungssatz** — siehe Architekturdokument Abschnitt 2.1. Wird dieser Begriff in älteren Entwürfen als eigener Schritt vor dem ersten Satz beschrieben, ist das die überholte Version |
| Korrektur | `CorrectionEvent` | Eine manuelle Anpassung der von der Engine gezählten Wiederholungszahl durch den Nutzer nach Satzende | Wird niemals live während eines laufenden Satzes ausgelöst, nur danach (siehe Fehler-State-UX-Prinzip) |
| Pause | Zustand `paused` in `WorkoutState` | Die Zeit zwischen Satzende und dem Beginn des nächsten Satzes | Ab 60 s ohne Bewegung wechselt die Firmware zusätzlich in einen Wake-on-Motion-Sparmodus — das ist ein Firmware-Zustand, kein separater App-Zustand |
| Magic Moment | *(kein Code-Artefakt — Produktprinzip)* | Der Moment der ersten automatisch gezählten Wiederholung ohne Nutzer-Tap | Wird nie als Feature-Flag oder Funktion implementiert, sondern beschreibt die UX-Anforderung an Phase 1 |
| Kanonisches Protokoll | `protocol.yaml` | Die einzige verbindliche BLE-Byte-Format-Definition | Ersetzt jede abweichende Beschreibung in Prosa-Dokumenten |

## Rollenbegriffe (für die KI-Zusammenarbeit)

| Begriff | Bedeutung |
|---|---|
| "Ausführende KI" | Die schwächere KI (z. B. Claude Code), die die eigentliche Implementierung vornimmt |
| "Mensch im Loop" | Die in `00_ENTSCHEIDUNGEN_ERFORDERLICH.md` benannte Person, die bei Eskalationen kontaktiert wird |
| "Eskalation" | Das bewusste Stoppen der ausführenden KI vor einer Entscheidung, die laut `ESKALATIONS_PLAYBOOK.md` nicht selbstständig getroffen werden darf |

## Bekannte Fallstricke (bewusst vermerkt)

- **"Set" ohne Kontext ist mehrdeutig** — kann Trainings-Satz oder Dart-Collection-Typ meinen. Im Code nie ohne Präfix verwenden.
- **"Session" wurde in `bauplan_projektgym.md` und `kompletter_bauplan.md` unterschiedlich verwendet** (teils als App-Sitzung, teils als Trainingseinheit) — ab sofort ausschließlich `WorkoutSession` = Trainingseinheit.
- **"Kalibrierung"** wurde in einer früheren Planungsversion als separater Schritt beschrieben — diese Version ist überholt (siehe oben).

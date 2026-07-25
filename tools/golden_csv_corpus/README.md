# Golden CSV Corpus

Ablageort fuer echte Aufnahmen (CsvSessionRecorder-Format) +
Ground-Truth-Manifeste fuer `tools/golden_csv_harness.py` (Audit Hebel #2,
"Counting Reliability DoD messen"). Aktuell leer - noch keine echten
Aufnahmen im Repo (per 2026-07-25 gezielt geprueft: keine vorhanden).

## Ablauf pro Aufnahme

1. Trainingssession mit aktivem CSV-Export aufzeichnen (siehe
   `app/lib/data/repositories/csv_session_recorder.dart`), Datei hierher
   kopieren, z.B. `2026-07-26_bizeps_curl_normal.csv`.
2. Direkt danach die echte, von Hand gezaehlte Wiederholungszahl pro Satz
   notieren (nicht aus dem Gedaechtnis Tage spaeter - siehe
   `docs/hardware/sessions/2026-07-24/HW_SESSION_A1_A5.md` fuer den
   gleichen Grundsatz beim A1-A5-Test).
3. Manifest anlegen: `<gleicher-name>.csv.meta.json` daneben, Schema
   siehe Docstring von `tools/golden_csv_harness.py`:

```json
{
  "recording": "2026-07-26_bizeps_curl_normal.csv",
  "exercise_id": "bicep_curl",
  "scenario": "normal",
  "known_active_reps": [12],
  "notes": "ruhiges Tempo, Griff wie gewohnt"
}
```

`scenario` ist eines von `normal` / `wiggle` / `slow` / `placement_variant`.
Bei `wiggle` (Handy/M5 nur bewegt, kein echtes Training) entfaellt
`known_active_reps` - Erwartung ist dort immer 0 gezaehlte Reps.

## Ausfuehren

```bash
python3 tools/golden_csv_harness.py --corpus-dir tools/golden_csv_corpus
```

Kombiniert mit echten Session-Exports (App-vs-Manuell):

```bash
python3 tools/golden_csv_harness.py \
  --corpus-dir tools/golden_csv_corpus \
  --exports pfad/zu/flowrep_export_*.json
```

## Bekannte Einschraenkung

Der Replay-Check in `golden_csv_harness.py` nutzt `WorkoutEngineSim`
(combined-Signal-Pfad, `tools/workout_engine_simulation.py`) - das prueft
den Pfad, der aktuell greift, wenn `useSignedProjectionCounting=false`
UND kein Profil mit `chosenSignal == gP` geladen ist (siehe
`workout_engine.dart`, Zeile ~587/981). Fuer Sessions mit einem echten
gP-Profil (nach erfolgreicher Guided-Calibration-2.0) bildet der Replay
NICHT den tatsaechlich verwendeten Zaehlpfad ab - dafuer fehlt noch eine
Python-Portierung der g_p-Projektion inkl. Rotationsachse. Siehe FENCE
REPORT der Session, die dieses Tool angelegt hat, fuer Details.

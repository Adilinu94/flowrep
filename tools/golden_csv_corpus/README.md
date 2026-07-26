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

## Optional: g_p-Zaehlpfad mitpruefen (gp_profile)

Wurde die Aufnahme mit einem echten, bereits kalibrierten Guided-
Calibration-2.0-Profil (chosenSignal=gP) gemacht, kann das Manifest
zusaetzlich einen `gp_profile`-Block bekommen - dann wird dieselbe
Aufnahme AUCH durch den g_p-Zaehlpfad (GpCountingSim in
workout_engine_simulation.py) wiedergegeben, direkt neben combined:

```json
{
  "recording": "...",
  "exercise_id": "bicep_curl",
  "scenario": "normal",
  "known_active_reps": [12],
  "gp_profile": {
    "rotation_axis": [0.98, 0.1, 0.05],
    "gyro_bias": [1.5, -1.0, 0.8],
    "theta_deg_per_s": 120.0
  }
}
```

`rotation_axis`/`gyro_bias`/`theta_deg_per_s` entsprechen 1:1 den
`ExerciseProfile`-Feldern `rotationAxis`/`gyroBias`/`theta` (siehe
`app/lib/domain/models/exercise_profile.dart`) - am einfachsten aus dem
Profil zu entnehmen, mit dem die Aufnahme tatsaechlich gemacht wurde.
Ohne `gp_profile` wird nur combined geprueft (wie bisher).

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

Beide Replays (`WorkoutEngineSim` fuer combined, `GpCountingSim` fuer
g_p) sind Kaltstart-Replays der Referenz-Engines auf den rohen
Bewegungsdaten, KEINE Rekonstruktion des exakten Live-Kalibrierungs-
zustands der echten Session. Ausserdem nicht abgedeckt:
- Ghost-Rep-Gate (separates State-unabhaengiges Gate um `_commitRep`,
  siehe `ghost_rep_gate.dart`) - in der echten App zusaetzlich aktiv.
- `SignalProcessor.observeForAxisLearning` (Online-Achsenlernen OHNE
  bekanntes Profil) - `gp_profile` geht immer von einer bereits
  bekannten, kalibrierten Achse aus.
Siehe Klassendocstring von `GpCountingSim` in
`tools/workout_engine_simulation.py` fuer Details.

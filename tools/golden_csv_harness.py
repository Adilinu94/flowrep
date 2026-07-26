"""
tools/golden_csv_harness.py

Golden-CSV-Messharness fuer die im Audit (docs/design/AUDIT_FULL_REPO_
IMPROVEMENTS.md, Hebel #2 "Counting Reliability DoD messen") geforderte
formale Pruefung: App-vs-Manuell, Wiggle (Fehlzaehlungen bei
Alltagsbewegung), Langsame Reps, Placement-Varianten.

Zwei unabhaengige Datenquellen:

1. SESSION-EXPORTS (ExportService, `flowrep_export_*.json`, Format
   "flowrep-export-v1", siehe app/lib/data/services/export_service.dart):
   enthalten pro Satz countedReps (was die ECHTE, live laufende App
   gezaehlt hat) und correctedReps (vom Nutzer im Correction-Flow
   bestaetigte Wahrheit, siehe confirmCorrection() in engine_provider.dart).
   Das ist die direkteste App-vs-Manuell-Quelle: kein Reference-Nachbau
   noetig, es ist woertlich was die App gezaehlt hat vs. was der Mensch
   bestaetigt hat.

2. ROHE CSV-AUFNAHMEN (CsvSessionRecorder-Format, siehe
   app/lib/data/repositories/csv_session_recorder.dart; dasselbe
   Einlese-Format wie tools/dsp_lab_phase2_real_data.py verwendet - dessen
   read_recording_csv()/find_active_windows() werden hier wiederverwendet,
   NICHT neu geschrieben) + ein neu eingefuehrtes Mini-Manifest
   (`<name>.csv.meta.json` daneben) mit der Wahrheit (Wiederholungszahl
   pro erkanntem `active`-Fenster, Szenario-Tag).

   Diese Rohdaten werden durch WorkoutEngineSim aus
   tools/workout_engine_simulation.py wiedergegeben - die bereits
   validierte, mit workout_engine.dart synchron gehaltene Referenz
   (NICHT UnifiedEngineSim: das ist eine schmalere Klasse nur fuer den
   Settle-Gate-Regressionstest, ohne Refractory/Prominence/Adaptive-
   Threshold-Logik und ohne Satzgrenzen). Traegt ein Manifest zusaetzlich
   einen "gp_profile"-Block, wird dieselbe Aufnahme AUSSERDEM durch
   GpCountingSim (Portierung von _detectPeakSigned + applyCalibration
   ChosenSignal.gP, ebenfalls in workout_engine_simulation.py) wiedergegeben
   - direkter combined-vs-g_p-Vergleich auf derselben echten Aufnahme.

   WICHTIGE EINSCHRAENKUNG: das ist ein Kaltstart-Replay der
   Referenz-Engine auf den rohen Bewegungsdaten, KEINE Rekonstruktion des
   exakten Live-Kalibrierungszustands der echten Session (die rohe CSV
   traegt diesen Zustand nicht). Es beantwortet "zaehlt der Algorithmus
   diese echte Bewegung strukturell richtig", nicht "was hat die App in
   genau dieser Sekunde live gezaehlt" - dafuer siehe Kategorie 1.

Nicht Teil dieses Skripts: dsp_lab_phase2_real_data.py /
dsp_lab_phase2_extended.py / workout_engine_simulation.py bleiben
unveraendert - andere Fragestellungen (DSP-Pipeline-Vergleich alt/neu
bzw. Kalibrierungs-Regressionstests), keine Zaehl-Genauigkeit auf echten
Aufnahmen.

Manifest-Schema (`<name>.csv.meta.json`, liegt neben `<name>.csv`):
{
  "recording": "<name>.csv",
  "exercise_id": "bicep_curl",
  "scenario": "normal" | "wiggle" | "slow" | "placement_variant",
  "known_active_reps": [12, 10],   // Pflicht ausser bei "wiggle": ein Wert
                                     pro erkanntem active-Fenster, in
                                     chronologischer Reihenfolge
  "placement_label": "wrist_top",  // optional, nur fuer placement_variant
  "notes": "Freitext",
  "gp_profile": {                  // optional - siehe unten
    "rotation_axis": [0.98, 0.1, 0.05],
    "gyro_bias": [1.5, -1.0, 0.8],
    "theta_deg_per_s": 120.0,
    "min_rep_interval_seconds": 0.7  // optional
  }
}
Bei scenario == "wiggle" wird known_active_reps ignoriert - Erwartung ist
schlicht 0 gezaehlte Reps ueber die GESAMTE Aufnahme, unabhaengig von
workout_state (reine Alltagsbewegung, kein echtes Training).

Optionales gp_profile: wenn vorhanden, wird die Aufnahme ZUSAETZLICH zum
combined-Replay auch durch GpCountingSim (g_p-Zaehlpfad, siehe dessen
Klassendocstring in workout_engine_simulation.py fuer Umfang/Grenzen)
wiedergegeben - direkter Vergleich combined vs. g_p auf derselben echten
Aufnahme. rotation_axis/gyro_bias/theta_deg_per_s entsprechen 1:1 den
ExerciseProfile-Feldern rotationAxis/gyroBias/theta (siehe
app/lib/domain/models/exercise_profile.dart) eines echten, bereits
kalibrierten Guided-Calibration-2.0-Profils mit chosenSignal=gP.

Ausfuehrung:
    python3 tools/golden_csv_harness.py --smoke-test
        Nur Skript-Logik gegen synthetische Fixtures pruefen (ersetzt
        KEINE echte Validierung - wie --smoke-test in
        dsp_lab_phase2_real_data.py). Exit-Code immer 0 wenn das Skript
        durchlaeuft (Smoke-Test prueft die Mechanik, nicht ob echte Daten
        gut sind).
    python3 tools/golden_csv_harness.py --exports export1.json export2.json
        App-vs-Manuell ueber echte Session-Exports.
    python3 tools/golden_csv_harness.py --corpus-dir tools/golden_csv_corpus/
        Wiggle/Langsame-Reps/Placement ueber echte Aufnahmen + Manifeste
        in diesem Ordner (siehe dort README.md).
    (Kombinierbar: --exports und --corpus-dir gleichzeitig fuer einen
    Gesamtreport. Exit-Code 1 wenn dabei mindestens eine Kategorie FAIL.)
"""
import argparse
import csv
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp_lab_phase2_real_data import read_recording_csv, find_active_windows
from workout_engine_simulation import (
    SignalProcessor,
    WorkoutEngineSim,
    GpCountingSim,
    make_clean_reps,
    make_slow_reps,
    make_incidental_movement,
)

EXPORT_FORMAT = "flowrep-export-v1"
REQUIRED_MANIFEST_KEYS = ["recording", "exercise_id", "scenario"]
VALID_SCENARIOS = ("normal", "wiggle", "slow", "placement_variant")
CSV_COLUMNS = [
    "timestamp_ms", "accel_x_g", "accel_y_g", "accel_z_g",
    "gyro_x_dps", "gyro_y_dps", "gyro_z_dps", "dyn_magnitude", "workout_state",
]

# Abnahmekriterien (Audit Hebel #2) - hier zentral, nicht verstreut.
APP_VS_MANUAL_EXACT_MATCH_MIN = 0.85
APP_VS_MANUAL_MAE_MAX = 0.5
REPLAY_TOLERANCE_REPS = 0  # exakte Uebereinstimmung gefordert


# ---------------------------------------------------------------------
# Kategorie 1: App-vs-Manuell (echte Session-Exports)
# ---------------------------------------------------------------------

def load_export_sets(path):
    """Liest ein flowrep-export-v1 JSON (ExportService), gibt Liste von
    Saetzen mit countedReps (App-Live-Zaehlung) und correctedReps
    (Nutzer-bestaetigte Wahrheit aus dem Correction-Flow) zurueck. Saetze
    OHNE correctedReps (== null, nie korrigiert -> keine bestaetigte
    Ground Truth) werden uebersprungen."""
    with open(path) as f:
        export = json.load(f)
    fmt = export.get("format")
    if fmt != EXPORT_FORMAT:
        raise ValueError(
            f"{path}: unerwartetes Export-Format '{fmt}' (erwartet "
            f"'{EXPORT_FORMAT}'). Vermutlich kein ExportService-Export."
        )
    rows = []
    for session in export.get("sessions", []):
        for s in session.get("sets", []):
            corrected = s.get("correctedReps")
            if corrected is None:
                continue
            rows.append({
                "source_file": os.path.basename(path),
                "exercise_id": s.get("exerciseId", "?"),
                "counted": s.get("countedReps"),
                "corrected": corrected,
            })
    return rows


def app_vs_manual_report(export_paths):
    rows = []
    for p in export_paths:
        rows.extend(load_export_sets(p))
    if not rows:
        return {"rows": [], "n": 0, "exact_match_rate": None, "mae": None,
                "bias": None, "passed": None}
    deltas = [r["counted"] - r["corrected"] for r in rows]
    exact_rate = sum(1 for d in deltas if d == 0) / len(rows)
    mae = sum(abs(d) for d in deltas) / len(rows)
    bias = sum(deltas) / len(rows)
    passed = (exact_rate >= APP_VS_MANUAL_EXACT_MATCH_MIN
              and mae <= APP_VS_MANUAL_MAE_MAX)
    return {"rows": rows, "n": len(rows), "exact_match_rate": exact_rate,
            "mae": mae, "bias": bias, "passed": passed}


# ---------------------------------------------------------------------
# Kategorie 2-4: Wiggle / Langsame Reps / Placement (rohe CSV + Manifest)
# ---------------------------------------------------------------------

def load_manifest(meta_path):
    with open(meta_path) as f:
        manifest = json.load(f)
    missing = [k for k in REQUIRED_MANIFEST_KEYS if k not in manifest]
    if missing:
        raise ValueError(f"{meta_path}: Manifest fehlen Pflichtfelder {missing}")
    if manifest["scenario"] not in VALID_SCENARIOS:
        raise ValueError(
            f"{meta_path}: unbekanntes scenario '{manifest['scenario']}' "
            f"(erlaubt: {VALID_SCENARIOS})"
        )
    if manifest["scenario"] != "wiggle" and "known_active_reps" not in manifest:
        raise ValueError(
            f"{meta_path}: known_active_reps ist Pflicht ausser bei scenario=wiggle"
        )
    if "gp_profile" in manifest:
        missing_gp = [k for k in ("rotation_axis", "gyro_bias", "theta_deg_per_s")
                      if k not in manifest["gp_profile"]]
        if missing_gp:
            raise ValueError(f"{meta_path}: gp_profile fehlen Pflichtfelder {missing_gp}")
    manifest["_dir"] = os.path.dirname(os.path.abspath(meta_path))
    return manifest


def replay_recording(data):
    """Spielt eine Aufnahme (Format read_recording_csv()) komplett durch
    WorkoutEngineSim ab (calibration_reps=1, wie der aktuelle echte
    Dart-Default). Siehe Modul-Docstring fuer die Einschraenkung dieses
    Replays. Gibt sortierte Rep-Zeitstempel (Sekunden) ueber die GESAMTE
    Aufnahme zurueck."""
    engine = WorkoutEngineSim(calibration_reps=1, has_valid_calibration=False)
    t = data["timestamp_ms"] / 1000.0
    accel_mag = np.sqrt(
        data["accel_x_g"] ** 2 + data["accel_y_g"] ** 2 + data["accel_z_g"] ** 2
    )
    gyro_mag = np.sqrt(
        data["gyro_x_dps"] ** 2 + data["gyro_y_dps"] ** 2 + data["gyro_z_dps"] ** 2
    )
    for i in range(len(t)):
        engine.process_sample(float(t[i]), float(accel_mag[i]), float(gyro_mag[i]))
    all_reps = [rt for s in engine.completed_sets for (rt, _peak) in s]
    all_reps += [rt for (rt, _peak) in engine.reps_in_set]
    return sorted(all_reps)


def replay_gp(data, gp_profile, hz=50.0):
    """Analog zu replay_recording(), aber ueber GpCountingSim (g_p-
    Zaehlpfad). Braucht ein Profil (Achse, Bias, theta) - siehe
    Manifest-Feld gp_profile im Modul-Docstring."""
    engine = GpCountingSim(
        rotation_axis=gp_profile["rotation_axis"],
        gyro_bias=gp_profile["gyro_bias"],
        theta_deg_per_s=gp_profile["theta_deg_per_s"],
        min_rep_interval_seconds=gp_profile.get("min_rep_interval_seconds"),
        hz=hz,
    )
    t = data["timestamp_ms"] / 1000.0
    for i in range(len(t)):
        engine.process_sample(i, float(data["gyro_x_dps"][i]),
                               float(data["gyro_y_dps"][i]),
                               float(data["gyro_z_dps"][i]))
    return sorted(float(t[i]) for i in engine.reps)


def _judge_reps(scenario, rep_times, known_active_reps, windows):
    """Gemeinsame Bewertungslogik (combined UND g_p nutzen dieselbe
    Vergleichslogik gegen dieselben known_active_reps/Fenster)."""
    if scenario == "wiggle":
        return len(rep_times) == 0, f"{len(rep_times)} Rep(s) (erwartet 0)"
    if len(known_active_reps) != len(windows):
        return False, (f"Fenster ({len(windows)}) != known_active_reps "
                        f"({len(known_active_reps)}) - passt nicht zusammen")
    all_ok = True
    parts = []
    for i, (s0, s1) in enumerate(windows):
        counted = sum(1 for rt in rep_times if s0 <= rt <= s1)
        ok = abs(counted - known_active_reps[i]) <= REPLAY_TOLERANCE_REPS
        all_ok = all_ok and ok
        parts.append(f"F{i + 1}: erwartet={known_active_reps[i]} replay={counted} "
                     f"[{'OK' if ok else 'FEHLER'}]")
    return all_ok, ", ".join(parts)


def check_recording(manifest):
    csv_path = os.path.join(manifest["_dir"], manifest["recording"])
    data = read_recording_csv(csv_path)
    t = data["timestamp_ms"] / 1000.0
    windows = find_active_windows(t, data["workout_state"])
    rep_times = replay_recording(data)
    known = manifest.get("known_active_reps", [])

    result = {
        "manifest": manifest["recording"],
        "scenario": manifest["scenario"],
        "exercise_id": manifest.get("exercise_id", "?"),
        "placement_label": manifest.get("placement_label"),
        "windows": len(windows),
        "reps_total": len(rep_times),
    }

    passed, detail = _judge_reps(manifest["scenario"], rep_times, known, windows)
    result["passed"] = passed
    result["detail"] = f"combined -> {detail}"

    gp_profile = manifest.get("gp_profile")
    if gp_profile:
        gp_rep_times = replay_gp(data, gp_profile)
        gp_passed, gp_detail = _judge_reps(manifest["scenario"], gp_rep_times, known, windows)
        result["gp_reps_total"] = len(gp_rep_times)
        result["gp_passed"] = gp_passed
        result["detail"] += f"  |  g_p -> {gp_detail}"
        result["passed"] = result["passed"] and gp_passed

    return result


def corpus_report(corpus_dir):
    if not corpus_dir or not os.path.isdir(corpus_dir):
        return []
    meta_paths = sorted(
        os.path.join(corpus_dir, f)
        for f in os.listdir(corpus_dir)
        if f.endswith(".meta.json")
    )
    return [check_recording(load_manifest(mp)) for mp in meta_paths]


# ---------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------

def print_report(app_vs_manual, corpus_results):
    """Gibt den konsolidierten Report aus. Rueckgabe: True/False (Gesamt-
    PASS/FAIL) oder None, wenn ueberhaupt keine Daten vorlagen."""
    print("=" * 78)
    print("GOLDEN-CSV-MESSHARNESS -- Counting Reliability DoD (Audit Hebel #2)")
    print("=" * 78)

    print("\n--- Kategorie: App-vs-Manuell (Session-Exports) ---")
    if app_vs_manual["n"] == 0:
        print("Keine Session-Exports mit bestaetigter Korrektur gefunden "
              "(--exports nicht angegeben oder leer).")
    else:
        for r in app_vs_manual["rows"]:
            delta = r["counted"] - r["corrected"]
            print(f"  [{r['source_file']}] {r['exercise_id']}: "
                  f"App={r['counted']}  Manuell={r['corrected']}  Delta={delta:+d}")
        status = "PASS" if app_vs_manual["passed"] else "FAIL"
        print(f"  n={app_vs_manual['n']}  "
              f"Exact-Match-Rate={app_vs_manual['exact_match_rate']:.0%} "
              f"(Ziel >= {APP_VS_MANUAL_EXACT_MATCH_MIN:.0%})  "
              f"MAE={app_vs_manual['mae']:.2f} (Ziel <= {APP_VS_MANUAL_MAE_MAX})  "
              f"Bias={app_vs_manual['bias']:+.2f}  [{status}]")

    for label, key in (("Wiggle (Alltagsbewegung)", "wiggle"),
                        ("Langsame Reps", "slow"),
                        ("Placement-Varianten", "placement_variant"),
                        ("Normal (Referenz)", "normal")):
        rows = [r for r in corpus_results if r["scenario"] == key]
        print(f"\n--- Kategorie: {label} ---")
        if not rows:
            print("  Keine Aufnahmen mit diesem Szenario im Corpus-Ordner gefunden.")
            continue
        for r in rows:
            status = "PASS" if r["passed"] else "FAIL"
            extra = f" [{r['placement_label']}]" if r.get("placement_label") else ""
            print(f"  {r['manifest']}{extra}: {r['detail']}  [{status}]")

    categories_seen = []
    all_passed = True
    if app_vs_manual["n"] > 0:
        categories_seen.append("app_vs_manual")
        all_passed = all_passed and app_vs_manual["passed"]
    for r in corpus_results:
        categories_seen.append(r["scenario"])
        all_passed = all_passed and r["passed"]

    print("\n" + "=" * 78)
    if not categories_seen:
        print("KEINE DATEN GEFUNDEN -- weder --exports noch --corpus-dir mit "
              "Inhalt angegeben. Nichts zu pruefen.")
        print("=" * 78)
        return None
    print(f"GESAMT: {'PASS' if all_passed else 'FAIL'}  "
          f"({len(categories_seen)} Pruefung(en): {', '.join(categories_seen)})")
    print("=" * 78)
    return all_passed


# ---------------------------------------------------------------------
# Synthetische Smoke-Fixtures (ersetzen KEINE echte Validierung, analog
# zu --smoke-test in dsp_lab_phase2_real_data.py)
# ---------------------------------------------------------------------

def _write_csv(path, rows):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(CSV_COLUMNS)
        w.writerows(rows)


def _magnitude_to_csv_rows(t, accel_mag_g, gyro_mag_dps, active_windows_s):
    """Vereinfachte Achsenplatzierung NUR fuer Smoke-Fixtures: Gyro
    komplett auf X (Rotation-um-X-Modellannahme, siehe
    dsp_lab_phase2_real_data.py check_axis_assignment), Beschleunigung
    komplett auf Z (Gravitation + Bewegung). Ersetzt KEINE echte
    3-Achsen-Aufnahme - fuers Pruefen der Harness-Logik selbst
    ausreichend, da hier ohnehin nur Betrags-Personas (make_clean_reps
    u.ae.) vorliegen, keine echten 3-Achsen-Daten.

    Wichtig (empirisch gefunden): make_clean_reps()/make_slow_reps()
    liefern gyro_mag mit gelegentlichen kleinen negativen Werten (keine
    echte Betrags-Semantik). Beim CSV-Rundtrip macht replay_recording()
    daraus via sqrt(gx^2+gy^2+gz^2) einen positiven Ausschlag (Vorzeichen
    geht verloren) - das kann echte Rep-Erkennung stoeren. Deshalb hier
    auf >=0 geclippt, bevor geschrieben wird.
    """
    sp = SignalProcessor()
    rows = []
    for i in range(len(t)):
        in_window = any(s0 <= t[i] <= s1 for s0, s1 in active_windows_s)
        state = "active" if in_window else "idle"
        accel_mag = max(0.0, float(accel_mag_g[i]))
        gyro_mag = max(0.0, float(gyro_mag_dps[i]))
        dm = sp.process(accel_mag, gyro_mag)
        rows.append([
            round(float(t[i]) * 1000, 1),
            0.0, 0.0, round(accel_mag, 4),
            round(gyro_mag, 4), 0.0, 0.0,
            round(dm, 4), state,
        ])
    return rows


def _axes_to_csv_rows(t, acc3, gyro3, active_windows_s):
    """Wie _magnitude_to_csv_rows, aber fuer ECHTE 3-Achsen-Rohdaten
    (z.B. make_incidental_movement - zufaellige Rotationsachse pro
    Event). Wichtig fuer einen fairen gp_profile-Vergleich: eine
    Kollabierung auf eine einzelne Achse (wie _magnitude_to_csv_rows es
    tut) wuerde genau den Achsen-Selektivitaets-Effekt zerstoeren, den
    der g_p-Pfad gegenueber combined zeigen soll."""
    sp = SignalProcessor()
    rows = []
    for i in range(len(t)):
        in_window = any(s0 <= t[i] <= s1 for s0, s1 in active_windows_s)
        state = "active" if in_window else "idle"
        ax, ay, az = float(acc3[i][0]), float(acc3[i][1]), float(acc3[i][2])
        gx, gy, gz = float(gyro3[i][0]), float(gyro3[i][1]), float(gyro3[i][2])
        accel_mag = float(np.sqrt(ax * ax + ay * ay + az * az))
        gyro_mag = float(np.sqrt(gx * gx + gy * gy + gz * gz))
        dm = sp.process(accel_mag, gyro_mag)
        rows.append([
            round(float(t[i]) * 1000, 1),
            round(ax, 4), round(ay, 4), round(az, 4),
            round(gx, 4), round(gy, 4), round(gz, 4),
            round(dm, 4), state,
        ])
    return rows


def _build_smoke_fixtures(out_dir):
    """Erzeugt 3 synthetische CSV+Manifest-Paare (normal/slow/wiggle,
    ueber bereits bestehende, validierte Personas aus
    workout_engine_simulation.py) plus ein synthetisches
    Session-Export-JSON (App-vs-Manuell, mit einem bewusst nicht
    exakt passenden Satz, um auch den FAIL-Pfad der Metrik zu pruefen).
    ERSETZT KEINE echte Validierung."""
    os.makedirs(out_dir, exist_ok=True)

    def write_pair(name, t, accel_mag, gyro_mag, scenario, known_active_reps, notes,
                   gp_profile=None):
        windows_s = [(float(t[0]), float(t[-1]))]
        _write_csv(os.path.join(out_dir, f"{name}.csv"),
                   _magnitude_to_csv_rows(t, accel_mag, gyro_mag, windows_s))
        meta = {"recording": f"{name}.csv", "exercise_id": "bicep_curl",
                "scenario": scenario, "notes": notes}
        if known_active_reps is not None:
            meta["known_active_reps"] = known_active_reps
        if gp_profile is not None:
            meta["gp_profile"] = gp_profile
        with open(os.path.join(out_dir, f"{name}.csv.meta.json"), "w") as f:
            json.dump(meta, f, indent=2)

    t, am, gm = make_clean_reps(5, seed=42)
    # make_clean_reps() skaliert gm nur als kleine combined-Nebenkomponente
    # (empirisch geprueft: Spitze ~33 deg/s) - fuer g_p (Schwellen-Boden
    # 50 deg/s, echte Curls 100-200 deg/s, siehe applyCalibration-Kommentar
    # in workout_engine.dart) auf realistische Rotations-Groessenordnung
    # hochskaliert, bevor die CSV geschrieben wird (combined bleibt
    # unbeeinflusst funktionsfaehig: WorkoutEngineSim kalibriert relativ
    # zum beobachteten Peak, nicht absolut).
    gm_gp_scale = gm * 5.0
    # _magnitude_to_csv_rows platziert Gyro komplett auf X, ohne Bias -
    # das gp_profile hier beschreibt exakt diese Konstruktion (axis=[1,0,0],
    # bias=[0,0,0]), damit g_p-Replay auf denselben Rohdaten mitgeprueft
    # werden kann. theta_deg_per_s = 0.5 * Spitzenwert, analog zur
    # Known-Count-Kalibrierung.
    write_pair("_smoke_normal", t, am, gm_gp_scale, "normal", [5],
               "Synthetisch, make_clean_reps(5, seed=42), Gyro x5 auf "
               "g_p-realistische Groessenordnung skaliert",
               gp_profile={"rotation_axis": [1.0, 0.0, 0.0],
                           "gyro_bias": [0.0, 0.0, 0.0],
                           "theta_deg_per_s": 0.5 * float(np.max(gm_gp_scale))})

    t, am, gm = make_slow_reps(4, seed=43)
    write_pair("_smoke_slow", t, am, gm, "slow", [4],
               "Synthetisch, make_slow_reps(4, seed=43)")

    t3, acc3, gyro3 = make_incidental_movement(12, seed=9001)
    windows3_s = [(float(t3[0]), float(t3[-1]))]
    _write_csv(os.path.join(out_dir, "_smoke_wiggle.csv"),
               _axes_to_csv_rows(t3, acc3, gyro3, windows3_s))
    with open(os.path.join(out_dir, "_smoke_wiggle.csv.meta.json"), "w") as f:
        json.dump({
            "recording": "_smoke_wiggle.csv", "exercise_id": "bicep_curl",
            "scenario": "wiggle",
            "notes": "Synthetisch, make_incidental_movement(12, seed=9001) - "
                     "reproduziert STATUS_FORTSCHRITT.md 2026-07-18 Beschwerde "
                     "('Wenn den M5 nur beege oder etwas drehe werden reps "
                     "gezaehlt'). Echte 3-Achsen-Rohdaten (nicht auf eine "
                     "Achse kollabiert) - zufaellige Rotationsachse pro "
                     "Event, damit der gp_profile-Vergleich unten fair ist.",
            "gp_profile": {"rotation_axis": [1.0, 0.0, 0.0],
                           "gyro_bias": [0.0, 0.0, 0.0],
                           "theta_deg_per_s": 120.0},
        }, f, indent=2)

    export = {
        "format": EXPORT_FORMAT,
        "exportedAt": "2026-07-25T00:00:00.000",
        "privacy": "smoke test fixture",
        "sessions": [{
            "id": "smoke-session-1", "startedAt": "2026-07-25T00:00:00.000",
            "endedAt": "2026-07-25T00:10:00.000",
            "sets": [
                {"id": "s1", "exerciseId": "bicep_curl", "countedReps": 12,
                 "correctedReps": 12, "effectiveReps": 12},
                {"id": "s2", "exerciseId": "bicep_curl", "countedReps": 9,
                 "correctedReps": 10, "effectiveReps": 10},
                {"id": "s3", "exerciseId": "bicep_curl", "countedReps": 8,
                 "correctedReps": 8, "effectiveReps": 8},
            ],
        }],
    }
    export_path = os.path.join(out_dir, "_smoke_export.json")
    with open(export_path, "w") as f:
        json.dump(export, f, indent=2)

    return export_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--exports", nargs="*", default=[],
                         help="Pfad(e) zu echten flowrep-export-v1 JSON-Dateien "
                              "(App-vs-Manuell)")
    parser.add_argument("--corpus-dir", default=None,
                         help="Ordner mit echten CSV-Aufnahmen + *.csv.meta.json "
                              "(Wiggle/Langsame Reps/Placement)")
    parser.add_argument("--smoke-test", action="store_true",
                         help="Nur Skript-Logik gegen synthetische Fixtures pruefen, "
                              "ersetzt KEINE echte Validierung")
    args = parser.parse_args()

    if args.smoke_test or (not args.exports and not args.corpus_dir):
        if not args.smoke_test:
            print("Weder --exports noch --corpus-dir angegeben - fuehre Smoke-Test "
                  "aus (synthetische Daten, ersetzt KEINE echte Validierung).\n")
        smoke_dir = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "_golden_csv_harness_smoke"
        )
        export_path = _build_smoke_fixtures(smoke_dir)
        avm = app_vs_manual_report([export_path])
        corpus = corpus_report(smoke_dir)
        print_report(avm, corpus)
        print("\n(Smoke-Test: obiges PASS/FAIL bezieht sich auf synthetische "
              "Fixtures und prueft nur, dass die Harness-Logik selbst korrekt "
              "rechnet - kein Urteil ueber echte Daten. Deshalb exit 0.)")
        sys.exit(0)
    else:
        avm = app_vs_manual_report(args.exports)
        corpus = corpus_report(args.corpus_dir)
        passed = print_report(avm, corpus)
        sys.exit(1 if passed is False else 0)

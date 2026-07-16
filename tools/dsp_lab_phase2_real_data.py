"""
dsp_lab_phase2_real_data.py
Execution Plan (05_EXECUTION_PLAN.md), Phase 2, Aufgaben 2+3: liest echte,
aus der App exportierte CSV-Aufnahmen ein (Format: siehe
app/lib/data/repositories/csv_session_recorder.dart bzw.
docs/Umbauplan Flowrep/08_CSV_AUFNAHME_IMPLEMENTIERUNGSPLAN.md - WEICHT
von der urspruenglichen Spalten-Spec in Dokument 07 ab, siehe dort
Abschnitt 2 fuer die Begruendung):

    timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,
    gyro_z_dps,dyn_magnitude,workout_state

Aufgabe 3 (Achsenzuordnung): prueft, welche rohe Gyro-Achse waehrend
Bewegung tatsaechlich die groesste Amplitude zeigt - Modellannahme aus
Dokument 03 ist Rotation um X.

Aufgabe 2 (Pause/Peak alt vs. neu auf echten Rohdaten): `dyn_magnitude`
steht schon in der CSV (von der App selbst mit der PRODUKTIONS-Pipeline
berechnet, siehe CsvSessionRecorder) - das ist die "alte" Seite, ohne
Neuberechnung. Die "neue" Seite (Komplementaerfilter) wird aus den
Rohspalten neu berechnet, mit der bereits validierten Implementierung aus
tools/dsp_lab_phase2_extended.py (nicht neu geschrieben, wiederverwendet).

Einheiten-Hinweis: Die CSV liefert g / Grad-pro-Sekunde (siehe Spaltennamen-
Suffixe _g/_dps), complementary_filter_pipeline() erwartet aber m/s^2 und
rad/s (siehe deren build_signal(), z.B. 9.81*cos(...)). Dieses Skript
konvertiert das intern; ein Sanity-Check (mittlere Beschleunigungsmagnitude
nahe 9,81 nach Konvertierung) prueft, ob diese Annahme zur tatsaechlichen
CSV passt, statt es stillschweigend anzunehmen.

Rep-Fenster werden automatisch aus der `workout_state`-Spalte erkannt
(zusammenhaengende `active`-Abschnitte) - kein manuelles Zeitstempel-Suchen
noetig, genau der Vorteil, fuer den diese Spalte zusaetzlich zu Dokument 07
eingefuehrt wurde (siehe 08_..., Abschnitt 2).

Ausfuehrung:
    python dsp_lab_phase2_real_data.py <pfad_zur_csv>
    python dsp_lab_phase2_real_data.py --smoke-test   (ohne echte Aufnahme,
        prueft nur die Skript-Logik gegen eine synthetische CSV - ersetzt
        KEINE echte Validierung, siehe Execution Plan Phase 2 Abnahmekriterium)
"""
import argparse
import csv
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp_lab_phase2_extended import complementary_filter_pipeline

REQUIRED_COLUMNS = [
    "timestamp_ms", "accel_x_g", "accel_y_g", "accel_z_g",
    "gyro_x_dps", "gyro_y_dps", "gyro_z_dps", "dyn_magnitude", "workout_state",
]


def read_recording_csv(path):
    """Liest eine CSV im CsvSessionRecorder-Format (siehe Modul-Docstring)."""
    numeric_cols = REQUIRED_COLUMNS[:-1]  # alles ausser workout_state
    data = {k: [] for k in REQUIRED_COLUMNS}
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        missing = [c for c in REQUIRED_COLUMNS if c not in (reader.fieldnames or [])]
        if missing:
            raise ValueError(
                f"CSV fehlen erwartete Spalten: {missing}. "
                f"Gefunden: {reader.fieldnames}. Erwartetes Format steht im "
                f"Modul-Docstring / in csv_session_recorder.dart."
            )
        for row in reader:
            for c in numeric_cols:
                data[c].append(float(row[c]))
            data["workout_state"].append(row["workout_state"])
    for c in numeric_cols:
        data[c] = np.array(data[c])
    return data


def to_complementary_filter_units(data):
    """g -> m/s^2, Grad/s -> rad/s (siehe Einheiten-Hinweis oben). Gibt
    zusaetzlich einen Sanity-Check-String zurueck statt die Annahme
    stillschweigend zu treffen."""
    ax = data["accel_x_g"] * 9.81
    ay = data["accel_y_g"] * 9.81
    az = data["accel_z_g"] * 9.81
    gx = np.radians(data["gyro_x_dps"])

    accel_mag = np.sqrt(ax**2 + ay**2 + az**2)
    mean_mag = float(np.mean(accel_mag))
    ok = 8.0 <= mean_mag <= 11.5
    msg = (f"Sanity-Check nach g->m/s^2-Konvertierung: mittlere "
           f"Beschleunigungsmagnitude={mean_mag:.2f} (erwartet nahe 9.81). "
           + ("OK." if ok else
              "ABWEICHUNG - Einheiten-Annahme (g/deg-per-s laut Spaltennamen) "
              "stimmt moeglicherweise nicht mit dieser CSV ueberein, Ergebnisse "
              "unten mit Vorsicht behandeln."))
    return ax, ay, az, gx, ok, msg


def find_active_windows(t, workout_state):
    """Aufgabe 2: Rep-Fenster automatisch aus zusammenhaengenden
    workout_state == 'active'-Abschnitten ableiten, statt Zeitstempel von
    Hand zu suchen (siehe Modul-Docstring)."""
    windows = []
    in_active = False
    start = None
    for i, s in enumerate(workout_state):
        if s == "active" and not in_active:
            start, in_active = t[i], True
        elif s != "active" and in_active:
            windows.append((start, t[i - 1]))
            in_active = False
    if in_active:
        windows.append((start, t[-1]))
    return windows


def check_axis_assignment(gyro_dps_by_axis):
    """Execution Plan Phase 2, Aufgabe 3: welche Gyro-Achse hat waehrend
    der Aufnahme die groesste Amplitude? Modellannahme (Dokument 03) ist
    Rotation um X."""
    amps = {name: float(np.ptp(vals)) for name, vals in gyro_dps_by_axis.items()}
    dominant = max(amps, key=amps.get)
    print("=== Achsen-Check (Aufgabe 3) ===")
    for name, v in amps.items():
        marker = "  <-- groesste Amplitude" if name == dominant else ""
        print(f"  {name}: peak-to-peak={v:.1f} deg/s{marker}")
    if dominant == "gyro_x_dps":
        print("  Modellannahme 'Rotation um X' (Dokument 03) bestaetigt.")
    else:
        print(f"  WARNUNG: Modellannahme 'Rotation um X' trifft NICHT zu "
              f"(dominante Achse ist {dominant}). complementary_filter_pipeline() "
              f"muesste vor Phase 3 entsprechend angepasst werden (andere Achse "
              f"als Rotationsachse, andere zwei als Gravitationsachsen).")
    print()
    return dominant


def pause_peak_ratios(t, dm, windows):
    out = []
    for i, (s0, s1) in enumerate(windows):
        pause_end = windows[i + 1][0] if i + 1 < len(windows) else s1 + 2.0
        peak = dm[(t >= s0) & (t < s1)].max()
        pause_mask = (t >= s1) & (t < pause_end)
        if not pause_mask.any():
            continue
        pause = dm[pause_mask].mean()
        out.append(pause / peak)
    return out


def compare_pipelines(t, dyn_magnitude_deployed, ax, ay, az, gx, windows):
    """Aufgabe 2: alt (aus CSV, von der App mit der Produktions-Pipeline
    berechnet) vs. neu (hier aus den Rohdaten neu berechnet) auf denselben
    echten Rohdaten."""
    if len(windows) == 0:
        print("Keine 'active'-Phasen in workout_state gefunden - "
              "Pause/Peak-Vergleich (Aufgabe 2) uebersprungen.")
        return

    ratios_deployed = pause_peak_ratios(t, dyn_magnitude_deployed, windows)
    dm_new = complementary_filter_pipeline(t, ax, ay, az, gx)
    ratios_new = pause_peak_ratios(t, dm_new, windows)

    print(f"=== Pause/Peak-Vergleich auf ECHTEN Daten (Aufgabe 2, "
          f"{len(windows)} erkannte Reps) ===")
    for i, (rd, rn) in enumerate(zip(ratios_deployed, ratios_new)):
        print(f"  Rep {i + 1}: aktuell deployt={rd:.3f}   komplementaer={rn:.3f}")
    if ratios_deployed and ratios_new:
        print(f"  Mittelwert: aktuell deployt={np.mean(ratios_deployed):.3f}   "
              f"komplementaer={np.mean(ratios_new):.3f}")
    print("  Abnahmekriterium (Dokument 05, Phase 2): komplementaer muss "
          "spuerbar UNTER aktuell deployt liegen, sonst laut Skript-1c-Befund "
          "(synthetisch) Phase 3 nicht beginnen.")
    print()


def _write_smoke_test_csv(path):
    """Erzeugt eine synthetische CSV im echten CsvSessionRecorder-Format,
    NUR um dieses Skript ohne reale Aufnahme auf Programmierfehler zu
    pruefen. Ersetzt KEINE echte Validierung (Dokument 05 Phase 2
    Abnahmekriterium verlangt echte Daten)."""
    from dsp_lab_phase2_extended import build_signal, current_production_pipeline
    windows_s = [(10.0, 12.0), (13.0, 15.0), (16.0, 18.0)]
    t, rx, ry, rz, gx_rad = build_signal(rep_freq_hz=0.5, rom_deg=140,
                                          rep_windows=windows_s, seed=1)
    dm = current_production_pipeline(t, rx, ry, rz, gx_rad)
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(REQUIRED_COLUMNS)
        for i in range(len(t)):
            in_window = any(s0 <= t[i] < s1 for s0, s1 in windows_s)
            state = "active" if in_window else "idle"
            w.writerow([
                round(t[i] * 1000, 1),
                round(rx[i] / 9.81, 4), round(ry[i] / 9.81, 4), round(rz[i] / 9.81, 4),
                round(np.degrees(gx_rad[i]), 4), 0.0, 0.0,
                round(dm[i], 4), state,
            ])


def run(csv_path):
    data = read_recording_csv(csv_path)
    t = data["timestamp_ms"] / 1000.0
    ax, ay, az, gx, units_ok, units_msg = to_complementary_filter_units(data)
    print(units_msg)
    print()
    check_axis_assignment({
        "gyro_x_dps": data["gyro_x_dps"],
        "gyro_y_dps": data["gyro_y_dps"],
        "gyro_z_dps": data["gyro_z_dps"],
    })
    windows = find_active_windows(t, data["workout_state"])
    compare_pipelines(t, data["dyn_magnitude"], ax, ay, az, gx, windows)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_path", nargs="?", help="Pfad zu einer echten Aufnahme-CSV")
    parser.add_argument("--smoke-test", action="store_true",
                         help="Nur Skript-Logik gegen synthetische CSV pruefen, "
                              "ersetzt keine echte Validierung")
    args = parser.parse_args()

    if args.smoke_test or not args.csv_path:
        if not args.smoke_test:
            print("Kein CSV-Pfad angegeben - fuehre Smoke-Test aus "
                  "(synthetische Daten, ersetzt KEINE echte Validierung).\n")
        smoke_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                   "_smoke_test_recording.csv")
        _write_smoke_test_csv(smoke_path)
        run(smoke_path)
    else:
        run(args.csv_path)

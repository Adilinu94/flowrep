"""
dsp_lab_phase2_extended.py
Phase 2 (05_EXECUTION_PLAN.md): Erweiterung von docs/Umbauplan Flowrep/
04_DSP_LABOR_PYTHON_VALIDIERUNG.md, Skript 1/1b.

Fragestellung: Kann der in ADR-019 vorgeschlagene Komplementaerfilter die
AKTUELL DEPLOYTE Formel (EMA + gyroWeight, signal_processor.dart) unter
realistischeren Bedingungen doch noch schlagen? Dokument 04 testete nur
sauberes Signal ohne Haltungsdrift/Gyro-Bias - beides dort explizit als
Luecke benannt ("Was dieser Test nicht zeigt").

Getestet werden zwei zusaetzliche, realistische Effekte:
  - posture_drift_deg: Ruhehaltung driftet leicht zwischen den Reps
    (Person streckt den Arm nicht jedes Mal exakt gleich weit aus)
  - gyro_bias_dps: konstanter Gyro-Bias, ein reales IMU-Artefakt. Da der
    Komplementaerfilter das Gyrosignal AUFINTEGRIERT, akkumuliert ein
    solcher Bias ueber die Zeit zu einem wachsenden Fehler in der
    Gravitationsschaetzung - ein klassisches Problem von AHRS/Komplementaer-
    filtern in der Literatur, in Dokument 04 aber noch nicht geprueft.

Annahmen (nicht gemessen, plausible Groessenordnung): 4 Grad Std.abw.
Haltungsdrift pro Rep, 3 Grad/s Gyro-Bias. Sollte durch echte BMI270-Messung
(Szene G aus Dokument 07) ersetzt werden, sobald verfuegbar.

Ausfuehrung: python dsp_lab_phase2_extended.py
Ergebnis dieses Laufs: siehe docs/Umbauplan Flowrep/04_DSP_LABOR_PYTHON_VALIDIERUNG.md,
Abschnitt 'Skript 1c'.
"""
import numpy as np
from scipy.signal import butter, filtfilt


def butter_lowpass_filter(data, cutoff, fs, order=2):
    nyq = 0.5 * fs
    b, a = butter(order, cutoff / nyq, btype='low', analog=False)
    return filtfilt(b, a, data)


def build_signal(rep_freq_hz, rom_deg, rep_windows, fs=50.0, seed=0,
                  posture_drift_deg=0.0, gyro_bias_dps=0.0):
    rng = np.random.default_rng(seed)
    total_s = rep_windows[-1][1] + 3.0
    t = np.arange(0, total_s, 1 / fs)
    angle_rad = np.zeros_like(t)

    n = len(rep_windows)
    rest_offsets_deg = (np.cumsum(rng.normal(0, posture_drift_deg, n))
                         if posture_drift_deg > 0 else np.zeros(n))

    prev_end = 0.0
    for i, (s0, s1) in enumerate(rep_windows):
        rest_mask = (t >= prev_end) & (t < s0)
        angle_rad[rest_mask] = np.radians(rest_offsets_deg[i])
        mask = (t >= s0) & (t < s1)
        tt = t[mask] - s0
        angle_rad[mask] = (np.radians(rest_offsets_deg[i])
                            + (np.sin(2*np.pi*rep_freq_hz*tt - np.pi/2)+1)/2 * np.radians(rom_deg))
        prev_end = s1
    angle_rad[t >= prev_end] = np.radians(rest_offsets_deg[-1])

    gyro_x_rad_s = np.gradient(angle_rad, t)

    grav_y = 9.81 * np.cos(angle_rad)
    grav_z = 9.81 * np.sin(angle_rad)
    dyn_acc_y = np.zeros_like(t)
    dyn_acc_z = np.zeros_like(t)
    for (s0, s1) in rep_windows:
        mask = (t >= s0) & (t < s1)
        tt = t[mask] - s0
        dyn_acc_y[mask] = np.sin(2*np.pi*rep_freq_hz*tt) * 3.0
        dyn_acc_z[mask] = np.sin(2*np.pi*rep_freq_hz*tt + np.pi/4) * 1.5

    noise_a = rng.normal(0, 0.3, len(t))
    noise_g = rng.normal(0, 0.05, len(t))
    bias_rad_s = np.radians(gyro_bias_dps)

    raw_y = grav_y + dyn_acc_y + noise_a
    raw_z = grav_z + dyn_acc_z + noise_a
    raw_x = rng.normal(0, 0.3, len(t))
    gyro_x_meas = gyro_x_rad_s + noise_g + bias_rad_s
    return t, raw_x, raw_y, raw_z, gyro_x_meas


def complementary_filter_pipeline(t, rx, ry, rz, gyro_x, fs=50.0, alpha=0.02, trust_bw=1.5):
    n = len(t)
    dt = np.diff(t, prepend=t[0] - 1/fs)
    g_hat = np.array([ry[0], rz[0]])
    norm = np.linalg.norm(g_hat)
    g_hat = g_hat / norm * 9.81 if norm > 1e-6 else np.array([9.81, 0.0])
    lin_y = np.zeros(n)
    lin_z = np.zeros(n)
    for i in range(n):
        dtheta = gyro_x[i] * dt[i]
        c, s = np.cos(dtheta), np.sin(dtheta)
        g_pred = np.array([g_hat[0]*c - g_hat[1]*s, g_hat[0]*s + g_hat[1]*c])
        accel_mag = np.hypot(ry[i], rz[i])
        trust = np.exp(-((accel_mag - 9.81)**2) / (2 * trust_bw**2))
        a_eff = alpha * trust
        accel_dir = np.array([ry[i], rz[i]])
        accel_norm = np.linalg.norm(accel_dir)
        if accel_norm > 1e-6:
            accel_dir = accel_dir / accel_norm * 9.81
            g_hat = (1 - a_eff) * g_pred + a_eff * accel_dir
        else:
            g_hat = g_pred
        lin_y[i] = ry[i] - g_hat[0]
        lin_z[i] = rz[i] - g_hat[1]
    lin_x = butter_lowpass_filter(rx, 2.0, fs)
    return np.sqrt(lin_x**2 + lin_y**2 + lin_z**2)


def current_production_pipeline(t, rx, ry, rz, gyro_x_rad_s, fs=50.0, ema_alpha=0.6, gyro_weight=0.05):
    accel_g_y = ry / 9.81
    accel_g_z = rz / 9.81
    accel_g_x = rx / 9.81
    accel_mag_g = np.sqrt(accel_g_x**2 + accel_g_y**2 + accel_g_z**2)
    gyro_deg_s = np.abs(gyro_x_rad_s) * (180.0 / np.pi)
    combined_raw = accel_mag_g + gyro_deg_s * gyro_weight
    filtered = np.zeros_like(combined_raw)
    filtered[0] = combined_raw[0]
    for i in range(1, len(combined_raw)):
        filtered[i] = filtered[i-1] * (1 - ema_alpha) + combined_raw[i] * ema_alpha
    return filtered


def ratios(t, dm, windows):
    out = []
    for i, (s0, s1) in enumerate(windows):
        p_end = windows[i+1][0] if i+1 < len(windows) else s1 + 2
        peak = dm[(t >= s0) & (t < s1)].max()
        pause = dm[(t >= s1) & (t < p_end)].mean()
        out.append((peak, pause, pause/peak))
    return out


def mean_ratio(t, dm, windows):
    rs = ratios(t, dm, windows)
    return float(np.mean([r[2] for r in rs]))


if __name__ == "__main__":
    windows = [(10.0, 12.0), (13.0, 15.0), (16.0, 18.0)]
    t, rx, ry, rz, gx = build_signal(rep_freq_hz=0.5, rom_deg=140, rep_windows=windows, seed=1)

    dm_comp = complementary_filter_pipeline(t, rx, ry, rz, gx)
    dm_curr = current_production_pipeline(t, rx, ry, rz, gx)

    print("=== SANITY CHECK gegen Dokument 04 (muss ~0.15/0.21/0.14 und ~0.09/0.09/0.09 ergeben) ===")
    print("Komplementaer:", [f"{r[2]:.2f}" for r in ratios(t, dm_comp, windows)])
    print("Aktuell deployt:", [f"{r[2]:.2f}" for r in ratios(t, dm_curr, windows)])
    print()

    print("=== Szenario: + Haltungsdrift zwischen Reps (4 Grad Std.abw.) ===")
    t2, rx2, ry2, rz2, gx2 = build_signal(0.5, 140, windows, seed=1, posture_drift_deg=4.0)
    print("Komplementaer Ø:", round(mean_ratio(t2, complementary_filter_pipeline(t2, rx2, ry2, rz2, gx2), windows), 3))
    print("Aktuell deployt Ø:", round(mean_ratio(t2, current_production_pipeline(t2, rx2, ry2, rz2, gx2), windows), 3))
    print()

    print("=== Szenario: + Gyro-Bias (3 Grad/s) ===")
    t3, rx3, ry3, rz3, gx3 = build_signal(0.5, 140, windows, seed=1, gyro_bias_dps=3.0)
    print("Komplementaer Ø:", round(mean_ratio(t3, complementary_filter_pipeline(t3, rx3, ry3, rz3, gx3), windows), 3))
    print("Aktuell deployt Ø:", round(mean_ratio(t3, current_production_pipeline(t3, rx3, ry3, rz3, gx3), windows), 3))
    print()

    print("=== Szenario: Haltungsdrift + Gyro-Bias kombiniert ===")
    t4, rx4, ry4, rz4, gx4 = build_signal(0.5, 140, windows, seed=1, posture_drift_deg=4.0, gyro_bias_dps=3.0)
    print("Komplementaer Ø:", round(mean_ratio(t4, complementary_filter_pipeline(t4, rx4, ry4, rz4, gx4), windows), 3))
    print("Aktuell deployt Ø:", round(mean_ratio(t4, current_production_pipeline(t4, rx4, ry4, rz4, gx4), windows), 3))
    print()

    print("=== Parameter-Sweep Komplementaerfilter (alpha x trust_bw), worst-case ueber alle 4 Szenarien ===")
    scenarios = [("Basis", t, rx, ry, rz, gx), ("Drift", t2, rx2, ry2, rz2, gx2),
                 ("Bias", t3, rx3, ry3, rz3, gx3), ("Drift+Bias", t4, rx4, ry4, rz4, gx4)]
    best = None
    for alpha in [0.01, 0.02, 0.05, 0.1, 0.2]:
        for trust_bw in [1.0, 1.5, 2.5]:
            row = [mean_ratio(ts, complementary_filter_pipeline(ts, rxs, rys, rzs, gxs, alpha=alpha, trust_bw=trust_bw), windows)
                   for (_, ts, rxs, rys, rzs, gxs) in scenarios]
            worst = max(row)
            if best is None or worst < best[0]:
                best = (worst, alpha, trust_bw, row)
    print(f"Bestes robustes Setting: alpha={best[1]}, trust_bw={best[2]}, "
          f"schlechtester Fall ueber alle 4 Szenarien={best[0]:.3f}")
    print("(zum Vergleich: aktuell deployte Formel liegt in allen 4 Szenarien bei 0.091-0.098)")

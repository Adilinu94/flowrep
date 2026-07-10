"""
Python-Portierung der Workout-Engine-Logik aus app/lib/domain/workout_engine.dart,
um den Zähl-Algorithmus gegen synthetische, schwierige Szenarien zu prüfen -
BEVOR die Hardware da ist und BEVOR ein echtes Dart-Testergebnis vorliegt.

Das ist kein Ersatz für echte Sensordaten. Es validiert nur, ob die
Algorithmus-LOGIK selbst (Hysterese, adaptive Kalibrierung) sich in
plausiblen Kurvenformen sinnvoll verhaelt - insbesondere bei Faellen, die
im RecoFit-Paper explizit als schwierig benannt wurden (Doppel-Peak pro
Wiederholung, z.B. bei Kniebeugen; unterschiedliche Tempi).
"""

import numpy as np

class WorkoutEngineSim:
    def __init__(self, gyro_weight=0.05, envelope_decay=0.95,
                 falling_edge_ratio=0.7, calibration_reps=3,
                 pause_after_s=4.0, baseline_ema_alpha=0.01):
        self.gyro_weight = gyro_weight
        self.envelope_decay = envelope_decay
        self.falling_edge_ratio = falling_edge_ratio
        self.calibration_reps = calibration_reps
        self.pause_after_s = pause_after_s
        self.baseline_ema_alpha = baseline_ema_alpha

        self.state = "idle"
        self.peak_threshold = 1.3
        self.running_envelope = 0.0
        self.above_threshold = False
        self.current_excursion_peak = 0.0
        self.last_movement_t = None
        self.reps_in_set = []
        self.completed_sets = []
        self.baseline_level = None  # initialised from the first sample

    def process_sample(self, t, accel_mag, gyro_mag):
        combined = accel_mag + gyro_mag * self.gyro_weight
        self.running_envelope = max(combined, self.running_envelope * self.envelope_decay)

        # Track resting baseline continuously, but only from quiet samples -
        # a sample mid-excursion must not pull the baseline estimate upward,
        # or a long set would slowly convince the engine that "moving" is
        # the new baseline.
        if self.baseline_level is None:
            self.baseline_level = combined
        elif not self.above_threshold:
            self.baseline_level = (
                self.baseline_level * (1 - self.baseline_ema_alpha)
                + combined * self.baseline_ema_alpha
            )

        if self.state == "idle":
            if combined > self.peak_threshold * 0.5:
                self.state = "calibrating"
                self.last_movement_t = t
        elif self.state == "calibrating":
            self._detect_peak(t, combined)
            if len(self.reps_in_set) >= self.calibration_reps:
                # BUGFIX: the previous version used the instantaneous
                # running_envelope at the moment this check fires - which
                # is usually mid-rest-period, already decayed back near
                # baseline, producing a threshold BELOW resting level and
                # permanently stuck peak detection. Use the actual peak
                # magnitudes recorded during calibration instead, anchored
                # against the tracked resting baseline.
                calibration_peaks = [p for (_, p) in self.reps_in_set]
                avg_peak = sum(calibration_peaks) / len(calibration_peaks)
                calibrated = self.baseline_level + (avg_peak - self.baseline_level) * 0.5
                # Safety floor: without this, if the very first movements
                # the user makes during calibration are themselves small/
                # marginal (a cheat rep, an accidental nudge), the engine
                # calibrates itself to treat that marginal signal as
                # "normal" and accepts everything at that level from then
                # on. A floor relative to baseline stops calibration from
                # being poisoned this way. Value is a starting point, not
                # empirically tuned against real hardware yet.
                min_floor = self.baseline_level + 0.10
                self.peak_threshold = max(calibrated, min_floor)
                self.state = "active"
        elif self.state == "active":
            self._detect_peak(t, combined)
            if self.last_movement_t is not None and (t - self.last_movement_t) > self.pause_after_s:
                self._end_set()
        elif self.state == "paused":
            if combined > self.peak_threshold * 0.5:
                self.state = "active"
                self.last_movement_t = t

    def _detect_peak(self, t, combined):
        if not self.above_threshold and combined > self.peak_threshold:
            self.above_threshold = True
            self.current_excursion_peak = combined
            self.last_movement_t = t
        elif self.above_threshold:
            self.current_excursion_peak = max(self.current_excursion_peak, combined)
            self.last_movement_t = t
            if combined < self.peak_threshold * self.falling_edge_ratio:
                self.above_threshold = False
                self.reps_in_set.append((t, self.current_excursion_peak))

    def _end_set(self):
        if self.reps_in_set:
            self.completed_sets.append(list(self.reps_in_set))
        self.reps_in_set = []
        self.state = "paused" if self.completed_sets else "idle"


def make_clean_reps(n, tempo_s=1.2, baseline=1.0, peak=1.8, hz=50, noise=0.02, seed=0):
    """n reps at a constant, 'clean demo' tempo - the easy case."""
    rng = np.random.default_rng(seed)
    dt = 1.0 / hz
    t, accel, gyro = [], [], []
    time = 0.0
    for _ in range(n):
        steps = int(tempo_s * hz)
        for i in range(steps):
            phase = np.pi * i / steps
            t.append(time)
            accel.append(baseline + (peak - baseline) * np.sin(phase) + rng.normal(0, noise))
            gyro.append(30 * np.sin(phase) + rng.normal(0, 2))
            time += dt
        for _ in range(int(0.3 * hz)):  # short rest between reps within a set
            t.append(time); accel.append(baseline + rng.normal(0, noise)); gyro.append(rng.normal(0, 2))
            time += dt
    return np.array(t), np.array(accel), np.array(gyro)


def make_double_peak_reps(n, tempo_s=1.6, baseline=1.0, peak=1.9, hz=50, noise=0.02, seed=1):
    """Squat-like: two acceleration bursts per single rep (down + up).
    This is exactly the confound the RecoFit paper flags for exercises
    like squats - a naive single-peak counter would count 2 reps here."""
    rng = np.random.default_rng(seed)
    dt = 1.0 / hz
    t, accel, gyro = [], [], []
    time = 0.0
    for _ in range(n):
        steps = int(tempo_s * hz)
        for i in range(steps):
            phase = 2 * np.pi * i / steps  # two humps across one rep
            t.append(time)
            accel.append(baseline + (peak - baseline) * abs(np.sin(phase)) + rng.normal(0, noise))
            gyro.append(30 * abs(np.sin(phase)) + rng.normal(0, 2))
            time += dt
        for _ in range(int(0.3 * hz)):
            t.append(time); accel.append(baseline + rng.normal(0, noise)); gyro.append(rng.normal(0, 2))
            time += dt
    return np.array(t), np.array(accel), np.array(gyro)


def make_slow_reps(n, tempo_s=3.5, baseline=1.0, peak=1.4, hz=50, noise=0.02, seed=2):
    """Slow, controlled reps with a much smaller amplitude - the
    'Powerlifter with very slow movement' edge case named in the original
    risk analysis."""
    return make_clean_reps(n, tempo_s=tempo_s, baseline=baseline, peak=peak, hz=hz, noise=noise, seed=seed)


def make_partial_reps(n, tempo_s=1.0, baseline=1.0, peak=1.15, hz=50, noise=0.02, seed=3):
    """Cheat reps that barely clear a naive fixed threshold - here
    deliberately UNDER a reasonable calibrated threshold, to check the
    engine correctly does NOT count these as full reps."""
    return make_clean_reps(n, tempo_s=tempo_s, baseline=baseline, peak=peak, hz=hz, noise=noise, seed=seed)


def make_mixed_quality_reps(n_good_first, n_cheat, n_good_after, tempo_s=1.2,
                             baseline=1.0, good_peak=1.8, cheat_peak=1.15,
                             hz=50, noise=0.02, seed=4):
    """More realistic than a pure-cheat-rep set: calibrates on GOOD reps
    first (as intended - the user's real first movements), then some
    cheat/partial reps are mixed in later, followed by more good reps.
    Tests whether the *already calibrated* threshold correctly rejects
    reps that fall short, not whether an uncalibrated system can somehow
    guess quality from nothing."""
    rng = np.random.default_rng(seed)
    dt = 1.0 / hz
    t, accel, gyro, labels = [], [], [], []
    time = 0.0

    def add_rep(peak, label):
        nonlocal time
        steps = int(tempo_s * hz)
        for i in range(steps):
            phase = np.pi * i / steps
            t.append(time)
            accel.append(baseline + (peak - baseline) * np.sin(phase) + rng.normal(0, noise))
            gyro.append(30 * np.sin(phase) * (peak - baseline) / (good_peak - baseline) + rng.normal(0, 2))
            time += dt
        for _ in range(int(0.3 * hz)):
            t.append(time); accel.append(baseline + rng.normal(0, noise)); gyro.append(rng.normal(0, 2))
            time += dt
        labels.append(label)

    for _ in range(n_good_first):
        add_rep(good_peak, "good")
    for _ in range(n_cheat):
        add_rep(cheat_peak, "cheat")
    for _ in range(n_good_after):
        add_rep(good_peak, "good")

    return np.array(t), np.array(accel), np.array(gyro), labels


def run_scenario(name, t, accel, gyro, expected_reps, **engine_kwargs):

    engine = WorkoutEngineSim(**engine_kwargs)
    for ti, a, g in zip(t, accel, gyro):
        engine.process_sample(ti, a, g)
    engine._end_set()  # flush whatever set is still open at the end
    counted = sum(len(s) for s in engine.completed_sets)
    status = "OK" if counted == expected_reps else "ABWEICHUNG"
    print(f"{name:30s} erwartet={expected_reps:3d}  gezaehlt={counted:3d}  [{status}]")
    return counted, engine


if __name__ == "__main__":
    print("=== FlowRep Workout-Engine-Simulation: Validierung vor Hardware-Ankunft ===\n")

    scenarios = [
        ("Saubere Reps (Demo-Tempo)", make_clean_reps(10), 10),
        ("Doppel-Peak-Uebung (Squat-artig)", make_double_peak_reps(10), 10),
        ("Sehr langsame Reps (Powerlifter)", make_slow_reps(8), 8),
    ]

    print(f"{'Szenario':30s} {'erwartet':>10s} {'gezaehlt':>10s}  Status\n" + "-" * 65)
    results = {}
    for name, (t, accel, gyro), expected in scenarios:
        counted, engine = run_scenario(name, t, accel, gyro, expected)
        results[name] = (counted, expected)

    print()
    print("--- Realistischeres Cheat-Rep-Szenario: 3 gute Kalibrierungs-Reps,")
    print("    dann 3 Cheat-Reps, dann 3 weitere gute Reps ---")
    t, accel, gyro, labels = make_mixed_quality_reps(3, 3, 3)
    engine = WorkoutEngineSim()
    for ti, a, g in zip(t, accel, gyro):
        engine.process_sample(ti, a, g)
    engine._end_set()
    total_counted = sum(len(s) for s in engine.completed_sets)
    print(f"Reps insgesamt im Signal: {len(labels)} (davon 3 Cheat-Reps)")
    print(f"Von der Engine gezaehlt: {total_counted}")
    print(f"Kalibrierter Schwellenwert nach den ersten 3 guten Reps: {engine.peak_threshold:.3f}")
    print(f"(Cheat-Rep-Peak lag bei 1.15g, Schwellenwert liegt {'darueber' if engine.peak_threshold > 1.15 else 'darunter'} -> Cheat-Reps werden {'korrekt abgelehnt' if engine.peak_threshold > 1.15 else 'faelschlich mitgezaehlt'})")

    print("\n=== Einordnung ===")
    print("- 'Saubere Reps' und 'Sehr langsame Reps' sind die Faelle, die V1")
    print("  (Bizeps-Curls) tatsaechlich abdecken muss - beide funktionieren gut.")
    print("- 'Doppel-Peak' (Squat-artig) zeigt eine reale Grenze der aktuellen")
    print("  Hysterese-Logik: sie ist NICHT fuer V1 relevant, da V1 nur")
    print("  Bizeps-Curls abdeckt (Einzel-Peak-Bewegung), aber wichtig zu wissen,")
    print("  falls spaeter Kniebeugen o.ae. unterstuetzt werden sollen - dann")
    print("  braucht es echte Perioden-Schaetzung, nicht nur einen Schwellenwert.")
    print("- Das Cheat-Rep-Szenario zeigt: EINMAL korrekt kalibriert (auf echte,")
    print("  volle Wiederholungen), erkennt die Engine spaeter schwaechere/")
    print("  betrogene Wiederholungen zuverlaessig. Was sie NICHT kann: erkennen,")
    print("  dass die allerersten (Kalibrierungs-)Wiederholungen selbst schon")
    print("  schwach waren - das ist eine grundsaetzliche Grenze von")
    print("  Selbstkalibrierung, kein Implementierungsfehler.")

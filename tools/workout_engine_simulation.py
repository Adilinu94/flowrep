"""
Python-Portierung der Workout-Engine-Logik aus app/lib/domain/workout_engine.dart
und app/lib/domain/signal_processor.dart, um den Zähl-Algorithmus gegen
synthetische Szenarien zu prüfen, BEVOR ein echter Hardware-Test noetig ist.

=== SYNCHRONISATIONS-STAND: 2026-07-12 ===
Diese Version wurde nach docs/ANALYSE_EXTERNE_KI_2026-07-12.md Punkt F neu
aufgebaut. Vorher fehlte der komplette Guided-Calibration-Pfad
(WorkoutState.guidedCalibration) in dieser Datei, und die idle/paused/
falling-edge-Logik der normalen WorkoutEngineSim war noch auf dem alten,
nicht-baseline-relativen Stand (der reale HyperOS-Bug vom 2026-07-12, der
in workout_engine.dart bereits gefixt war, aber hier nie nachgezogen wurde).

Neu in dieser Version:
  1. SignalProcessor als eigene Klasse (statt inline dupliziert)
  2. WorkoutEngineSim: idle/paused-Trigger und Falling-Edge jetzt
     baseline-relativ (siehe processSample()/_detectPeak() in
     workout_engine.dart)
  3. GuidedCalibrationSim: komplette Portierung von
     startGuidedCalibration() / _finishGuidedCalibration() /
     _findGyroValidatedPeaks() / _findPeaksWithIndices() / _medianFilter()
  4. GEFIXTER FUND (siehe run_guided_calibration_suite() unten): Der
     Median-Filter (5 Samples) erzeugt bei sauberen, kontrollierten
     Wiederholungen ein Plateau exakt am Scheitelpunkt. Eine strikte
     Lokal-Maximum-Pruefung (`smoothed[i] > beide Nachbarn`) findet darin
     GAR KEINEN Peak, weil kein einzelner Index in einem Plateau strikt
     groesser als BEIDE Nachbarn ist. Bei der realen App-Datenrate (~14-20 Hz
     laut eigenen Screenshots) trat das in dieser Simulation in 30 von 30
     Durchlaeufen auf - die Kalibrierung wurde nie fertig. FIX ANGEWENDET
     2026-07-12 in workout_engine.dart _findPeaksWithIndices() (>= statt >
     auf einer Seite - Standardtechnik gegen Plateaus). GuidedCalibrationSim
     unten spiegelt jetzt den GEFIXTEN Code wider (Standardklasse = aktueller
     Dart-Stand). GuidedCalibrationSimStrictLegacy bewahrt das alte,
     fehlerhafte Verhalten nur noch zum Vergleich/zur Dokumentation auf.

Das ist kein Ersatz für echte Sensordaten. Empfehlung: echte CALIB-Logs
(AppLogger.i('CALIB peaks=...')) aus einem Kalibrierungslauf mitschneiden
und hier als zusaetzliches Szenario einspeisen, sobald verfuegbar.
"""

import numpy as np


# ============================================================
# SignalProcessor — Portierung von app/lib/domain/signal_processor.dart
# ============================================================

class SignalProcessor:
    """accel_mag + gyro_mag * gyro_weight, dann kausaler EMA-Tiefpass."""

    def __init__(self, gyro_weight=0.05, lowpass_alpha=0.6):
        self.gyro_weight = gyro_weight
        self.lowpass_alpha = lowpass_alpha
        self.last_filtered = None

    def process(self, accel_mag, gyro_mag):
        raw_combined = accel_mag + gyro_mag * self.gyro_weight
        if self.last_filtered is None:
            self.last_filtered = raw_combined
        else:
            self.last_filtered = (
                self.last_filtered * (1 - self.lowpass_alpha)
                + raw_combined * self.lowpass_alpha
            )
        return self.last_filtered

    def reset(self):
        self.last_filtered = None


# ============================================================
# WorkoutEngineSim — normaler Workout-Betrieb (idle/calibrating/active/paused)
# Synchronisiert mit workout_engine.dart, Stand 2026-07-12.
# ============================================================

class WorkoutEngineSim:
    def __init__(self, gyro_weight=0.05, envelope_decay=0.95,
                 falling_edge_ratio=0.7, calibration_reps=3,
                 pause_after_s=4.0, baseline_ema_alpha=0.01,
                 lowpass_alpha=0.6, initial_peak_threshold=1.2):
        self.signal_processor = SignalProcessor(gyro_weight=gyro_weight, lowpass_alpha=lowpass_alpha)
        self.envelope_decay = envelope_decay
        self.falling_edge_ratio = falling_edge_ratio
        self.calibration_reps = calibration_reps
        self.pause_after_s = pause_after_s
        self.baseline_ema_alpha = baseline_ema_alpha

        self.state = "idle"
        self.peak_threshold = initial_peak_threshold
        self.running_envelope = 0.0
        self.above_threshold = False
        self.current_excursion_peak = 0.0
        self.last_movement_t = None
        self.reps_in_set = []
        self.completed_sets = []
        self.baseline_level = None

    def process_sample(self, t, accel_mag, gyro_mag):
        combined = self.signal_processor.process(accel_mag, gyro_mag)
        self.running_envelope = max(combined, self.running_envelope * self.envelope_decay)

        if self.baseline_level is None:
            self.baseline_level = combined
        elif not self.above_threshold:
            self.baseline_level = (
                self.baseline_level * (1 - self.baseline_ema_alpha)
                + combined * self.baseline_ema_alpha
            )

        # Baseline-relativ (Fix vom 2026-07-12): reine Gravity (~1.0g) darf
        # idle/paused nicht sofort verlassen.
        activation = self.baseline_level + (self.peak_threshold - self.baseline_level) * 0.5

        if self.state == "idle":
            if combined > activation:
                self.state = "calibrating"
                self.last_movement_t = t
                self._detect_peak(t, combined)
        elif self.state == "calibrating":
            self._detect_peak(t, combined)
            if len(self.reps_in_set) >= self.calibration_reps:
                calibration_peaks = sorted(p for (_, p) in self.reps_in_set)
                mid = len(calibration_peaks) // 2
                if len(calibration_peaks) % 2 == 1:
                    median_peak = calibration_peaks[mid]
                else:
                    median_peak = (calibration_peaks[mid - 1] + calibration_peaks[mid]) / 2
                calibrated = self.baseline_level + (median_peak - self.baseline_level) * 0.5
                min_floor = self.baseline_level + 0.10
                self.peak_threshold = max(calibrated, min_floor)
                self.state = "active"
        elif self.state == "active":
            self._detect_peak(t, combined)
            if self.last_movement_t is not None and (t - self.last_movement_t) > self.pause_after_s:
                self._end_set()
        elif self.state == "paused":
            if combined > activation:
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
            # Baseline-relativ (Fix vom 2026-07-12): sonst kann das Signal
            # bei niedrigem kalibriertem Threshold nie unter die
            # Falling-Edge-Schwelle fallen (siehe DEBUGSESSION_2026-07-12.md).
            falling_threshold = self.baseline_level + (self.peak_threshold - self.baseline_level) * self.falling_edge_ratio
            if combined < falling_threshold:
                self.above_threshold = False
                self.reps_in_set.append((t, self.current_excursion_peak))

    def _end_set(self):
        if self.reps_in_set:
            self.completed_sets.append(list(self.reps_in_set))
        self.reps_in_set = []
        self.state = "paused" if self.completed_sets else "idle"


# ============================================================
# GuidedCalibrationSim — Portierung von WorkoutState.guidedCalibration
# (bisher komplett unportiert). 1:1 aus workout_engine.dart, Stand
# 2026-07-12, EINSCHLIESSLICH des unten dokumentierten Plateau-Verhaltens.
# ============================================================

class GuidedCalibrationSim:
    MIN_PEAK_HEIGHT = 1.2
    MIN_PEAK_DISTANCE_SAMPLES = 12
    CALIBRATION_PERCENTILE = 0.3
    CALIBRATION_TARGET_REPS = 10
    MIN_GYRO_PEAK_DEG_PER_S = 50.0

    def __init__(self, gyro_weight=0.05, lowpass_alpha=0.6):
        self.signal_processor = SignalProcessor(gyro_weight=gyro_weight, lowpass_alpha=lowpass_alpha)
        self.calibration_signals = []
        self.calibration_gyro_signals = []
        self.peak_threshold = None
        self.min_threshold_above_baseline = None
        self.baseline_level = 0.0
        self.finished = False
        self.calibration_peaks_found = 0

    def start(self, initial_baseline=1.0):
        self.calibration_signals = []
        self.calibration_gyro_signals = []
        self.baseline_level = initial_baseline
        self.finished = False

    def process_sample(self, accel_mag, gyro_mag):
        if self.finished:
            return False
        combined = self.signal_processor.process(accel_mag, gyro_mag)
        self.calibration_signals.append(combined)
        self.calibration_gyro_signals.append(gyro_mag)

        peaks = self._find_gyro_validated_peaks()
        if len(peaks) >= self.CALIBRATION_TARGET_REPS:
            self._finish(peaks)
            return True
        return False

    def _median_filter(self, signal, window=5):
        half = window // 2
        result = []
        n = len(signal)
        for i in range(n):
            start = max(0, min(i - half, n - 1))
            end = max(0, min(i + half + 1, n))
            w = sorted(signal[start:end])
            result.append(w[len(w) // 2])
        return result

    def _find_peaks_with_indices(self, signal):
        """1:1 Portierung von _findPeaksWithIndices() in workout_engine.dart,
        Stand NACH dem Plateau-Fix vom 2026-07-12. Tie-tolerant (>= links,
        > rechts) - siehe Moduldoc oben. Fuer das VORHER-Verhalten siehe
        GuidedCalibrationSimStrictLegacy weiter unten."""
        if len(signal) < 5:
            return []
        smoothed = self._median_filter(signal, 5)
        maxima = [i for i in range(1, len(smoothed) - 1)
                  if smoothed[i] >= smoothed[i - 1] and smoothed[i] > smoothed[i + 1]]

        peaks = []
        last_peak_index = None
        for idx in maxima:
            if smoothed[idx] < self.MIN_PEAK_HEIGHT:
                continue
            if last_peak_index is not None and (idx - last_peak_index) < self.MIN_PEAK_DISTANCE_SAMPLES:
                if smoothed[idx] > peaks[-1][1]:
                    peaks[-1] = [idx, smoothed[idx]]
                    last_peak_index = idx
                continue
            peaks.append([idx, smoothed[idx]])
            last_peak_index = idx
        return peaks

    def _find_gyro_validated_peaks(self):
        if len(self.calibration_signals) < 5 or len(self.calibration_gyro_signals) < 5:
            return []
        accel_peaks = self._find_peaks_with_indices(self.calibration_signals)
        validated = []
        for idx, mag in accel_peaks:
            if idx < len(self.calibration_gyro_signals) and \
                    self.calibration_gyro_signals[idx] >= self.MIN_GYRO_PEAK_DEG_PER_S:
                validated.append(mag)
        return validated

    def _finish(self, peaks):
        self.calibration_peaks_found = len(peaks)
        if len(peaks) >= 5:
            peaks_sorted = sorted(peaks)
            index = round(len(peaks_sorted) * self.CALIBRATION_PERCENTILE)
            index = min(max(index, 0), len(peaks_sorted) - 1)
            new_threshold = peaks_sorted[index]
        else:
            new_threshold = self.peak_threshold if self.peak_threshold is not None else 1.2
        self.peak_threshold = new_threshold
        excursion = self.peak_threshold - self.baseline_level
        self.min_threshold_above_baseline = min(max(excursion * 0.5, 0.10), 2.0)
        self.finished = True


class GuidedCalibrationSimStrictLegacy(GuidedCalibrationSim):
    """Verhalten VOR dem Plateau-Fix vom 2026-07-12 (strikte `>` auf beiden
    Seiten). Nur noch zu Vergleichs-/Dokumentationszwecken in
    run_guided_calibration_suite() erhalten - NICHT mehr der aktuelle
    Dart-Stand (siehe GuidedCalibrationSim oben, das ist jetzt aktuell)."""

    def _find_peaks_with_indices(self, signal):
        if len(signal) < 5:
            return []
        smoothed = self._median_filter(signal, 5)
        maxima = [i for i in range(1, len(smoothed) - 1)
                  if smoothed[i] > smoothed[i - 1] and smoothed[i] > smoothed[i + 1]]
        peaks = []
        last_peak_index = None
        for idx in maxima:
            if smoothed[idx] < self.MIN_PEAK_HEIGHT:
                continue
            if last_peak_index is not None and (idx - last_peak_index) < self.MIN_PEAK_DISTANCE_SAMPLES:
                if smoothed[idx] > peaks[-1][1]:
                    peaks[-1] = [idx, smoothed[idx]]
                    last_peak_index = idx
                continue
            peaks.append([idx, smoothed[idx]])
            last_peak_index = idx
        return peaks


# ============================================================
# Szenario-Generatoren: normaler Workout-Betrieb (bestehend, unveraendert
# relevant fuer WorkoutEngineSim)
# ============================================================

def make_clean_reps(n, tempo_s=1.2, baseline=1.0, peak=1.8, hz=50, noise=0.02, seed=0):
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
        for _ in range(int(0.3 * hz)):
            t.append(time); accel.append(baseline + rng.normal(0, noise)); gyro.append(rng.normal(0, 2))
            time += dt
    return np.array(t), np.array(accel), np.array(gyro)


def make_double_peak_reps(n, tempo_s=1.6, baseline=1.0, peak=1.9, hz=50, noise=0.02, seed=1):
    rng = np.random.default_rng(seed)
    dt = 1.0 / hz
    t, accel, gyro = [], [], []
    time = 0.0
    for _ in range(n):
        steps = int(tempo_s * hz)
        for i in range(steps):
            phase = 2 * np.pi * i / steps
            t.append(time)
            accel.append(baseline + (peak - baseline) * abs(np.sin(phase)) + rng.normal(0, noise))
            gyro.append(30 * abs(np.sin(phase)) + rng.normal(0, 2))
            time += dt
        for _ in range(int(0.3 * hz)):
            t.append(time); accel.append(baseline + rng.normal(0, noise)); gyro.append(rng.normal(0, 2))
            time += dt
    return np.array(t), np.array(accel), np.array(gyro)


def make_slow_reps(n, tempo_s=3.5, baseline=1.0, peak=1.4, hz=50, noise=0.02, seed=2):
    return make_clean_reps(n, tempo_s=tempo_s, baseline=baseline, peak=peak, hz=hz, noise=noise, seed=seed)


def make_mixed_quality_reps(n_good_first, n_cheat, n_good_after, tempo_s=1.2,
                             baseline=1.0, good_peak=1.8, cheat_peak=1.15,
                             hz=50, noise=0.02, seed=4):
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


def make_noisy_calibration_reps(n_calib=3, n_after=7, tempo_s=1.2,
                                  baseline=1.0, peak=1.8, hz=50,
                                  calib_noise=0.15, normal_noise=0.02, seed=10):
    rng = np.random.default_rng(seed)
    dt = 1.0 / hz
    t, accel, gyro = [], [], []
    time = 0.0

    def add_rep(noise_level):
        nonlocal time
        steps = int(tempo_s * hz)
        for i in range(steps):
            phase = np.pi * i / steps
            t.append(time)
            accel.append(baseline + (peak - baseline) * np.sin(phase) + rng.normal(0, noise_level))
            gyro.append(30 * np.sin(phase) + rng.normal(0, noise_level * 50))
            time += dt
        for _ in range(int(0.3 * hz)):
            t.append(time); accel.append(baseline + rng.normal(0, noise_level)); gyro.append(rng.normal(0, noise_level * 50))
            time += dt

    for _ in range(n_calib):
        add_rep(calib_noise)
    for _ in range(n_after):
        add_rep(normal_noise)
    return np.array(t), np.array(accel), np.array(gyro)


def make_false_start_then_reps(n_after=8, tempo_s=1.2, baseline=1.0, peak=1.8,
                                 hz=50, noise=0.02, seed=13):
    rng = np.random.default_rng(seed)
    dt = 1.0 / hz
    t, accel, gyro = [], [], []
    time = 0.0
    false_start_peak = 0.85
    steps = int(0.4 * hz)
    for i in range(steps):
        phase = np.pi * i / steps
        t.append(time)
        accel.append(baseline + (false_start_peak - baseline) * np.sin(phase) + rng.normal(0, noise))
        gyro.append(10 * np.sin(phase) + rng.normal(0, 2))
        time += dt
    for _ in range(int(0.5 * hz)):
        t.append(time); accel.append(baseline + rng.normal(0, noise)); gyro.append(rng.normal(0, 2))
        time += dt

    def add_rep():
        nonlocal time
        steps = int(tempo_s * hz)
        for i in range(steps):
            phase = np.pi * i / steps
            t.append(time)
            accel.append(baseline + (peak - baseline) * np.sin(phase) + rng.normal(0, noise))
            gyro.append(30 * np.sin(phase) + rng.normal(0, 2))
            time += dt
        for _ in range(int(0.3 * hz)):
            t.append(time); accel.append(baseline + rng.normal(0, noise)); gyro.append(rng.normal(0, 2))
            time += dt

    for _ in range(n_after):
        add_rep()
    return np.array(t), np.array(accel), np.array(gyro)


def run_scenario(name, t, accel, gyro, expected_reps, **engine_kwargs):
    engine = WorkoutEngineSim(**engine_kwargs)
    for ti, a, g in zip(t, accel, gyro):
        engine.process_sample(ti, a, g)
    engine._end_set()
    counted = sum(len(s) for s in engine.completed_sets)
    status = "OK" if counted == expected_reps else "ABWEICHUNG"
    print(f"{name:45s} erwartet={expected_reps:3d}  gezaehlt={counted:3d}  [{status}]")
    return counted, engine


# ============================================================
# Szenario-Generatoren: Guided Calibration (NEU)
# ============================================================

def make_guided_calibration_curls(n, hz=50, tempo_s=1.2, rest_s=0.3,
                                   accel_peak=1.9, gyro_peak_deg_s=120,
                                   noise=0.03, seed=0):
    """n synchronisierte Accel+Gyro-Ausschlaege (gleiche Phase - wie eine
    echte Curl-Rotation ums Ellbogengelenk), getrennt durch Ruhephasen."""
    rng = np.random.default_rng(seed)
    accel, gyro = [], []
    for _ in range(n):
        steps = int(tempo_s * hz)
        for i in range(steps):
            phase = np.pi * i / steps
            a = 1.0 + (accel_peak - 1.0) * np.sin(phase) + rng.normal(0, noise)
            g = gyro_peak_deg_s * np.sin(phase) + rng.normal(0, noise * 30)
            accel.append(a); gyro.append(g)
        for _ in range(int(rest_s * hz)):
            accel.append(1.0 + rng.normal(0, noise))
            gyro.append(rng.normal(0, noise * 30))
    return accel, gyro


def run_guided_calibration_case(name, accel, gyro, sim_cls=GuidedCalibrationSim,
                                  initial_baseline=1.0):
    sim = sim_cls()
    sim.start(initial_baseline=initial_baseline)
    for a, g in zip(accel, gyro):
        if sim.process_sample(a, g):
            break
    status = "OK" if sim.finished else "NICHT ABGESCHLOSSEN"
    print(f"{name:55s} fertig={str(sim.finished):5s} peaks={sim.calibration_peaks_found:3d}  [{status}]")
    return sim


def run_guided_calibration_suite():
    print("\n" + "=" * 78)
    print("=== Guided-Calibration-Suite (WorkoutState.guidedCalibration) ===")
    print("=" * 78 + "\n")

    print("--- 1. Demo-Tempo (50 Hz, wie in den obigen Szenarien) ---")
    accel, gyro = make_guided_calibration_curls(10, hz=50, seed=20)
    run_guided_calibration_case("10 saubere Curls @ 50 Hz", accel, gyro)

    print("\n--- 2. REALE App-Datenrate (~15 Hz laut eigenen Screenshots) ---")
    accel, gyro = make_guided_calibration_curls(10, hz=15, seed=21)
    run_guided_calibration_case("10 saubere Curls @ 15 Hz (aktueller/gefixter Algorithmus)", accel, gyro)
    run_guided_calibration_case("10 saubere Curls @ 15 Hz (Legacy-Verhalten vor dem Fix)",
                                 accel, gyro, sim_cls=GuidedCalibrationSimStrictLegacy)

    print("\n--- 3. Gyro-Plausibilisierung: reine Accel-Bewegung ohne Rotation ---")
    accel, gyro = make_guided_calibration_curls(10, hz=15, gyro_peak_deg_s=0, seed=22)
    run_guided_calibration_case("10x Arm heben ohne Rotation, Accel allein wuerde reichen",
                                 accel, gyro)
    accel, gyro = make_guided_calibration_curls(10, hz=15, gyro_peak_deg_s=120, seed=22)
    run_guided_calibration_case("Kontrolle: gleiche Accel-Kurve MIT Rotation (sollte zaehlen)",
                                 accel, gyro)

    print("\n--- 4. Statistische Absicherung: 30 Wiederholungen bei 15 Hz ---")
    ok_current, ok_legacy = 0, 0
    for seed in range(30):
        accel, gyro = make_guided_calibration_curls(10, hz=15, seed=100 + seed)
        s1 = GuidedCalibrationSim(); s1.start(1.0)
        for a, g in zip(accel, gyro):
            if s1.process_sample(a, g):
                break
        if s1.finished:
            ok_current += 1
        s2 = GuidedCalibrationSimStrictLegacy(); s2.start(1.0)
        for a, g in zip(accel, gyro):
            if s2.process_sample(a, g):
                break
        if s2.finished:
            ok_legacy += 1
    print(f"Aktueller (gefixter) Algorithmus:  {ok_current}/30 Kalibrierungen erfolgreich abgeschlossen")
    print(f"Legacy-Verhalten vor dem Fix:       {ok_legacy}/30 Kalibrierungen erfolgreich abgeschlossen")

    print("\n=== Einordnung ===")
    print("- Der 5-Sample-Median-Filter erzeugt bei sauberen, kontrollierten")
    print("  Wiederholungen ein Plateau exakt am Scheitelpunkt. Eine strikte")
    print("  Lokal-Maximum-Pruefung (`> beide Nachbarn`, Legacy-Verhalten oben)")
    print("  konnte darin strukturell KEINEN Punkt finden, auch wenn der Peak")
    print("  klar und eindeutig war - bei der realen App-Datenrate (~14-20 Hz)")
    print("  0 von 30 erfolgreiche Kalibrierungen.")
    print("- FIX ANGEWENDET (2026-07-12): _findPeaksWithIndices() in")
    print("  workout_engine.dart ist jetzt tie-tolerant (>= auf einer Seite -")
    print("  Standardtechnik gegen Plateaus). GuidedCalibrationSim oben spiegelt")
    print("  diesen gefixten Stand wider: 30/30 in dieser Simulation.")
    print("- Weiterhin offen: mit echten CALIB-Logs von einem Kalibrierungslauf")
    print("  auf dem echten Geraet gegenpruefen (siehe Moduldoc oben).")


if __name__ == "__main__":
    print("=== FlowRep Workout-Engine-Simulation ===\n")

    scenarios = [
        ("Saubere Reps (Demo-Tempo)", make_clean_reps(10), 10),
        ("Doppel-Peak-Uebung (Squat-artig)", make_double_peak_reps(10), 10),
        ("Sehr langsame Reps (Powerlifter)", make_slow_reps(8), 8),
    ]
    print(f"{'Szenario':45s} {'erwartet':>10s} {'gezaehlt':>10s}  Status\n" + "-" * 78)
    for name, (t, accel, gyro), expected in scenarios:
        run_scenario(name, t, accel, gyro, expected)

    print("\n--- Cheat-Rep-Szenario: 3 gute Kalibrierungs-Reps, 3 Cheat-Reps, 3 gute Reps ---")
    t, accel, gyro, labels = make_mixed_quality_reps(3, 3, 3)
    engine = WorkoutEngineSim()
    for ti, a, g in zip(t, accel, gyro):
        engine.process_sample(ti, a, g)
    engine._end_set()
    total_counted = sum(len(s) for s in engine.completed_sets)
    print(f"Reps insgesamt im Signal: {len(labels)} (davon 3 Cheat-Reps), gezaehlt: {total_counted}, "
          f"Schwellenwert: {engine.peak_threshold:.3f}")

    print("\n--- Robustheits-Suite (unsaubere/unregelmaessige normale Reps) ---")
    print("(Toleranzband, nicht exakt - siehe make_noisy_calibration_reps-Docstring)")

    def _run_tolerant(name, t, accel, gyro, expected, tolerance):
        engine = WorkoutEngineSim()
        for ti, a, g in zip(t, accel, gyro):
            engine.process_sample(ti, a, g)
        engine._end_set()
        counted = sum(len(s) for s in engine.completed_sets)
        ok = abs(counted - expected) <= tolerance
        print(f"{name:45s} erwartet={expected:3d}  gezaehlt={counted:3d}  [{'OK' if ok else 'ABWEICHUNG'}]")
        return counted, engine

    t, accel, gyro = make_noisy_calibration_reps()
    _run_tolerant("Zittrige Kalibrierung (starkes Rauschen erste 3 Reps)", t, accel, gyro, 10, tolerance=2)
    t, accel, gyro = make_false_start_then_reps(n_after=8)
    _run_tolerant("Kurze Fehlbewegung vor echten Reps", t, accel, gyro, 8, tolerance=1)

    run_guided_calibration_suite()

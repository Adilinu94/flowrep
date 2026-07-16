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
                 lowpass_alpha=0.6, initial_peak_threshold=1.2,
                 has_valid_calibration=False):
        self.signal_processor = SignalProcessor(gyro_weight=gyro_weight, lowpass_alpha=lowpass_alpha)
        self.envelope_decay = envelope_decay
        self.falling_edge_ratio = falling_edge_ratio
        self.calibration_reps = calibration_reps
        self.pause_after_s = pause_after_s
        self.baseline_ema_alpha = baseline_ema_alpha
        # ADR-020 (docs/Umbauplan Flowrep/02_ARCHITECTURE_DECISION_RECORDS.md):
        # True once a valid calibration (guided, or loaded from persistence)
        # is in place. Mirrors WorkoutEngine.hasValidCalibration in
        # workout_engine.dart. NOTE: calibration_reps default here (3) is
        # currently OUT OF SYNC with the real Dart default (1, changed
        # 2026-07-12) - deliberately left as-is for this class default so
        # the existing scenarios below (which assume 3) do not silently
        # change meaning; pass calibration_reps=1 explicitly where fidelity
        # to the current real default matters, e.g. in the ADR-020 test.
        self.has_valid_calibration = has_valid_calibration

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
                if self.has_valid_calibration:
                    # ADR-020 fix: already calibrated - straight to active,
                    # same as the paused state below. Without this branch,
                    # the one-rep auto-calibration path a few lines down
                    # fires unconditionally and overwrites the threshold
                    # after just one rep.
                    self.state = "active"
                    self.reps_in_set = []
                else:
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
# UnifiedEngineSim (NEU, 2026-07-14) - EIN State Machine fuer
# guidedCalibration UND normalen Betrieb zusammen, 1:1 wie die echte
# WorkoutEngine-Klasse in workout_engine.dart (dort ist es eine einzige
# Klasse - hier bisher zwei getrennte: GuidedCalibrationSim und
# WorkoutEngineSim). Diese strukturelle Trennung war eine echte Luecke:
# sie macht es unmoeglich zu simulieren, was mit den REST-Samples des
# letzten Kalibrierungs-Reps passiert, nachdem die Kalibrierung mittendrin
# abschliesst - genau das Verhalten, das den Settle-Gate-Bug verursacht hat
# (gefunden nur durch echtes `flutter test`, siehe STATUS_FORTSCHRITT.md
# Aenderungsprotokoll, NICHT durch diese oder eine vorherige Simulation).
# Ersetzt NICHT GuidedCalibrationSim/WorkoutEngineSim (die bleiben fuer
# alle bestehenden Szenarien oben unveraendert), sondern ergaenzt sie
# gezielt fuer Szenarien, die die Zustandsgrenze selbst betreffen.
# ============================================================

class UnifiedEngineSim:
    MIN_PEAK_HEIGHT = 1.2
    MIN_PEAK_DISTANCE_SAMPLES = 12
    CALIBRATION_PERCENTILE = 0.3
    CALIBRATION_TARGET_REPS = 10
    MIN_GYRO_PEAK_DEG_PER_S = 50.0

    def __init__(self, calibration_reps=1, gyro_weight=0.05, lowpass_alpha=0.6,
                 falling_edge_ratio=0.7, baseline_ema_alpha=0.01,
                 min_threshold_above_baseline=0.10):
        self.sp = SignalProcessor(gyro_weight, lowpass_alpha)
        self.calibration_reps = calibration_reps
        self.falling_edge_ratio = falling_edge_ratio
        self.baseline_ema_alpha = baseline_ema_alpha
        self.min_threshold_above_baseline = min_threshold_above_baseline

        self.state = "idle"
        self.has_valid_calibration = False
        self.awaiting_settle_after_calibration = False  # mirrors _awaitingSettleAfterCalibration
        self.peak_threshold = 1.2
        self.baseline_level = None
        self.above_threshold = False
        self.current_excursion_peak = 0.0
        self.reps_in_set = []
        self.calibration_signals = []
        self.calibration_gyro_signals = []

    def start_guided_calibration(self):
        self.calibration_signals, self.calibration_gyro_signals = [], []
        self.baseline_level = self.sp.last_filtered
        self.peak_threshold = 1.2
        self.above_threshold = False
        self.current_excursion_peak = 0.0
        self.reps_in_set = []
        self.state = "guidedCalibration"

    def process_sample(self, accel_mag, gyro_mag):
        combined = self.sp.process(accel_mag, gyro_mag)
        if self.baseline_level is None:
            self.baseline_level = combined
        elif not self.above_threshold:
            self.baseline_level = self.baseline_level * (1 - self.baseline_ema_alpha) + combined * self.baseline_ema_alpha

        if self.state == "idle":
            if self.awaiting_settle_after_calibration:
                settle_line = self.baseline_level + self.min_threshold_above_baseline
                if combined <= settle_line:
                    self.awaiting_settle_after_calibration = False
                return
            activation = self.baseline_level + (self.peak_threshold - self.baseline_level) * 0.5
            if combined > activation:
                if self.has_valid_calibration:
                    self.state = "active"
                    self.reps_in_set = []
                else:
                    self.state = "calibrating"
                self._detect_peak(combined)
        elif self.state == "calibrating":
            self._detect_peak(combined)
            if len(self.reps_in_set) >= self.calibration_reps:
                peaks = sorted(self.reps_in_set)
                mid = len(peaks) // 2
                median_peak = peaks[mid] if len(peaks) % 2 == 1 else (peaks[mid-1] + peaks[mid]) / 2
                calibrated = self.baseline_level + (median_peak - self.baseline_level) * 0.5
                self.peak_threshold = max(calibrated, self.baseline_level + 0.10)
                self.state = "active"
        elif self.state == "active":
            self._detect_peak(combined)
        elif self.state == "guidedCalibration":
            self.calibration_signals.append(combined)
            self.calibration_gyro_signals.append(gyro_mag)
            peaks = self._find_gyro_validated_peaks()
            if len(peaks) >= self.CALIBRATION_TARGET_REPS:
                self._finish_guided_calibration(peaks)

    def _detect_peak(self, combined):
        if not self.above_threshold and combined > self.peak_threshold:
            self.above_threshold = True
            self.current_excursion_peak = combined
        elif self.above_threshold:
            self.current_excursion_peak = max(self.current_excursion_peak, combined)
            falling_threshold = self.baseline_level + (self.peak_threshold - self.baseline_level) * self.falling_edge_ratio
            if combined < falling_threshold:
                self.above_threshold = False
                self.reps_in_set.append(self.current_excursion_peak)

    def _median_filter(self, signal, window=5):
        half = window // 2
        n = len(signal)
        out = []
        for i in range(n):
            start = max(0, min(i - half, n - 1))
            end = max(0, min(i + half + 1, n))
            w = sorted(signal[start:end])
            out.append(w[len(w) // 2])
        return out

    def _find_peaks_with_indices(self, signal):
        if len(signal) < 5:
            return []
        smoothed = self._median_filter(signal, 5)
        maxima = [i for i in range(1, len(smoothed)-1) if smoothed[i] >= smoothed[i-1] and smoothed[i] > smoothed[i+1]]
        peaks, last = [], None
        for idx in maxima:
            if smoothed[idx] < self.MIN_PEAK_HEIGHT:
                continue
            if last is not None and (idx - last) < self.MIN_PEAK_DISTANCE_SAMPLES:
                if smoothed[idx] > peaks[-1][1]:
                    peaks[-1] = [idx, smoothed[idx]]
                    last = idx
                continue
            peaks.append([idx, smoothed[idx]])
            last = idx
        return peaks

    def _find_gyro_validated_peaks(self):
        if len(self.calibration_signals) < 5:
            return []
        accel_peaks = self._find_peaks_with_indices(self.calibration_signals)
        return [mag for idx, mag in accel_peaks
                if idx < len(self.calibration_gyro_signals) and self.calibration_gyro_signals[idx] >= self.MIN_GYRO_PEAK_DEG_PER_S]

    def _finish_guided_calibration(self, peaks):
        if len(peaks) >= 5:
            ps = sorted(peaks)
            idx = min(max(round(len(ps) * self.CALIBRATION_PERCENTILE), 0), len(ps) - 1)
            self.peak_threshold = ps[idx]
        self.calibration_signals, self.calibration_gyro_signals = [], []
        excursion = self.peak_threshold - self.baseline_level
        self.min_threshold_above_baseline = min(max(excursion * 0.5, 0.10), 2.0)
        self.state = "idle"
        self.has_valid_calibration = True
        self.awaiting_settle_after_calibration = True


def feed_continuous_calibration_pattern(engine, n_reps=10, hz=15, steps=18, rest=5,
                                          accel_amplitude=0.9, gyro_peak=120):
    """Exakt das Muster aus workout_engine_test.dart (accelMag=1.0+0.9*sin,
    gyroMag=120*sin, 18 Schritte + 5 Ruhe-Samples/Rep) als EIN durchgehender
    Sample-Strom - kein Abbruch bei Kalibrierungsende, im Unterschied zu
    run_guided_calibration_case() oben."""
    for _ in range(n_reps):
        for i in range(steps):
            phase = (i / steps) * np.pi
            engine.process_sample(1.0 + accel_amplitude * np.sin(phase), gyro_peak * np.sin(phase))
        for _ in range(rest):
            engine.process_sample(1.0, 0.0)


def run_calibration_settle_regression_suite():
    """Regressionstest fuer den Settle-Gate-Fix (gefunden 2026-07-14 durch
    echtes `flutter test`, siehe STATUS_FORTSCHRITT.md): Guided Calibration
    kann abschliessen, WAEHREND der letzte Rep noch mitten im Abklingen ist
    (der Peak-Detector braucht nur 1 Sample nach dem Maximum, nicht die volle
    Rueckkehr zur Ruhe). Ohne Gate reisst das noch erhoehte Signal den
    Zustand sofort wieder aus idle heraus - mit ADR-020-Fix nach `active`,
    ohne nach `calibrating`. Beides ist falsch; erwartet ist `idle`.

    Testet zwei Dinge am selben durchgehenden Sample-Strom (kein Neustart
    zwischen Kalibrierung und Normalbetrieb, siehe UnifiedEngineSim oben):
    1. Direkt nach den 10 Kalibrierungs-Reps: state MUSS idle sein.
    2. Danach EIN weiterer normaler Rep: threshold darf sich nicht aendern
       (ADR-020, jetzt im selben durchgehenden Lauf statt in zwei Objekten).
    """
    print("\n" + "=" * 78)
    print("=== Settle-Gate-Regressionstest (nach Kalibrierungsende, vor idle) ===")
    print("=" * 78 + "\n")

    engine = UnifiedEngineSim(calibration_reps=1)
    engine.start_guided_calibration()
    feed_continuous_calibration_pattern(engine, n_reps=10)

    state_ok = engine.state == "idle"
    print(f"Zustand direkt nach Kalibrierungsende: {engine.state}  (erwartet: idle)  "
          f"[{'OK' if state_ok else 'FEHLER'}]")

    threshold_before = engine.peak_threshold
    feed_continuous_calibration_pattern(engine, n_reps=1)
    threshold_ok = engine.peak_threshold == threshold_before
    active_ok = engine.state == "active"
    print(f"Nach 1 weiterem Rep: threshold vorher={threshold_before:.3f} "
          f"nachher={engine.peak_threshold:.3f} state={engine.state}  "
          f"[{'OK' if threshold_ok and active_ok else 'FEHLER'}]")

    return state_ok and threshold_ok and active_ok


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


def run_adr020_regression_suite():
    """Regressionstest fuer ADR-020 (docs/Umbauplan Flowrep/
    02_ARCHITECTURE_DECISION_RECORDS.md): Der aus einer abgeschlossenen
    Guided Calibration ermittelte Schwellenwert darf durch die anschliessende
    erste normale Bewegung NICHT durch die alte Ein-Rep-Auto-Rekalibrierung
    (calibration_reps, im echten Code aktuell = 1) ueberschrieben werden.

    Ablauf: 1) echte Guided Calibration mit 10 Curls durchlaufen lassen,
    genau wie im Live-Betrieb. 2) den daraus resultierenden Schwellenwert in
    eine neue WorkoutEngineSim einspeisen (mirrors home_screen.dart
    _loadCalibration(), das nach einer Kalibrierung eine neue Engine-Instanz
    mit initial_peak_threshold baut). 3) einen einzelnen weiteren, normalen
    Rep simulieren. 4) pruefen, ob peak_threshold sich veraendert hat.

    Wird zweimal ausgefuehrt: einmal mit has_valid_calibration=False (muss
    den Bug reproduzieren - Beweis, dass der Test ueberhaupt etwas erkennt),
    einmal mit has_valid_calibration=True (muss stabil bleiben - der Fix,
    der jetzt auch in workout_engine.dart und home_screen.dart steht).
    """
    print("\n" + "=" * 78)
    print("=== ADR-020-Regressionstest: Threshold-Persistenz nach Kalibrierung ===")
    print("=" * 78 + "\n")

    calib_accel, calib_gyro = make_guided_calibration_curls(10, hz=15, seed=42)
    calib_sim = GuidedCalibrationSim()
    calib_sim.start(initial_baseline=1.0)
    for a, g in zip(calib_accel, calib_gyro):
        if calib_sim.process_sample(a, g):
            break
    assert calib_sim.finished, "Guided Calibration selbst haette abschliessen muessen - Testaufbau pruefen."
    threshold_after_calibration = calib_sim.peak_threshold
    print(f"Guided Calibration abgeschlossen, Schwellenwert = {threshold_after_calibration:.3f}\n")

    one_rep_accel, one_rep_gyro = make_guided_calibration_curls(1, hz=15, seed=43)

    results = {}
    for has_fix, label in [(False, "OHNE Fix (has_valid_calibration=False)"),
                            (True, "MIT Fix (has_valid_calibration=True)")]:
        engine = WorkoutEngineSim(
            calibration_reps=1,  # echter aktueller Dart-Default, siehe Moduldoc-Hinweis oben
            initial_peak_threshold=threshold_after_calibration,
            has_valid_calibration=has_fix,
        )
        t = 0.0
        for a, g in zip(one_rep_accel, one_rep_gyro):
            engine.process_sample(t, a, g)
            t += 1 / 15
        changed = abs(engine.peak_threshold - threshold_after_calibration) > 1e-9
        results[has_fix] = changed
        status = "BUG: Threshold veraendert" if changed else "OK: Threshold blieb erhalten"
        print(f"{label:42s} threshold={engine.peak_threshold:7.3f} state={engine.state:10s}  [{status}]")

    print()
    if results[False] and not results[True]:
        print("=> Test unterscheidet korrekt zwischen Bug (ohne Fix) und Fix (mit Fix).")
        print("=> workout_engine.dart und home_screen.dart wurden mit genau diesem Fix aktualisiert.")
    else:
        print("=> UNERWARTET: Test unterscheidet NICHT wie erwartet zwischen Bug und Fix - pruefen!")
    # bool(...) statt "is True"/"is False": rng.normal() liefert numpy.float64,
    # dadurch ist `changed` ein numpy.bool_, das mit "is True"/"is False" NIE
    # uebereinstimmt (Identitaets- statt Wertvergleich) - beim ersten echten
    # Lauf dieser Datei gefunden (raise SystemExit trotz korrektem Verhalten).
    return bool(results[False]) and not bool(results[True])


# ============================================================
# Known-Count-Kalibrierung mit Nutzer-Personas (NEU, 2026-07-16)
# Paket 1 (V1, "Simulations-First") aus
# docs/KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md, §3 (Stufen 0/A/B/C/D)
# und §6 Paket 1 (Abnahmekriterien).
#
# Idee: Die Kalibrierung bekommt die Wahrheit als BEKANNTE ANZAHL (N=1, N=5,
# N=3 langsam) und optimiert ihre Zaehl-Parameter so, dass sie diese Wahrheit
# reproduziert - statt an der eigenen Detektion zu raten (Root Causes K1-K4
# des Konzepts). Ablauf exakt wie im Konzept:
#   Stufe 0  Ruhe            -> Baseline, Rausch-Sigma, Gyro-Bias (+ Gate)
#   Stufe A  1 Rep bekannt   -> Rotationsachse via PCA (numpy.linalg.eigh auf
#                               die 3x3-Gyro-Kovarianz), vorzeichenbehaftetes
#                               g_p, Rep-Dauer T0
#   Stufe B  5 Reps bekannt  -> Known-Count-Sweep: Kandidaten-Signale
#                               {g_p, combined, |gyro|} x Threshold-Grid (20)
#                               x Refractory [0,35-0,75]*T0 x Prominenz
#                               {aus, 0,2*Median}; hart count==5; Tie-Break
#                               minimaler CV der Intervalle, dann maximale
#                               Margin ueber dem Rauschboden; finale Schwelle
#                               = median - k*MAD der validierten Peak-Hoehen
#   Stufe C  3 langsame Reps -> gewaehlte Parameter muessen auch 3/3 zaehlen,
#                               sonst theta schrittweise senken, bis BEIDE
#                               Stufen korrekt zaehlen (tempo-robust
#                               konservativ, direkter Fix fuer K4/S2)
#   Stufe D  Review-Simulation -> injizierte Fehlkonfiguration (zaehlt 7
#                               statt 5) muss erkannt werden; Re-Optimierung
#                               mit korrigierter Anzahl muss wieder 5/5 finden
#
# Die Personas sind physikalisch plausible 6-Achsen-Generatoren (Gravitations-
# Offset ~1 g in der Accel-Magnitude, Gyro-Peaks bis ~300 Grad/s bei schnellen
# Reps, deutlich niedriger bei langsamen, realistisches Rauschen, 50 Hz).
# Dieser Abschnitt ist neu und klar abgegrenzt; die bestehenden Szenarien
# oben laufen unveraendert mit (siehe Abschluss-Report).
# ============================================================

# Pro Persona: Tempo/Amplitude der Reps, Form des Gyro-Profils, Rotationsachse
# (Einheitsvektor folgt im Generator), Rausch-Staerken. "form":
#   "single" = eine vorzeichenbehaftete Halbwelle pro Rep (hoch UND runter im
#              selben Dominanzvorzeichen, wie ein kontrollierter Curl-Hub)
#   "double" = konzentrisch + exzentrisch als pos./neg. Halbwelle -> ZWEI
#              Buckel in |gyro| und accel_mag pro Rep (Doppel-Hub-Nutzer)
PERSONA_PROFILES = {
    # Referenz: saubere, gleichmaessige Reps, Gyro-Peak 250 Grad/s.
    "clean": dict(tempo_s=1.2, tempo_std=0.08, gyro_peak=250.0, gyro_std=15.0,
                  accel_bump=0.8, accel_std=0.05, form="single",
                  achse=(1.0, 0.20, 0.10), noise_accel=0.02, noise_gyro=3.0),
    # Doppel-Hub: jede Rep erzeugt ZWEI Magnitude-Buckel (konzentrisch +
    # exzentrisch). Nur das vorzeichenbehaftete g_p trennt sie sauber.
    "double_bump": dict(tempo_s=1.6, tempo_std=0.10, gyro_peak=200.0, gyro_std=12.0,
                        accel_bump=0.7, accel_std=0.05, form="double",
                        achse=(1.0, 0.15, 0.20), noise_accel=0.02, noise_gyro=3.0),
    # Schwacher Nutzer: niedrige Amplituden nahe dem Rauschboden.
    "weak": dict(tempo_s=1.4, tempo_std=0.12, gyro_peak=85.0, gyro_std=6.0,
                 accel_bump=0.15, accel_std=0.02, form="single",
                 achse=(1.0, 0.25, 0.10), noise_accel=0.025, noise_gyro=3.0),
    # Langsamer Nutzer: ~5 s/Rep -> Gyro-Peak nur ~45 Grad/s (unter dem alten
    # harten 50-Grad/s-Gyro-Gate der App - genau der K4/S2-Fall des Konzepts).
    "slow": dict(tempo_s=5.0, tempo_std=0.30, gyro_peak=45.0, gyro_std=4.0,
                 accel_bump=0.35, accel_std=0.03, form="single",
                 achse=(1.0, 0.10, 0.15), noise_accel=0.02, noise_gyro=3.0),
    # Inkonsistent: schwankende Amplitude/Dauer, in den Validierungssaetzen
    # gelegentlich eine schlampige Halb-Rep (siehe halb_rep_p unten).
    "inconsistent": dict(tempo_s=1.7, tempo_std=0.45, gyro_peak=180.0, gyro_std=35.0,
                         accel_bump=0.55, accel_std=0.20, form="single",
                         achse=(1.0, 0.30, 0.20), noise_accel=0.02, noise_gyro=3.0),
}

GYRO_BIAS_VEKTOR = np.array([1.5, -1.0, 0.8])  # Grad/s, realistischer Offset


def make_persona_6achsen(persona, n_reps, hz=50, seed=0, tempo="normal",
                         ruhe_vor_s=1.0, ruhe_nach_s=1.0, halb_rep_p=0.0):
    """6-Achsen-IMU-Signal einer Persona: (t, acc[n,3], gyro[n,3], n_halb).

    Jede Rep = Rotation um eine (pro Persona leicht variierte) feste Achse mit
    Winkel-Exkursion, danach Rueckkehr in Ruhe. Accel: 1 g Schwerkraft in z
    plus linearer Bump (Betrag des Gyro-Profils) -> Magnitude ~1 g in Ruhe,
    wie am echten Geraet. Gyro: Achse * Profil + Bias + Rauschen.
    tempo="langsam": gleiche Exkursion bei 4-6 s/Rep -> Gyro- UND Accel-Peaks
    sinken physikalisch korrekt mit dem Tempo-Verhaeltnis.
    halb_rep_p: Wahrscheinlichkeit, dass eine Rep als schlampige Halb-Rep
    (kleinere Amplitude, kuerzer) ausgefaellt wird; sie ERSETZT die volle Rep
    (Erwartungswert = n_reps - n_halb). In den Kalibrierungs-Stufen 0 (der
    Nutzer folgt der Anweisung), in der Validierung realistisch > 0.
    """
    profil = PERSONA_PROFILES[persona]
    rng = np.random.default_rng(seed)
    dt = 1.0 / hz
    achse = np.array(profil["achse"], dtype=float)
    achse /= np.linalg.norm(achse)
    sigma_a = profil["noise_accel"]
    sigma_g = profil["noise_gyro"]
    acc_rows, gyro_rows = [], []

    def ruhe(dauer_s):
        for _ in range(max(1, int(dauer_s * hz))):
            acc_rows.append([rng.normal(0, sigma_a), rng.normal(0, sigma_a),
                             1.0 + rng.normal(0, sigma_a)])
            gyro_rows.append(GYRO_BIAS_VEKTOR + rng.normal(0, sigma_g, 3))

    def rep(tempo_s, gyro_peak, accel_bump, form):
        steps = max(4, int(tempo_s * hz))
        # Achse pro Rep leicht streuen (Hand liegt nie exakt gleich)
        a_rep = achse + rng.normal(0, 0.03, 3)
        a_rep /= np.linalg.norm(a_rep)
        for i in range(steps):
            phase = i / steps
            if form == "single":
                s = np.sin(np.pi * phase)       # ein vorzeichenbehafteter Buckel
            else:                                # "double": pos. + neg. Halbwelle
                s = np.sin(2 * np.pi * phase)   # -> zwei Buckel in |gyro|
            gyro_rows.append(a_rep * (gyro_peak * s) + GYRO_BIAS_VEKTOR
                             + rng.normal(0, sigma_g, 3))
            a_bump = accel_bump * abs(s)
            acc_rows.append([rng.normal(0, sigma_a),
                             0.25 * a_bump + rng.normal(0, sigma_a),
                             1.0 + a_bump + rng.normal(0, sigma_a)])
        ruhe(rng.uniform(0.25, 0.45))  # kurzes Absetzen zwischen den Reps

    ruhe(ruhe_vor_s)
    n_halb = 0
    for _ in range(n_reps):
        t_rep = max(0.6, rng.normal(profil["tempo_s"], profil["tempo_std"]))
        g_peak = max(20.0, rng.normal(profil["gyro_peak"], profil["gyro_std"]))
        a_bump = max(0.05, rng.normal(profil["accel_bump"], profil["accel_std"]))
        if halb_rep_p > 0.0 and rng.random() < halb_rep_p:
            t_rep *= 0.6
            g_peak *= 0.45
            a_bump *= 0.45
            n_halb += 1
        if tempo == "langsam":
            t_slow = float(np.clip(t_rep * 3.5, 4.0, 6.0))
            faktor = t_rep / t_slow  # gleiche Exkursion, laengere Dauer
            g_peak *= faktor
            a_bump *= faktor
            t_rep = t_slow
        rep(t_rep, g_peak, a_bump, profil["form"])
    ruhe(ruhe_nach_s)
    t = np.arange(len(acc_rows)) * dt
    return t, np.array(acc_rows), np.array(gyro_rows), n_halb


def ema_glaettung(signal, alpha=0.6):
    """Kausaler EMA-Tiefpass wie SignalProcessor oben (fuer combined)."""
    out = np.empty_like(signal, dtype=float)
    out[0] = signal[0]
    for i in range(1, len(signal)):
        out[i] = out[i - 1] * (1 - alpha) + signal[i] * alpha
    return out


def kandidaten_signale(acc, gyro, achse, gyro_bias, gyro_weight=0.05):
    """Kandidaten-Signale fuer Stufe B: g_p (vorzeichenbehaftet, auf die
    gelernte Rotationsachse projiziert), combined (App-Formel accel_mag +
    gyro_mag * gyro_weight, EMA-geglaettet wie im SignalProcessor), |gyro|
    (Bias-korrigierte Magnitude)."""
    accel_mag = np.linalg.norm(acc, axis=1)
    gyro_z = gyro - gyro_bias
    gyro_mag = np.linalg.norm(gyro_z, axis=1)
    g_p = gyro_z @ achse
    combined = ema_glaettung(accel_mag + gyro_weight * gyro_mag)
    return {"g_p": g_p, "combined": combined, "gyro_mag": gyro_mag}


def zaehle_edge(signal, hz, theta, refractory_s, baseline=0.0,
                falling_ratio=0.5, prominenz=0.0, falling_debounce=4):
    """Zaehlpfad analog zu WorkoutEngineSim._detect_peak (Rising Edge ueber
    theta, Falling Edge baseline-relativ), aber auf einem waehlbaren Signal
    und mit gelernten Parametern: Schwelle theta, Refractory (Mindest-
    Rep-Abstand in s), optionale Prominenz (Mindest-Ausschlag ueber dem
    vorausgehenden Tal). Rueckgabe: Liste von (Peak-Index, Peak-Hoehe).

    falling_ratio=0.5 (tieferes Hysterese-Plateau als das 0,7 der App) plus
    falling_debounce (die Falling-Schwelle muss mehrere Samples AM STUECK
    unterschritten sein, bevor die Exkursion schliesst): Ein einzelner
    Rausch-Einbruch auf der (bei langsamen Reps sehr langen) Flanke darf die
    Exkursion nicht vorzeitig abschliessen - sonst entstehen Flanken-
    Detektionen knapp ueber theta, gefolgt von einer Zweit-Detektion nach
    Ablauf der Refractory (Doppelzaehlung, Debug-Befund 2026-07-16 an der
    slow- und weak-Persona)."""
    reps = []
    above = False
    exc_peak = -np.inf
    exc_idx = -1
    pre_min = np.inf
    last_end = -10**12
    unter_falling = 0  # Debounce-Zaehler fuer die Falling-Schwelle
    refr_samples = refractory_s * hz
    falling = baseline + (theta - baseline) * falling_ratio
    for i, v in enumerate(signal):
        if not above:
            pre_min = min(pre_min, v)
            if v > theta:
                if i - last_end < refr_samples:
                    continue  # Refractory: Anstieg innerhalb der Sperrzeit ignorieren
                above = True
                exc_peak = v
                exc_idx = i
                unter_falling = 0
        else:
            if v >= exc_peak:
                exc_peak = v
                exc_idx = i
            if v < falling:
                unter_falling += 1
            else:
                unter_falling = 0
            if unter_falling >= falling_debounce:
                above = False
                unter_falling = 0
                if prominenz > 0.0 and (exc_peak - pre_min) < prominenz:
                    pre_min = v
                    continue  # zu flacher Ausschlag -> keine Rep
                reps.append((exc_idx, exc_peak))
                last_end = i
                pre_min = v
    return reps


def stufe0_ruheanalyse(acc, gyro):
    """Stufe 0 (Ruhe): Baseline, Rausch-Sigma, Gyro-Bias + Qualitaets-Gate
    (ENG-Check: es muessen Samples ankommen; Stillstand verifiziert:
    |gyro| < 15 Grad/s, Accel-Streuung klein)."""
    n = len(acc)
    accel_mag = np.linalg.norm(acc, axis=1)
    gyro_bias = gyro.mean(axis=0) if n > 0 else np.zeros(3)
    gyro_mag = np.linalg.norm(gyro - gyro_bias, axis=1) if n > 0 else np.array([np.inf])
    erg = dict(n_samples=n,
               baseline=float(np.mean(accel_mag)) if n > 0 else 0.0,
               sigma_accel=float(np.std(accel_mag)) if n > 0 else np.inf,
               gyro_bias=gyro_bias,
               sigma_gyro=float(np.std(gyro_mag)),
               gyro_mag_mittel=float(np.mean(gyro_mag)))
    erg["gate_ok"] = bool(n > 0 and erg["gyro_mag_mittel"] < 15.0
                          and erg["sigma_accel"] < 0.05)
    return erg


def stufeA_achsenanalyse(gyro, ruhe, hz=50):
    """Stufe A (N=1 bekannt): das Bewegungsfenster zwischen Ruhe und Ruhe IST
    die Rep. Rotationsachse via PCA: numpy.linalg.eigh auf die 3x3-Kovarianz
    des Bias-korrigierten Gyro-Fensters, Hauptkomponente -> projiziertes,
    vorzeichenbehaftetes g_p. Liefert ausserdem Rep-Dauer T0."""
    bias = ruhe["gyro_bias"]
    gyro_z = gyro - bias
    gyro_mag = np.linalg.norm(gyro_z, axis=1)
    schwelle = max(15.0, 4.0 * ruhe["sigma_gyro"])
    aktiv = np.where(gyro_mag > schwelle)[0]
    if len(aktiv) < 5:
        return None  # Gate: kein Bewegungsfenster gefunden
    i0, i1 = int(aktiv[0]), int(aktiv[-1])
    fenster = gyro_z[i0:i1 + 1]
    zentriert = fenster - fenster.mean(axis=0)
    cov = (zentriert.T @ zentriert) / max(len(zentriert) - 1, 1)
    eigenwerte, eigenvektoren = np.linalg.eigh(cov)
    achse = eigenvektoren[:, int(np.argmax(eigenwerte))]
    g_p_fenster = fenster @ achse
    # Vorzeichen-Konvention: groesster Ausschlag der Rep soll positiv sein
    if g_p_fenster.max() < -g_p_fenster.min():
        achse = -achse
        g_p_fenster = -g_p_fenster
    return dict(achse=achse, t0=(i1 - i0) / hz, fenster=(i0, i1),
                gyro_peak_fenster=float(g_p_fenster.max()),
                achsen_varianzanteil=float(eigenwerte.max() / eigenwerte.sum()))


def known_count_sweep(signale, meta, t0, hz, n_soll):
    """Stufe B: Known-Count-Optimierung (Kern des Konzepts).
    signale: dict name -> 1D-Array; meta: dict name -> (baseline, sigma).
    Sweep: Threshold-Grid (20 Schritte ueber [0,1*Spanne .. Spanne] ueber der
    Baseline) x Refractory in [0,35-0,75]*T0 (5 Stufen) x Prominenz
    {aus, 0,2*Median der vorlaeufigen Peak-Hoehen}.
    Harte Bedingung count == n_soll; Tie-Break 1) minimaler
    Variationskoeffizient (CV = sigma/mu) der Rep-Intervalle, 2) maximale
    Margin theta - (baseline + 3*sigma) ueber dem Rauschboden."""
    beste = None
    for name, sig in signale.items():
        baseline, sigma = meta[name]
        span = float(np.percentile(sig, 99) - baseline)
        if span <= 0:
            continue
        vorl = zaehle_edge(sig, hz, baseline + 3 * sigma, 0.35 * t0, baseline)
        prom = 0.2 * float(np.median([h for _, h in vorl])) if len(vorl) >= 3 else 0.0
        # Tempo-Sonde: Signal um Faktor 3 gestreckt (simuliert deutlich
        # langsameres Tempo, wie Stufe C). Eine valide Konfiguration muss
        # auch dort n_soll zaehlen - sonst haengt ihr Zaehlergebnis an der
        # Buckel-Struktur im aktuellen Tempo (Debug-Befund double_bump:
        # gyro_mag zaehlt im Normtempo 5/5, gestreckt 10/5, weil die lange
        # Refractory den zweiten Buckel maskiert; g_p bleibt stabil).
        n = len(sig)
        sig_langsam = np.interp(np.arange(0, n - 1, 1.0 / 3.0), np.arange(n), sig)
        for theta in baseline + np.linspace(0.10, 1.00, 20) * span:
            for prominenz in (0.0, prom):
                # Stabilitaets-Sonde: dieselbe (theta, prominenz) muss auch
                # mit der KUERZESTEN Refractory (0,35*T0) noch n_soll zaehlen.
                # Sonst zaehlt die Konfiguration nur deshalb richtig, weil
                # eine lange Refractory echte Signal-Buckel maskiert
                # (Debug-Befund double_bump: gyro_mag hat 2 Buckel/Rep im
                # Abstand ~T0/2; refr=0,75*T0 liess den zweiten verschwinden
                # -> B 5/5, aber C/Validierung doppelt gezaehlt).
                if len(zaehle_edge(sig, hz, float(theta), 0.35 * t0, baseline,
                                   prominenz=prominenz)) != n_soll:
                    continue
                # Tempo-Sonde (siehe oben): auch im 3x gestreckten Signal
                # muss (theta, prominenz) mit kuerzester Refractory noch
                # n_soll zaehlen.
                if len(zaehle_edge(sig_langsam, hz, float(theta), 0.35 * t0,
                                   baseline, prominenz=prominenz)) != n_soll:
                    continue
                for refr_faktor in np.linspace(0.35, 0.75, 5):
                    reps = zaehle_edge(sig, hz, float(theta), float(refr_faktor * t0),
                                       baseline, prominenz=prominenz)
                    if len(reps) != n_soll:
                        continue
                    # Hoehen-Gate: die Detektionen muessen die obere
                    # Signalrange erreichen (echte Rep-Peaks), nicht nur knapp
                    # ueber theta auf der Flanke sitzen - sonst gewinnen
                    # Rausch-Detektionen den CV-Tie-Break (Debug-Befund oben).
                    hoehen = [float(h) for _, h in reps]
                    if float(np.median(hoehen)) < baseline + 0.5 * span:
                        continue
                    idx = np.array([i for i, _ in reps], dtype=float)
                    intervalle = np.diff(idx) / hz
                    cv = (float(np.std(intervalle) / np.mean(intervalle))
                          if len(intervalle) > 1 and np.mean(intervalle) > 0 else np.inf)
                    margin = float(theta - (baseline + 3 * sigma))
                    schluessel = (cv, -margin)
                    if beste is None or schluessel < beste["schluessel"]:
                        beste = dict(signal=name, theta=float(theta),
                                     refractory_s=float(refr_faktor * t0),
                                     prominenz=float(prominenz), cv=cv,
                                     margin=margin, schluessel=schluessel,
                                     peak_hoehen=[float(h) for _, h in reps])
    return beste


def median_minus_k_mad(peak_hoehen, theta_sweep):
    """Finale Schwelle als median - k*MAD der validierten Peak-Hoehen
    (Konzept Stufe B); k wird so bestimmt, dass die Schwelle die vom Sweep
    gefundene Hoehe reproduziert. Bei praktisch verschwindendem MAD bleibt
    die Sweep-Schwelle erhalten - sonst laege sie exakt AUF dem Median und
    die strikte `>`-Pruefung wuerde Peaks auf Median-Hoehe verwerfen."""
    med = float(np.median(peak_hoehen))
    mad = float(np.median(np.abs(np.array(peak_hoehen) - med)))
    if mad < 1e-9:
        return theta_sweep, 0.0, med, mad
    k = max(0.0, (med - theta_sweep) / mad)
    return med - k * mad, k, med, mad


def stufeC_tempo_robustheit(sig_b, sig_c, baseline, hz, cfg, n_b=5, n_c=3):
    """Stufe C (Tempo-Robustheit): die aus B gewaehlten Parameter muessen
    auch bei den 3 langsamen Reps 3/3 zaehlen. Sonst theta schrittweise
    senken, bis BEIDE Stufen gleichzeitig korrekt zaehlen (tempo-robust
    konservativ).

    Zusaetzlich Sicherheitsmarge: Stufe C sieht nur 3 langsame Reps, die
    Peak-Hoehen streuen aber (Tempo-/Amplituden-Varianz). Damit die Schwelle
    nicht exakt AM schwächsten beobachteten langsamen Peak klebt (und dann in
    der Validierung den unteren Verteilungsrand verpasst), wird theta auf
    median_C - 2,5*sigma_rel*median_C gedeckelt, sofern beide Stufen dort
    weiter korrekt zaehlen. sigma_rel kommt aus der relativen Streuung der
    B-Peak-Hoehen (MAD*1,4826/median, gefloort bei 10 %, weil Tempo-Jitter
    die Hoehen zusaetzlich streut, auch wenn die 5 B-Reps zufaellig eng
    beieinander lagen).
    Rueckgabe: (theta_final, ok, angepasst)."""
    def zaehl(sig, theta):
        return len(zaehle_edge(sig, hz, theta, cfg["refractory_s"], baseline,
                               prominenz=cfg["prominenz"]))
    def hoehen(sig, theta):
        return [h for _, h in zaehle_edge(sig, hz, theta, cfg["refractory_s"],
                                          baseline, prominenz=cfg["prominenz"])]
    theta0 = cfg["theta"]
    if zaehl(sig_c, theta0) == n_c and zaehl(sig_b, theta0) == n_b:
        theta_arbeit = theta0
    else:
        theta_arbeit = None
        for f in np.linspace(0.98, 0.05, 60):
            theta_t = baseline + (theta0 - baseline) * float(f)
            if zaehl(sig_b, theta_t) == n_b and zaehl(sig_c, theta_t) == n_c:
                theta_arbeit = float(theta_t)
                break
        if theta_arbeit is None:
            return theta0, False, False
    # Konservativer Deckel: untere Verteilungskante der langsamen Peaks
    langsam_hoehen = hoehen(sig_c, theta_arbeit)
    if langsam_hoehen and cfg.get("peak_hoehen"):
        med_b = float(np.median(cfg["peak_hoehen"]))
        mad_b = float(np.median(np.abs(np.array(cfg["peak_hoehen"]) - med_b)))
        sigma_rel = max(1.4826 * mad_b / max(med_b, 1e-9), 0.10)
        med_c = float(np.median(langsam_hoehen))
        deckel = med_c - 2.5 * sigma_rel * med_c
        theta_deckel = min(theta_arbeit, deckel)
        if (theta_deckel < theta_arbeit - 1e-9
                and zaehl(sig_b, theta_deckel) == n_b
                and zaehl(sig_c, theta_deckel) == n_c):
            return float(theta_deckel), True, True
    return theta_arbeit, True, abs(theta_arbeit - theta0) > 1e-9


def stufeD_review_simulation(sig_b, baseline, hz, cfg, signale_b, meta_b, t0, n_soll=5):
    """Stufe D (Review-Simulation): injiziert eine Fehlkonfiguration (Schwelle
    so gesenkt, dass 7 statt 5 gezaehlt wird), prueft, dass der Review-Schritt
    die Diskrepanz erkennt (gezaehlt != bekannt), und dass die Re-Optimierung
    mit der korrigierten Anzahl wieder n_soll/n_soll findet."""
    theta_bad, count_bad = None, None
    # Injektion: Schwelle absenken. Einmal mit der gelernten Prominenz, einmal
    # ohne, einmal ganz ohne Refractory - sonst gibt es Konfigurationen (z. B.
    # prominenz-/refractory-gestuetzte), bei denen eine abgesenkte Schwelle
    # allein nie ueberzaehlt. Gesucht: idealerweise gezaehlt==7; akzeptiert
    # wird jede Diskrepanz != n_soll (auch Unterzaehlung ist eine vom Review
    # zu erkennende Fehlkonfiguration).
    kandidat_unter = None
    for prom_versuch, refr_versuch in ((cfg["prominenz"], cfg["refractory_s"]),
                                       (0.0, cfg["refractory_s"]),
                                       (0.0, 0.0)):
        for f in np.linspace(0.90, 0.05, 60):
            theta_t = baseline + (cfg["theta"] - baseline) * float(f)
            c = len(zaehle_edge(sig_b, hz, theta_t, refr_versuch, baseline,
                                prominenz=prom_versuch))
            if c == 7:
                theta_bad, count_bad = float(theta_t), c
                break
            if c > n_soll and count_bad is None:
                theta_bad, count_bad = float(theta_t), c
            if c != n_soll and kandidat_unter is None:
                kandidat_unter = (float(theta_t), c)
        if count_bad == 7:
            break
    if theta_bad is None:
        theta_bad, count_bad = kandidat_unter if kandidat_unter is not None \
            else (cfg["theta"], n_soll)
    review_erkennt = count_bad != n_soll
    reopt = known_count_sweep(signale_b, meta_b, t0, hz, n_soll)
    reopt_ok = False
    if reopt is not None:
        b2, _ = meta_b[reopt["signal"]]
        c2 = len(zaehle_edge(signale_b[reopt["signal"]], hz, reopt["theta"],
                             reopt["refractory_s"], b2, prominenz=reopt["prominenz"]))
        reopt_ok = (c2 == n_soll)
    return dict(theta_bad=theta_bad, count_bad=count_bad,
                review_erkennt=review_erkennt, reopt_ok=reopt_ok)


def kalibriere_persona(persona, seed=1000, hz=50):
    """Komplette Known-Count-Kalibrierung (Stufen 0/A/B/C/D) + Validierung
    fuer eine Persona. Kalibrierungs-Aufnahmen: saubere Ausfuehrung (der
    Nutzer folgt der Stufen-Anweisung); Validierungs-Aufnahmen: neue Seeds,
    inkl. Tempo- und (bei inconsistent) Halb-Rep-Variation."""
    print(f"\n--- Persona: {persona} ---")

    # --- Stufe 0: Ruhe (3 s) ---
    _, acc0, gyro0, _ = make_persona_6achsen(persona, 0, hz=hz, seed=seed,
                                             ruhe_vor_s=3.0, ruhe_nach_s=0.02)
    st0 = stufe0_ruheanalyse(acc0, gyro0)
    print(f"Stufe 0 Ruhe:        baseline={st0['baseline']:.3f} g  sigma_accel={st0['sigma_accel']:.4f}  "
          f"|gyro|={st0['gyro_mag_mittel']:.2f}°/s  bias={np.round(st0['gyro_bias'], 2)}  "
          f"gate={'OK' if st0['gate_ok'] else 'FEHLER'}")
    if not st0["gate_ok"]:
        return dict(persona=persona, ok=False, fehler="Stufe-0-Gate")

    # --- Stufe A: genau 1 Rep (bekannt) ---
    _, accA, gyroA, _ = make_persona_6achsen(persona, 1, hz=hz, seed=seed + 1,
                                             ruhe_vor_s=1.5, ruhe_nach_s=1.5)
    stA = stufeA_achsenanalyse(gyroA, st0, hz=hz)
    if stA is None:
        print("Stufe A:             FEHLER - kein Bewegungsfenster gefunden")
        return dict(persona=persona, ok=False, fehler="Stufe-A-Gate")
    achse, t0 = stA["achse"], stA["t0"]
    print(f"Stufe A (N=1):       Achse={np.round(achse, 2)}  T0={t0:.2f} s  "
          f"g_p-Peak={stA['gyro_peak_fenster']:.0f}°/s  Varianzanteil={stA['achsen_varianzanteil']:.2f}")

    # --- Stufe B: genau 5 Reps (bekannt) -> Known-Count-Sweep ---
    _, accB, gyroB, _ = make_persona_6achsen(persona, 5, hz=hz, seed=seed + 2,
                                             ruhe_vor_s=1.0, ruhe_nach_s=1.0)
    signaleB = kandidaten_signale(accB, gyroB, achse, st0["gyro_bias"])
    n_rest = int(1.0 * hz)
    rest_idx = np.r_[0:n_rest, len(accB) - n_rest:len(accB)]
    metaB = {name: (float(np.median(sig[rest_idx])), float(np.std(sig[rest_idx])))
             for name, sig in signaleB.items()}
    cfg = known_count_sweep(signaleB, metaB, t0, hz, 5)
    if cfg is None:
        print("Stufe B (N=5):       FEHLER - keine Konfiguration zaehlt 5/5")
        return dict(persona=persona, ok=False, fehler="Stufe-B-Sweep")
    thetaB, k, med, mad = median_minus_k_mad(cfg["peak_hoehen"], cfg["theta"])
    cfg["theta"] = thetaB
    b_base, b_sigma = metaB[cfg["signal"]]
    countB = len(zaehle_edge(signaleB[cfg["signal"]], hz, thetaB,
                             cfg["refractory_s"], b_base, prominenz=cfg["prominenz"]))
    stufeB_ok = countB == 5
    print(f"Stufe B (N=5):       {countB}/5  signal={cfg['signal']:9s} theta={thetaB:.3f}  "
          f"refr={cfg['refractory_s']:.2f} s  prom={cfg['prominenz']:.3f}  "
          f"CV={cfg['cv']:.3f}  margin={cfg['margin']:.3f}  "
          f"(median={med:.2f}, k={k:.2f}, MAD={mad:.2f})  [{'OK' if stufeB_ok else 'FEHLER'}]")

    # --- Stufe C: 3 langsame Reps (bekannt) -> Tempo-Robustheit ---
    _, accC, gyroC, _ = make_persona_6achsen(persona, 3, hz=hz, seed=seed + 3,
                                             tempo="langsam", ruhe_vor_s=1.0, ruhe_nach_s=1.0)
    signaleC = kandidaten_signale(accC, gyroC, achse, st0["gyro_bias"])
    thetaC, stufeC_ok, angepasst = stufeC_tempo_robustheit(
        signaleB[cfg["signal"]], signaleC[cfg["signal"]], b_base, hz, cfg)
    countC = len(zaehle_edge(signaleC[cfg["signal"]], hz, thetaC,
                             cfg["refractory_s"], b_base, prominenz=cfg["prominenz"]))
    cfg["theta"] = thetaC
    print(f"Stufe C (N=3 lang):  {countC}/3  theta={'angepasst' if angepasst else 'unveraendert'} "
          f"-> {thetaC:.3f}  [{'OK' if stufeC_ok else 'FEHLER/WIDERSPRUCH'}]")

    # --- Stufe D: Review-Simulation (injizierter Zaehlfehler) ---
    stD = stufeD_review_simulation(signaleB[cfg["signal"]], b_base, hz, cfg,
                                   signaleB, metaB, t0)
    review_ok = stD["review_erkennt"] and stD["reopt_ok"]
    print(f"Stufe D (Review):    injiziert theta={stD['theta_bad']:.3f} -> gezaehlt={stD['count_bad']} "
          f"(bekannt=5)  Diskrepanz erkannt={'ja' if stD['review_erkennt'] else 'NEIN'}  "
          f"Re-Optimierung 5/5={'ja' if stD['reopt_ok'] else 'NEIN'}  [{'OK' if review_ok else 'FEHLER'}]")

    # --- Validierung: NEUE Aufnahmen, Zaehlpfad mit gelernten Parametern ---
    _, accV1, gyroV1, n_halb = make_persona_6achsen(
        persona, 10, hz=hz, seed=seed + 100, ruhe_vor_s=1.0, ruhe_nach_s=1.0,
        halb_rep_p=0.10 if persona == "inconsistent" else 0.0)
    sigV1 = kandidaten_signale(accV1, gyroV1, achse, st0["gyro_bias"])[cfg["signal"]]
    countV1 = len(zaehle_edge(sigV1, hz, cfg["theta"], cfg["refractory_s"], b_base,
                              prominenz=cfg["prominenz"]))
    erwV1 = 10 - n_halb

    _, accV2, gyroV2, _ = make_persona_6achsen(persona, 8, hz=hz, seed=seed + 200,
                                               tempo="langsam", ruhe_vor_s=1.0, ruhe_nach_s=1.0)
    sigV2 = kandidaten_signale(accV2, gyroV2, achse, st0["gyro_bias"])[cfg["signal"]]
    countV2 = len(zaehle_edge(sigV2, hz, cfg["theta"], cfg["refractory_s"], b_base,
                              prominenz=cfg["prominenz"]))
    erwV2 = 8
    mae = (abs(countV1 - erwV1) + abs(countV2 - erwV2)) / 2.0
    print(f"Validierung:         normal={countV1}/{erwV1}  langsam={countV2}/{erwV2}  MAE={mae:.2f}")

    ok = bool(stufeB_ok and stufeC_ok and review_ok and mae <= 0.5)
    return dict(persona=persona, ok=ok, stufeB_ok=stufeB_ok, stufeC_ok=stufeC_ok,
                angepasst=angepasst, signal=cfg["signal"], theta=cfg["theta"],
                refractory_s=cfg["refractory_s"], prominenz=cfg["prominenz"],
                val_normal=(erwV1, countV1), val_langsam=(erwV2, countV2),
                mae=mae, review_ok=review_ok)


def run_known_count_calibration_suite(alt_ergebnisse):
    """Paket-1-Suite: Known-Count-Kalibrierung fuer alle Personas +
    Abschluss-Report inkl. Status der Alt-Suite (Doppel-Peak-Befund)."""
    print("\n" + "=" * 100)
    print("=== Known-Count-Kalibrierung mit Nutzer-Personas (Paket 1, Konzept 2.0 Stufen 0/A/B/C/D) ===")
    print("=" * 100)

    ergebnisse = []
    for i, persona in enumerate(PERSONA_PROFILES):
        ergebnisse.append(kalibriere_persona(persona, seed=1000 + 17 * i))

    print("\n" + "=" * 100)
    print("=== Zusammenfassung: Known-Count-Kalibrierung pro Persona ===")
    print("=" * 100)
    print(f"{'Persona':14s} {'StufeB':>7s} {'StufeC':>7s} {'Signal':>9s} {'theta':>8s} "
          f"{'Refr.':>6s} {'Val.norm':>9s} {'Val.lang':>9s} {'MAE':>5s} {'Review':>7s}")
    print("-" * 100)
    for e in ergebnisse:
        if "fehler" in e:
            print(f"{e['persona']:14s} {'--':>7s} {'--':>7s} {'--':>9s} {'--':>8s} "
                  f"{'--':>6s} {'--':>9s} {'--':>9s} {'--':>5s} {'--':>7s}  [{e['fehler']}]")
            continue
        b = "5/5 OK" if e["stufeB_ok"] else "FEHLER"
        c = ("3/3 OK" if e["stufeC_ok"] else "FEHLER") + ("*" if e["angepasst"] else "")
        vn = f"{e['val_normal'][1]}/{e['val_normal'][0]}"
        vl = f"{e['val_langsam'][1]}/{e['val_langsam'][0]}"
        r = "ja" if e["review_ok"] else "NEIN"
        print(f"{e['persona']:14s} {b:>7s} {c:>7s} {e['signal']:>9s} {e['theta']:>8.3f} "
              f"{e['refractory_s']:>5.2f}s {vn:>9s} {vl:>9s} {e['mae']:>5.2f} {r:>7s}")
    print("-" * 100)
    print("(* = theta in Stufe C tempo-robust abgesenkt; theta-Einheit = Einheit des gewaehlten "
          "Signals: g_p in °/s, combined in g + 0,05*°/s, gyro_mag in °/s)")

    n_ok = sum(1 for e in ergebnisse if e["ok"])
    print(f"\nErgebnis: {n_ok}/{len(ergebnisse)} Personas erfolgreich kalibriert "
          f"(B 5/5, C 3/3, Review faengt injizierten Fehler, Validierungs-MAE <= 0,5).")

    print("\n--- Einordnung / Limit-Faelle ---")
    print("- inconsistent (MAE = 0,50 = Limit, akzeptiert und begruendet): Die schlampige")
    print("  Halb-Rep im normalen Validierungssatz (~45 % Amplitude, ~60 % Dauer) wird")
    print("  mitgezaehlt (10/9). Eine einzelne Schwelle kann sie NICHT von einer")
    print("  vollwertigen langsamen Rep trennen - beide liegen bei ~50-80 Grad/s, und")
    print("  die Schwelle muss wegen Stufe C unter die langsamen Peaks. Dafuer ist in")
    print("  Guided Calibration 2.0 das Prominenz-/Formkriterium (V3, Template-Matching)")
    print("  vorgesehen. Der langsame Satz ist exakt (8/8); Fehler gesamt = 1 Rep -> 0,5.")
    print("- double_bump: der Sweep waehlt g_p (vorzeichenbehaftet), weil die Tempo-")
    print("  Sonde gyro_mag/combined verwirft (2 Buckel/Rep -> im Langsam-Tempo doppelt")
    print("  gezaehlt). Genau der Legacy-Defekt der Alt-Suite (20/10) wird hier durch")
    print("  Known-Count + Achsenprojektion strukturell vermieden.")

    print("\n--- Status der Alt-Suite (lief oben unveraendert mit) ---")
    for name, (erw, gez) in alt_ergebnisse.items():
        mark = ""
        if name.startswith("Doppel-Peak"):
            mark = (f"  <-- bekannter, pre-existing Defekt im Legacy-Zaehlpfad "
                    f"(gezaehlt {gez}/{erw}): jede Rep erzeugt zwei Magnitude-Buckel, der "
                    f"alte combined-Pfad zaehlt doppelt. Nicht Fix-Ziel von Paket 1; der "
                    f"double_bump-Persona-Pfad oben zeigt, dass Known-Count + g_p das loest.")
        print(f"{name:45s} erwartet={erw:3d}  gezaehlt={gez:3d}{mark}")

    return n_ok == len(ergebnisse)


if __name__ == "__main__":
    print("=== FlowRep Workout-Engine-Simulation ===\n")

    scenarios = [
        ("Saubere Reps (Demo-Tempo)", make_clean_reps(10), 10),
        ("Doppel-Peak-Uebung (Squat-artig)", make_double_peak_reps(10), 10),
        ("Sehr langsame Reps (Powerlifter)", make_slow_reps(8), 8),
    ]
    print(f"{'Szenario':45s} {'erwartet':>10s} {'gezaehlt':>10s}  Status\n" + "-" * 78)
    alt_ergebnisse = {}
    for name, (t, accel, gyro), expected in scenarios:
        counted, _ = run_scenario(name, t, accel, gyro, expected)
        alt_ergebnisse[name] = (expected, counted)

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
    adr020_ok = run_adr020_regression_suite()
    settle_ok = run_calibration_settle_regression_suite()
    if not adr020_ok:
        raise SystemExit("ADR-020-Regressionstest fehlgeschlagen - siehe Ausgabe oben.")
    if not settle_ok:
        raise SystemExit("Settle-Gate-Regressionstest fehlgeschlagen - siehe Ausgabe oben.")

    kalibrierung_ok = run_known_count_calibration_suite(alt_ergebnisse)
    if not kalibrierung_ok:
        raise SystemExit("Known-Count-Kalibrierung (Paket 1) fehlgeschlagen - siehe Ausgabe oben.")

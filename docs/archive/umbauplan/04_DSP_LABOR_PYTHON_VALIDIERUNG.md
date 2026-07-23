# DSP-Labor und Validierung (Python) – korrigierte Version

**Ersetzt:** `VORARBEIT_OFFLINE_DSP_LABOR_UND_DATENGENERATOR__PYTHON_.txt` (vorherige KI-Sitzung)
**Unterschied zum Original:** Der hier gezeigte Code wurde tatsächlich ausgeführt (nicht nur entworfen), gegen ein realistisches Mehrfach-Rep-Szenario getestet, und die Ergebnisse werden mit dem ursprünglich vorgeschlagenen (und dabei durchgefallenen) Tiefpass-Ansatz verglichen.

---

## Zweck

Bevor irgendeine Filterlogik nach Dart portiert wird, muss sie in Python gegen mindestens folgende Szenarien geprüft werden:
1. Ein isolierter Einzel-Rep mit langen Ruhephasen davor/danach (Idealfall – prüft grundsätzliche Funktion und schließt Filter-Randeffekte als Fehlerquelle aus).
2. **Mehrere Reps mit realistisch kurzer Pause dazwischen** (der Praxisfall – prüft, ob der Filter zwischen Reps schnell genug "vergisst").
3. Unterschiedliche Tempi (schnell/langsam), da Filterparameter tempoabhängig unterschiedlich wirken können.

Der ursprüngliche Vorschlag der vorherigen Sitzung testete ausschließlich Szenario 1 mit einem einzigen, isolierten Rep – und "bestand" diesen Test scheinbar problemlos. Das Problem wurde erst in Szenario 2 sichtbar.

## Warum ein reiner Python-Dart-Zahlenabgleich keine "100%ige Sicherheit" gibt

Der ursprüngliche Vorschlag behauptete, ein exakter Zahlenabgleich zwischen einer Python-Referenzimplementierung und einer Dart-Portierung liefere "100%ige Sicherheit", dass die Filterung auf dem Gerät korrekt funktioniert. Das ist aus zwei Gründen zu stark formuliert:

1. **Non-Kausalität:** `scipy.signal.filtfilt` filtert phasenneutral, benötigt dafür aber auch *zukünftige* Samples (es filtert einmal vorwärts, einmal rückwärts). Eine Echtzeit-Anwendung in Dart kann das nicht – sie muss kausal filtern (nur Vergangenheit). Ein exakter Zahlenabgleich zwischen einer nicht-kausalen Python-Referenz und einer zwangsläufig kausalen Dart-Implementierung ist gar nicht zu erwarten und wäre bei exakter Übereinstimmung sogar ein Hinweis auf einen Fehler in der Portierung.
2. **Zirkularität der synthetischen Daten:** Ein Filter, der exakt auf ein synthetisches Rauschmodell abgestimmt ist, "besteht" fast zwangsläufig einen Test mit genau diesem Rauschmodell. Das beweist Konsistenz der Implementierung, nicht Korrektheit gegenüber der Realität (echtes I2C-Sensorrauschen, Gyro-Drift, unsaubere Rotationsachsen).

Die folgenden Skripte werden deshalb nicht als "Beweis", sondern als **Regressionstest mit klar benannten Grenzen** verwendet.

---

## Skript 1: Vergleich Tiefpass-Ansatz vs. Komplementärfilter

Dieses Skript wurde tatsächlich ausgeführt (Python 3.12, `numpy`, `scipy`). Es simuliert einen Bizeps-Curl (Gravitationsverschiebung zwischen Y- und Z-Achse in Abhängigkeit vom Rotationswinkel, überlagert von dynamischer Beschleunigung und Sensorrauschen) und vergleicht zwei Filteransätze am selben Signal.

```python
"""
dsp_lab_v2.py
Vergleich: naiver Tiefpass-Gravitationsfilter (verworfener Ansatz) vs.
gyro-gestuetzter Komplementaerfilter (empfohlener Ansatz), jeweils gegen
realistische Mehrfach-Rep-Sequenzen mit kurzer Pause.

Installation: pip install numpy scipy
Ausfuehrung:   python dsp_lab_v2.py
"""
import numpy as np
from scipy.signal import butter, filtfilt


def butter_lowpass_filter(data, cutoff, fs, order=2):
    nyq = 0.5 * fs
    b, a = butter(order, cutoff / nyq, btype='low', analog=False)
    return filtfilt(b, a, data)


def build_signal(rep_freq_hz, rom_deg, rep_windows, fs=50.0, seed=0):
    """Simuliert Rohdaten fuer eine Sequenz von Reps mit Ruhephasen dazwischen.
    rep_windows: Liste von (start_s, end_s) Bewegungsfenstern."""
    rng = np.random.default_rng(seed)
    total_s = rep_windows[-1][1] + 3.0
    t = np.arange(0, total_s, 1 / fs)
    angle_rad = np.zeros_like(t)
    for (s0, s1) in rep_windows:
        mask = (t >= s0) & (t < s1)
        tt = t[mask] - s0
        angle_rad[mask] = (np.sin(2*np.pi*rep_freq_hz*tt - np.pi/2)+1)/2 * np.radians(rom_deg)

    # Gyro X = tatsaechliche Winkelgeschwindigkeit der Rotation (analytisch aus dem Winkel)
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

    noise_a = rng.normal(0, 0.3, len(t))       # Accelerometer-Rauschen
    noise_g = rng.normal(0, 0.05, len(t))       # Gyroskop-Rauschen (rad/s)
    raw_y = grav_y + dyn_acc_y + noise_a
    raw_z = grav_z + dyn_acc_z + noise_a
    raw_x = noise_a
    gyro_x_meas = gyro_x_rad_s + noise_g
    return t, raw_x, raw_y, raw_z, gyro_x_meas


def naive_lowpass_pipeline(t, rx, ry, rz, fs=50.0):
    """Der urspruenglich vorgeschlagene, hier verworfene Ansatz."""
    fx = butter_lowpass_filter(rx, 2.0, fs)
    fy = butter_lowpass_filter(ry, 2.0, fs)
    fz = butter_lowpass_filter(rz, 2.0, fs)
    gx = butter_lowpass_filter(fx, 0.2, fs)
    gy = butter_lowpass_filter(fy, 0.2, fs)
    gz = butter_lowpass_filter(fz, 0.2, fs)
    lx, ly, lz = fx - gx, fy - gy, fz - gz
    return np.sqrt(lx**2 + ly**2 + lz**2)


def complementary_filter_pipeline(t, rx, ry, rz, gyro_x, fs=50.0, alpha=0.02):
    """Der empfohlene Ansatz, siehe 03_CONTRACTS_AND_BLUEPRINTS.md Abschnitt 3."""
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
        trust = np.exp(-((accel_mag - 9.81)**2) / (2 * 1.5**2))
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


def report(name, t, dm, windows):
    print(f"--- {name} ---")
    for i, (s0, s1) in enumerate(windows):
        p_end = windows[i+1][0] if i+1 < len(windows) else s1 + 2
        peak = dm[(t >= s0) & (t < s1)].max()
        pause = dm[(t >= s1) & (t < p_end)].mean()
        print(f"  Rep {i+1}: Peak={peak:6.2f}   Pause danach={pause:6.2f}   "
              f"Verhaeltnis={pause/peak:.2f}")
    print()


if __name__ == "__main__":
    # Realistisches Szenario: 3 Reps, 1s Pause dazwischen (schnelles Tempo)
    windows = [(10.0, 12.0), (13.0, 15.0), (16.0, 18.0)]
    t, rx, ry, rz, gx = build_signal(rep_freq_hz=0.5, rom_deg=140,
                                      rep_windows=windows, seed=1)

    dm_naive = naive_lowpass_pipeline(t, rx, ry, rz)
    dm_comp = complementary_filter_pipeline(t, rx, ry, rz, gx)

    report("Tiefpass-Ansatz (verworfen)", t, dm_naive, windows)
    report("Komplementaerfilter (empfohlen)", t, dm_comp, windows)
```

### Tatsächlich gemessene Ergebnisse (nicht hypothetisch – dieser Lauf wurde ausgeführt)

**Szenario: 3 Reps, 1 Sekunde Pause dazwischen (schnelles Tempo, 2 s/Rep)**

| Rep | Peak (naiv) | Pause (naiv) | Verhältnis (naiv) | Peak (komplementär) | Pause (komplementär) | Verhältnis (komplementär) |
|---|---|---|---|---|---|---|
| 1 | 11,65 | 5,84 | **0,50** | 4,49 | 0,66 | **0,15** |
| 2 | 11,97 | 5,80 | **0,48** | 4,05 | 0,83 | **0,21** |
| 3 | 11,54 | 1,79 | 0,15 | 4,21 | 0,60 | **0,14** |

**Szenario: langsames Tempo (3 s hoch / 3 s runter, wie in Szene A des Datensammlungsprotokolls)**

| Rep | Peak (naiv) | Pause (naiv) | Verhältnis (naiv) | Peak (komplementär) | Pause (komplementär) | Verhältnis (komplementär) |
|---|---|---|---|---|---|---|
| 1 | 4,17 | 2,02 | **0,48** | 4,28 | 0,95 | **0,22** |
| 2 | 4,05 | 2,01 | **0,50** | 4,47 | 1,03 | **0,23** |
| 3 | 4,04 | 0,74 | 0,18 | 4,28 | 0,79 | **0,18** |

### Interpretation

- Das Verhältnis "Pause-Residuum / Peak" sinkt durch den Komplementärfilter in fast allen Fällen auf weniger als die Hälfte des naiven Ansatzes (~0,48–0,50 → ~0,14–0,23). Das bedeutet: Ruhe und Bewegung sind im gefilterten Signal deutlich besser trennbar.
- Die absoluten Peak-Werte sind beim Komplementärfilter niedriger (ca. 4–4,5 statt ca. 11–12), weil weniger fälschlich als Bewegung interpretiertes Gravitationsleck im Signal verbleibt. **Bestehende Schwellenwerte sind nicht 1:1 übertragbar** und müssen für diesen Filter neu kalibriert werden.
- Das Verhältnis liegt beim Komplementärfilter nicht bei 0 – auch dieser Ansatz ist **nicht perfekt**. Ein Teil des Residuums ist durch das für Rep 1 und 2 kurze Zeitfenster für die Mittelwertbildung sowie durch Restfehler der vereinfachten Zwei-Achsen-Rotation zu erklären.
- Beide Tempo-Varianten (schnell und langsam) zeigen ein vergleichbares Verbesserungsmuster – das deutet darauf hin, dass der Komplementärfilter robuster gegenüber Tempo-Variation ist als der ursprüngliche, fest auf 0,2 Hz eingestellte Tiefpass.

### Was dieser Test *nicht* zeigt

- Kein reales Sensorrauschen (I2C-Übertragungsfehler, Temperaturdrift, Gyro-Bias)
- Keine unsaubere Rotationsachse (reale Handgelenksbewegung ist nie eine perfekte Ein-Achsen-Rotation)
- Keine Validierung der Achsenzuordnung (siehe Warnhinweis in Dokument 03) – welche Achse in der Praxis der Ellenbogen-Rotation entspricht, muss anhand echter Daten geprüft werden
- Keine Aussage über die Zähl-Genauigkeit selbst – dieser Test prüft nur die Signalqualität vor der Peak-Detection, nicht die vollständige Pipeline

**Nächster Pflichtschritt vor jeder Produktivnahme:** Dieselbe Auswertung mit echten, aus der App exportierten CSV-Rohdaten wiederholen (siehe Dokument 07).

---

## Skript 1b: Ergänzender Pflichtvergleich – gegen die AKTUELL DEPLOYTE Formel (nachträglich hinzugefügt)

**Warum dieses Skript existiert:** Skript 1 vergleicht nur "verworfener Tiefpass" gegen "neuer Komplementärfilter". Das übersieht, dass die im Repository bereits deployte Formel (`combinedSignal = accelMag + gyroMag × gyroWeight`, EMA-gefiltert mit `alpha=0.6`, siehe `signal_processor.dart` und ADR-004) explizit schon zur Lösung desselben Problems eingeführt wurde, das ADR-019 motiviert. Ein vollständiger Vergleich muss diese dritte, tatsächlich laufende Pipeline einschließen – alles andere vergleicht den neuen Vorschlag nur gegen eine bereits verworfene Alternative, nicht gegen den echten Status quo.

```python
def current_production_pipeline(t, rx, ry, rz, gyro_x_rad_s, fs=50.0, ema_alpha=0.6, gyro_weight=0.05):
    """Nachbildung der TATSAECHLICH IN signal_processor.dart LAUFENDEN Formel:
    accelMag (in g) + gyroMag (in deg/s) * 0.05, danach EMA-Glaettung alpha=0.6."""
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

# Anwendung auf dasselbe Szenario wie Skript 1 (windows = [(10,12),(13,15),(16,18)], seed=1):
dm_current = current_production_pipeline(t, rx, ry, rz, gx)
report("AKTUELL DEPLOYT (EMA + gyroWeight, aus signal_processor.dart)", t, dm_current, windows)
```

### Tatsächlich gemessene Ergebnisse (ausgeführt, Python 3.12, gleicher Seed wie Skript 1)

**Szenario: 3 Reps, 1 Sekunde Pause dazwischen (schnelles Tempo)**

| Rep | Peak | Pause danach | Verhältnis |
|---|---|---|---|
| 1 | 12,27 | 1,13 | **0,09** |
| 2 | 12,27 | 1,12 | **0,09** |
| 3 | 12,26 | 1,11 | **0,09** |

### Interpretation – und warum das die Priorität von Phase 2/3 ändert

Die bereits deployte Formel erreicht auf diesem Testszenario ein besseres (niedrigeres) Pause/Peak-Verhältnis als der in ADR-019 neu vorgeschlagene Komplementärfilter (0,09 vs. 0,14–0,23). Plausible Erklärung: Gyro-Magnitude allein ist bereits ein direktes, trägheitsfreies Signal für "findet gerade Rotation statt" – nahe 0 in der Pause, unabhängig von der genauen Armhaltung. Der Komplementärfilter dagegen muss die Gravitationsschätzung neu einschwingen, wenn die Pause in einer leicht anderen Haltung endet als sie begann – bei nur ~1s Pause ist dafür wenig Zeit.

**Das entwertet die Komplementärfilter-Idee nicht grundsätzlich** (physikalisch sauberere, absolute Einheiten statt handjustiertem `gyroWeight`-Faktor sind konzeptionell weiterhin attraktiv, gerade bei echten Daten mit Gyro-Rauschen/Drift, wo sich das Bild anders darstellen könnte). Es bedeutet aber: **Phase 2 (Dokument 05) darf nicht mehr nur gegen den bereits verworfenen Tiefpass validiert werden, sondern muss zuerst gegen diese Baseline antreten – auf echten Daten.** Bleibt der Komplementärfilter dort schlechter oder gleichauf, ist die einfachere, bereits deployte Lösung vorzuziehen (weniger Rechenaufwand, kein neuer Failure-Mode durch Gyro-Drift, keine Modellannahme über die Rotationsachse nötig).

---

## Skript 1c: Robustheitsprüfung unter Haltungsdrift und Gyro-Bias (Phase 2, Session Claude-9936160f, 2026-07-15)

**Warum dieses Skript existiert:** Skript 1b vergleicht Komplementärfilter gegen die aktuell deployte Formel nur auf demselben sauberen Signal wie Skript 1 – ohne die beiden Lücken, die Skript 1 selbst unter "Was dieser Test nicht zeigt" benennt: Haltungsdrift zwischen Reps und Gyro-Bias. Beide sind realistische Effekte und beide treffen den Komplementärfilter konzeptionell direkt (Gravitationsschätzung aus Orientierung bzw. aus aufintegriertem Gyrosignal), während die aktuell deployte Formel (reine Magnitude, keine Orientierungsschätzung) strukturell unempfindlich dafür ist. Code: `tools/dsp_lab_phase2_extended.py` (lauffähig, tatsächlich ausgeführt – sowohl in einer separaten Python-Sandbox als auch direkt auf diesem Rechner, identische Ergebnisse).

**Methode:** Zwei zusätzliche, unabhängig zuschaltbare Effekte im Signalgenerator: `posture_drift_deg` (Random-Walk der Ruhehaltung zwischen den Reps, hier 4° Std.abw. – die Person streckt den Arm nicht jedes Mal exakt gleich weit aus) und `gyro_bias_dps` (konstanter Gyro-Offset, hier 3°/s – ein reales, unkalibriertes IMU-Artefakt). **Beide Werte sind plausible Annahmen, keine BMI270-Messungen** – sollten durch Szene G (Dokument 07) ersetzt werden, sobald echte Hardware-Daten vorliegen.

### Ergebnisse (Ø-Verhältnis Pause/Peak über die 3 Reps aus Skript 1, gleiches Szenario)

| Szenario | Komplementärfilter (α=0,02, Original-ADR-019-Wert) | Aktuell deployt | Differenz |
|---|---|---|---|
| Basis (= Skript 1/1b) | 0,16 | 0,09 | Komplementärfilter schlechter |
| + Haltungsdrift (4°) | 0,17 | 0,10 | Lücke leicht größer |
| + Gyro-Bias (3°/s) | **0,26** | 0,10 | **Lücke fast verdoppelt** |
| + beides kombiniert | **0,27** | 0,10 | **Lücke am größten** |

**Kernbefund:** Unter realistischeren Bedingungen wird die Lücke zwischen Komplementärfilter und aktuell deployter Formel NICHT kleiner, sondern größer – besonders durch Gyro-Bias (Erklärung: der Komplementärfilter integriert das Gyrosignal auf, ein konstanter Bias akkumuliert dadurch über die Zeit zu einem wachsenden Orientierungsfehler; die aktuelle Formel nutzt Gyro nur als unintegrierte Magnitude pro Sample, ein konstanter Bias schlägt sich dort nur als kleiner, konstanter Offset nieder, nicht als wachsender Fehler). Das ist ein in der AHRS-Literatur bekanntes Verhalten von Komplementärfiltern, war in Dokument 04 aber noch nicht geprüft.

**Parameter-Sweep (α von 0,01 bis 0,2, Trust-Bandbreite von 1,0 bis 2,5), worst-case über alle 4 Szenarien gleichzeitig:** Das robusteste gefundene Setting (α=0,2 statt der ursprünglich vorgeschlagenen 0,02 – 10× höher) erreicht einen worst-case von 0,095, was mit der aktuell deployten Formel (0,091–0,098) ungefähr gleichauf liegt, sie in 2 von 4 Szenarien knapp schlägt und in 2 von 4 knapp verliert – **ein Unentschieden, kein klarer Sieg**. Wichtiger Vorbehalt dazu: α=0,2 bedeutet, dass die Gravitationsschätzung zu 20 % pro Sample Richtung Accelerometer-Messwert korrigiert wird statt zu 2 % – der Filter verhält sich damit kaum noch wie eine gyro-dominierte Integration, sondern eher wie ein schnell reagierender, akzelerometerlastiger Schätzer. Das könnte genau die theoretische Robustheit während dynamischer Bewegung untergraben, die der Komplementärfilteransatz eigentlich bieten sollte – das hier verwendete Pause/Peak-Verhältnis prüft das nicht direkt (es misst nur Ruhe- vs. Bewegungstrennung, nicht Qualität/Verzögerung der Peak-Form selbst).

### Einordnung nach ADR-019s eigener Vorgabe

ADR-019 legt fest: *"Bleibt der Komplementärfilter dort schlechter oder gleichauf, ist die einfachere, bereits deployte Lösung vorzuziehen."* Nach dieser Prüfung: mit den ursprünglich vorgeschlagenen Parametern ist der Komplementärfilter unter realistischeren Bedingungen eindeutig schlechter (0,26–0,27 vs. 0,10). Selbst mit aggressivem Tuning (α=0,2) wird bestenfalls ein Unentschieden erreicht, bei mutmaßlichem Verlust der theoretischen Robustheits-Begründung, die die ADR ursprünglich motiviert hat. **Empfehlung: Phase 3 (Dart-Portierung der Gravitationskompensation) auf Basis des aktuellen Erkenntnisstands NICHT beginnen.** Die bereits deployte, einfachere Formel bleibt die besser belegte Wahl. Das ist weiterhin ausschließlich synthetisch – siehe unten.

### Was auch dieser Test *nicht* zeigt (Einschränkungen bleiben, wie in Skript 1 benannt)

Weiterhin kein echtes Sensorrauschen, keine unsaubere Mehrachsen-Rotation, keine Validierung der Achsenzuordnung, keine Aussage über die volle Zähl-Pipeline. Die 4°/3°-Annahmen sind Schätzungen, keine Messungen. Der eigentliche, in Dokument 07 als Szene F/G beschriebene Praxistest mit echten CSV-Daten aus der App steht weiterhin aus – **und ist damit Voraussetzung für eine wirklich belastbare Phase-2-Entscheidung, nicht nur ein "nice-to-have".**

---

## Skript 2: Regressionstest für den Kalibrierungs-Bug (ADR-020)

Ergänzend zum DSP-Vergleich muss die Python-Simulation um den in ADR-020 beschriebenen Fall erweitert werden. Skelett (an die tatsächliche Struktur von `tools/workout_engine_simulation.py` anzupassen, dort existierende Klassen wiederverwenden, nicht duplizieren):

```python
def test_guided_calibration_threshold_persists():
    """Regressionstest fuer ADR-020: Der aus 10 Reps ermittelte Schwellenwert
    darf sich nach Abschluss der Guided Calibration NICHT mehr aendern,
    auch wenn danach weitere Reps ausgefuehrt werden."""
    sim = WorkoutEngineSim(exercise_id="bicep_curl")
    sim.start_guided_calibration(target_reps=10)
    for _ in range(10):
        feed_synthetic_rep(sim, peak_magnitude=1.3)  # Hilfsfunktion, an echtes API anpassen
    threshold_after_calibration = sim.peak_threshold

    feed_synthetic_rep(sim, peak_magnitude=1.3)  # ein weiterer, normaler Rep

    assert sim.peak_threshold == threshold_after_calibration, (
        f"Schwellenwert hat sich veraendert: "
        f"{threshold_after_calibration} -> {sim.peak_threshold}. "
        f"Das deutet auf den in ADR-020 beschriebenen Bug hin."
    )
```

Dieser Test muss **vor** der Implementierung des Fixes fehlschlagen (das bestätigt, dass der Test den Bug tatsächlich erkennt) und danach dauerhaft grün bleiben.

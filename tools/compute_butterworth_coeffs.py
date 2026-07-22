#!/usr/bin/env python3
"""
Berechnet exakte Butterworth-Bandpass-Koeffizienten fuer FlowRep.
Ausgabe: Dart-kompatible Koeffizienten als Second-Order Sections (SOS).

Verwendung: python3 tools/compute_butterworth_coeffs.py
"""
import numpy as np
from scipy.signal import butter, sosfreqz

# === PARAMETER (NICHT AENDERN) ===
FS = 50.0        # Abtastrate in Hz (M5StickC Plus2 IMU)
F_LOW = 0.3      # Untere Grenzfrequenz (Hz) - unterhalb: Drift/Gravitation
F_HIGH = 5.0     # Obere Grenzfrequenz (Hz) - oberhalb: Handzittern/Stoesse
ORDER = 4        # Gesamtordnung (ergibt 4 Biquad-Sektionen)

# === BERECHNUNG ===
sos = butter(ORDER, [F_LOW, F_HIGH], btype='band', fs=FS, output='sos')

print(f"// Butterworth Bandpass: {F_LOW}-{F_HIGH} Hz, Ordnung {ORDER}, fs={FS} Hz")
print(f"// {len(sos)} Biquad-Sektionen (Second-Order Sections)")
print(f"// Generiert von scipy.signal.butter — NICHT manuell aendern!")
print()

for i, section in enumerate(sos):
    b0, b1, b2, a0, a1, a2 = section
    assert abs(a0 - 1.0) < 1e-10, f"a0 != 1.0 in Sektion {i}: {a0}"
    print(f"// Sektion {i + 1}:")
    print(f"static const double _b0_s{i + 1} = {b0:.15e};")
    print(f"static const double _b1_s{i + 1} = {b1:.15e};")
    print(f"static const double _b2_s{i + 1} = {b2:.15e};")
    print(f"static const double _a1_s{i + 1} = {a1:.15e};")
    print(f"static const double _a2_s{i + 1} = {a2:.15e};")
    print()

# === VERIFIKATION ===
w, h = sosfreqz(sos, worN=8192, fs=FS)
h_db = 20 * np.log10(np.abs(h) + 1e-20)

idx_2hz = np.argmin(np.abs(w - 2.0))
gain_2hz = h_db[idx_2hz]
assert -1.0 < gain_2hz < 1.0, f"FEHLER: Verstaerkung bei 2Hz = {gain_2hz:.2f} dB (erwartet ~0 dB)"

idx_005 = np.argmin(np.abs(w - 0.05))
gain_005 = h_db[idx_005]
assert gain_005 < -40.0, f"FEHLER: Verstaerkung bei 0.05Hz = {gain_005:.2f} dB (erwartet < -40 dB)"

idx_20 = np.argmin(np.abs(w - 20.0))
gain_20 = h_db[idx_20]
assert gain_20 < -40.0, f"FEHLER: Verstaerkung bei 20Hz = {gain_20:.2f} dB (erwartet < -40 dB)"

print("// === VERIFIKATION BESTANDEN ===")
print(f"// 2 Hz:    {gain_2hz:.2f} dB (erwartet: ~0 dB)")
print(f"// 0.05 Hz: {gain_005:.2f} dB (erwartet: < -40 dB)")
print(f"// 20 Hz:   {gain_20:.2f} dB (erwartet: < -40 dB)")

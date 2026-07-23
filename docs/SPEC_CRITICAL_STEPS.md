# FlowRep — Kritische Implementierungsschritte (Detaillierte Anweisungen)

> **Zweck**: Dieses Dokument erweitert die 5 schwierigsten und fehleranfälligsten
> Implementierungsschritte aus der Spezifikation mit vollständigen,
> interpretationsfreien Anweisungen.
>
> **Regel**: Jeder Schritt ist exakt beschrieben. Keine Abweichungen. Keine Eigeninterpretation.

---

## STATUS-MATRIX (aktualisiert)

> **WICHTIG**: Dieses Dokument ist teilweise historisch. Der Code ist maßgeblich.
> Zukünftige Agents: NICHTS erneut implementieren — nur als Referenz lesen.

| Schritt | Thema | Status | Abweichung |
|---------|-------|--------|------------|
| 1 | Butterworth Bandpass | ✅ Erledigt | 0.1–5 Hz (nicht 0.3); 4 Sektionen; Koeff. via scipy |
| 2 | JitterBuffer | ✅ Erledigt | Generisch `JitterBuffer<T>`, 6 Samples, Underrun-Metriken ergänzt |
| 3 | WorkoutEngine Facade | ✅ Erledigt | Feature-Flag `_useNewPipeline=false`, Shadow-Mode ergänzt |
| 4 | RepCounter Pipeline | ✅ Erledigt | Peak auf smoothedGp (signiert), nicht Envelope |
| 5 | ExerciseEngine Integration | ✅ Erledigt | SignalChain→RepCounter→StateMachine, isSettled=250 |

**Bewusst offen** (erfordert Hardware-Validierung):
- `_useNewPipeline = true` setzen (nach Shadow-Mode mit echten CSV-Daten)
- Legacy-Code löschen (nach Gate)
- Template end-to-end verdrahten (ExerciseProfile → ExerciseEngine.setTemplate)

---

## KRITISCHER SCHRITT 1: Butterworth Bandpass Filter (P1-02)

### Warum kritisch?
- Falsche Koeffizienten → Filter oszilliert oder dämpft alles → gesamte Pipeline unbrauchbar
- Falsche Sektionsreihenfolge → DC-Offset bleibt im Signal → Peaks werden falsch erkannt
- Direct Form I statt II Transposed → numerische Instabilität bei 50Hz → Filter divergiert

### Vorbedingungen
- Python 3.x mit `scipy` und `numpy` installiert
- Projektordner `flowrep/tools/` existiert (ggf. erstellen)

### Schritt 1.1: Python-Script erstellen

**Datei**: `flowrep/tools/compute_butterworth_coeffs.py`

**Exakter Inhalt** (Zeile für Zeile):

```python
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
# butter() mit output='sos' liefert Second-Order Sections
# Jede Sektion: [b0, b1, b2, a0, a1, a2] mit a0 immer = 1.0 (normalisiert)
sos = butter(ORDER, [F_LOW, F_HIGH], btype='band', fs=FS, output='sos')

print(f"// Butterworth Bandpass: {F_LOW}-{F_HIGH} Hz, Ordnung {ORDER}, fs={FS} Hz")
print(f"// {len(sos)} Biquad-Sektionen (Second-Order Sections)")
print(f"// Generiert von scipy.signal.butter — NICHT manuell aendern!")
print()

for i, section in enumerate(sos):
    b0, b1, b2, a0, a1, a2 = section
    # a0 sollte immer 1.0 sein (scipy normalisiert automatisch)
    assert abs(a0 - 1.0) < 1e-10, f"a0 != 1.0 in Sektion {i}: {a0}"
    print(f"// Sektion {i + 1}:")
    print(f"static const double _b0_s{i + 1} = {b0:.15e};")
    print(f"static const double _b1_s{i + 1} = {b1:.15e};")
    print(f"static const double _b2_s{i + 1} = {b2:.15e};")
    print(f"static const double _a1_s{i + 1} = {a1:.15e};")
    print(f"static const double _a2_s{i + 1} = {a2:.15e};")
    print()

# === VERIFIKATION ===
# Frequenzgang an kritischen Punkten pruefen
w, h = sosfreqz(sos, worN=8192, fs=FS)
h_db = 20 * np.log10(np.abs(h) + 1e-20)

# Bei 2 Hz (mitten im Band): sollte ~0 dB sein
idx_2hz = np.argmin(np.abs(w - 2.0))
gain_2hz = h_db[idx_2hz]
assert -1.0 < gain_2hz < 1.0, f"FEHLER: Verstaerkung bei 2Hz = {gain_2hz:.2f} dB (erwartet ~0 dB)"

# Bei 0.05 Hz (weit unterhalb): sollte < -40 dB sein
idx_005 = np.argmin(np.abs(w - 0.05))
gain_005 = h_db[idx_005]
assert gain_005 < -40.0, f"FEHLER: Verstaerkung bei 0.05Hz = {gain_005:.2f} dB (erwartet < -40 dB)"

# Bei 20 Hz (weit oberhalb): sollte < -40 dB sein
idx_20 = np.argmin(np.abs(w - 20.0))
gain_20 = h_db[idx_20]
assert gain_20 < -40.0, f"FEHLER: Verstaerkung bei 20Hz = {gain_20:.2f} dB (erwartet < -40 dB)"

print("// === VERIFIKATION BESTANDEN ===")
print(f"// 2 Hz:  {gain_2hz:.2f} dB (erwartet: ~0 dB)")
print(f"// 0.05 Hz: {gain_005:.2f} dB (erwartet: < -40 dB)")
print(f"// 20 Hz: {gain_20:.2f} dB (erwartet: < -40 dB)")
```

### Schritt 1.2: Script ausführen und Ausgabe kopieren

```bash
cd flowrep
python3 tools/compute_butterworth_coeffs.py
```

**Erwartete Ausgabe**: 4 Sektionen mit je 5 Koeffizienten + Verifikationsmeldung.
**FEHLERFALL**: Wenn `assert` fehlschlägt → scipy-Version zu alt → `pip install --upgrade scipy`

### Schritt 1.3: Dart-Datei erstellen

**Datei**: `app/lib/domain/filters/butterworth.dart`

**Exakte Struktur** (in dieser Reihenfolge):

```dart
/// Kausaler Butterworth-Bandpassfilter 4. Ordnung.
///
/// Entfernt Frequenzen unterhalb [lowCutoffHz] (Drift, Gravitation)
/// und oberhalb [highCutoffHz] (Handzittern, Stöße).
///
/// Implementierung als kaskadierte Biquad-Sektionen (Direct Form II Transposed)
/// für numerische Stabilität bei 50 Hz Abtastrate.
///
/// Koeffizienten generiert von: tools/compute_butterworth_coeffs.py
/// NICHT manuell ändern!
library;

import 'dart:math' as math;

/// Interne Biquad-Sektion (2. Ordnung, Direct Form II Transposed).
class _BiquadSection {
  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  double _z1 = 0.0; // Zustandsvariable 1
  double _z2 = 0.0; // Zustandsvariable 2

  _BiquadSection({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });

  /// Verarbeitet EIN Sample. Direct Form II Transposed.
  ///
  /// Formeln (exakt so implementieren, NICHT umstellen):
  ///   y  = b0 * x + z1
  ///   z1 = b1 * x - a1 * y + z2
  ///   z2 = b2 * x - a2 * y
  double process(double x) {
    final y = b0 * x + _z1;
    _z1 = b1 * x - a1 * y + _z2;
    _z2 = b2 * x - a2 * y;
    return y;
  }

  void reset() {
    _z1 = 0.0;
    _z2 = 0.0;
  }
}

/// Butterworth-Bandpassfilter für IMU-Signalverarbeitung.
///
/// Standardparameter: 0.1–5.0 Hz bei 50 Hz Abtastrate, 4. Ordnung.
class ButterworthBandpass {
  // === KOEFFIZIENTEN ===
  // HIER die exakten Werte aus dem Python-Script-Output einsetzen!
  // Format: static const double _b0_s1 = <WERT AUS PYTHON>;
  //
  // WICHTIG: Die Reihenfolge der Sektionen ist KRITISCH.
  // scipy.signal.butter mit output='sos' liefert Sektionen in der
  // korrekten Reihenfolge. Diese Reihenfolge BEIBEHALTEN.
  // NICHT umsortieren (z.B. nicht "erst alle Highpass, dann alle Lowpass")!

  // [HIER: Koeffizienten aus Python-Output einfügen]
  // Beispiel (WERTE ERSETZEN mit tatsächlichem Output):
  // static const double _b0_s1 = 2.067344426597812e-03;
  // static const double _b1_s1 = 0.000000000000000e+00;
  // ...

  final List<_BiquadSection> _sections;
  int _sampleCount = 0;

  /// Erstellt den Bandpassfilter.
  ///
  /// [sampleRateHz] muss 50.0 sein (M5StickC Plus2 IMU-Rate).
  /// Andere Werte erfordern Neuberechnung der Koeffizienten!
  ButterworthBandpass({
    double sampleRateHz = 50.0,
    double lowCutoffHz = 0.3,
    double highCutoffHz = 5.0,
    int order = 4,
  }) : _sections = _buildSections() {
    // Parameter-Validierung (nur Debug-Hinweis, keine Exception)
    assert(sampleRateHz == 50.0,
        'Koeffizienten sind nur für 50 Hz gültig!');
  }

  /// Erstellt die 4 Biquad-Sektionen mit den vorgegebenen Koeffizienten.
  static List<_BiquadSection> _buildSections() {
    return [
      // Sektion 1 (Werte aus Python-Output):
      _BiquadSection(b0: 0, b1: 0, b2: 0, a1: 0, a2: 0), // ERSETZEN
      // Sektion 2:
      _BiquadSection(b0: 0, b1: 0, b2: 0, a1: 0, a2: 0), // ERSETZEN
      // Sektion 3:
      _BiquadSection(b0: 0, b1: 0, b2: 0, a1: 0, a2: 0), // ERSETZEN
      // Sektion 4:
      _BiquadSection(b0: 0, b1: 0, b2: 0, a1: 0, a2: 0), // ERSETZEN
    ];
  }

  /// Verarbeitet EIN Sample durch alle 4 Sektionen.
  ///
  /// NaN-Schutz: Bei NaN-Eingabe wird 0.0 zurückgegeben.
  /// Infinity-Schutz: Bei ±Infinity wird auf ±1e6 geclipped.
  double process(double input) {
    // NaN-Schutz
    if (input.isNaN) return 0.0;

    // Infinity-Schutz (verhindert Filter-Divergenz)
    if (input.isInfinite) {
      input = input > 0 ? 1e6 : -1e6;
    }

    // Kaskade: Ausgabe jeder Sektion ist Eingabe der nächsten
    var x = input;
    for (final section in _sections) {
      x = section.process(x);
    }

    _sampleCount++;
    return x;
  }

  /// Setzt alle internen Zustände zurück.
  ///
  /// AUFRUFEN BEI:
  /// - Neue Trainingssession
  /// - BLE-Reconnect
  /// - Übungswechsel
  /// - Nach Kalibrierung
  void reset() {
    for (final section in _sections) {
      section.reset();
    }
    _sampleCount = 0;
  }

  /// Anzahl der seit dem letzten reset() verarbeiteten Samples.
  int get sampleCount => _sampleCount;

  /// true, wenn der Filter eingeschwungen ist.
  ///
  /// Vor dem Einschwingen (sampleCount <= 16) sind die Ausgabewerte
  /// unzuverlässig und sollten NICHT für Peak-Detection verwendet werden.
  /// 16 Samples = 320ms bei 50 Hz.
  bool get isSettled => _sampleCount > 16;
}
```

### Schritt 1.4: Koeffizienten einsetzen

**KRITISCH**: Die Platzhalter `_BiquadSection(b0: 0, ...)` MÜSSEN mit den exakten Werten aus dem Python-Output ersetzt werden.

**So geht's**:
1. Python-Script ausführen
2. Für jede Sektion die 5 Werte (b0, b1, b2, a1, a2) ablesen
3. In `_buildSections()` einsetzen
4. `a0` wird NICHT benötigt (ist immer 1.0, scipy normalisiert)

### Schritt 1.5: Verifikation

```bash
cd app
flutter analyze lib/domain/filters/butterworth.dart
flutter test test/filters/butterworth_test.dart
```

### Stolperfallen

| # | Fehler | Symptom | Vermeidung |
|---|--------|---------|-----------|
| 1 | Koeffizienten aus Spezifikation (Näherung) statt Python-Output | Filter dämpft zu stark oder oszilliert | IMMER Python-Script ausführen |
| 2 | Sektionen umsortiert | DC-Offset bleibt, Peaks verschoben | Reihenfolge aus scipy BEIBEHALTEN |
| 3 | Direct Form I statt II Transposed | Filter divergiert nach ~1000 Samples | Exakt die 3 Formeln aus dem Code verwenden |
| 4 | `a0` nicht durch 1.0 ersetzt | Koeffizienten falsch | scipy normalisiert automatisch, a0 immer 1.0 |
| 5 | Kein NaN-Schutz | Ein NaN → alle folgenden Ausgaben NaN | `if (input.isNaN) return 0.0` als ERSTE Zeile |
| 6 | Kein reset() bei Session-Wechsel | Alte Transiente verfälschen neue Messung | reset() in SignalChain.reset() aufrufen |

---

## KRITISCHER SCHRITT 2: PeakDetector mit Pan-Tompkins (P2-01)

### Warum kritisch?
- Die adaptive Schwelle ist der Kern der Rep-Erkennung
- Falsche SPK/NPK-Initialisierung → erste 5-10 Reps werden nicht erkannt
- Fehlender Refractory → Doppelzählung bei jeder Rep
- Falsche Falling-Edge-Erkennung → Peaks werden zu früh oder zu spät bestätigt

### Vorbedingungen
- `ProcessedFrame` existiert (aus P1-09)
- `PeakEvent` Datenklasse definiert

### Schritt 2.1: Zustandsmaschine des PeakDetectors

Der PeakDetector hat intern 3 Zustände:

```
┌─────────┐    smoothed > θ     ┌──────────┐    smoothed < θ*ratio    ┌──────────┐
│  IDLE   │ ──────────────────→ │ RISING   │ ──────────────────────→  │ FALLING  │
│(wartet) │                     │(trackt   │                          │(debounce)│
└─────────┘                     │ Maximum) │                          └────┬─────┘
     ↑                          └──────────┘                               │
     │                           ↑                                         │
     │                           │ smoothed steigt                         │ debounce
     │                           │ wieder an                               │ erreicht
     │                           └─────────────────────────────────────────┘
     │                                                                     │
     └──────────────────── Peak bestätigt oder verworfen ──────────────────┘
```

### Schritt 2.2: Vollständige Implementierungslogik

```dart
/// Datei: app/lib/domain/detection/peak_detector.dart

// Interne Zustände
enum _DetectorState { idle, rising, falling }

class PeakDetector {
  // === KONFIGURATION (aus Konstruktor) ===
  final double _sampleRateHz;
  final double _thresholdFactor;   // 0.25
  final double _fallingRatio;      // 0.5
  final int _fallingDebounce;      // 4 Samples
  final Duration _refractory;      // 500ms
  final double _prominenceRatio;   // 0.2

  // === ADAPTIVE SCHWELLE (Pan-Tompkins) ===
  double _spk;  // Signal-Peak-Level (EMA bestätigter Peaks)
  double _npk;  // Noise-Peak-Level (EMA abgelehnter Peaks)

  // === ZUSTAND ===
  _DetectorState _state = _DetectorState.idle;
  double _currentMax = 0.0;        // Maximum der aktuellen Excursion
  double _currentMin = double.maxFinite; // Minimum VOR der Excursion
  int _excursionStartIndex = 0;    // Sample-Index bei Rising Edge
  int _fallingCount = 0;           // Debounce-Zähler für Falling Edge
  final List<double> _window = []; // Signalverlauf der Excursion
  int _sampleIndex = 0;            // Globaler Sample-Zähler
  DateTime? _lastPeakAt;           // Für Refractory

  // === KONSTRUKTOR ===
  PeakDetector({
    required double sampleRateHz,
    double initialSpk = 100.0,
    double initialNpk = 10.0,
    double thresholdFactor = 0.25,
    double fallingRatio = 0.5,
    int fallingDebounce = 4,
    double refractorySeconds = 0.5,
    double prominenceRatio = 0.2,
  })  : _sampleRateHz = sampleRateHz,
        _spk = initialSpk,
        _npk = initialNpk,
        _thresholdFactor = thresholdFactor,
        _fallingRatio = fallingRatio,
        _fallingDebounce = fallingDebounce,
        _refractory = Duration(milliseconds: (refractorySeconds * 1000).round()),
        _prominenceRatio = prominenceRatio;

  /// Aktuelle adaptive Schwelle.
  double get currentThreshold => _npk + _thresholdFactor * (_spk - _npk);

  /// Verarbeitet EIN Frame. Gibt PeakEvent zurück wenn Peak bestätigt.
  PeakEvent? process(ProcessedFrame frame) {
    _sampleIndex++;
    final value = frame.gpSmoothed; // Das geglättete g_p-Signal

    // NaN-Schutz
    if (value.isNaN) return null;

    final theta = currentThreshold;

    switch (_state) {
      case _DetectorState.idle:
        // Warte auf Rising Edge
        if (value > theta && !_inRefractory(frame.timestamp)) {
          _state = _DetectorState.rising;
          _currentMax = value;
          _excursionStartIndex = _sampleIndex;
          _window.clear();
          _window.add(value);
          // _currentMin wurde VOR der Excursion getrackt
        } else {
          // Tracke Minimum für Prominenz-Berechnung
          if (value < _currentMin) {
            _currentMin = value;
          }
        }
        break;

      case _DetectorState.rising:
        _window.add(value);
        if (value > _currentMax) {
          _currentMax = value;
          _fallingCount = 0; // Reset bei neuem Maximum
        }
        // Prüfe Falling Edge
        if (value < theta * _fallingRatio) {
          _state = _DetectorState.falling;
          _fallingCount = 1;
        }
        break;

      case _DetectorState.falling:
        _window.add(value);
        if (value > _currentMax) {
          // Doch kein Falling — zurück zu Rising
          _state = _DetectorState.rising;
          _currentMax = value;
          _fallingCount = 0;
        } else {
          _fallingCount++;
          if (_fallingCount >= _fallingDebounce) {
            // Falling Edge bestätigt → Peak-Kandidat auswerten
            final result = _evaluatePeak(frame.timestamp);
            _state = _DetectorState.idle;
            _currentMin = value; // Neues Minimum für nächste Excursion
            return result;
          }
        }
        break;
    }
    return null;
  }

  /// Wertet einen Peak-Kandidaten aus.
  PeakEvent? _evaluatePeak(DateTime timestamp) {
    final prominence = _currentMax - _currentMin;
    final minProminence = _spk * _prominenceRatio;

    if (prominence >= minProminence) {
      // Peak bestätigt → SPK aktualisieren
      _spk = 0.125 * _currentMax + 0.875 * _spk;
      _lastPeakAt = timestamp;

      return PeakEvent(
        sampleIndex: _sampleIndex,
        timestamp: timestamp,
        peakValue: _currentMax,
        precedingValley: _currentMin,
        prominence: prominence,
        durationSamples: _window.length,
        window: List<double>.from(_window), // Kopie!
      );
    } else {
      // Peak verworfen → NPK aktualisieren
      _npk = 0.125 * _currentMax + 0.875 * _npk;
      return null;
    }
  }

  /// Refractory-Prüfung (zeitbasiert).
  bool _inRefractory(DateTime now) {
    if (_lastPeakAt == null) return false;
    return now.difference(_lastPeakAt!) < _refractory;
  }

  void reset() {
    _state = _DetectorState.idle;
    _currentMax = 0.0;
    _currentMin = double.maxFinite;
    _fallingCount = 0;
    _window.clear();
    _sampleIndex = 0;
    _lastPeakAt = null;
    // SPK/NPK NICHT resetten (werden aus Profil geladen)
  }
}
```

### Schritt 2.3: Stolperfallen

| # | Fehler | Symptom | Vermeidung |
|---|--------|---------|-----------|
| 1 | `_currentMin` nicht VOR der Excursion tracken | Prominenz immer 0 | Minimum nur im `idle`-Zustand aktualisieren |
| 2 | `_window` nicht kopieren bei PeakEvent | Template-Matcher sieht leeres Window | `List<double>.from(_window)` |
| 3 | Refractory sample-basiert statt zeitbasiert | Doppelzählung bei variablem BLE-Timing | `DateTime.difference()` verwenden |
| 4 | SPK/NPK in reset() auf 0 setzen | Erste Reps nach Reconnect werden nicht erkannt | SPK/NPK nur aus Profil laden, nicht resetten |
| 5 | `_fallingDebounce` zu niedrig (1-2) | Rauschen erzeugt falsche Peaks | Mindestens 4 Samples (80ms) |
| 6 | Kein NaN-Schutz auf `frame.gpSmoothed` | Ein NaN → State Machine hängt | Erste Zeile: `if (value.isNaN) return null` |

---

## KRITISCHER SCHRITT 3: WorkoutEngine Facade Rewrite (P3-03)

### Warum kritisch?
- Die WorkoutEngine ist 1029 Zeilen und wird von HomeScreen, CalibrationWizard und Tests aufgerufen
- Ein Fehler bricht ALLE bestehenden Tests
- Die öffentliche API MUSS identisch bleiben

### Vorbedingungen
- Alle Phase-2-Klassen existieren und sind getestet
- Bestehende Tests laufen grün VOR dem Rewrite

### Schritt 3.1: Strategie (Facade-Pattern)

**REGEL**: Die öffentliche API von WorkoutEngine ändert sich NICHT.

```
VORHER:
  HomeScreen → WorkoutEngine.processSample(s) → [1029 Zeilen interne Logik]

NACHHER:
  HomeScreen → WorkoutEngine.processSample(s) → SignalChain → RepCounter → StateMachine
                                                  (delegiert, gleiche API)
```

### Schritt 3.2: Exakte Vorgehensweise

**SCHRITT A**: Bestehende Tests laufen lassen und Ergebnis dokumentieren
```bash
cd app
flutter test > test_results_before.txt 2>&1
```

**SCHRITT B**: Neue interne Felder hinzufügen (NICHTS löschen!)
```dart
// Am Anfang von WorkoutEngine, NEBEN den bestehenden Feldern:
late final SignalChain _signalChain;
late final RepCounter _repCounter;
late final WorkoutStateMachine _stateMachine;
bool _useNewPipeline = false; // Feature-Flag!
```

**SCHRITT C**: Im Konstruktor initialisieren
```dart
// Am ENDE des bestehenden Konstruktors:
_signalChain = SignalChain(
  gpProjection: GpProjection(rotationAxis: [1,0,0], gyroBias: [0,0,0]),
  bandpass: ButterworthBandpass(),
  oneEuro: OneEuroFilter(sampleRateHz: 50.0),
  envelope: EnvelopeDetector(sampleRateHz: 50.0),
);
_repCounter = RepCounter(
  peakDetector: PeakDetector(sampleRateHz: 50.0),
  templateMatcher: TemplateMatcher(),
  phaseValidator: PhaseValidator(),
  qualityScorer: QualityScorer(),
);
_stateMachine = WorkoutStateMachine(hasValidCalibration: hasValidCalibration);
```

**SCHRITT D**: processSample() erweitern (NICHT ersetzen!)
```dart
void processSample(SensorSample s) {
  // BESTEHENDER CODE bleibt (für _useNewPipeline == false)
  if (!_useNewPipeline) {
    _processSampleLegacy(s); // Umbenannter alter Code
    return;
  }

  // NEUER PFAD
  final frame = _signalChain.process(s);
  final rep = _repCounter.processFrame(frame);
  if (rep != null) {
    _stateMachine.handleEvent(RepCounted(rep: rep));
    _repsInSet.add(Rep(timestamp: rep.timestamp, peakMagnitude: rep.peakMagnitude));
    _emitStateEvent();
  }
  _checkPauseTimeout(s.timestamp);
}
```

**SCHRITT E**: Alten Code in `_processSampleLegacy()` umbenennen
- Alle bestehenden privaten Methoden bleiben
- Werden nur von `_processSampleLegacy()` aufgerufen
- KEINE Löschung in diesem Schritt!

**SCHRITT F**: Feature-Flag aktivieren
```dart
// In applyCalibration() oder nach erfolgreicher Kalibrierung:
_useNewPipeline = true;
```

**SCHRITT G**: Tests laufen lassen
```bash
flutter test > test_results_after.txt 2>&1
diff test_results_before.txt test_results_after.txt
```

**SCHRITT H**: Erst wenn ALLE Tests grün sind → alten Code löschen

### Schritt 3.3: Stolperfallen

| # | Fehler | Symptom | Vermeidung |
|---|--------|---------|-----------|
| 1 | Alten Code sofort löschen | Tests brechen, kein Rollback möglich | Feature-Flag + Legacy-Pfad beibehalten |
| 2 | Öffentliche API ändern | HomeScreen kompiliert nicht | KEINE Änderung an öffentlichen Methoden |
| 3 | `events` Stream-Verhalten ändern | UI reagiert nicht mehr | Gleiche Events zur gleichen Zeit emittieren |
| 4 | CalibrationController nicht anbinden | Guided Calibration bricht | CalibrationController nutzt weiterhin WorkoutEngine-Callbacks |
| 5 | dispose() nicht erweitern | Memory Leak | `_signalChain.reset()` in dispose() aufrufen |

---

## KRITISCHER SCHRITT 4: JitterBuffer + SignalChain Integration (P1-09, P1-13)

### Warum kritisch?
- Timer-basierte Ausgabe erzeugt einen zweiten "Thread" (Dart Event Loop)
- Falsche Integration → Samples kommen doppelt oder fehlen
- SignalChain-Reihenfolge falsch → Filterergebnisse sinnlos

### Schritt 4.1: JitterBuffer — Exakte Timer-Logik

```dart
/// Datei: app/lib/data/providers/jitter_buffer.dart

import 'dart:async';

class JitterBuffer {
  final int _bufferSize;
  final Duration _outputInterval;
  final List<dynamic> _buffer = []; // SensorSample
  Timer? _outputTimer;
  bool _running = false;
  int _underrunCount = 0;

  JitterBuffer({
    int bufferSize = 6,
    Duration outputInterval = const Duration(milliseconds: 20),
  })  : _bufferSize = bufferSize,
        _outputInterval = outputInterval;

  /// Fügt einen Batch hinzu (von BLE empfangen, typisch 4 Samples).
  void addBatch(List<dynamic> samples) {
    if (!_running) return; // Nicht puffern wenn nicht gestartet
    _buffer.addAll(samples);
    // Überlauf-Schutz: älteste Samples verwerfen
    while (_buffer.length > _bufferSize) {
      _buffer.removeAt(0);
    }
  }

  /// Startet die periodische Ausgabe.
  ///
  /// WICHTIG: Nur EINMAL aufrufen. Bei erneutem Aufruf: erst stop().
  void start(void Function(dynamic) onSample) {
    if (_running) return; // Doppelstart verhindern
    _running = true;
    _outputTimer = Timer.periodic(_outputInterval, (_) {
      if (_buffer.isNotEmpty) {
        onSample(_buffer.removeAt(0));
      } else {
        _underrunCount++;
        // Kein Sample verfügbar — Timer tickt leer (erwartet bei Lücken)
      }
    });
  }

  void stop() {
    _outputTimer?.cancel();
    _outputTimer = null;
    _running = false;
  }

  int get pendingCount => _buffer.length;
  bool get isUnderrun => _underrunCount > 0;
  int get underrunCount => _underrunCount;

  void reset() {
    _buffer.clear();
    _underrunCount = 0;
  }

  void dispose() {
    stop();
    _buffer.clear();
  }
}
```

### Schritt 4.2: Integration in BleSensorProvider

**Exakte Änderung** in `ble_sensor_provider.dart`:

```dart
// NEUES FELD (neben bestehenden Feldern):
final JitterBuffer _jitterBuffer = JitterBuffer(bufferSize: 6);

// IN _startPolling(), NACH dem ersten erfolgreichen Read:
// VORHER:
//   for (final s in samples) { _sampleController.add(s); }
// NACHHER:
_jitterBuffer.addBatch(samples);

// NACH _startPolling() Setup (einmalig):
_jitterBuffer.start((sample) {
  if (!_sampleController.isClosed) {
    _sampleController.add(sample as SensorSample);
  }
});

// IN dispose():
_jitterBuffer.dispose();
```

### Schritt 4.3: SignalChain — Exakte Verarbeitungsreihenfolge

```dart
/// Datei: app/lib/domain/filters/signal_chain.dart

class SignalChain {
  final GpProjection _gpProjection;
  final ButterworthBandpass _bandpass;
  final OneEuroFilter _oneEuro;
  final EnvelopeDetector _envelope;
  int _frameIndex = 0;

  SignalChain({
    required GpProjection gpProjection,
    required ButterworthBandpass bandpass,
    required OneEuroFilter oneEuro,
    required EnvelopeDetector envelope,
  })  : _gpProjection = gpProjection,
        _bandpass = bandpass,
        _oneEuro = oneEuro,
        _envelope = envelope;

  /// Verarbeitet ein Roh-Sample durch die GESAMTE Kette.
  ///
  /// REIHENFOLGE (KRITISCH — NICHT ÄNDERN):
  /// 1. g_p Projektion (3D → 1D, signiert)
  /// 2. Butterworth Bandpass (0.1-5 Hz)
  /// 3. One Euro (adaptive Glättung)
  /// 4. Envelope (Hüllkurve für Diagnose)
  ProcessedFrame process(SensorSample sample) {
    _frameIndex++;

    // 1. g_p Projektion
    final gpRaw = _gpProjection.project(sample.gx, sample.gy, sample.gz);

    // 2. Butterworth Bandpass
    final gpBandpassed = _bandpass.process(gpRaw);

    // 3. One Euro Filter
    final gpSmoothed = _oneEuro.process(gpBandpassed);

    // 4. Envelope (für adaptive Schwelle / Diagnose)
    final envelopeValue = _envelope.process(gpSmoothed);

    return ProcessedFrame(
      timestamp: sample.timestamp,
      sampleIndex: _frameIndex,
      gx: sample.gx,
      gy: sample.gy,
      gz: sample.gz,
      gpRaw: gpRaw,
      gpBandpassed: gpBandpassed,
      gpSmoothed: gpSmoothed,
      envelope: envelopeValue,
      accelMagnitude: sample.accelMagnitude,
    );
  }

  void reset() {
    _bandpass.reset();
    _oneEuro.reset();
    _envelope.reset();
    _frameIndex = 0;
  }

  bool get isSettled => _bandpass.isSettled && _oneEuro.isInitialized;
}
```

### Schritt 4.4: Stolperfallen

| # | Fehler | Symptom | Vermeidung |
|---|--------|---------|-----------|
| 1 | JitterBuffer.start() mehrfach aufrufen | Doppelte Samples | `if (_running) return` Guard |
| 2 | `_sampleController.isClosed` nicht prüfen | Crash nach dispose() | Immer prüfen vor `.add()` |
| 3 | SignalChain-Reihenfolge falsch | Butterworth bekommt 3D-Vektor statt 1D | Exakt: GpProj → Butter → OneEuro → Envelope |
| 4 | GpProjection nicht mit Kalibrierungs-Achse initialisiert | g_p ist immer ~0 | Achse aus ExerciseProfile laden |
| 5 | Timer.periodic nicht cancelled | Memory Leak, Samples nach dispose() | `dispose()` ruft `stop()` |

---

## KRITISCHER SCHRITT 5: TemplateMatcher NCC (P2-03)

### Warum kritisch?
- Division durch Null bei std=0 (flaches Signal)
- Lineare Interpolation bei sehr kurzen Windows (< 10 Samples) erzeugt Artefakte
- Falsche Normalisierung → NCC immer ~0 → alle Reps abgelehnt

### Schritt 5.1: Vollständige Implementierungslogik

```dart
/// Datei: app/lib/domain/detection/template_matcher.dart

import 'dart:math' as math;

class TemplateMatcher {
  final double _correlationThreshold;
  final int _templateLength;
  List<double>? _template; // Normalisiert: mean=0, std=1

  TemplateMatcher({
    double correlationThreshold = 0.65,
    int templateLength = 64,
  })  : _correlationThreshold = correlationThreshold,
        _templateLength = templateLength;

  void setTemplate(List<double> template) {
    // Template muss bereits normalisiert sein (mean=0, std=1)
    // Wird von TemplateExtractor geliefert
    _template = List<double>.from(template); // Kopie
  }

  bool get hasTemplate => _template != null;

  /// Vergleicht ein Window mit dem Template.
  ///
  /// Rückgabe: MatchResult mit Korrelation und Akzeptanz.
  MatchResult match(List<double> window) {
    // FALL 1: Kein Template → immer akzeptieren (Fallback-Modus)
    if (_template == null) {
      return MatchResult(correlation: 1.0, accepted: true, shapeDeviation: 0.0);
    }

    // FALL 2: Window zu kurz → ablehnen
    if (window.length < 10) {
      return MatchResult(correlation: 0.0, accepted: false, shapeDeviation: 1.0);
    }

    // FALL 3: NaN im Window → ablehnen
    if (window.any((v) => v.isNaN)) {
      return MatchResult(correlation: 0.0, accepted: false, shapeDeviation: 1.0);
    }

    // SCHRITT 1: Resamplen auf Template-Länge
    final resampled = _resample(window, _templateLength);

    // SCHRITT 2: Normalisieren (mean=0, std=1)
    final mean = resampled.reduce((a, b) => a + b) / resampled.length;
    final variance = resampled.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / resampled.length;
    final std = math.sqrt(variance);

    // FALL 4: std ≈ 0 (flaches Signal) → ablehnen
    if (std < 1e-10) {
      return MatchResult(correlation: 0.0, accepted: false, shapeDeviation: 1.0);
    }

    final normalized = resampled.map((v) => (v - mean) / std).toList();

    // SCHRITT 3: Normalisierte Kreuzkorrelation
    var sum = 0.0;
    for (var i = 0; i < _templateLength; i++) {
      sum += _template![i] * normalized[i];
    }
    final ncc = sum / _templateLength;

    // SCHRITT 4: Bewerten
    final accepted = ncc > _correlationThreshold;
    return MatchResult(
      correlation: ncc,
      accepted: accepted,
      shapeDeviation: 1.0 - ncc.abs(),
    );
  }

  /// Lineare Interpolation: resampled [input] auf [targetLength] Werte.
  ///
  /// BEISPIEL: input=[0,10,20] (3 Werte), targetLength=5
  /// → output=[0, 5, 10, 15, 20]
  static List<double> _resample(List<double> input, int targetLength) {
    if (input.length == targetLength) return List<double>.from(input);

    final result = List<double>.filled(targetLength, 0.0);
    final ratio = (input.length - 1) / (targetLength - 1);

    for (var i = 0; i < targetLength; i++) {
      final srcPos = i * ratio;
      final srcIdx = srcPos.floor();
      final frac = srcPos - srcIdx;

      if (srcIdx + 1 < input.length) {
        result[i] = input[srcIdx] * (1.0 - frac) + input[srcIdx + 1] * frac;
      } else {
        result[i] = input[input.length - 1];
      }
    }
    return result;
  }

  void reset() {
    _template = null;
  }
}
```

### Schritt 5.2: Stolperfallen

| # | Fehler | Symptom | Vermeidung |
|---|--------|---------|-----------|
| 1 | Division durch std=0 | NaN/Infinity → alle folgenden Reps abgelehnt | `if (std < 1e-10) return rejected` |
| 2 | Resampling bei length=1 | Division durch 0 in `ratio` | `if (input.length < 2) return rejected` |
| 3 | Template nicht normalisiert | NCC immer ~0 | TemplateExtractor normalisiert VOR setTemplate() |
| 4 | Window-Referenz statt Kopie | Template-Matcher sieht veränderte Daten | `List.from()` bei PeakEvent.window |
| 5 | Threshold zu hoch (0.9) | Legitime Reps werden abgelehnt | Start bei 0.65, adaptiv steigerbar |

---

## KONTROLLPUNKTE (nach JEDEM kritischen Schritt)

```
□ flutter analyze — 0 Issues
□ flutter test — alle grün (bestehende + neue)
□ Keine Flutter-Imports in domain/ (nur dart:math, dart:async, dart:core)
□ DartDoc auf ALLEN öffentlichen Klassen und Methoden
□ Keine TODO-Kommentare ohne Ticket-Nummer
□ Keine Magic Numbers ohne benannte Konstante
□ reset() setzt ALLE internen Zustände zurück
□ NaN-Schutz auf ALLEN Eingabepfaden
□ Keine Division ohne Null-Check
□ List-Kopien wo nötig (keine shared mutable state)
```

---

*Ende der kritischen Implementierungsschritte.*

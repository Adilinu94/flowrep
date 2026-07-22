# FlowRep — Technische Spezifikation, Teil 2 (Teile 3–9)

> Fortsetzung von `SPEC_IMPLEMENTATION_BLUEPRINT.md` (Teile 1–2)

---

## TEIL 3 — Rep Counting Engine Rewrite

### 3.1 Zerlegung des WorkoutEngine God Objects

**Aktuell**: `workout_engine.dart` = 1029 Zeilen, enthält:
- State Machine (idle/calibrating/active/paused/guidedCalibration/connectionLost)
- Peak Detection (_detectPeak, _detectPeakSigned)
- Calibration Logic (startGuidedCalibration, _finishGuidedCalibration, _findPeaks...)
- Adaptive Threshold (_confirmedPeaks, adaptiveThresholdRatio)
- Set Management (_endSet, _repsInSet)
- Diagnostics (diagEngineSampleCount, diagMaxAccel...)
- Connection Handling (handleDisconnect, handleReconnect)
- Calibration Persistence (applyCalibration)

**Ziel**: Aufteilung in 7 eigenständige Klassen (siehe Diagramm in Part 1, Abschnitt 3.1).

### 3.2 Klasse: WorkoutStateMachine

**Datei**: `app/lib/domain/state/workout_state_machine.dart`

**Zweck**: Expliziter, deterministischer Zustandsautomat. Keine Signalverarbeitung — nur Zustandsübergänge basierend auf Events.

**Zustände**:
```dart
enum WorkoutState {
  idle,              // Kein Training aktiv
  calibrating,       // Auto-Kalibrierung (1 Rep, Legacy-Pfad)
  active,            // Reps werden gezählt
  resting,           // Pause zwischen Sätzen (Timer läuft)
  paused,            // Manuell pausiert
  guidedCalibration, // Guided Calibration 2.0 aktiv
  connectionLost,    // BLE verloren
}
```

**Events (Auslöser für Übergänge)**:
```dart
sealed class EngineEvent {}
class MovementDetected extends EngineEvent {}
class CalibrationRepComplete extends EngineEvent { final int repCount; }
class CalibrationComplete extends EngineEvent { final double threshold; }
class RepCounted extends EngineEvent { final RepEvent rep; }
class RestTimerExpired extends EngineEvent {}
class PauseTimeout extends EngineEvent { final Duration elapsed; }
class UserPaused extends EngineEvent {}
class UserResumed extends EngineEvent {}
class ConnectionLostEvent extends EngineEvent {}
class ConnectionRestored extends EngineEvent {}
class GuidedCalibrationStarted extends EngineEvent {}
class GuidedCalibrationFinished extends EngineEvent {}
```

**Übergangstabelle**:
```
┌─────────────────────┬──────────────────────────┬─────────────────────┐
│ Aktueller Zustand   │ Event                    │ Neuer Zustand       │
├─────────────────────┼──────────────────────────┼─────────────────────┤
│ idle                │ MovementDetected         │ calibrating*        │
│ idle                │ MovementDetected (kalib.)│ active              │
│ idle                │ GuidedCalibrationStarted │ guidedCalibration   │
│ calibrating         │ CalibrationRepComplete   │ active              │
│ active              │ RepCounted               │ active (bleibt)     │
│ active              │ PauseTimeout             │ resting             │
│ active              │ UserPaused               │ paused              │
│ active              │ ConnectionLostEvent      │ connectionLost      │
│ resting             │ MovementDetected         │ active              │
│ resting             │ RestTimerExpired         │ idle                │
│ paused              │ UserResumed              │ active              │
│ paused              │ MovementDetected         │ active              │
│ guidedCalibration   │ GuidedCalibrationFinished│ idle                │
│ connectionLost      │ ConnectionRestored       │ idle                │
└─────────────────────┴──────────────────────────┴─────────────────────┘
* calibrating nur wenn hasValidCalibration == false
```

**Öffentliche API**:
```dart
class WorkoutStateMachine {
  WorkoutStateMachine({
    required bool hasValidCalibration,
    Duration restTimeout = const Duration(seconds: 30),
    Duration pauseTimeout = const Duration(seconds: 4),
  });

  /// Verarbeitet ein Event. Gibt den neuen Zustand zurück.
  /// Wirft StateError bei ungültigem Übergang.
  WorkoutState handleEvent(EngineEvent event);

  /// Aktueller Zustand.
  WorkoutState get currentState;

  /// Zeitstempel des letzten Übergangs.
  DateTime get lastTransitionAt;

  /// Reset auf idle (bei Reconnect).
  void reset();
}
```

**Private Variablen**:
```dart
WorkoutState _state = WorkoutState.idle;
DateTime _lastTransitionAt = DateTime.now();
DateTime? _lastRepAt;  // für Pause-Timeout
final bool _hasValidCalibration;
final Duration _restTimeout;
final Duration _pauseTimeout;
```

### 3.3 Klasse: PeakDetector

**Datei**: `app/lib/domain/detection/peak_detector.dart`

**Zweck**: Erkennt Peaks im gefilterten g_p-Signal mittels adaptiver Schwelle (Pan-Tompkins-inspiriert). Ersetzt `_detectPeak()` und `_detectPeakSigned()` aus WorkoutEngine.

**Algorithmus (Pan-Tompkins adaptiv)**:
```
Zwei laufende Schwellen:
  SPK = Signal-Peak-Level (EMA der bestätigten Peaks)
  NPK = Noise-Peak-Level (EMA der abgelehnten Peaks)

Schwelle:
  θ = NPK + 0.25 * (SPK - NPK)

Pro Sample:
  WENN smoothed > θ UND nicht in Refractory:
    → Rising Edge (Excursion startet)
    → Tracke Maximum
  WENN smoothed < θ * fallingRatio:
    → Falling Edge (Excursion endet)
    → Peak-Kandidat erzeugen
    → WENN Prominenz ausreichend:
      → SPK aktualisieren: SPK = 0.125*peak + 0.875*SPK
      → PeakEvent emittieren
    → SONST:
      → NPK aktualisieren: NPK = 0.125*peak + 0.875*NPK
```

**Öffentliche API**:
```dart
class PeakDetector {
  PeakDetector({
    required double sampleRateHz,
    double initialSpk = 100.0,   // °/s, aus Kalibrierung
    double initialNpk = 10.0,    // °/s, aus Ruhephase
    double thresholdFactor = 0.25,
    double fallingRatio = 0.5,
    int fallingDebounce = 4,
    double refractorySeconds = 0.5,
    double prominenceRatio = 0.2,
  });

  /// Verarbeitet ein gefiltertes Sample.
  /// Rückgabe: PeakEvent wenn ein Peak bestätigt wurde, sonst null.
  PeakEvent? process(ProcessedFrame frame);

  /// Konfiguration aus ExerciseProfile laden.
  void configureFromProfile(ExerciseProfile profile);

  void reset();

  // Diagnose
  double get currentThreshold;
  double get spkLevel;
  double get npkLevel;
}
```

**PeakEvent (Datenobjekt)**:
```dart
class PeakEvent {
  final int sampleIndex;
  final DateTime timestamp;
  final double peakValue;       // Maximum der Excursion
  final double precedingValley;  // Minimum vor der Excursion
  final double prominence;       // peakValue - precedingValley
  final int durationSamples;     // Dauer der Excursion in Samples
  final List<double> window;     // Signalverlauf der Excursion (für Template)
}
```

**Refractory-Logik**:
```dart
// Zeitbasiert (nicht sample-basiert wie aktuell!)
final Duration _refractory;
DateTime? _lastPeakAt;

bool get _inRefractory {
  if (_lastPeakAt == null) return false;
  return DateTime.now().difference(_lastPeakAt!) < _refractory;
}
```

> **WICHTIG**: Die aktuelle Implementierung nutzt `minRepIntervalSamples` (sample-basiert).
> Die neue Implementierung nutzt `refractorySeconds` (zeitbasiert).
> Grund: Der JitterBuffer stellt ein ehrliches 20ms-Raster her.

### 3.4 Klasse: TemplateMatcher

**Datei**: `app/lib/domain/detection/template_matcher.dart`

**Zweck**: Vergleicht den Signalverlauf einer erkannten Excursion mit dem gelernten Rep-Template mittels normalisierter Kreuzkorrelation (NCC).

**Algorithmus (Normalisierte Kreuzkorrelation)**:
```
Gegeben:
  template[0..N-1]  (gelernt, normalisiert: mean=0, std=1)
  candidate[0..M-1] (aktuelle Excursion, M kann ≠ N sein)

Schritt 1: Candidate auf Template-Länge resamplen (lineare Interpolation)
  resampled[0..N-1] = interpolate(candidate, N)

Schritt 2: Normalisieren
  resampled_norm = (resampled - mean(resampled)) / std(resampled)

Schritt 3: Kreuzkorrelation
  NCC = Σ(template[i] * resampled_norm[i]) / N

Ergebnis:
  NCC ∈ [-1, 1]
  NCC > threshold (0.65) → Rep akzeptiert
  NCC ≤ threshold → Rep abgelehnt (falsche Bewegung)
```

**Öffentliche API**:
```dart
class TemplateMatcher {
  TemplateMatcher({
    double correlationThreshold = 0.65,
    int templateLength = 64,
  });

  void setTemplate(List<double> template);
  MatchResult match(List<double> window);
  bool get hasTemplate;
  void reset();
}
```

**MatchResult**:
```dart
class MatchResult {
  final double correlation;     // -1.0 bis 1.0
  final bool accepted;          // correlation > threshold
  final double shapeDeviation;  // 1.0 - |correlation|
}
```

**Laufzeit**: O(N) pro Match, N=64 → 64 MUL + 63 ADD + Resampling
**Speicher**: 64 doubles (Template) + 64 doubles (Resampled) = 1 KB

**Grenzfälle**:
- Kein Template gesetzt → `match()` gibt immer `accepted: true` (Fallback)
- Window kürzer als 10 Samples → `accepted: false`
- Window enthält NaN → `accepted: false`
- std(candidate) ≈ 0 → `accepted: false`

### 3.5 Klasse: PhaseValidator

**Datei**: `app/lib/domain/detection/phase_validator.dart`

**Zweck**: Prüft konzentrisch→exzentrische Phasenfolge via g_p-Vorzeichen.

**Logik**:
```
Für Bizeps-Curl (g_p > 0 = konzentrisch):
  1. g_p steigt über 0 → konzentrische Phase beginnt
  2. g_p erreicht Maximum → Umkehrpunkt
  3. g_p fällt unter 0 → exzentrische Phase beginnt
  4. g_p kehrt zu ≈0 zurück → Rep vollständig

Validierung:
  - hasConcentric: max(g_p_window) > concentricThreshold
  - hasEccentric: min(g_p_window) < eccentricThreshold
  - sequenceValid: Maximum VOR Minimum
  - durationRatio: eccentric/concentric ∈ [0.5, 3.0]
```

**Öffentliche API**:
```dart
class PhaseValidator {
  PhaseValidator({
    double concentricMinDegPerS = 20.0,
    double eccentricMinDegPerS = 10.0,
    double durationRatioMin = 0.5,
    double durationRatioMax = 3.0,
  });

  PhaseResult validate(List<double> gpWindow, {bool expectedPositiveFirst = true});
  void configureFromProfile(ExerciseProfile profile);
}
```

**PhaseResult**:
```dart
class PhaseResult {
  final bool hasConcentric;
  final bool hasEccentric;
  final bool sequenceValid;
  final double concentricDurationS;
  final double eccentricDurationS;
  final double durationRatio;
  final bool accepted;
}
```

### 3.6 Klasse: RepCounter (Orchestrator)

**Datei**: `app/lib/domain/counting/rep_counter.dart`

**Zweck**: Orchestriert PeakDetector → TemplateMatcher → PhaseValidator → QualityScorer.

**Öffentliche API**:
```dart
class RepCounter {
  RepCounter({
    required PeakDetector peakDetector,
    required TemplateMatcher templateMatcher,
    required PhaseValidator phaseValidator,
    required QualityScorer qualityScorer,
  });

  RepEvent? processFrame(ProcessedFrame frame);
  void configureFromProfile(ExerciseProfile profile);
  int get repsInCurrentSet;
  RepEvent? get lastRep;
  void resetSet();
  void reset();
}
```

**Interne Logik in processFrame()**:
```dart
RepEvent? processFrame(ProcessedFrame frame) {
  final peak = _peakDetector.process(frame);
  if (peak == null) return null;

  final match = _templateMatcher.match(peak.window);
  if (!match.accepted) return null;

  final phase = _phaseValidator.validate(peak.window);
  if (!phase.accepted) return null;

  final quality = _qualityScorer.score(
    correlation: match.correlation,
    phase: phase,
    peak: peak,
  );

  _repCount++;
  return RepEvent(
    repNumber: _repCount,
    quality: quality,
    timestamp: frame.timestamp,
    peakMagnitude: peak.peakValue,
    correlation: match.correlation,
    tempoSeconds: phase.concentricDurationS + phase.eccentricDurationS,
  );
}
```

### 3.7 Klasse: QualityScorer

**Datei**: `app/lib/domain/counting/quality_scorer.dart`

**Bewertungskriterien**:
```
Score = w1*correlationScore + w2*romScore + w3*tempoScore + w4*symmetryScore

Gewichte: w1=0.40, w2=0.25, w3=0.20, w4=0.15

correlationScore = correlation * 100
romScore = clamp(peakProminence / expectedProminence, 0, 1) * 100
tempoScore = 100 - |actualTempo - expectedTempo| / expectedTempo * 100
symmetryScore = 100 - |durationRatio - 1.0| * 50
```

**RepQuality (Datenobjekt)**:
```dart
class RepQuality {
  final double totalScore;        // 0.0 - 100.0
  final double correlationScore;
  final double romScore;
  final double tempoScore;
  final double symmetryScore;

  QualityLevel get level {
    if (totalScore >= 85) return QualityLevel.excellent;
    if (totalScore >= 70) return QualityLevel.good;
    if (totalScore >= 50) return QualityLevel.fair;
    return QualityLevel.poor;
  }
}

enum QualityLevel { excellent, good, fair, poor }
```

### 3.8 Klasse: OnlineAdapter

**Datei**: `app/lib/domain/counting/online_adapter.dart`

**Zweck**: Aktualisiert laufende Statistiken nach jeder bestätigten Rep.

```dart
class OnlineAdapter {
  OnlineAdapter({double emaAlpha = 0.1});

  void onRepConfirmed(RepEvent rep);
  double get adaptivePeakLevel;
  double get adaptiveInterval;
  double get adaptiveProminence;
  bool get isAdaptive;  // >= 3 Reps
  void reset();
}
```

### 3.9 WorkoutEngine als Facade (nach Rewrite)

**Was bleibt**: Klasse `WorkoutEngine`, `processSample()`, `events` Stream, `dispose()`

**Was entfernt wird**:
- `_detectPeak()`, `_detectPeakSigned()` → PeakDetector
- `_findPeaksWithIndices()`, `_medianFilter()` → CalibrationController
- Alle `_calibration*` Felder → CalibrationController
- Alle `_gp*` Felder → GpProjection + PeakDetector
- `_confirmedPeaks` → OnlineAdapter

**Neue interne Struktur** (~120 Zeilen):
```dart
class WorkoutEngine {
  WorkoutEngine({required this.exerciseId, ...})
    : _signalChain = SignalChain(...),
      _repCounter = RepCounter(...),
      _stateMachine = WorkoutStateMachine(...);

  void processSample(SensorSample s) {
    final frame = _signalChain.process(s);
    final rep = _repCounter.processFrame(frame);
    if (rep != null) {
      _stateMachine.handleEvent(RepCounted(rep: rep));
      _emitEvent(rep);
    }
    _checkPauseTimeout(s.timestamp);
  }
}
```

---

## TEIL 4 — Calibration System 2.0 Erweiterung

### 4.1 ExerciseProfile Erweiterung

**Neue Felder** (alle optional, bestehende Profile bleiben gültig):
```dart
// NEU: Template Matching
final List<double>? repTemplate;       // 64 Werte, normalisiert
final double templateCorrThreshold;    // Standard: 0.65

// NEU: ROM-Validierung
final double? expectedProminence;      // °/s
final double prominenceTolerance;      // Standard: 0.3

// NEU: Phasen-Modell
final double? concentricRatioExpected;
final double durationRatioMin;         // 0.5
final double durationRatioMax;         // 3.0

// NEU: Adaptive Parameter-Init
final double? initialSpk;
final double? initialNpk;
```

### 4.2 Klasse: TemplateExtractor

**Datei**: `app/lib/domain/calibration/template_extractor.dart`

**Algorithmus**:
```
1. Alle validierten Reps aus Stufe B sammeln (PeakEvent.window)
2. Jede Rep auf 64 Samples resamplen (lineare Interpolation)
3. Jede Rep normalisieren: (x - mean) / std
4. Median über alle Reps bilden (robust gegen Ausreißer)
5. Ergebnis: repTemplate[0..63]
```

```dart
class TemplateExtractor {
  static const int templateLength = 64;
  static List<double>? extract(List<List<double>> windows);
  static List<double> resample(List<double> input, int targetLength);
  static List<double> normalize(List<double> input);
}
```

### 4.3 CalibrationController Änderungen

- In `_finishKnownSet()`: Template-Extraktion aufrufen
- In `finalize()`: `repTemplate` und `expectedProminence` in ExerciseProfile schreiben
- Alles andere (Stufen, Known-Count-Sweep, PCA, Tap-to-Tag) bleibt unverändert

---

## TEIL 5 — BLE & Firmware Architektur

### 5.1 Klasse: JitterBuffer

**Datei**: `app/lib/data/providers/jitter_buffer.dart`

**Problem**: 4 Samples kommen gleichzeitig (alle 80ms) → Zeitbereichsanalyse korrupt.
**Lösung**: Ringpuffer (Größe 6), Timer gibt alle 20ms ein Sample aus. Latenz: 60ms.

```dart
class JitterBuffer {
  JitterBuffer({int bufferSize = 6, Duration outputInterval = 20ms});
  void addBatch(List<SensorSample> samples);
  void start(void Function(SensorSample) onSample);
  void stop();
  int get pendingCount;
  bool get isUnderrun;
  void reset();
  void dispose();
}
```

### 5.2 Integration in BleSensorProvider

```dart
// VORHER: for (final s in samples) { _sampleController.add(s); }
// NACHHER: _jitterBuffer.addBatch(samples);
// JitterBuffer.start() emittiert einzeln an _sampleController
```

### 5.3 Firmware: Keine Änderungen in Phase 1-4

---

## TEIL 6 — Flutter Application Architecture

### 6.1 Riverpod Setup

Neue Dependencies:
```yaml
flutter_riverpod: ^2.5.1    # MIT
vibration: ^2.0.0           # BSD
audioplayers: ^6.1.0        # MIT
```

### 6.2 Provider-Struktur

```dart
// engine_provider.dart
final engineProvider = StateNotifierProvider<EngineNotifier, WorkoutUiState>(...);

class WorkoutUiState {
  final WorkoutState workoutState;
  final int repsInCurrentSet;
  final RepEvent? lastRep;
  final double? lastQualityScore;
  final bool isConnected;
}
```

### 6.3 UI Widget Extraktion

HomeScreen (734 Zeilen) → ~150 Zeilen + 5 Widgets:
- `RepCounterDisplay` — Große Rep-Zahl + Quality-Ring
- `ConnectionStatusCard` — BLE-Status
- `SetHistoryCard` — Letzter Satz
- `QualityIndicator` — Farbiger Ring
- `SignalDebugView` — Nur kDebugMode

---

## TEIL 7 — Teststrategie

### 7.1 Unit Tests (pro Klasse)

| Klasse | Test-Datei | Kritische Fälle |
|--------|-----------|-----------------|
| ButterworthBandpass | `test/filters/butterworth_test.dart` | DC-Block, Durchlass, Sperrbereich, NaN |
| OneEuroFilter | `test/filters/one_euro_test.dart` | Konvergenz, Sprung, Parameter-Update |
| GpProjection | `test/filters/gp_projection_test.dart` | Achse, Bias |
| PeakDetector | `test/detection/peak_detector_test.dart` | Schwelle, Refractory |
| TemplateMatcher | `test/detection/template_matcher_test.dart` | NCC, Resampling |
| PhaseValidator | `test/detection/phase_validator_test.dart` | Sequenz, Dauer |
| RepCounter | `test/counting/rep_counter_test.dart` | E2E synthetisch |
| WorkoutStateMachine | `test/state/state_machine_test.dart` | Alle Übergänge |
| JitterBuffer | `test/providers/jitter_buffer_test.dart` | Timing, Überlauf |

### 7.2 DSP-Verifikationstests

7 Szenarien: Perfekte Rep, Doppelhump, Rauschen, Langsame Rep, Schnelle Reps, Falsche Bewegung, Ermüdung.

### 7.3 Akzeptanzkriterien

| Kriterium | Ziel |
|-----------|------|
| Rep-Genauigkeit | < 5% Abweichung |
| False Positive Rate | < 0.5/min bei Ruhe |
| Latenz (Rep → UI) | < 200ms |
| CPU-Last (Filter) | < 5% Cortex-A53 |
| RAM (Filter) | < 10 KB |

---

## TEIL 8 — Entwicklungs-Roadmap

### Phase 1: Signal Foundation (Woche 1-2)
14 Tickets (P1-01 bis P1-14), ~22h Aufwand

### Phase 2: Detection Engine (Woche 3-4)
11 Tickets (P2-01 bis P2-11), ~27h Aufwand

### Phase 3: Engine Rewrite (Woche 5-6)
10 Tickets (P3-01 bis P3-10), ~25h Aufwand

### Phase 4: Flutter Architecture (Woche 7-8)
9 Tickets (P4-01 bis P4-09), ~20h Aufwand

### Phase 5: Polish & Features (Woche 9-12)
8 Tickets (P5-01 bis P5-08), ~29h Aufwand

**Gesamt**: ~123h, 12 Wochen bei 1 Entwickler

---

## TEIL 9 — KI-Implementierungsanweisungen

### 9.1 Arbeitspaket-Format

```
═══ ARBEITSPAKET [ID]: [Titel] ═══
ZIEL: [Ein Satz]
KONTEXT: [Was existiert]
BETROFFENE DATEIEN: [Liste]
VORAUSSETZUNGEN: [Abhängigkeiten]
SCHRITT 1..N: [Exakte Anweisungen]
STOLPERFALLEN: [Bekannte Fehler]
DEFINITION OF DONE: [Prüfbare Kriterien]
TESTFÄLLE: [Input → Output]
```

### 9.2 Arbeitspaket P1-02: Butterworth Filter

```
═══ ARBEITSPAKET P1-02: Butterworth Bandpass Filter ═══

ZIEL: Kausalen IIR-Bandpassfilter 4. Ordnung als Dart-Klasse implementieren.

KONTEXT:
  - Flutter-App, Dart SDK >=3.4.0
  - Ordner: app/lib/domain/filters/ (NEU, erstellen)
  - Keine Flutter-Imports (pure Dart)
  - Koeffizienten aus tools/compute_butterworth_coeffs.py

BETROFFENE DATEIEN:
  - [neu]: app/lib/domain/filters/butterworth.dart

VORAUSSETZUNGEN: P1-01 (Python-Script ausgeführt)

SCHRITT 1: Datei erstellen
  - Klasse _BiquadSection:
    - final double b0, b1, b2, a1, a2
    - double _z1 = 0.0, _z2 = 0.0
    - double process(double x):
        y = b0*x + _z1
        _z1 = b1*x - a1*y + _z2
        _z2 = b2*x - a2*y
        return y
    - void reset(): _z1 = 0; _z2 = 0

  - Klasse ButterworthBandpass:
    - Konstruktor({sampleRateHz=50.0, lowCutoffHz=0.3, highCutoffHz=5.0, order=4})
    - Koeffizienten als static const (aus Python-Output)
    - final List<_BiquadSection> _sections (4 Sektionen)
    - int _sampleCount = 0
    - double process(double input):
        if (input.isNaN) return 0.0;
        for (section in _sections) input = section.process(input);
        _sampleCount++;
        return input;
    - void reset()
    - int get sampleCount
    - bool get isSettled => _sampleCount > 16

STOLPERFALLEN:
  - NICHT Näherungskoeffizienten verwenden — NUR Python-Output!
  - Direct Form II Transposed (NICHT Direct Form I)
  - Highpass-Sektionen ZUERST, dann Lowpass
  - order=4 = 4 Biquad-Sektionen

DEFINITION OF DONE:
  - [ ] Datei existiert
  - [ ] Keine Flutter-Imports
  - [ ] flutter analyze: 0 Issues
  - [ ] Kompiliert ohne Fehler

TESTFÄLLE:
  - DC-Block: 200× process(1.0) → |Ausgabe| < 0.01
  - Durchlass: sin(2Hz) → Amplitude > 0.9
  - Sperrbereich: sin(20Hz) → Amplitude < 0.05
  - NaN: process(NaN) → 0.0
```

### 9.3 Arbeitspaket P1-04: One Euro Filter

```
═══ ARBEITSPAKET P1-04: One Euro Filter ═══

ZIEL: Adaptiven Low-Pass-Filter (Casiez 2012) implementieren.

BETROFFENE DATEIEN:
  - [neu]: app/lib/domain/filters/one_euro_filter.dart

SCHRITT 1: Datei erstellen
  - Klasse OneEuroFilter:
    - Konstruktor({required sampleRateHz, minCutoff=1.0, beta=0.007, dCutoff=1.0})
    - _te = 1.0 / sampleRateHz
    - double? _lastFiltered, _lastFilteredDeriv
    - double process(double value):
        if (_lastFiltered == null) { _lastFiltered = value; return value; }
        dx = (value - _lastFiltered!) / _te
        alphaD = _alpha(_dCutoff)
        dxHat = alphaD * dx + (1-alphaD) * (_lastFilteredDeriv ?? 0.0)
        cutoff = _minCutoff + _beta * dxHat.abs()
        alpha = _alpha(cutoff)
        xHat = alpha * value + (1-alpha) * _lastFiltered!
        _lastFiltered = xHat; _lastFilteredDeriv = dxHat
        return xHat
    - double _alpha(double cutoff):
        tau = 1.0 / (2 * pi * cutoff)
        return 1.0 / (1.0 + _te / tau)
    - void updateParameters({double? minCutoff, double? beta})
    - void reset()
    - bool get isInitialized

STOLPERFALLEN:
  - dart:math für pi importieren
  - _te = 1/sampleRate (NICHT sampleRate!)
  - Erster Aufruf: Ausgabe = Eingabe (kein Filter)

DEFINITION OF DONE:
  - [ ] flutter analyze: 0 Issues
  - [ ] Kein Flutter-Import

TESTFÄLLE:
  - Konstant: 100× process(5.0) → ≈ 5.0
  - Sprung: schnelle Reaktion
  - reset(): isInitialized == false
```

### 9.4 Kontrollpunkte (nach JEDEM Paket)

```
□ flutter analyze (0 Issues)
□ flutter test (alle grün)
□ Keine Flutter-Imports in domain/filters/ oder domain/detection/
□ DartDoc auf allen öffentlichen APIs
□ Keine Magic Numbers ohne Konstante
```

### 9.5 Strikte Reihenfolge

```
P1-01 → P1-02 → P1-03 → ... → P1-14
  → P2-01 → ... → P2-11
    → P3-01 → ... → P3-10
      → P4-01 → ... → P4-09
        → P5-01 → ... → P5-08
```

**Regel**: Ein Paket darf erst beginnen, wenn alle vorherigen die Definition of Done erfüllen.

---

## ANHANG A — Glossar

| Begriff | Bedeutung |
|---------|-----------|
| g_p | Signed Gyro Projection |
| NCC | Normalized Cross-Correlation |
| Biquad | Biquadratische Filtersektion (2. Ordnung) |
| IIR | Infinite Impulse Response |
| SPK/NPK | Signal/Noise Peak Level (Pan-Tompkins) |
| ROM | Range of Motion |
| PCA | Principal Component Analysis |

## ANHANG B — Bestehende Dateien: Aktionen

| Datei | Aktion |
|-------|--------|
| `workout_engine.dart` | REFACTORIEREN zur Facade |
| `signal_processor.dart` | ERSETZEN durch SignalChain |
| `calibration_controller.dart` | VERSCHIEBEN + ERWEITERN |
| `exercise_profile.dart` | ERWEITERN |
| `home_screen.dart` | REFACTORIEREN (734→150 Zeilen) |
| `ble_sensor_provider.dart` | ÄNDERN (JitterBuffer) |
| `ble_protocol_parser.dart` | UNVERÄNDERT |
| `calibration_store.dart` | UNVERÄNDERT |
| `firmware/src/main.cpp` | UNVERÄNDERT (Phase 1-4) |

---

*Ende der vollständigen Spezifikation.*

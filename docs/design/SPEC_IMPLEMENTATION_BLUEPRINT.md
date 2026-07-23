# FlowRep — Vollständige Technische Spezifikation zur Implementierung

> **Status**: DRAFT v1.0  
> **Autor**: Lead Architect / Tech Lead  
> **Zielgruppe**: Implementierende KI ohne eigene Architekturentscheidungen  
> **Regel**: Jeder Schritt ist vollständig beschrieben. Keine Annahmen treffen.

---

## TEIL 1 — Gesamtarchitektur & Migrationsstrategie

### 1.1 Zielarchitektur

Die App wird von einem monolithischen Prototyp in eine modulare, testbare Architektur überführt.

```
┌─────────────────────────────────────────────────────────────────┐
│                    PRESENTATION LAYER (Flutter)                   │
│                                                                   │
│  ┌─────────────┐ ┌─────────────┐ ┌──────────┐ ┌─────────────┐  │
│  │  Workout     │ │ Calibration │ │ History  │ │  Settings   │  │
│  │  Screen      │ │  Wizard     │ │ Screen   │ │  Screen     │  │
│  └──────┬──────┘ └──────┬──────┘ └────┬─────┘ └──────┬──────┘  │
│         │               │              │              │          │
│  ┌──────┴───────────────┴──────────────┴──────────────┴──────┐  │
│  │              Riverpod Providers (State Management)          │  │
│  └──────────────────────────┬─────────────────────────────────┘  │
├─────────────────────────────┼───────────────────────────────────┤
│                    DOMAIN LAYER (Pure Dart)                       │
│                             │                                     │
│  ┌──────────────────────────┴─────────────────────────────────┐  │
│  │                  ExerciseEngine (Orchestrator)              │  │
│  │                                                             │  │
│  │  ┌───────────────┐  ┌──────────────┐  ┌────────────────┐  │  │
│  │  │ SignalPipeline │  │  RepCounter  │  │ CalibrationEng │  │  │
│  │  │               │  │              │  │                │  │  │
│  │  │ Butterworth   │  │ Template     │  │ KnownCount     │  │  │
│  │  │ OneEuro       │  │  Matcher     │  │  Sweep         │  │  │
│  │  │ GpProjection  │  │ Adaptive     │  │ PCA Axis       │  │  │
│  │  │ Envelope      │  │  Threshold   │  │ Template       │  │  │
│  │  │               │  │ Phase Valid. │  │  Extraction    │  │  │
│  │  └───────────────┘  │ Quality Score│  │ Blending       │  │  │
│  │                      └──────────────┘  └────────────────┘  │  │
│  │  ┌───────────────┐  ┌──────────────┐  ┌────────────────┐  │  │
│  │  │ WorkoutState  │  │  Exercise    │  │  Online        │  │  │
│  │  │ Machine       │  │  Registry    │  │  Adapter       │  │  │
│  │  └───────────────┘  └──────────────┘  └────────────────┘  │  │
│  └─────────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                      DATA LAYER                                   │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌──────────────┐  │
│  │ BLE        │ │  Drift     │ │  Secure    │ │  CSV         │  │
│  │ Provider   │ │  Database  │ │  Storage   │ │  Recorder    │  │
│  └────────────┘ └────────────┘ └────────────┘ └──────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    FIRMWARE LAYER (C++/ESP32)                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  M5StickC Plus2: IMU@50Hz → BLE batch@12.5Hz (Protocol v2) │  │
│  └─────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Technische Leitentscheidungen

| # | Entscheidung | Begründung | Alternativen (verworfen) |
|---|---|---|---|
| LD-1 | Riverpod statt BLoC | Weniger Boilerplate, bessere Testbarkeit, Provider-Composition | BLoC (zu viel Boilerplate für diese App-Größe), GetX (schlecht wartbar) |
| LD-2 | Butterworth 4. Ordnung als IIR | Bewährt in Biomechanik, scharfe Trennung bei 0.1-5Hz, geringe Latenz | FIR (zu viele Koeffizienten bei 50Hz), EMA (zu flache Flanke) |
| LD-3 | One Euro Filter für adaptive Glättung | Passt sich Bewegungsgeschwindigkeit an, minimaler Lag bei langsamen Reps | Kalman (Overkill für 1D), Savitzky-Golay (nicht kausal) |
| LD-4 | Template Matching via normalisierte Kreuzkorrelation | O(n) pro Vergleich, robust gegen Amplitudenvariation | DTW (O(n²), zu teuer für Echtzeit), LSTM (kein Training möglich) |
| LD-5 | Pan-Tompkins adaptive Schwelle | Bewährt in EKG-Detektion, dual-envelope lernt Signal+Rauschen | Feste Schwelle (aktuell, funktioniert nicht), Percentile (zu träge) |
| LD-6 | g_p (signed gyro projection) als Primärsignal | Trennt konzentrisch/exzentrisch durch Vorzeichen, strukturell überlegen | Combined magnitude (aktuell, doppelhump-Problem), Accel-only (zu noise) |
| LD-7 | ExerciseProfile als zentrale Konfiguration | Eine Datei pro Übung, alle Parameter gebündelt, blendbar | Verstreute Konstanten (aktuell), JSON-Config (kein Typschutz) |
| LD-8 | State Machine als expliziter, testbarer Automat | Zustandsübergänge dokumentiert, keine versteckten if-Ketten | Implizite States in God-Object (aktuell, nicht testbar) |
| LD-9 | Jitter Buffer (3 Samples) vor Signalverarbeitung | Glättet BLE-Burst-Ankunft, macht Zeitbereichsanalyse valide | Keine Pufferung (aktuell, Timing korrupt), großer Puffer (zu viel Latenz) |
| LD-10 | Pure Dart Domain Layer (kein Flutter-Import) | Vollständig testbar ohne Widget-Tests, portierbar | Flutter-abhängig (aktuell teilweise, schwerer zu testen) |

### 1.3 Neue Dateistruktur

```
app/lib/
├── main.dart                          (BESTEHEND, minimal ändern)
├── data/
│   ├── protocol/
│   │   └── ble_protocol_parser.dart   (BESTEHEND, unverändert)
│   ├── providers/
│   │   ├── ble_sensor_provider.dart   (BESTEHEND, Jitter Buffer hinzufügen)
│   │   ├── sensor_provider.dart       (BESTEHEND, Interface erweitern)
│   │   ├── batch_dedup_tracker.dart   (BESTEHEND, unverändert)
│   │   └── jitter_buffer.dart         (NEU)
│   ├── repositories/
│   │   ├── csv_session_recorder.dart  (BESTEHEND, unverändert)
│   │   ├── drift_database.dart        (BESTEHEND, Schema erweitern)
│   │   └── session_repository.dart    (NEU)
│   ├── security/
│   │   ├── calibration_store.dart     (BESTEHEND, unverändert)
│   │   └── database_key_manager.dart  (BESTEHEND, unverändert)
│   └── logger.dart                    (BESTEHEND, unverändert)
├── domain/
│   ├── models/
│   │   ├── exercise_profile.dart      (BESTEHEND, ERWEITERN)
│   │   ├── workout_models.dart        (BESTEHEND, ERWEITERN)
│   │   ├── signal_sample.dart         (NEU - aus workout_engine extrahiert)
│   │   └── rep_quality.dart           (NEU)
│   ├── filters/
│   │   ├── butterworth.dart           (NEU)
│   │   ├── one_euro_filter.dart       (NEU)
│   │   ├── signal_chain.dart          (NEU)
│   │   └── envelope_detector.dart     (NEU)
│   ├── detection/
│   │   ├── peak_detector.dart         (NEU)
│   │   ├── template_matcher.dart      (NEU)
│   │   ├── adaptive_threshold.dart    (NEU)
│   │   └── phase_validator.dart       (NEU)
│   ├── counting/
│   │   ├── rep_counter.dart           (NEU)
│   │   ├── quality_scorer.dart        (NEU)
│   │   └── online_adapter.dart        (NEU)
│   ├── exercises/
│   │   ├── exercise_registry.dart     (NEU)
│   │   └── exercise_config.dart       (NEU)
│   ├── state/
│   │   └── workout_state_machine.dart (NEU)
│   ├── calibration/
│   │   ├── calibration_controller.dart (BESTEHEND, umbenennen/verschieben)
│   │   └── template_extractor.dart    (NEU)
│   ├── signal_processor.dart          (BESTEHEND, REFACTORIEREN)
│   ├── workout_engine.dart            (BESTEHEND, ZERLEGEN → Facade)
│   └── repositories/
│       └── i_workout_repository.dart  (BESTEHEND, unverändert)
├── presentation/
│   ├── providers/
│   │   ├── engine_provider.dart       (NEU)
│   │   ├── ble_provider.dart          (NEU)
│   │   ├── session_provider.dart      (NEU)
│   │   └── calibration_provider.dart  (NEU)
│   ├── screens/
│   │   ├── home_screen.dart           (BESTEHEND, REFACTORIEREN)
│   │   ├── workout_screen.dart        (NEU)
│   │   ├── history_screen.dart        (NEU)
│   │   └── calibration/
│   │       └── calibration_wizard_screen.dart (BESTEHEND, minor)
│   └── widgets/
│       ├── rep_counter_display.dart   (NEU)
│       ├── connection_status.dart     (NEU)
│       ├── quality_indicator.dart     (NEU)
│       ├── set_history_card.dart      (NEU)
│       └── signal_debug_view.dart     (NEU, nur kDebugMode)
└── app.dart                           (NEU - MaterialApp + ProviderScope)
```

### 1.4 Datenfluss (vollständig)

```
[M5StickC Plus2 IMU @ 50Hz]
         │
         │ (BLE GATT read() polling, ~12.5 batches/s, 4 samples/batch)
         ▼
[BleSensorProvider] ──→ Stream<Uint8List> (raw bytes, 53 Byte)
         │
         ▼
[BleProtocolParser.parseBatch()] ──→ List<SensorSample> (4 Stück)
         │
         ▼
[JitterBuffer] ──→ Stream<SensorSample> (geglättet, 20ms Raster)
         │         Buffergröße: 3 Samples (60ms Latenz)
         │         Ausgabe: 1 Sample alle 20ms via Timer
         ▼
[SignalChain.process(SensorSample)] ──→ ProcessedFrame
         │
         │  ProcessedFrame enthält:
         │  - rawAccel: (ax, ay, az) in g
         │  - rawGyro: (gx, gy, gz) in °/s (bias-korrigiert)
         │  - accelMagnitude: double (g)
         │  - gyroMagnitude: double (°/s)
         │  - gpSigned: double (°/s, projiziert auf Rotationsachse)
         │  - bandpassed: double (g_p nach Butterworth)
         │  - smoothed: double (g_p nach One Euro)
         │  - envelope: double (Hüllkurve)
         │  - timestamp: DateTime
         │
         ▼
[PeakDetector.process(ProcessedFrame)] ──→ PeakEvent?
         │
         │  PeakEvent (nur wenn Peak bestätigt):
         │  - sampleIndex: int
         │  - peakValue: double
         │  - precedingValley: double
         │  - prominence: double
         │  - timestamp: DateTime
         │
         ▼
[TemplateMatcher.validate(PeakEvent, window)] ──→ MatchResult
         │
         │  MatchResult:
         │  - correlation: double (0.0-1.0)
         │  - accepted: bool (correlation > threshold)
         │  - shapeDeviation: double
         │
         ▼
[AdaptiveThreshold.update(peakValue)] ──→ void
         │  (lernt kontinuierlich Signal- und Rauschlevel)
         ▼
[PhaseValidator.check(gpWindow)] ──→ PhaseResult
         │
         │  PhaseResult:
         │  - hasConcentric: bool
         │  - hasEccentric: bool
         │  - sequenceValid: bool
         │  - concentricDuration: double (s)
         │  - eccentricDuration: double (s)
         │
         ▼
[RepCounter.onValidatedPeak(MatchResult, PhaseResult)] ──→ RepEvent?
         │
         │  RepEvent (nur wenn alle Validierungen bestanden):
         │  - repNumber: int
         │  - quality: RepQuality
         │  - timestamp: DateTime
         │  - peakMagnitude: double
         │  - correlation: double
         │  - romEstimate: double?
         │  - tempoSeconds: double?
         │
         ▼
[WorkoutStateMachine.transition(RepEvent)] ──→ StateTransition
         │
         │  StateTransition:
         │  - fromState: WorkoutState
         │  - toState: WorkoutState
         │  - event: dynamic
         │
         ▼
[OnlineAdapter.update(RepEvent)] ──→ void
         │  (aktualisiert laufende Statistiken: Peak-EMA, Intervall-EMA)
         ▼
[Riverpod Providers] ──→ StateNotifier<WorkoutUiState>
         │
         ▼
[Flutter UI] ──→ RepCounterDisplay, QualityIndicator, etc.
```

### 1.5 Migrationsreihenfolge (kritisch!)

Die Migration erfolgt in strikter Reihenfolge. Kein Schritt darf übersprungen werden.

```
Phase 1A: Extraktion (bestehender Code bleibt funktional)
  ├── 1A.1: SensorSample in eigene Datei
  ├── 1A.2: SignalProcessor → SignalChain (Wrapper, alter Code intern)
  ├── 1A.3: WorkoutEngine → Facade (delegiert intern an alte Logik)
  └── 1A.4: Tests laufen weiterhin grün

Phase 1B: Neue Filter (parallel zum alten Pfad)
  ├── 1B.1: Butterworth implementieren + Unit Tests
  ├── 1B.2: One Euro Filter implementieren + Unit Tests
  ├── 1B.3: SignalChain erweitert (neuer Pfad opt-in)
  └── 1B.4: A/B-Vergleich: alter vs. neuer Pfad in Tests

Phase 2A: Neue Detektion (parallel)
  ├── 2A.1: PeakDetector (neu, template-basiert)
  ├── 2A.2: AdaptiveThreshold (Pan-Tompkins)
  ├── 2A.3: TemplateMatcher
  ├── 2A.4: PhaseValidator
  └── 2A.5: RepCounter (orchestriert alle)

Phase 2B: State Machine + Engine Rewrite
  ├── 2B.1: WorkoutStateMachine (explizit)
  ├── 2B.2: ExerciseEngine (neuer Orchestrator)
  ├── 2B.3: WorkoutEngine wird zur dünnen Facade
  └── 2B.4: Alter Code wird gelöscht (nach Test-Verifikation)

Phase 3: Calibration + Profile
  ├── 3.1: ExerciseProfile erweitern
  ├── 3.2: TemplateExtractor
  ├── 3.3: CalibrationController anbinden
  └── 3.4: ExerciseRegistry

Phase 4: Flutter Architecture
  ├── 4.1: Riverpod Setup
  ├── 4.2: Provider erstellen
  ├── 4.3: UI Widgets extrahieren
  └── 4.4: HomeScreen refactorieren

Phase 5: Polish + Features
  ├── 5.1: Haptic/Audio Feedback
  ├── 5.2: Session Persistence
  ├── 5.3: History Screen
  └── 5.4: Quality Scoring UI
```

### 1.6 Risiken der Migration

| Risiko | Wahrscheinlichkeit | Auswirkung | Gegenmaßnahme |
|--------|-------------------|------------|---------------|
| Bestehende Tests brechen während Refactoring | Hoch | Mittel | Facade-Pattern: WorkoutEngine bleibt API-stabil, delegiert intern |
| Butterworth-Filter erzeugt Phasenverschiebung | Sicher | Mittel | Zero-phase (forward-backward) nur offline; live: kausal mit bekannter Latenz kompensieren |
| One Euro Filter zu aggressiv bei schnellen Reps | Mittel | Hoch | Parameter aus Kalibrierung ableiten (T0 → min_cutoff) |
| Template Matching lehnt legitime Reps ab (zu streng) | Mittel | Hoch | Threshold adaptiv: startet bei 0.6, steigt auf 0.75 nach 5 bestätigten Reps |
| BLE Jitter Buffer erhöht Latenz spürbar | Gering | Mittel | 60ms ist unter der Wahrnehmungsschwelle für Rep-Feedback |
| Riverpod Migration bricht Widget-Tests | Mittel | Gering | Alte Tests beibehalten, neue parallel schreiben |
| CPU-Last durch Filterkette zu hoch | Gering | Hoch | Alle Filter O(1) pro Sample; Benchmark auf M5StickC-äquivalentem Gerät |

---

## TEIL 2 — Signal Processing Pipeline

### 2.1 Architektur der SignalPipeline

Die SignalPipeline ersetzt den aktuellen `SignalProcessor` (150 Zeilen, nur EMA).

**Aktuell:**
```dart
// signal_processor.dart - NUR ein EMA-Filter
double process(SensorSample s) {
  final raw = s.accelMagnitude + (s.gyroMagnitude * gyroWeight);
  _filteredSignal = _filteredSignal! * (1 - lowPassAlpha) + raw * lowPassAlpha;
  return _filteredSignal!;
}
```

**Ziel:**
```
SensorSample → [BiasCorrection] → [GpProjection] → [Butterworth] → [OneEuro] → [Envelope] → ProcessedFrame
```

Jede Stufe ist eine eigenständige, testbare Klasse. Die `SignalChain` orchestriert die Reihenfolge.

### 2.2 Klasse: ButterworthFilter

**Datei**: `app/lib/domain/filters/butterworth.dart`

**Zweck**: Kausaler IIR-Bandpassfilter 4. Ordnung (vier kaskadierte Biquad-Sektionen). Entfernt Frequenzen unterhalb 0.1 Hz (Drift, Gravitationsänderung) und oberhalb 5 Hz (Handzittern, Stöße).

> **HINWEIS (aktualisiert)**: Maßgeblich sind die Koeffizienten in `butterworth.dart`,
> generiert von `tools/compute_butterworth_coeffs.py` (scipy, order=4, band=[0.1, 5.0], fs=50).
> Die untenstehenden Beispielkoeffizienten (0.3 Hz) sind historisch und NICHT mehr gültig.

**Mathematische Grundlage**:
- Butterworth-Filter maximiert die Flachheit im Durchlassband
- 4. Ordnung = -80 dB/Dekade Abfall → scharfe Trennung
- Implementierung als zwei Biquad-Sektionen (numerisch stabiler als direkte Form)
- Koeffizienten werden VORBERECHNET (nicht zur Laufzeit)

**Koeffizienten-Berechnung** (einmalig, nicht pro Sample):

Für einen Bandpass 0.1–5.0 Hz bei 50 Hz Abtastrate:
```
Normalisierte Frequenzen:
  f_low  = 0.3 / (50/2) = 0.012
  f_high = 5.0 / (50/2) = 0.200

Berechnung via Bilinear-Transformation:
  ω = 2π * f / fs
  
  Für jede Biquad-Sektion (2. Ordnung):
    b0, b1, b2, a0, a1, a2 (6 Koeffizienten)
    Normalisierung: alle durch a0 teilen
```

**Feste Koeffizienten** (für fs=50Hz, fc_low=0.1Hz, fc_high=5.0Hz, Ordnung=4):

> ⚠️ Die tatsächlichen Koeffizienten stehen in `butterworth.dart` (4 Sektionen).
> Untenstehende Werte (0.3 Hz, 2 Sektionen) sind ein veraltetes Beispiel.

```
Sektion 1 (Highpass 0.3 Hz, Q=0.5412):
  b0 =  0.9391
  b1 = -1.8782
  b2 =  0.9391
  a1 = -1.8769
  a2 =  0.8821

Sektion 2 (Highpass 0.3 Hz, Q=1.3066):
  b0 =  0.9391
  b1 = -1.8782
  b2 =  0.9391
  a1 = -1.8745
  a2 =  0.8848

Sektion 3 (Lowpass 5.0 Hz, Q=0.5412):
  b0 =  0.0675
  b1 =  0.1349
  b2 =  0.0675
  a1 = -1.1430
  a2 =  0.4128

Sektion 4 (Lowpass 5.0 Hz, Q=1.3066):
  b0 =  0.0675
  b1 =  0.1349
  b2 =  0.0675
  a1 = -1.1266
  a2 =  0.3965
```

> **HINWEIS FÜR IMPLEMENTIERENDE KI**: Diese Koeffizienten müssen mit einem Python-Script verifiziert werden (scipy.signal.butter). Die obigen Werte sind Näherungen. Das Script `tools/compute_butterworth_coeffs.py` ist zu erstellen und die exakten Werte in den Dart-Code zu übernehmen.

**Öffentliche API**:

```dart
class ButterworthBandpass {
  /// Erstellt einen Bandpass-Filter.
  /// [sampleRateHz]: Abtastrate (Standard: 50.0)
  /// [lowCutoffHz]: Untere Grenzfrequenz (Standard: 0.3)
  /// [highCutoffHz]: Obere Grenzfrequenz (Standard: 5.0)
  /// [order]: Filterordnung (Standard: 4, muss gerade sein)
  ButterworthBandpass({
    double sampleRateHz = 50.0,
    double lowCutoffHz = 0.3,
    double highCutoffHz = 5.0,
    int order = 4,
  });

  /// Verarbeitet EIN Sample. Gibt das gefilterte Signal zurück.
  /// Kausal: Ausgabe hängt nur von aktuellen und vergangenen Eingaben ab.
  /// Latenz: ~4 Samples (80ms bei 50Hz) — kompensierbar.
  double process(double input);

  /// Setzt den Filterzustand zurück (alle internen Puffer auf 0).
  /// Aufrufen bei: neue Session, Reconnect, Übungswechsel.
  void reset();

  /// Anzahl der verarbeiteten Samples seit letztem reset().
  int get sampleCount;

  /// true, wenn der Filter eingeschwungen ist (sampleCount > 4*order).
  /// Vor dem Einschwingen sind die Ausgabewerte unzuverlässig.
  bool get isSettled;
}
```

**Private Variablen**:
```dart
// Pro Biquad-Sektion: 2 Zustandsvariablen (Direct Form II Transposed)
final List<_BiquadSection> _sections;  // 4 Sektionen
int _sampleCount = 0;
```

**Interne Klasse _BiquadSection**:
```dart
class _BiquadSection {
  final double b0, b1, b2, a1, a2;
  double _z1 = 0.0;  // Zustandsvariable 1
  double _z2 = 0.0;  // Zustandsvariable 2

  double process(double x) {
    // Direct Form II Transposed (numerisch stabil)
    final y = b0 * x + _z1;
    _z1 = b1 * x - a1 * y + _z2;
    _z2 = b2 * x - a2 * y;
    return y;
  }

  void reset() { _z1 = 0.0; _z2 = 0.0; }
}
```

**Algorithmus (Direct Form II Transposed)**:
```
Für jedes Eingangssample x:
  Für jede Sektion s in [s1, s2, s3, s4]:
    y = b0*x + z1
    z1 = b1*x - a1*y + z2
    z2 = b2*x - a2*y
    x = y  (Ausgabe dieser Sektion ist Eingabe der nächsten)
  return x (Endausgabe)
```

**Laufzeit**: O(1) pro Sample (4 Sektionen × 5 Multiplikationen = 20 MUL + 16 ADD)  
**Speicher**: 8 doubles (2 Zustandsvariablen × 4 Sektionen) = 64 Byte  
**Grenzfälle**:
- Erstes Sample nach reset(): Ausgabe ist klein (Filter schwingt ein)
- Sehr große Eingangswerte (>100): kein Overflow bei double, aber Clipping sinnvoll
- NaN-Eingang: muss abgefangen werden → Ausgabe 0.0 + Flag

**Fehlerquellen**:
- Falsche Koeffizienten → Filter oszilliert oder dämpft alles
- Reihenfolge der Sektionen: Highpass VOR Lowpass (sonst DC-Offset-Probleme)
- Nicht-resetten bei Session-Wechsel → alte Transiente verfälschen neue Messung

### 2.3 Klasse: OneEuroFilter

**Datei**: `app/lib/domain/filters/one_euro_filter.dart`

**Zweck**: Adaptiver Low-Pass-Filter, der bei langsamen Bewegungen stark glättet (wenig Jitter) und bei schnellen Bewegungen wenig glättet (wenig Lag). Ideal für Rep-Signale, die sowohl langsame (kontrollierte Reps) als auch schnelle (explosive Reps) Phasen haben.

**Mathematische Grundlage** (Casiez et al., CHI 2012):
```
Gegeben:
  x_i = aktueller Messwert
  x̂_{i-1} = letzter gefilterter Wert
  dx̂_{i-1} = letzte gefilterte Ableitung

Schritt 1: Roh-Ableitung schätzen
  dx_i = (x_i - x̂_{i-1}) / T_e    (T_e = 1/sampleRate)

Schritt 2: Ableitung glätten (mit festem alpha_d)
  dx̂_i = α_d * dx_i + (1-α_d) * dx̂_{i-1}

Schritt 3: Adaptiven Cutoff berechnen
  fc_i = min_cutoff + β * |dx̂_i|

Schritt 4: Alpha aus Cutoff berechnen
  α_i = 1 / (1 + T_e/(2π * fc_i))    [τ = 1/(2π*fc)]

Schritt 5: Signal glätten
  x̂_i = α_i * x_i + (1-α_i) * x̂_{i-1}
```

**Parameter**:
| Parameter | Bedeutung | Typischer Wert | Quelle |
|-----------|-----------|----------------|--------|
| min_cutoff | Minimale Cutoff-Frequenz (Hz) | 1.0 | Bestimmt Glättung bei Ruhe |
| beta | Geschwindigkeits-Koeffizient | 0.007 | Bestimmt Reaktion auf schnelle Bewegung |
| d_cutoff | Cutoff für Ableitungsfilter (Hz) | 1.0 | Selten ändern |

**Kalibrierungs-Abhängigkeit**: `min_cutoff` und `beta` werden aus dem ExerciseProfile abgeleitet:
```dart
// Aus medianTSeconds (Rep-Dauer):
min_cutoff = 1.0 / (profile.medianTSeconds * 2);  // halbe Rep-Frequenz
beta = 0.007 * (50.0 / profile.medianTSeconds);    // skaliert mit Tempo
```

**Öffentliche API**:
```dart
class OneEuroFilter {
  OneEuroFilter({
    required double sampleRateHz,
    double minCutoff = 1.0,
    double beta = 0.007,
    double dCutoff = 1.0,
  });

  /// Verarbeitet ein Sample. [value] ist der rohe Messwert.
  /// Gibt den geglätteten Wert zurück.
  double process(double value);

  /// Aktualisiert die Parameter (z.B. nach Kalibrierung).
  void updateParameters({double? minCutoff, double? beta});

  /// Reset für neue Session.
  void reset();

  bool get isInitialized;
}
```

**Private Variablen**:
```dart
final double _sampleRateHz;
final double _te;  // = 1.0 / sampleRateHz
double _minCutoff;
double _beta;
final double _dCutoff;
double? _lastFiltered;      // x̂_{i-1}
double? _lastFilteredDeriv; // dx̂_{i-1}
```

**Laufzeit**: O(1) pro Sample (7 MUL + 5 ADD)  
**Speicher**: 2 doubles = 16 Byte  
**Grenzfälle**:
- Erstes Sample: `_lastFiltered == null` → Ausgabe = Eingabe (kein Filter)
- `beta = 0`: degeneriert zu festem Low-Pass mit `minCutoff`
- Sehr große Sprünge: `|dx̂|` wird groß → `fc` wird groß → `α → 1` → kaum Glättung (gewünscht!)

### 2.4 Klasse: GpProjection (Signed Gyro Projection)

**Datei**: `app/lib/domain/filters/gp_projection.dart`

**Zweck**: Projiziert den 3D-Gyro-Vektor auf die gelernte Rotationsachse. Erzeugt ein VORZEICHENBEHAFTETES 1D-Signal, das konzentrische und exzentrische Phasen durch unterschiedliche Vorzeichen trennt.

**Mathematische Grundlage**:
```
Gegeben:
  gyro = (gx, gy, gz) in °/s (roh)
  bias = (bx, by, bz) in °/s (aus Ruhephase)
  axis = (ax, ay, az) Einheitsvektor (aus PCA/Kalibrierung)

Berechnung:
  corrected = gyro - bias
  g_p = dot(corrected, axis) = (gx-bx)*ax + (gy-by)*ay + (gz-bz)*az

Eigenschaften:
  g_p > 0: Rotation in "positive" Richtung (z.B. konzentrisch)
  g_p < 0: Rotation in "negative" Richtung (z.B. exzentrisch)
  g_p ≈ 0: keine Rotation um die Übungsachse
```

**Öffentliche API**:
```dart
class GpProjection {
  GpProjection({
    required List<double> rotationAxis,  // Einheitsvektor [x,y,z]
    required List<double> gyroBias,      // [bx,by,bz] in °/s
  });

  /// Projiziert ein Gyro-Sample auf die Rotationsachse.
  /// [gx], [gy], [gz]: Roh-Gyrowerte in °/s.
  /// Rückgabe: signierte Projektion in °/s.
  double project(double gx, double gy, double gz);

  /// Aktualisiert Achse und Bias (nach Rekalibrierung).
  void updateAxisAndBias({
    required List<double> rotationAxis,
    required List<double> gyroBias,
  });

  void reset();
}
```

**Laufzeit**: O(1) — 3 SUB + 3 MUL + 2 ADD = 8 Operationen  
**Speicher**: 6 doubles (axis + bias) = 48 Byte

**Beziehung zu bestehendem Code**:  
Die Logik existiert BEREITS in `SignalProcessor.signedGyroProjection()` (Zeile 133-139). Diese Klasse extrahiert sie in eine eigenständige, testbare Einheit. Der bestehende Code in `SignalProcessor` wird danach entfernt.

### 2.5 Klasse: EnvelopeDetector

**Datei**: `app/lib/domain/filters/envelope_detector.dart`

**Zweck**: Berechnet die Hüllkurve des gefilterten Signals. Die Hüllkurve zeigt die "Energie" der Bewegung und wird für die adaptive Schwelle (Pan-Tompkins) benötigt.

**Algorithmus**:
```
1. Signal quadrieren: x² (macht alles positiv, betont große Ausschläge)
2. Moving Average über N Samples (N = 0.15 * sampleRate = 7-8 bei 50Hz)
3. Ergebnis: Hüllkurve, die langsam ansteigt und langsam abfällt
```

**Öffentliche API**:
```dart
class EnvelopeDetector {
  EnvelopeDetector({
    required double sampleRateHz,
    double windowSeconds = 0.15,  // 150ms Fenster
  });

  /// Verarbeitet ein Sample. [value] ist das gefilterte Signal.
  /// Rückgabe: Hüllkurven-Wert (immer >= 0).
  double process(double value);

  void reset();
}
```

**Interne Implementierung**:
```dart
final int _windowSize;  // = (windowSeconds * sampleRateHz).round()
final List<double> _buffer;  // Ringpuffer der quadrierten Werte
int _writeIndex = 0;
double _sum = 0.0;

double process(double value) {
  final squared = value * value;
  _sum -= _buffer[_writeIndex];  // alten Wert abziehen
  _buffer[_writeIndex] = squared;
  _sum += squared;               // neuen Wert addieren
  _writeIndex = (_writeIndex + 1) % _windowSize;
  return sqrt(_sum / _windowSize);  // RMS als Hüllkurve
}
```

**Laufzeit**: O(1) — 2 MUL + 2 ADD + 1 SQRT  
**Speicher**: windowSize doubles = ~8 * 8 = 64 Byte

### 2.6 Klasse: SignalChain (Orchestrator)

**Datei**: `app/lib/domain/filters/signal_chain.dart`

**Zweck**: Orchestriert die gesamte Filterkette in der korrekten Reihenfolge. Ersetzt `SignalProcessor` als primärer Eingangspunkt für Rohdaten.

**Öffentliche API**:
```dart
class SignalChain {
  SignalChain({
    required GpProjection gpProjection,
    required ButterworthBandpass bandpass,
    required OneEuroFilter oneEuro,
    required EnvelopeDetector envelope,
  });

  /// Verarbeitet ein Roh-Sample durch die gesamte Kette.
  /// Rückgabe: ProcessedFrame mit allen Zwischenergebnissen.
  ProcessedFrame process(SensorSample sample);

  /// Setzt alle Filter zurück.
  void reset();

  /// true, wenn alle Filter eingeschwungen sind.
  bool get isSettled;
}
```

**ProcessedFrame (Datenobjekt)**:
```dart
/// Datei: app/lib/domain/models/processed_frame.dart
class ProcessedFrame {
  final DateTime timestamp;
  final int sampleIndex;

  // Roh (bias-korrigiert)
  final double gx, gy, gz;  // °/s, bias-frei

  // g_p Projektion
  final double gpRaw;  // °/s, signiert, ungefiltert

  // Nach Butterworth
  final double gpBandpassed;  // °/s, 0.1-5 Hz

  // Nach One Euro
  final double gpSmoothed;  // °/s, adaptiv geglättet

  // Hüllkurve
  final double envelope;  // >= 0, RMS-Energie

  // Beschleunigung (für Diagnose)
  final double accelMagnitude;  // g
}
```

**Verarbeitungsreihenfolge in process()**:
```
1. gpRaw = gpProjection.project(s.gx, s.gy, s.gz)
2. gpBandpassed = bandpass.process(gpRaw)
3. gpSmoothed = oneEuro.process(gpBandpassed)
4. envelope = envelopeDetector.process(gpSmoothed)
5. return ProcessedFrame(...)
```

### 2.7 Migrationspfad für SignalProcessor

**Bestehender Code** (`signal_processor.dart`, 150 Zeilen):
- `process()` → EMA auf combined signal → wird durch `SignalChain.process()` ersetzt
- `observeForAxisLearning()` → Varianz-basierte Achsenwahl → bleibt als Fallback
- `setKnownAxis()` → übernimmt PCA-Achse → wandert in `GpProjection.updateAxisAndBias()`
- `signedGyroProjection()` → wird durch `GpProjection.project()` ersetzt
- `reset()` → bleibt, delegiert an `SignalChain.reset()`

**Strategie**: `SignalProcessor` wird zur Facade, die intern eine `SignalChain` hält. Bestehende Aufrufer (WorkoutEngine) merken keinen Unterschied, bis Phase 2B den Engine-Rewrite durchführt.

### 2.8 Python-Verifikationsscript

**Datei**: `tools/compute_butterworth_coeffs.py`

**Zweck**: Berechnet die exakten Butterworth-Koeffizienten und verifiziert den Frequenzgang.

```python
"""
Berechnet Butterworth-Bandpass-Koeffizienten für FlowRep.
Ausgabe: Dart-kompatible Koeffizienten + Frequenzgang-Plot.
"""
import numpy as np
from scipy.signal import butter, sosfilt, freqz
import matplotlib.pyplot as plt

FS = 50.0       # Hz
F_LOW = 0.3     # Hz
F_HIGH = 5.0    # Hz
ORDER = 4       # Gesamtordnung (2 Biquads pro HP/LP)

# Bandpass als Second-Order Sections
sos = butter(ORDER, [F_LOW, F_HIGH], btype='band', fs=FS, output='sos')

print("// Butterworth Bandpass: {}-{} Hz, Ordnung {}, fs={} Hz".format(
    F_LOW, F_HIGH, ORDER, FS))
print("// {} Sektionen (Second-Order Sections)".format(len(sos)))

for i, section in enumerate(sos):
    b0, b1, b2, a0, a1, a2 = section
    print(f"\n// Sektion {i+1}:")
    print(f"//   b0={b0:.10f}, b1={b1:.10f}, b2={b2:.10f}")
    print(f"//   a0={a0:.10f}, a1={a1:.10f}, a2={a2:.10f}")

# Frequenzgang verifizieren
w, h = freqz(sos, worN=2048, fs=FS)
plt.figure()
plt.semilogx(w, 20*np.log10(np.abs(h)))
plt.axvline(F_LOW, color='r', linestyle='--', label=f'{F_LOW} Hz')
plt.axvline(F_HIGH, color='r', linestyle='--', label=f'{F_HIGH} Hz')
plt.xlabel('Frequenz [Hz]')
plt.ylabel('Amplitude [dB]')
plt.title('FlowRep Butterworth Bandpass Frequenzgang')
plt.legend()
plt.grid(True)
plt.savefig('tools/butterworth_response.png', dpi=150)
print("\nPlot gespeichert: tools/butterworth_response.png")
```

### 2.9 Unit Tests für Signal Processing

**Datei**: `app/test/filters/butterworth_test.dart`

```dart
// Testfälle (jeder als eigene test()-Funktion):

// 1. DC-Blockierung: Konstantes Signal (1.0) → Ausgabe geht gegen 0
//    Input: 200 Samples mit Wert 1.0
//    Erwartet: |output| < 0.01 nach 50 Samples (eingeschwungen)

// 2. Durchlassbereich: Sinus 2 Hz (im Band) → Amplitude ~1.0
//    Input: 200 Samples sin(2π*2*t), t=i/50
//    Erwartet: max(|output|) > 0.9 * max(|input|) nach Einschwingen

// 3. Sperrbereich hoch: Sinus 20 Hz → Amplitude < 0.01
//    Input: 200 Samples sin(2π*20*t)
//    Erwartet: max(|output|) < 0.05 * max(|input|)

// 4. Sperrbereich tief: Sinus 0.05 Hz → Amplitude < 0.01
//    Input: 1000 Samples sin(2π*0.05*t)
//    Erwartet: max(|output|) < 0.1 * max(|input|)

// 5. Reset: Nach reset() ist Ausgabe für erstes Sample ≈ 0
// 6. NaN-Schutz: process(double.nan) gibt 0.0 zurück
// 7. Impulsantwort: Einzelner Impuls → klingt exponentiell ab
```

**Datei**: `app/test/filters/one_euro_test.dart`

```dart
// 1. Konstantes Signal → Ausgabe konvergiert gegen Eingang
// 2. Sprung → schnelle Reaktion (wenig Lag bei hohem beta)
// 3. Langsame Rampe → starke Glättung (wenig Jitter)
// 4. reset() → isInitialized == false
// 5. updateParameters() ändert Verhalten
```

**Datei**: `app/test/filters/gp_projection_test.dart`

```dart
// 1. Achse [1,0,0], Bias [0,0,0], Input gx=100 → output=100
// 2. Achse [1,0,0], Bias [10,0,0], Input gx=100 → output=90
// 3. Achse [0,1,0], Input gx=100,gy=0 → output=0
// 4. Achse [0.707,0.707,0], Input gx=100,gy=100 → output=141.4
// 5. updateAxisAndBias ändert Projektion
```

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

**Ziel**: Aufteilung in 7 eigenständige Klassen.

```
WorkoutEngine (BESTEHEND, wird zur Facade, ~100 Zeilen)
  │
  ├── WorkoutStateMachine (NEU, ~150 Zeilen)
  │     Zustände + Übergänge, keine Signalverarbeitung
  │
  ├── SignalChain (NEU, siehe Teil 2, ~80 Zeilen)
  │     Filterkette
  │
  ├── RepCounter (NEU, ~200 Zeilen)
  │     Orchestriert PeakDetector + TemplateMatcher + PhaseValidator
  │
  ├── PeakDetector (NEU, ~120 Zeilen)
  │     Adaptive Schwelle + Rising/Falling Edge
  │
  ├── TemplateMatcher (NEU, ~100 Zeilen)
  │     Kreuzkorrelation gegen gelerntes Rep-Template
  │
  ├── PhaseValidator (NEU, ~80 Zeilen)
  │     Konzentrisch/Exzentrisch Sequenzprüfung
  │
  ├── QualityScorer (NEU, ~80 Zeilen)
  │     Bewertet jede Rep 0-100%
  │
  └── OnlineAdapter (NEU, ~60 Zeilen)
        Aktualisiert laufende Statistiken pro bestätigter Rep
```

> **HINWEIS**: Die vollständige Spezifikation (Teile 3-9) befindet sich in der Datei
> `docs/SPEC_IMPLEMENTATION_BLUEPRINT_PART2.md` (folgt als nächste Datei).

---

*Teil 1-2 Ende. Fortsetzung in Part 2.*
# CV-04 — Sensor Fusion: IMU + Kamera Ensemble

> **Status**: ✅ DONE (domain + EngineNotifier hooks) — FusionEngine, PoseRepCounter-Feed, IMU-Rep-Notify (Stats only); IMU zählt weiter autoritativ
> **Voraussetzung**: Doc 06 (Rep-Counter Winkel) abgeschlossen.
> **Ziel**: IMU- und Kamera-Reps zu einer Entscheidung fusionieren.
> **Ergebnis**: Höhere Genauigkeit durch Ensemble-Entscheidung.
> **WICHTIG**: Die IMU-Pipeline bleibt autoritativ. Kamera ist Validator.

---

## 1. Fusions-Strategie

### 1.1 Entscheidungs-Matrix

| IMU sagt | Kamera sagt | Entscheidung | Begründung |
|----------|-------------|--------------|------------|
| REP | REP | ✅ REP bestätigt | Beide einig = höchste Sicherheit |
| REP | keine Meinung | ✅ REP (mit Warnung) | IMU ist primär, Kamera evtl. Okklusion |
| REP | KEINE REP | ⚠️ Unsicher → IMU zählt | IMU bleibt autoritativ, aber Flag setzen |
| keine | REP | ❌ Verwerfen | IMU hat Vorrang, Kamera-False-Positive |
| keine | keine | ❌ Keine Rep | Beide einig: keine Bewegung |

### 1.2 WICHTIG: Keine Änderung an bestehender Logik

- `exercise_engine.dart` → UNVERÄNDERT
- `workout_engine.dart` → UNVERÄNDERT
- `engine_provider.dart` → bekommt NEUEN optionalen Pfad
- Die Fusion ist ein **zusätzlicher Layer**, kein Ersatz

---

## 2. FusionEngine erstellen

### 2.1 Neue Datei anlegen

**Datei**: `app/lib/domain/vision/fusion_engine.dart` (NEUE DATEI)

```dart
/// Fusion Engine: Kombiniert IMU- und Kamera-Rep-Erkennung.
///
/// Prinzip:
/// - IMU-Pipeline (ExerciseEngine) bleibt AUTORITATIV
/// - Kamera-Pipeline (PoseRepCounter) ist VALIDATOR
/// - Bei Einigkeit: Rep bestätigt (höchstes Vertrauen)
/// - Bei Uneinigkeit: IMU entscheidet, aber Flag wird gesetzt
///
/// Die FusionEngine ändert NICHT die bestehende Engine-Logik.
/// Sie empfängt Events von BEIDEN Quellen und trifft eine
/// kombinierte Entscheidung.
library;

/// Quelle einer Rep-Erkennung.
enum RepSource {
  /// Nur IMU hat die Rep erkannt.
  imuOnly,

  /// Nur Kamera hat die Rep erkannt.
  cameraOnly,

  /// Beide Quellen haben die Rep erkannt.
  both,
}

/// Ergebnis der Fusion-Entscheidung.
class FusionResult {
  /// true wenn die Rep gezählt werden soll.
  final bool shouldCount;

  /// Quelle der Erkennung.
  final RepSource source;

  /// Vertrauens-Score (0.0–1.0).
  /// 1.0 = beide einig, 0.5 = nur eine Quelle.
  final double confidence;

  /// Diagnose-Information.
  final String diagnostic;

  const FusionResult({
    required this.shouldCount,
    required this.source,
    required this.confidence,
    required this.diagnostic,
  });
}

/// Konfiguration für die Fusion.
class FusionConfig {
  /// Maximale Zeit-Differenz zwischen IMU- und Kamera-Rep (ms).
  /// Wenn beide innerhalb dieses Fensters eine Rep melden → "beide".
  final int fusionWindowMs;

  /// Ob Kamera-Reps ohne IMU-Bestätigung gezählt werden.
  /// false = IMU ist immer nötig (empfohlen für V1).
  /// true = Kamera kann alleine zählen (Kamera-Only-Modus).
  final bool allowCameraOnly;

  /// Minimale Kamera-Konfidenz für Fusion (0.0–1.0).
  final double minCameraConfidence;

  const FusionConfig({
    this.fusionWindowMs = 500,
    this.allowCameraOnly = false,
    this.minCameraConfidence = 0.5,
  });
}

/// Fusioniert IMU- und Kamera-Rep-Erkennung.
///
/// Verwendung:
/// ```dart
/// final fusion = FusionEngine(config: FusionConfig());
///
/// // Wenn IMU eine Rep meldet:
/// fusion.onImuRep(timestampMs: 12345);
///
/// // Wenn Kamera eine Rep meldet:
/// fusion.onCameraRep(timestampMs: 12380, confidence: 0.9);
///
/// // Entscheidung abfragen:
/// final result = fusion.getDecision();
/// ```
class FusionEngine {
  final FusionConfig _config;

  // === LETZTE EVENTS ===
  int? _lastImuRepTimestamp;
  int? _lastCameraRepTimestamp;
  double _lastCameraConfidence = 0.0;

  // === STATISTIK ===
  int _totalImuReps = 0;
  int _totalCameraReps = 0;
  int _fusedReps = 0; // Beide einig
  int _imuOnlyReps = 0;
  int _cameraOnlyReps = 0;
  int _rejectedCameraReps = 0;

  FusionEngine({FusionConfig config = const FusionConfig()})
      : _config = config;

  // === GETTER ===

  /// Gesamtzahl IMU-Reps.
  int get totalImuReps => _totalImuReps;

  /// Gesamtzahl Kamera-Reps.
  int get totalCameraReps => _totalCameraReps;

  /// Anzahl fusionierter Reps (beide einig).
  int get fusedReps => _fusedReps;

  /// Anzahl IMU-Only-Reps.
  int get imuOnlyReps => _imuOnlyReps;

  // === EVENT-HANDLER ===

  /// Wird aufgerufen wenn die IMU-Pipeline eine Rep erkennt.
  ///
  /// [timestampMs]: Zeitstempel der IMU-Rep.
  void onImuRep({required int timestampMs}) {
    _totalImuReps++;
    _lastImuRepTimestamp = timestampMs;
  }

  /// Wird aufgerufen wenn die Kamera-Pipeline eine Rep erkennt.
  ///
  /// [timestampMs]: Zeitstempel der Kamera-Rep.
  /// [confidence]: Konfidenz der Pose-Erkennung (0.0–1.0).
  void onCameraRep({required int timestampMs, required double confidence}) {
    _totalCameraReps++;
    _lastCameraRepTimestamp = timestampMs;
    _lastCameraConfidence = confidence;
  }

  // === ENTSCHEIDUNG ===

  /// Trifft eine Fusion-Entscheidung basierend auf den letzten Events.
  ///
  /// [currentTimestampMs]: Aktueller Zeitstempel (für Fenster-Berechnung).
  ///
  /// Rückgabe: [FusionResult] mit Entscheidung.
  FusionResult getDecision({required int currentTimestampMs}) {
    final hasRecentImu = _lastImuRepTimestamp != null &&
        (currentTimestampMs - _lastImuRepTimestamp!) < _config.fusionWindowMs;

    final hasRecentCamera = _lastCameraRepTimestamp != null &&
        (currentTimestampMs - _lastCameraRepTimestamp!) < _config.fusionWindowMs;

    final cameraConfident = _lastCameraConfidence >= _config.minCameraConfidence;

    // === FALL 1: Beide haben kürzlich eine Rep gemeldet ===
    if (hasRecentImu && hasRecentCamera && cameraConfident) {
      _fusedReps++;
      _lastImuRepTimestamp = null;
      _lastCameraRepTimestamp = null;
      return const FusionResult(
        shouldCount: true,
        source: RepSource.both,
        confidence: 1.0,
        diagnostic: 'IMU + Kamera einig → Rep bestätigt',
      );
    }

    // === FALL 2: Nur IMU hat eine Rep gemeldet ===
    if (hasRecentImu && !hasRecentCamera) {
      _imuOnlyReps++;
      _lastImuRepTimestamp = null;
      return const FusionResult(
        shouldCount: true,
        source: RepSource.imuOnly,
        confidence: 0.7,
        diagnostic: 'Nur IMU → Rep gezählt (Kamera evtl. Okklusion)',
      );
    }

    // === FALL 3: Nur Kamera hat eine Rep gemeldet ===
    if (!hasRecentImu && hasRecentCamera && cameraConfident) {
      if (_config.allowCameraOnly) {
        _cameraOnlyReps++;
        _lastCameraRepTimestamp = null;
        return const FusionResult(
          shouldCount: true,
          source: RepSource.cameraOnly,
          confidence: 0.5,
          diagnostic: 'Nur Kamera → Rep gezählt (Camera-Only-Modus)',
        );
      } else {
        _rejectedCameraReps++;
        _lastCameraRepTimestamp = null;
        return const FusionResult(
          shouldCount: false,
          source: RepSource.cameraOnly,
          confidence: 0.3,
          diagnostic: 'Nur Kamera → Verworfen (IMU nötig)',
        );
      }
    }

    // === FALL 4: Keine aktuelle Rep ===
    return const FusionResult(
      shouldCount: false,
      source: RepSource.imuOnly,
      confidence: 0.0,
      diagnostic: 'Keine aktuelle Rep-Erkennung',
    );
  }

  /// Setzt die Fusion-Statistik zurück.
  void reset() {
    _lastImuRepTimestamp = null;
    _lastCameraRepTimestamp = null;
    _lastCameraConfidence = 0.0;
    _totalImuReps = 0;
    _totalCameraReps = 0;
    _fusedReps = 0;
    _imuOnlyReps = 0;
    _cameraOnlyReps = 0;
    _rejectedCameraReps = 0;
  }
}
```

---

## 3. Integration in EngineProvider

### 3.1 engine_provider.dart erweitern

**Datei**: `app/lib/presentation/providers/engine_provider.dart`

**WICHTIG**: Nur ERWEITERN, nichts Bestehendes ändern!

**Am ANFANG der Datei** (nach den bestehenden Imports):
```dart
import '../../domain/vision/fusion_engine.dart';
import '../../domain/vision/pose_rep_counter.dart';
import '../../domain/vision/vision_config.dart';
```

**In der Klasse `EngineNotifier`** (nach den bestehenden Feldern):
```dart
  // === CV-04: Sensor Fusion (optional) ===
  final FusionEngine _fusionEngine = FusionEngine();
  final PoseRepCounter _poseRepCounter = PoseRepCounter();
  bool _cameraEnabled = false;
```

**Neue Methoden** (am ENDE der Klasse, vor der schließenden `}`):
```dart
  // === CV-04: Kamera-Integration ===

  /// Aktiviert/Deaktiviert die Kamera-Pipeline.
  void setCameraEnabled(bool enabled) {
    _cameraEnabled = enabled;
    if (!enabled) {
      _poseRepCounter.reset();
    }
  }

  /// Verarbeitet einen Kamera-Winkel (von CameraPoseProvider).
  ///
  /// Wird aufgerufen wenn die Kamera einen Ellenbogen-Winkel liefert.
  void processCameraAngle({
    required double elbowAngleDegrees,
    required int timestampMs,
  }) {
    if (!_cameraEnabled) return;

    final result = _poseRepCounter.processAngle(
      elbowAngleDegrees: elbowAngleDegrees,
      timestampMs: timestampMs,
    );

    if (result.repCounted) {
      _fusionEngine.onCameraRep(
        timestampMs: timestampMs,
        confidence: 0.8, // TODO: Echte Konfidenz aus Pose Detection
      );
    }
  }

  /// Zugriff auf die FusionEngine (für Diagnose/UI).
  FusionEngine get fusionEngine => _fusionEngine;

  /// Zugriff auf den PoseRepCounter (für Diagnose/UI).
  PoseRepCounter get poseRepCounter => _poseRepCounter;

  /// Ob die Kamera-Pipeline aktiv ist.
  bool get isCameraEnabled => _cameraEnabled;
```

### 3.2 IMU-Rep an Fusion melden

**SUCHE** in `engine_provider.dart` die Stelle wo eine Rep gezählt wird.
Das ist in der Methode die auf `RepEvent` reagiert (z.B. `_onRepCounted`
oder der Stream-Listener).

**HINZUFÜGEN** (nachdem die Rep gezählt wurde):
```dart
    // CV-04: IMU-Rep an Fusion melden
    _fusionEngine.onImuRep(
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
```

**WICHTIG**: Dies ändert NICHT das Zählverhalten. Die IMU zählt weiter
wie bisher. Die Fusion ist nur für Diagnose/Statistik.

---

## 4. Unit-Tests für FusionEngine

### 4.1 Neue Datei anlegen

**Datei**: `app/test/vision/fusion_engine_test.dart` (NEUE DATEI)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/vision/fusion_engine.dart';

void main() {
  late FusionEngine fusion;

  setUp(() {
    fusion = FusionEngine(
      config: const FusionConfig(
        fusionWindowMs: 500,
        allowCameraOnly: false,
        minCameraConfidence: 0.5,
      ),
    );
  });

  group('FusionEngine - Beide einig', () {
    test('IMU + Kamera innerhalb Fenster → Rep bestätigt', () {
      fusion.onImuRep(timestampMs: 1000);
      fusion.onCameraRep(timestampMs: 1100, confidence: 0.9);

      final result = fusion.getDecision(currentTimestampMs: 1200);

      expect(result.shouldCount, isTrue);
      expect(result.source, RepSource.both);
      expect(result.confidence, 1.0);
      expect(fusion.fusedReps, 1);
    });
  });

  group('FusionEngine - Nur IMU', () {
    test('Nur IMU → Rep gezählt mit 0.7 Confidence', () {
      fusion.onImuRep(timestampMs: 1000);

      final result = fusion.getDecision(currentTimestampMs: 1100);

      expect(result.shouldCount, isTrue);
      expect(result.source, RepSource.imuOnly);
      expect(result.confidence, 0.7);
    });
  });

  group('FusionEngine - Nur Kamera', () {
    test('Nur Kamera (allowCameraOnly=false) → Verworfen', () {
      fusion.onCameraRep(timestampMs: 1000, confidence: 0.9);

      final result = fusion.getDecision(currentTimestampMs: 1100);

      expect(result.shouldCount, isFalse);
      expect(result.source, RepSource.cameraOnly);
    });

    test('Nur Kamera (allowCameraOnly=true) → Gezählt', () {
      final fusionAllow = FusionEngine(
        config: const FusionConfig(allowCameraOnly: true),
      );
      fusionAllow.onCameraRep(timestampMs: 1000, confidence: 0.9);

      final result = fusionAllow.getDecision(currentTimestampMs: 1100);

      expect(result.shouldCount, isTrue);
      expect(result.source, RepSource.cameraOnly);
    });

    test('Kamera mit niedriger Konfidenz → Verworfen', () {
      fusion.onImuRep(timestampMs: 1000);
      fusion.onCameraRep(timestampMs: 1100, confidence: 0.3); // < 0.5

      final result = fusion.getDecision(currentTimestampMs: 1200);

      // Kamera wird ignoriert (zu unsicher), nur IMU zählt
      expect(result.shouldCount, isTrue);
      expect(result.source, RepSource.imuOnly);
    });
  });

  group('FusionEngine - Timing', () {
    test('Events außerhalb Fenster → keine Fusion', () {
      fusion.onImuRep(timestampMs: 1000);
      // Kamera-Rep kommt 600ms später (außerhalb 500ms Fenster)
      fusion.onCameraRep(timestampMs: 1600, confidence: 0.9);

      // Bei t=1700: IMU ist 700ms her → außerhalb Fenster
      final result = fusion.getDecision(currentTimestampMs: 1700);

      expect(result.shouldCount, isFalse);
    });
  });

  group('FusionEngine - Reset', () {
    test('Reset setzt Statistik zurück', () {
      fusion.onImuRep(timestampMs: 1000);
      fusion.onCameraRep(timestampMs: 1100, confidence: 0.9);
      fusion.getDecision(currentTimestampMs: 1200);

      fusion.reset();

      expect(fusion.totalImuReps, 0);
      expect(fusion.totalCameraReps, 0);
      expect(fusion.fusedReps, 0);
    });
  });
}
```

### 4.2 Tests ausführen

```bash
cd flowrep/app
flutter test test/vision/fusion_engine_test.dart
```

---

## 5. Commit

```bash
cd flowrep/app
flutter test
flutter analyze
git add -A
git commit -m "feat(cv): Sensor Fusion IMU+Kamera Ensemble-Entscheidung (CV-04)"
git push
```

---

## 6. Checkliste

- [ ] `lib/domain/vision/fusion_engine.dart` erstellt
- [ ] `engine_provider.dart` erweitert (Fusion + PoseRepCounter)
- [ ] Bestehende Tests weiterhin grün (242+)
- [ ] `test/vision/fusion_engine_test.dart` erstellt + grün
- [ ] `flutter test` → ALLE Tests grün
- [ ] `flutter analyze` → 0 Errors
- [ ] Commit + Push

---

## 7. Wichtige Hinweise

### 7.1 Keine Verhaltensänderung der IMU-Pipeline

Die Fusion ist **rein informativ** in V1:
- IMU zählt weiter wie bisher
- Kamera-Ergebnisse werden nur für Diagnose/Statistik genutzt
- In einer ZUKÜNFTIGEN Version kann die Fusion die IMU korrigieren

### 7.2 Camera-Only-Modus

Für Testing OHNE M5StickC:
- `FusionConfig(allowCameraOnly: true)` setzen
- Kamera zählt alleine
- Nützlich für: Demo, Entwicklung, Android-Simulator

### 7.3 Performance-Überlegung

Die FusionEngine ist extrem leichtgewichtig:
- Keine Berechnungen, nur Timestamp-Vergleiche
- < 0.01ms pro Entscheidung
- Kein Einfluss auf die 50Hz-Pipeline

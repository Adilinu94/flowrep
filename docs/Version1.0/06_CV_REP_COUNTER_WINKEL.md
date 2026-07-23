# CV-03 — Rep-Counter via Gelenkwinkel (Bicep Curl)

> **Voraussetzung**: Doc 05 (Kamera-Setup) abgeschlossen.
> **Ziel**: Reps über Ellenbogen-Winkel zählen (State Machine).
> **Ergebnis**: Kamera zählt Bicep-Curl-Reps eigenständig.
> **Test**: Unit-Tests für die State Machine + manueller Test.

---

## 1. Konzept: Winkel-basiertes Rep-Counting

### 1.1 Wie funktioniert es?

Ein Bicep Curl hat zwei klare Positionen:
- **UNTEN**: Arm gestreckt → Ellenbogen-Winkel ≈ 170°
- **OBEN**: Arm kontrahiert → Ellenbogen-Winkel ≈ 40-60°

Eine Rep = Übergang UNTEN → OBEN → UNTEN.

### 1.2 State Machine

```
         Winkel > 160°
    ┌──────────────────────┐
    │                      ▼
┌───┴───┐  Winkel < 90°  ┌─────┐
│ UNTEN │ ──────────────→ │ OBEN │
└───┬───┘                 └──┬──┘
    │                        │
    │    Winkel > 160°       │
    │◄───────────────────────┘
    │
    ▼ (beim Übergang OBEN → UNTEN)
  REP GEZÄHLT!
```

### 1.3 Hysterese (Schwellenwert mit Puffer)

**WARUM Hysterese?** Ohne Puffer würde ein Winkel von 89°→91°→89°
drei Reps zählen. Mit Hysterese:
- "OBEN" wird erst bei < 90° erreicht
- "UNTEN" wird erst bei > 160° erreicht
- Dazwischen: Zustand bleibt unverändert

---

## 2. PoseRepCounter erstellen

### 2.1 Neue Datei anlegen

**Datei**: `app/lib/domain/vision/pose_rep_counter.dart` (NEUE DATEI)

```dart
/// Winkel-basierter Rep-Counter für Pose Estimation.
///
/// Zählt Reps über den Ellenbogen-Winkel (Bicep Curl).
/// Verwendet eine Hysterese-State-Machine:
///   UNTEN (Winkel > angleDown) → OBEN (Winkel < angleUp) → REP
///
/// WICHTIG: Dieser Counter ist UNABHÄNGIG von der IMU-Pipeline.
/// Er kann alleine laufen (Kamera-Only-Modus) oder als
/// Validator für die IMU-Pipeline (Fusion-Modus, siehe Doc 07).
library;

import 'vision_config.dart';

/// Zustände der Rep-Erkennung.
enum PoseRepState {
  /// Initialzustand: Warte auf erste gültige Pose.
  waiting,

  /// Arm ist unten (gestreckt). Warte auf Kontraktion.
  armDown,

  /// Arm ist oben (kontrahiert). Warte auf Streckung.
  armUp,
}

/// Ergebnis der Verarbeitung eines Pose-Frames.
class PoseRepResult {
  /// true wenn in diesem Frame eine Rep gezählt wurde.
  final bool repCounted;

  /// Aktuelle Rep-Nummer (laufend).
  final int repNumber;

  /// Aktueller Ellenbogen-Winkel in Grad (null wenn keine Pose erkannt).
  final double? currentAngle;

  /// Aktueller Zustand der State Machine.
  final PoseRepState state;

  /// Diagnose: Grund für Ablehnung (null wenn OK).
  final String? rejectionReason;

  const PoseRepResult({
    required this.repCounted,
    required this.repNumber,
    this.currentAngle,
    required this.state,
    this.rejectionReason,
  });

  /// Konstante für "kein Ergebnis" (keine Pose erkannt).
  static const PoseRepResult noPose = PoseRepResult(
    repCounted: false,
    repNumber: 0,
    currentAngle: null,
    state: PoseRepState.waiting,
    rejectionReason: 'Keine Pose erkannt',
  );
}

/// Zählt Reps über den Ellenbogen-Winkel.
///
/// Verwendung:
/// ```dart
/// final counter = PoseRepCounter(config: VisionConfig());
///
/// // Pro Kamera-Frame:
/// final result = counter.processAngle(elbowAngleDegrees: 45.0);
/// if (result.repCounted) {
///   print('Rep ${result.repNumber}!');
/// }
/// ```
class PoseRepCounter {
  // === KONFIGURATION ===
  final VisionConfig _config;

  // === ZUSTAND ===
  PoseRepState _state = PoseRepState.waiting;
  int _repCount = 0;
  int _lastRepTimestampMs = 0;
  int _repStartTimestampMs = 0;

  // === DIAGNOSE ===
  int _totalFramesProcessed = 0;
  int _framesWithoutPose = 0;
  int _framesRejectedTooFast = 0;
  int _framesRejectedTooSlow = 0;

  PoseRepCounter({VisionConfig config = const VisionConfig()})
      : _config = config;

  // === GETTER ===

  /// Anzahl gezählter Reps.
  int get repCount => _repCount;

  /// Aktueller Zustand.
  PoseRepState get state => _state;

  /// Gesamtzahl verarbeiteter Frames.
  int get totalFramesProcessed => _totalFramesProcessed;

  /// Frames ohne erkannte Pose.
  int get framesWithoutPose => _framesWithoutPose;

  // === KERNLOGIK ===

  /// Verarbeitet einen Ellenbogen-Winkel.
  ///
  /// [elbowAngleDegrees]: Aktueller Winkel in Grad (0–180).
  ///   - ~170° = Arm gestreckt (unten)
  ///   - ~45° = Arm kontrahiert (oben)
  ///
  /// [timestampMs]: Zeitstempel des Frames (für Timing-Validierung).
  ///
  /// Rückgabe: [PoseRepResult] mit Zähl-Ergebnis.
  PoseRepResult processAngle({
    required double elbowAngleDegrees,
    required int timestampMs,
  }) {
    _totalFramesProcessed++;

    // === TIMING-VALIDIERUNG ===
    final timeSinceLastRep =
        _lastRepTimestampMs > 0
            ? (timestampMs - _lastRepTimestampMs) / 1000.0
            : double.infinity;

    // === STATE MACHINE ===
    switch (_state) {
      case PoseRepState.waiting:
        // Warte auf erste "unten"-Position
        if (elbowAngleDegrees > _config.angleDownThreshold) {
          _state = PoseRepState.armDown;
        }
        return PoseRepResult(
          repCounted: false,
          repNumber: _repCount,
          currentAngle: elbowAngleDegrees,
          state: _state,
        );

      case PoseRepState.armDown:
        // Warte auf Kontraktion (Winkel wird klein)
        if (elbowAngleDegrees < _config.angleUpThreshold) {
          _state = PoseRepState.armUp;
          _repStartTimestampMs = timestampMs;
        }
        return PoseRepResult(
          repCounted: false,
          repNumber: _repCount,
          currentAngle: elbowAngleDegrees,
          state: _state,
        );

      case PoseRepState.armUp:
        // Warte auf Streckung (Winkel wird groß) → REP!
        if (elbowAngleDegrees > _config.angleDownThreshold) {
          // Timing prüfen
          final repDuration =
              (timestampMs - _repStartTimestampMs) / 1000.0;

          // Zu schnell? (Doppelzählung / Zittern)
          if (timeSinceLastRep < _config.minRepIntervalSeconds) {
            _framesRejectedTooFast++;
            _state = PoseRepState.armDown;
            return PoseRepResult(
              repCounted: false,
              repNumber: _repCount,
              currentAngle: elbowAngleDegrees,
              state: _state,
              rejectionReason:
                  'Zu schnell (${timeSinceLastRep.toStringAsFixed(2)}s < '
                  '${_config.minRepIntervalSeconds}s)',
            );
          }

          // Zu langsam? (Pause / keine echte Rep)
          if (repDuration > _config.maxRepDurationSeconds) {
            _framesRejectedTooSlow++;
            _state = PoseRepState.armDown;
            return PoseRepResult(
              repCounted: false,
              repNumber: _repCount,
              currentAngle: elbowAngleDegrees,
              state: _state,
              rejectionReason:
                  'Zu langsam (${repDuration.toStringAsFixed(2)}s > '
                  '${_config.maxRepDurationSeconds}s)',
            );
          }

          // === REP GEZÄHLT! ===
          _repCount++;
          _lastRepTimestampMs = timestampMs;
          _state = PoseRepState.armDown;

          return PoseRepResult(
            repCounted: true,
            repNumber: _repCount,
            currentAngle: elbowAngleDegrees,
            state: _state,
          );
        }
        // Noch oben, warte weiter
        return PoseRepResult(
          repCounted: false,
          repNumber: _repCount,
          currentAngle: elbowAngleDegrees,
          state: _state,
        );
    }
  }

  /// Signalisiert dass keine Pose erkannt wurde.
  ///
  /// Ändert den Zustand NICHT (kurze Okklusion soll nicht resetten).
  void processNoPose() {
    _framesWithoutPose++;
  }

  /// Setzt den Counter zurück (neue Session / Übungswechsel).
  void reset() {
    _state = PoseRepState.waiting;
    _repCount = 0;
    _lastRepTimestampMs = 0;
    _repStartTimestampMs = 0;
    _totalFramesProcessed = 0;
    _framesWithoutPose = 0;
    _framesRejectedTooFast = 0;
    _framesRejectedTooSlow = 0;
  }
}
```

---

## 3. flutter_pose_detection einbinden

### 3.1 CameraPoseProvider erweitern

**Datei**: `app/lib/data/providers/camera_pose_provider.dart`

**ÄNDERUNG**: Die `startDetection()`-Methode ersetzen.

**SUCHE** diesen Block:
```dart
    // Frame-Stream starten
    // HINWEIS: Die eigentliche Pose-Detection-Integration mit
    // flutter_pose_detection erfolgt in Doc 06 (Rep-Counter).
    // Hier wird nur der Kamera-Stream eingerichtet.
    //
    // TODO(cv-06): flutter_pose_detection NpuPoseDetector hier einbinden.
    // Für jetzt: Kamera läuft, Frames werden noch nicht verarbeitet.

    debugPrint('[CameraPose] Detection gestartet (Kamera-Stream aktiv).');
```

**ERSETZE** durch:
```dart
    // Pose Detector initialisieren
    try {
      _poseDetector = NpuPoseDetector(
        config: PoseDetectorConfig.realtime(),
      );
      final mode = await _poseDetector!.initialize();
      debugPrint('[CameraPose] Pose Detector aktiv (Modus: ${mode.name})');
    } catch (e) {
      _error = 'Pose Detector Fehler: $e';
      _isDetecting = false;
      notifyListeners();
      return;
    }

    // Frame-Stream mit Pose Detection starten
    _cameraController!.startImageStream((CameraImage image) async {
      if (!_isDetecting) return;

      try {
        // Bild zu Bytes konvertieren
        final bytes = _convertYUV420ToJPEG(image);
        if (bytes == null) return;

        // Pose Detection ausführen
        final result = await _poseDetector!.detectPose(bytes);

        if (result.hasPoses && result.firstPose != null) {
          final pose = result.firstPose!;
          final landmarks = pose.landmarks
              .map((l) => PoseLandmark(
                    x: l.x,
                    y: l.y,
                    z: l.z,
                    confidence: l.visibility ?? 0.0,
                  ))
              .toList();

          final frame = PoseFrame(
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            landmarks: landmarks,
            processingTimeMs: result.processingTimeMs,
          );

          if (!_poseFrameController.isClosed) {
            _poseFrameController.add(frame);
          }
        }
      } catch (e) {
        debugPrint('[CameraPose] Frame-Verarbeitungsfehler: $e');
      }
    });

    debugPrint('[CameraPose] Detection gestartet (Pose Stream aktiv).');
```

### 3.2 Neue Imports und Felder hinzufügen

**Am ANFANG der Datei** (nach den bestehenden Imports):
```dart
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
```

**In der Klasse** (nach `String? _error;`):
```dart
  NpuPoseDetector? _poseDetector;
```

**In `dispose()`** (vor `_cameraController?.dispose();`):
```dart
    _poseDetector?.dispose();
    _poseDetector = null;
```

### 3.3 YUV→JPEG Konvertierung (Hilfsmethode)

**Am ENDE der Klasse** (vor der schließenden `}`):

```dart
  /// Konvertiert YUV420 CameraImage zu JPEG-Bytes.
  ///
  /// WICHTIG: flutter_pose_detection erwartet JPEG/PNG-Bytes.
  /// Die Kamera liefert YUV420. Diese Konvertierung ist nötig.
  ///
  /// HINWEIS: Auf manchen Geräten kann dies langsam sein (~10-20ms).
  /// Für Production: Native Platform Channel verwenden.
  /// Für Development/Testing: Akzeptabel.
  Uint8List? _convertYUV420ToJPEG(CameraImage image) {
    // TODO(cv-opt): Native YUV→RGB Konvertierung für Performance.
    // Für jetzt: image.planes direkt nutzen wenn möglich.
    //
    // WICHTIG: flutter_pose_detection's detectPose() erwartet
    /// JPEG/PNG-Bytes. Die genaue Konvertierung hängt vom Gerät ab.
    //
    // ALTERNATIVE: camera-Plugin's buildPreview() oder
    // startVideoCapture() mit Frame-Extraktion verwenden.
    //
    // FÜR TESTING: Siehe Doc 08 (Webcam-Modus) für einen
    // einfacheren Weg ohne YUV-Konvertierung.
    return null; // Placeholder — wird in der Praxis durch
                 // Platform-spezifische Konvertierung ersetzt.
  }
```

**WICHTIGER HINWEIS FÜR DEN IMPLEMENTIERER:**

Die YUV→JPEG-Konvertierung ist der **schwierigste Teil** dieses Docs.
Es gibt drei mögliche Ansätze:

1. **Einfach (für Testing)**: `camera`-Plugin's `takePicture()` in einer
   Schleife verwenden (langsam, ~5 FPS, aber funktioniert)

2. **Mittel**: `image.toByteData()` + manuelle YUV→RGB-Konvertierung
   in Dart (mittel-schnell, ~15 FPS)

3. **Schnell (Production)**: Native Platform Channel (Kotlin/Swift)
   für YUV→RGB (~30 FPS)

**Für die ERSTE Implementierung**: Ansatz 1 verwenden.
Die App zählt trotzdem korrekt, nur mit niedrigerer Framerate.

---

## 4. Unit-Tests für PoseRepCounter

### 4.1 Neue Datei anlegen

**Datei**: `app/test/vision/pose_rep_counter_test.dart` (NEUE DATEI)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/vision/pose_rep_counter.dart';
import 'package:flowrep/domain/vision/vision_config.dart';

void main() {
  late PoseRepCounter counter;

  setUp(() {
    counter = PoseRepCounter(
      config: const VisionConfig(
        angleDownThreshold: 160.0,
        angleUpThreshold: 90.0,
        minRepIntervalSeconds: 0.5,
        maxRepDurationSeconds: 5.0,
      ),
    );
  });

  group('PoseRepCounter - Grundfunktionen', () {
    test('Startet im waiting-Zustand', () {
      expect(counter.state, PoseRepState.waiting);
      expect(counter.repCount, 0);
    });

    test('Erkennt eine vollständige Rep', () {
      // 1. Arm unten (170°)
      var result = counter.processAngle(
        elbowAngleDegrees: 170.0,
        timestampMs: 1000,
      );
      expect(result.state, PoseRepState.armDown);
      expect(result.repCounted, isFalse);

      // 2. Arm hoch (45°)
      result = counter.processAngle(
        elbowAngleDegrees: 45.0,
        timestampMs: 2000,
      );
      expect(result.state, PoseRepState.armUp);
      expect(result.repCounted, isFalse);

      // 3. Arm wieder runter (170°) → REP!
      result = counter.processAngle(
        elbowAngleDegrees: 170.0,
        timestampMs: 3000,
      );
      expect(result.repCounted, isTrue);
      expect(result.repNumber, 1);
      expect(counter.repCount, 1);
    });

    test('Zählt mehrere Reps korrekt', () {
      // Rep 1
      counter.processAngle(elbowAngleDegrees: 170.0, timestampMs: 1000);
      counter.processAngle(elbowAngleDegrees: 45.0, timestampMs: 2000);
      counter.processAngle(elbowAngleDegrees: 170.0, timestampMs: 3000);

      // Rep 2
      counter.processAngle(elbowAngleDegrees: 45.0, timestampMs: 4000);
      counter.processAngle(elbowAngleDegrees: 170.0, timestampMs: 5000);

      expect(counter.repCount, 2);
    });

    test('Ignoriert kleine Winkeländerungen (Hysterese)', () {
      // Arm unten
      counter.processAngle(elbowAngleDegrees: 170.0, timestampMs: 1000);

      // Winkel ändert sich leicht, bleibt aber > 90° → kein Zustandswechsel
      counter.processAngle(elbowAngleDegrees: 120.0, timestampMs: 1500);
      counter.processAngle(elbowAngleDegrees: 100.0, timestampMs: 2000);
      counter.processAngle(elbowAngleDegrees: 95.0, timestampMs: 2500);

      expect(counter.state, PoseRepState.armDown);
      expect(counter.repCount, 0);
    });
  });

  group('PoseRepCounter - Timing-Validierung', () {
    test('Lehnt zu schnelle Reps ab', () {
      // Rep 1 (normal)
      counter.processAngle(elbowAngleDegrees: 170.0, timestampMs: 1000);
      counter.processAngle(elbowAngleDegrees: 45.0, timestampMs: 2000);
      counter.processAngle(elbowAngleDegrees: 170.0, timestampMs: 3000);
      expect(counter.repCount, 1);

      // Rep 2 (zu schnell: nur 200ms nach Rep 1)
      counter.processAngle(elbowAngleDegrees: 45.0, timestampMs: 3100);
      final result = counter.processAngle(
        elbowAngleDegrees: 170.0,
        timestampMs: 3200, // Nur 200ms nach Rep 1
      );

      expect(result.repCounted, isFalse);
      expect(result.rejectionReason, contains('Zu schnell'));
      expect(counter.repCount, 1); // Nicht erhöht
    });

    test('Lehnt zu langsame Reps ab', () {
      // Arm unten
      counter.processAngle(elbowAngleDegrees: 170.0, timestampMs: 1000);

      // Arm hoch
      counter.processAngle(elbowAngleDegrees: 45.0, timestampMs: 2000);

      // Arm runter, aber nach 6 Sekunden (zu langsam)
      final result = counter.processAngle(
        elbowAngleDegrees: 170.0,
        timestampMs: 8000, // 6s nach repStart
      );

      expect(result.repCounted, isFalse);
      expect(result.rejectionReason, contains('Zu langsam'));
      expect(counter.repCount, 0);
    });
  });

  group('PoseRepCounter - Reset', () {
    test('Reset setzt alles zurück', () {
      counter.processAngle(elbowAngleDegrees: 170.0, timestampMs: 1000);
      counter.processAngle(elbowAngleDegrees: 45.0, timestampMs: 2000);
      counter.processAngle(elbowAngleDegrees: 170.0, timestampMs: 3000);
      expect(counter.repCount, 1);

      counter.reset();

      expect(counter.repCount, 0);
      expect(counter.state, PoseRepState.waiting);
      expect(counter.totalFramesProcessed, 0);
    });
  });

  group('PoseRepCounter - Edge Cases', () {
    test('Warte-Zustand ignoriert kleine Winkel', () {
      // Im waiting-Zustand: Winkel < 160° → bleibt waiting
      counter.processAngle(elbowAngleDegrees: 90.0, timestampMs: 1000);
      expect(counter.state, PoseRepState.waiting);

      counter.processAngle(elbowAngleDegrees: 45.0, timestampMs: 2000);
      expect(counter.state, PoseRepState.waiting);
    });

    test('processNoPose ändert Zustand nicht', () {
      counter.processAngle(elbowAngleDegrees: 170.0, timestampMs: 1000);
      expect(counter.state, PoseRepState.armDown);

      counter.processNoPose();
      expect(counter.state, PoseRepState.armDown); // Unverändert
      expect(counter.framesWithoutPose, 1);
    });
  });
}
```

### 4.2 Tests ausführen

```bash
cd flowrep/app
flutter test test/vision/pose_rep_counter_test.dart
```

**Erwartetes Ergebnis**: Alle Tests grün.

---

## 5. Commit

```bash
cd flowrep/app
flutter test
flutter analyze
git add -A
git commit -m "feat(cv): Winkel-basierter Rep-Counter für Bicep Curl (CV-03)"
git push
```

---

## 6. Checkliste

- [ ] `lib/domain/vision/pose_rep_counter.dart` erstellt
- [ ] `camera_pose_provider.dart` erweitert (Pose Detector + Image Stream)
- [ ] `test/vision/pose_rep_counter_test.dart` erstellt + grün
- [ ] `flutter test` → ALLE Tests grün
- [ ] `flutter analyze` → 0 Errors
- [ ] Commit + Push

---

## 7. Häufige Fehler und Lösungen

| Fehler | Ursache | Lösung |
|--------|---------|--------|
| `NpuPoseDetector` nicht gefunden | Import fehlt | `import 'package:flutter_pose_detection/flutter_pose_detection.dart';` |
| `detectPose` erwartet `Uint8List` | Falsches Format | JPEG-Bytes übergeben, nicht YUV |
| Tests schlagen fehl bei Timing | Timestamps zu nah | Mindestens 500ms Abstand zwischen Reps in Tests |
| `camera` Plugin Crash | Permission nicht erteilt | Auf Gerät: Kamera-Berechtigung manuell erteilen |
| Winkel immer 0 | Landmarks nicht erkannt | Konfidenz prüfen, minLandmarkConfidence senken |

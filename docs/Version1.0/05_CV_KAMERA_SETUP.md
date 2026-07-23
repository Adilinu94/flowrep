# CV-02 — Kamera-Setup: flutter_pose_detection Integration

> **Status**: 🟡 PARTIAL — VisionConfig + AngleCalculator + CAMERA permissions (Android/iOS) erledigt; `flutter_pose_detection`/Live-Preview noch offen
> **Voraussetzung**: Doc 04 (Architektur) gelesen und verstanden.
> **Ziel**: Kamera-Stream + Pose Detection in FlowRep integrieren.
> **Ergebnis**: App zeigt Live-Kamerabild mit erkannten Körperpunkten.
> **Test**: `flutter test` grün + manuelle Prüfung auf Gerät/Emulator.

---

## 1. Dependency hinzufügen

### 1.1 pubspec.yaml erweitern

**Datei**: `app/pubspec.yaml`

**Position**: Nach Zeile 65 (`audioplayers: ^6.1.0`) einfügen:

```yaml
  # CV-02: Pose Estimation für Kamera-basiertes Rep-Counting
  flutter_pose_detection: ^0.4.0
  camera: ^0.11.0+2
```

**WICHTIG**: `camera` wird für den Kamera-Stream benötigt.
`flutter_pose_detection` nutzt intern MediaPipe/TFLite.

### 1.2 Dependencies installieren

```bash
cd flowrep/app
flutter pub get
```

**Fehlerbehandlung**:
- Falls `flutter_pose_detection` nicht auflöst: Version auf `^0.3.0` ändern
- Falls `camera` Konflikte macht: `camera: ^0.10.6` versuchen
- Nach `pub get`: `flutter clean && flutter pub get`

---

## 2. Android-Permissions

### 2.1 AndroidManifest.xml erweitern

**Datei**: `app/android/app/src/main/AndroidManifest.xml`

**Position**: Innerhalb von `<manifest>`, VOR dem `<application>`-Tag.
Suche die Zeile mit `<uses-permission android:name="android.permission.CAMERA"` —
falls sie NICHT existiert, füge sie ein:

```xml
    <!-- CV-02: Kamera für Pose Estimation -->
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
```

**WICHTIG**: `android:required="false"` bedeutet:
- Die App kann auch OHNE Kamera installiert werden
- Google Play zeigt die App auch auf Geräten ohne Kamera
- FlowRep funktioniert weiterhin nur mit IMU (ohne Kamera)

### 2.2 minSdkVersion prüfen

**Datei**: `app/android/app/build.gradle`

**Prüfen**: `minSdkVersion` muss mindestens **21** sein.
Für NPU-Support (Snapdragon): **31** empfohlen.

Falls `minSdkVersion` < 21:
```gradle
android {
    defaultConfig {
        minSdkVersion 21  // Minimum für camera-Plugin
    }
}
```

---

## 3. iOS-Permissions (für spätere iOS-Unterstützung)

### 3.1 Info.plist erweitern

**Datei**: `app/ios/Runner/Info.plist`

**Position**: Innerhalb des `<dict>`-Tags, nach dem letzten `<key>`-Eintrag:

```xml
	<!-- CV-02: Kamera für Pose Estimation -->
	<key>NSCameraUsageDescription</key>
	<string>FlowRep nutzt die Kamera zur Bewegungserkennung und Rep-Zählung. Videodaten werden ausschließlich lokal verarbeitet und niemals übertragen.</string>
```

**WICHTIG**: Der Text MUSS auf Deutsch sein (DSGVO).
Er erklärt WARUM die Kamera genutzt wird.

---

## 4. VisionConfig erstellen

### 4.1 Neue Datei anlegen

**Datei**: `app/lib/domain/vision/vision_config.dart` (NEUE DATEI)

**Ordner erstellen**: `app/lib/domain/vision/` (existiert noch nicht)

```dart
/// Konfiguration für die Computer-Vision-Pipeline.
///
/// Alle Schwellenwerte und Parameter für Pose Estimation
/// und winkelbasiertes Rep-Counting.
library;

/// Konfiguration für Pose Estimation und Rep-Erkennung.
class VisionConfig {
  /// Minimale Konfidenz für einen Landmark (0.0–1.0).
  /// Unter diesem Wert wird der Landmark als "nicht erkannt" behandelt.
  final double minLandmarkConfidence;

  /// Ellenbogen-Winkel für "unten" (gestreckt) in Grad.
  /// Bicep Curl: Arm ist gestreckt wenn Winkel > dieser Wert.
  final double angleDownThreshold;

  /// Ellenbogen-Winkel für "oben" (kontrahiert) in Grad.
  /// Bicep Curl: Arm ist kontrahiert wenn Winkel < dieser Wert.
  final double angleUpThreshold;

  /// Minimale Zeit zwischen zwei Reps (Sekunden).
  /// Verhindert Doppelzählung bei schnellem Zittern.
  final double minRepIntervalSeconds;

  /// Maximale Zeit für eine vollständige Rep (Sekunden).
  /// Länger = keine gültige Rep (zu langsam / Pause).
  final double maxRepDurationSeconds;

  /// Ob die Kamera-Pipeline aktiv ist.
  final bool enabled;

  /// Ob das Skelett-Overlay angezeigt wird.
  final bool showSkeletonOverlay;

  /// Kameramodus: 'back' (Rückkamera) oder 'front' (Frontkamera).
  final String cameraLens;

  const VisionConfig({
    this.minLandmarkConfidence = 0.5,
    this.angleDownThreshold = 160.0,
    this.angleUpThreshold = 90.0,
    this.minRepIntervalSeconds = 0.5,
    this.maxRepDurationSeconds = 5.0,
    this.enabled = false,
    this.showSkeletonOverlay = true,
    this.cameraLens = 'back',
  });

  /// Kopie mit geänderten Werten.
  VisionConfig copyWith({
    double? minLandmarkConfidence,
    double? angleDownThreshold,
    double? angleUpThreshold,
    double? minRepIntervalSeconds,
    double? maxRepDurationSeconds,
    bool? enabled,
    bool? showSkeletonOverlay,
    String? cameraLens,
  }) {
    return VisionConfig(
      minLandmarkConfidence:
          minLandmarkConfidence ?? this.minLandmarkConfidence,
      angleDownThreshold: angleDownThreshold ?? this.angleDownThreshold,
      angleUpThreshold: angleUpThreshold ?? this.angleUpThreshold,
      minRepIntervalSeconds:
          minRepIntervalSeconds ?? this.minRepIntervalSeconds,
      maxRepDurationSeconds: maxRepDurationSeconds ?? this.maxRepDurationSeconds,
      enabled: enabled ?? this.enabled,
      showSkeletonOverlay: showSkeletonOverlay ?? this.showSkeletonOverlay,
      cameraLens: cameraLens ?? this.cameraLens,
    );
  }
}
```

---

## 5. AngleCalculator erstellen

### 5.1 Neue Datei anlegen

**Datei**: `app/lib/domain/vision/angle_calculator.dart` (NEUE DATEI)

```dart
/// Berechnet Gelenkwinkel aus Pose-Landmarks.
///
/// Ein Gelenkwinkel wird aus DREI Punkten berechnet:
///   A (z.B. Schulter) → B (z.B. Ellenbogen) → C (z.B. Handgelenk)
///
/// Der Winkel ist der Innenwinkel bei B.
///
/// Formel:
///   BA = A - B (Vektor von B nach A)
///   BC = C - B (Vektor von B nach C)
///   Winkel = arccos( (BA · BC) / (|BA| * |BC|) )
library;

import 'dart:math';

/// Ein 2D-Punkt mit optionaler Konfidenz.
class LandmarkPoint {
  final double x;
  final double y;
  final double confidence;

  const LandmarkPoint({
    required this.x,
    required this.y,
    this.confidence = 1.0,
  });
}

/// Berechnet Gelenkwinkel aus drei Punkten.
class AngleCalculator {
  /// Berechnet den Winkel bei Punkt B (in Grad).
  ///
  /// [a]: Erster Punkt (z.B. Schulter)
  /// [b]: Scheitelpunkt (z.B. Ellenbogen)
  /// [c]: Dritter Punkt (z.B. Handgelenk)
  ///
  /// Rückgabe: Winkel in Grad (0–180).
  ///
  /// Beispiel Bicep Curl:
  ///   a = rechte Schulter
  ///   b = rechter Ellenbogen
  ///   c = rechtes Handgelenk
  ///   → Winkel ~170° = Arm gestreckt
  ///   → Winkel ~45° = Arm kontrahiert
  static double calculateAngle({
    required LandmarkPoint a,
    required LandmarkPoint b,
    required LandmarkPoint c,
  }) {
    // Vektor B→A
    final baX = a.x - b.x;
    final baY = a.y - b.y;

    // Vektor B→C
    final bcX = c.x - b.x;
    final bcY = c.y - b.y;

    // Skalarprodukt
    final dotProduct = baX * bcX + baY * bcY;

    // Beträge
    final magnitudeBA = sqrt(baX * baX + baY * baY);
    final magnitudeBC = sqrt(bcX * bcX + bcY * bcY);

    // Division durch Null vermeiden
    if (magnitudeBA < 1e-10 || magnitudeBC < 1e-10) {
      return 0.0;
    }

    // cos(Winkel) = Skalarprodukt / (|BA| * |BC|)
    var cosAngle = dotProduct / (magnitudeBA * magnitudeBC);

    // Numerische Sicherheit: auf [-1, 1] klemmen
    cosAngle = cosAngle.clamp(-1.0, 1.0);

    // Winkel in Radiant → Grad
    final angleRadians = acos(cosAngle);
    final angleDegrees = angleRadians * 180.0 / pi;

    return angleDegrees;
  }

  /// Prüft ob alle drei Punkte eine Mindestkonfidenz haben.
  ///
  /// [minConfidence]: Mindestkonfidenz (Standard: 0.5)
  ///
  /// Rückgabe: true wenn ALLE drei Punkte sicher genug erkannt wurden.
  static bool allConfident({
    required LandmarkPoint a,
    required LandmarkPoint b,
    required LandmarkPoint c,
    double minConfidence = 0.5,
  }) {
    return a.confidence >= minConfidence &&
        b.confidence >= minConfidence &&
        c.confidence >= minConfidence;
  }
}
```

---

## 6. CameraPoseProvider erstellen

### 6.1 Neue Datei anlegen

**Datei**: `app/lib/data/providers/camera_pose_provider.dart` (NEUE DATEI)

```dart
/// Kamera-Provider: Verwaltet Kamera-Stream und Pose Detection.
///
/// Verantwortlichkeiten:
/// 1. Kamera initialisieren und starten
/// 2. Frames an Pose Detector senden
/// 3. Erkannte Landmarks als Stream bereitstellen
/// 4. Kamera bei Bedarf stoppen und Ressourcen freigeben
///
/// WICHTIG: Dieser Provider ist OPTIONAL.
/// FlowRep funktioniert vollständig ohne ihn (nur IMU).
library;

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../../domain/vision/vision_config.dart';

/// Ein erkannter Pose-Frame mit Landmarks.
class PoseFrame {
  /// Zeitstempel in Millisekunden seit Epoch.
  final int timestampMs;

  /// Erkannte Landmarks (33 Punkte, MediaPipe-Format).
  /// Index 0 = Nase, 11 = linke Schulter, 12 = rechte Schulter,
  /// 13 = linker Ellenbogen, 14 = rechter Ellenbogen,
  /// 15 = linkes Handgelenk, 16 = rechtes Handgelenk.
  final List<PoseLandmark> landmarks;

  /// Verarbeitungszeit in Millisekunden.
  final double processingTimeMs;

  const PoseFrame({
    required this.timestampMs,
    required this.landmarks,
    required this.processingTimeMs,
  });
}

/// Ein einzelner Landmark-Punkt.
class PoseLandmark {
  final double x;
  final double y;
  final double z;
  final double confidence;

  const PoseLandmark({
    required this.x,
    required this.y,
    this.z = 0.0,
    required this.confidence,
  });
}

/// Verwaltet Kamera und Pose Detection.
class CameraPoseProvider extends ChangeNotifier {
  // === ZUSTAND ===
  CameraController? _cameraController;
  bool _isInitialized = false;
  bool _isDetecting = false;
  String? _error;

  // === STREAM ===
  final StreamController<PoseFrame> _poseFrameController =
      StreamController<PoseFrame>.broadcast();

  // === KONFIGURATION ===
  VisionConfig _config;

  CameraPoseProvider({VisionConfig config = const VisionConfig()})
      : _config = config;

  // === GETTER ===

  /// true wenn Kamera initialisiert und bereit.
  bool get isInitialized => _isInitialized;

  /// true wenn Pose Detection aktiv läuft.
  bool get isDetecting => _isDetecting;

  /// Fehlermeldung (null wenn kein Fehler).
  String? get error => _error;

  /// Stream von erkannten Pose-Frames.
  Stream<PoseFrame> get poseFrames => _poseFrameController.stream;

  /// Aktueller Kamera-Controller (für Vorschau-Widget).
  CameraController? get cameraController => _cameraController;

  /// Aktuelle Konfiguration.
  VisionConfig get config => _config;

  // === LEBENSZYKLUS ===

  /// Initialisiert die Kamera.
  ///
  /// [lens]: 'back' oder 'front' (Standard: aus Config).
  ///
  /// WICHTIG: Muss AUFGERUFEN werden bevor [startDetection].
  /// Darf nur einmal aufgerufen werden (prüft intern).
  Future<void> initializeCamera({String? lens}) async {
    if (_isInitialized) {
      debugPrint('[CameraPose] Bereits initialisiert, überspringe.');
      return;
    }

    try {
      // Verfügbare Kameras abrufen
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _error = 'Keine Kamera verfügbar.';
        notifyListeners();
        return;
      }

      // Richtige Kamera wählen
      final lensDirection = (lens ?? _config.cameraLens) == 'front'
          ? CameraLensDirection.front
          : CameraLensDirection.back;

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == lensDirection,
        orElse: () => cameras.first, // Fallback: erste verfügbare
      );

      // Controller erstellen
      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium, // 720p reicht für Pose Estimation
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      _isInitialized = true;
      _error = null;
      notifyListeners();

      debugPrint('[CameraPose] Kamera initialisiert: ${camera.name}');
    } catch (e) {
      _error = 'Kamera-Fehler: $e';
      _isInitialized = false;
      notifyListeners();
      debugPrint('[CameraPose] Fehler: $e');
    }
  }

  /// Startet die Pose Detection auf dem Kamera-Stream.
  ///
  /// WICHTIG: [initializeCamera] muss vorher aufgerufen worden sein.
  Future<void> startDetection() async {
    if (!_isInitialized || _cameraController == null) {
      _error = 'Kamera nicht initialisiert. Erst initializeCamera() aufrufen.';
      notifyListeners();
      return;
    }

    if (_isDetecting) {
      debugPrint('[CameraPose] Detection läuft bereits.');
      return;
    }

    _isDetecting = true;
    _error = null;
    notifyListeners();

    // Frame-Stream starten
    // HINWEIS: Die eigentliche Pose-Detection-Integration mit
    // flutter_pose_detection erfolgt in Doc 06 (Rep-Counter).
    // Hier wird nur der Kamera-Stream eingerichtet.
    //
    // TODO(cv-06): flutter_pose_detection NpuPoseDetector hier einbinden.
    // Für jetzt: Kamera läuft, Frames werden noch nicht verarbeitet.

    debugPrint('[CameraPose] Detection gestartet (Kamera-Stream aktiv).');
  }

  /// Stoppt die Pose Detection.
  void stopDetection() {
    _isDetecting = false;
    notifyListeners();
    debugPrint('[CameraPose] Detection gestoppt.');
  }

  /// Aktualisiert die Konfiguration.
  void updateConfig(VisionConfig newConfig) {
    _config = newConfig;
    notifyListeners();
  }

  /// Gibt alle Ressourcen frei.
  ///
  /// WICHTIG: Muss aufgerufen werden wenn die App die Kamera-Seite verlässt.
  @override
  void dispose() {
    _isDetecting = false;
    _cameraController?.dispose();
    _cameraController = null;
    _isInitialized = false;
    _poseFrameController.close();
    super.dispose();
  }
}
```

---

## 7. VisionProvider (Riverpod) erstellen

### 7.1 Neue Datei anlegen

**Datei**: `app/lib/presentation/providers/vision_provider.dart` (NEUE DATEI)

```dart
/// Riverpod-Provider für die Computer-Vision-Pipeline.
///
/// Stellt den CameraPoseProvider als ChangeNotifierProvider bereit.
/// Die UI kann über ref.watch(visionProvider) auf den Zustand zugreifen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/camera_pose_provider.dart';
import '../../domain/vision/vision_config.dart';

/// Provider für den CameraPoseProvider.
///
/// Verwendung in der UI:
/// ```dart
/// final vision = ref.watch(visionProvider);
/// if (vision.isInitialized) {
///   // Kamera-Vorschau anzeigen
/// }
/// ```
final visionProvider =
    ChangeNotifierProvider<CameraPoseProvider>((ref) {
  return CameraPoseProvider(
    config: const VisionConfig(
      enabled: true,
      showSkeletonOverlay: true,
      cameraLens: 'back',
    ),
  );
});

/// Provider für die VisionConfig (separat für Settings-Screen).
final visionConfigProvider = StateProvider<VisionConfig>((ref) {
  return const VisionConfig();
});
```

---

## 8. Test: Kamera-Setup validieren

### 8.1 Unit-Test für AngleCalculator

**Datei**: `app/test/vision/angle_calculator_test.dart` (NEUE DATEI)

**Ordner erstellen**: `app/test/vision/`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/vision/angle_calculator.dart';

void main() {
  group('AngleCalculator', () {
    test('180 Grad bei gestrecktem Arm', () {
      // Punkte auf einer Linie: A(0,0) - B(1,0) - C(2,0)
      final a = LandmarkPoint(x: 0, y: 0);
      final b = LandmarkPoint(x: 1, y: 0);
      final c = LandmarkPoint(x: 2, y: 0);

      final angle = AngleCalculator.calculateAngle(a: a, b: b, c: c);
      expect(angle, closeTo(180.0, 0.1));
    });

    test('90 Grad bei rechtem Winkel', () {
      // A(0,1) - B(0,0) - C(1,0) → rechter Winkel bei B
      final a = LandmarkPoint(x: 0, y: 1);
      final b = LandmarkPoint(x: 0, y: 0);
      final c = LandmarkPoint(x: 1, y: 0);

      final angle = AngleCalculator.calculateAngle(a: a, b: b, c: c);
      expect(angle, closeTo(90.0, 0.1));
    });

    test('45 Grad bei halbem Winkel', () {
      // A(0,1) - B(0,0) - C(1,1) → 45 Grad bei B
      final a = LandmarkPoint(x: 0, y: 1);
      final b = LandmarkPoint(x: 0, y: 0);
      final c = LandmarkPoint(x: 1, y: 1);

      final angle = AngleCalculator.calculateAngle(a: a, b: b, c: c);
      expect(angle, closeTo(45.0, 0.1));
    });

    test('0 Grad bei identischen Punkten', () {
      final a = LandmarkPoint(x: 1, y: 1);
      final b = LandmarkPoint(x: 1, y: 1);
      final c = LandmarkPoint(x: 1, y: 1);

      final angle = AngleCalculator.calculateAngle(a: a, b: b, c: c);
      expect(angle, equals(0.0));
    });

    test('allConfident prüft Mindestkonfidenz', () {
      final high = LandmarkPoint(x: 0, y: 0, confidence: 0.9);
      final low = LandmarkPoint(x: 0, y: 0, confidence: 0.3);

      expect(
        AngleCalculator.allConfident(a: high, b: high, c: high),
        isTrue,
      );
      expect(
        AngleCalculator.allConfident(a: high, b: low, c: high),
        isFalse,
      );
    });
  });
}
```

### 8.2 Unit-Test für VisionConfig

**Datei**: `app/test/vision/vision_config_test.dart` (NEUE DATEI)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/vision/vision_config.dart';

void main() {
  group('VisionConfig', () {
    test('Default-Werte sind korrekt', () {
      const config = VisionConfig();
      expect(config.minLandmarkConfidence, 0.5);
      expect(config.angleDownThreshold, 160.0);
      expect(config.angleUpThreshold, 90.0);
      expect(config.minRepIntervalSeconds, 0.5);
      expect(config.maxRepDurationSeconds, 5.0);
      expect(config.enabled, isFalse);
      expect(config.showSkeletonOverlay, isTrue);
      expect(config.cameraLens, 'back');
    });

    test('copyWith ändert nur angegebene Werte', () {
      const config = VisionConfig();
      final modified = config.copyWith(
        enabled: true,
        angleUpThreshold: 80.0,
      );

      expect(modified.enabled, isTrue);
      expect(modified.angleUpThreshold, 80.0);
      // Unveränderte Werte:
      expect(modified.angleDownThreshold, 160.0);
      expect(modified.cameraLens, 'back');
    });
  });
}
```

### 8.3 Tests ausführen

```bash
cd flowrep/app
flutter test test/vision/
```

**Erwartetes Ergebnis**: Alle Tests grün.

**Fehlerbehandlung**:
- `import` Fehler → Prüfe dass `lib/domain/vision/` Ordner existiert
- `camera` Package Fehler → `flutter pub get` erneut ausführen
- Falls `flutter_pose_detection` Import-Fehler verursacht:
  In `camera_pose_provider.dart` den Import entfernen (wird erst in Doc 06 benötigt)

---

## 9. Commit

```bash
cd flowrep/app
flutter test
flutter analyze
git add -A
git commit -m "feat(cv): Kamera-Setup mit Pose Estimation Grundlagen (CV-02)"
git push
```

---

## 10. Checkliste

- [ ] `flutter_pose_detection` und `camera` in pubspec.yaml
- [ ] `flutter pub get` erfolgreich
- [ ] Android: CAMERA Permission in AndroidManifest.xml
- [ ] Android: `uses-feature` mit `required="false"`
- [ ] iOS: NSCameraUsageDescription in Info.plist
- [ ] `lib/domain/vision/vision_config.dart` erstellt
- [ ] `lib/domain/vision/angle_calculator.dart` erstellt
- [ ] `lib/data/providers/camera_pose_provider.dart` erstellt
- [ ] `lib/presentation/providers/vision_provider.dart` erstellt
- [ ] `test/vision/angle_calculator_test.dart` erstellt + grün
- [ ] `test/vision/vision_config_test.dart` erstellt + grün
- [ ] `flutter test` → ALLE Tests grün (auch bestehende 242+)
- [ ] `flutter analyze` → 0 Errors
- [ ] Commit + Push

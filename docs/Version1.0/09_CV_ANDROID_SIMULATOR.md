# CV-06 — Android Simulator: Setup & Testing

> **Status**: ✅ DOC + Code-Soft-Fail — CameraPoseProvider setzt Fehler bei 0 Kameras / fehlendem Detector; App bleibt IMU-fähig. Emulator-Manuell-Setup bleibt Entwickler-Doku.
> **Voraussetzung**: Doc 05 (Kamera-Setup) abgeschlossen.
> **Ziel**: FlowRep mit Kamera-Pipeline im Android Emulator testen.
> **Ergebnis**: Entwickler kann ohne physisches Gerät testen.
> **EINSCHRÄNKUNG**: Emulator hat keine echte Kamera → Virtual Scene nötig.

---

## 1. Android Emulator: Kamera-Einschränkungen

### 1.1 Was funktioniert NICHT im Emulator

| Feature | Emulator | Physisches Gerät |
|---------|----------|-----------------|
| Echte Kamera | ❌ | ✅ |
| GPU Pose Detection | ❌ (nur CPU) | ✅ |
| NPU (Snapdragon) | ❌ | ✅ (nur Snapdragon) |
| Kamera-Preview | ⚠️ Virtual Scene | ✅ |
| BLE | ❌ | ✅ |
| Performance | Langsam | Normal |

### 1.2 Was FUNKTIONIERT im Emulator

| Feature | Funktioniert? |
|---------|---------------|
| App startet | ✅ |
| UI-Tests | ✅ |
| Pose Detection (CPU, langsam) | ✅ |
| Virtual Scene (simulierte Kamera) | ✅ |
| Rep-Counter-Logik | ✅ |
| Datenbank | ✅ |

---

## 2. Android Emulator einrichten

### 2.1 Voraussetzungen

- Android Studio installiert
- Android SDK (API 31+ empfohlen)
- Mindestens 8 GB RAM (Emulator braucht ~4 GB)
- Hardware-Beschleunigung (Intel HAXM oder AMD Hypervisor)

### 2.2 Emulator erstellen (Android Studio)

1. **Android Studio öffnen**
2. **Tools → Device Manager**
3. **Create Virtual Device**
4. **Gerät wählen**: "Pixel 7" (oder neuer)
5. **System Image**: API 34 (Android 14) — **x86_64** wählen
6. **WICHTIG**: "Google APIs" Image wählen (nicht "Google Play")
7. **Advanced Settings**:
   - RAM: 4096 MB
   - Internal Storage: 4096 MB
   - **Camera Front**: VirtualScene
   - **Camera Back**: VirtualScene
8. **Finish**

### 2.3 Virtual Scene konfigurieren

Der Emulator nutzt "Virtual Scene" als simulierte Kamera.

**Virtual Scene starten:**
1. Emulator starten
2. **Extended Controls** (drei Punkte `...` am Emulator-Rand)
3. **Virtual Scene** Tab
4. **Enable Virtual Scene** aktivieren
5. Ein virtuelles Objekt wählen (z.B. "Android Figure")

**WICHTIG**: Virtual Scene zeigt ein statisches 3D-Objekt.
Für Pose Estimation Testing ist das **eingeschränkt nutzbar**,
da kein echter Körper mit Gelenken sichtbar ist.

### 2.4 Alternative: Webcam als Emulator-Kamera

**Besser für Testing**: Die PC-Webcam als Emulator-Kamera nutzen.

**In Android Studio:**
1. Device Manager → Emulator bearbeiten
2. **Camera Back**: `Webcam0` (statt VirtualScene)
3. **Camera Front**: `Webcam0`
4. Speichern und Emulator neu starten

**Oder via Kommandozeile:**
```bash
emulator -avd Pixel_7_API_34 -camera-back webcam0 -camera-front webcam0
```

**Vorteil**: Echte Pose Estimation möglich (du sitzt vor der Webcam).

---

## 3. FlowRep im Emulator starten

### 3.1 Flutter-Setup prüfen

```bash
cd flowrep/app
flutter doctor
```

**Erwartet**: Android toolchain ✓, Android Studio ✓, Emulator ✓

### 3.2 Emulator starten

```bash
# Verfügbare Geräte anzeigen
flutter devices

# Falls Emulator nicht läuft:
flutter emulators --launch <emulator_id>
```

### 3.3 App starten

```bash
cd flowrep/app
flutter run -d emulator-5554
```

**WICHTIG**: Erster Start dauert 2-5 Minuten (Gradle Build).

### 3.4 Häufige Start-Fehler

| Fehler | Lösung |
|--------|--------|
| `No devices found` | Emulator starten: `flutter emulators --launch ...` |
| `Gradle build failed` | `cd android && ./gradlew clean` dann erneut |
| `INSTALL_FAILED_INSUFFICIENT_STORAGE` | Emulator-Speicher erhöhen (4GB+) |
| `Camera permission denied` | Settings → Apps → FlowRep → Permissions → Camera |
| `flutter_pose_detection` crash | Nur CPU-Modus verfügbar im Emulator (normal) |

---

## 4. Kamera-Pipeline im Emulator testen

### 4.1 Test-Szenario: Kamera-Only-Modus

Da im Emulator kein BLE/M5StickC verfügbar ist:

1. **App starten**
2. **Kamera-Modus aktivieren** (Settings oder Debug-Menü)
3. **FusionConfig**: `allowCameraOnly: true` setzen
4. **Vor die Webcam stellen** (falls Webcam als Kamera konfiguriert)
5. **Bicep Curls machen**
6. **Prüfen**: Reps werden gezählt

### 4.2 Test-Szenario: UI-Tests ohne Kamera

Für reine UI-Tests (ohne echte Pose Detection):

1. **App starten**
2. **Kamera-Modus deaktiviert lassen**
3. **IMU-Pipeline simulieren** (über Debug-Menü oder Test-Provider)
4. **UI-Interaktionen testen**: Start/Stop, Korrektur, Timer

### 4.3 Performance-Erwartungen

| Metrik | Emulator (CPU) | Physisch (GPU) |
|--------|---------------|----------------|
| Pose Detection | ~50-100ms | ~3ms |
| FPS | 5-10 | 30 |
| Rep-Erkennung | Verzögert | Echtzeit |
| Batterieverbrauch | N/A | Hoch |

**WICHTIG**: Im Emulator ist alles LANGSAM.
Das ist NORMAL und kein Bug.
Für Performance-Tests: IMMER physisches Gerät verwenden.

---

## 5. Automatisierte Tests im Emulator

### 5.1 Integration-Test (optional)

**Datei**: `app/integration_test/camera_flow_test.dart` (NEUE DATEI)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flowrep/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Camera Flow', () {
    testWidgets('App startet ohne Kamera-Crash', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // App sollte starten ohne abzustürzen
      // (Kamera ist optional, darf fehlen)
      expect(find.textContaining('FlowRep'), findsOneWidget);
    });

    testWidgets('Kamera-Permission wird angefragt', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Falls ein Kamera-Button existiert:
      // await tester.tap(find.byIcon(Icons.camera_alt));
      // await tester.pumpAndSettle();
      // Permission-Dialog sollte erscheinen (auf echtem Gerät)
    });
  });
}
```

### 5.2 Integration-Test ausführen

```bash
cd flowrep/app
flutter test integration_test/camera_flow_test.dart -d emulator-5554
```

**WICHTIG**: Integration-Tests brauchen den `integration_test` Package:

**pubspec.yaml** (dev_dependencies):
```yaml
  integration_test:
    sdk: flutter
```

---

## 6. Debugging-Tipps für den Emulator

### 6.1 Kamera-Debugging

```bash
# Emulator-Logs filtern (Kamera-bezogen)
adb logcat | grep -i "camera\|pose\|mediapipe"
```

### 6.2 Performance-Monitoring

```bash
# CPU/Memory des Emulators
adb shell top -m 10

# Flutter Performance Overlay
# In der App: Flutter DevTools → Performance
```

### 6.3 Pose Detection Debugging

Falls Pose Detection nicht funktioniert:
1. Prüfe ob `flutter_pose_detection` korrekt initialisiert wurde
2. Prüfe die Log-Ausgabe: `[CameraPose] Pose Detector aktiv (Modus: cpu)`
3. Im Emulator: NUR CPU-Modus verfügbar
4. Prüfe ob Kamera-Frames ankommen: `[CameraPose] Frame-Verarbeitungsfehler`

---

## 7. Vergleich: Emulator vs. Physisches Gerät

### 7.1 Wann Emulator nutzen

- UI-Layout-Tests
- Navigations-Flow-Tests
- Datenbank-Tests
- Rep-Counter-Logik-Tests (mit simulierten Daten)
- CI/CD (GitHub Actions nutzt Emulator)

### 7.2 Wann physisches Gerät nutzen

- Performance-Tests (FPS, Latenz)
- Echte Pose Estimation (GPU/NPU)
- BLE-Kommunikation (M5StickC)
- Batterie-Verbrauch
- Kamera-Qualität bei verschiedenen Lichtverhältnissen
- Benutzer-Akzeptanz-Tests

---

## 8. CI/CD: Emulator in GitHub Actions

### 8.1 Workflow (für spätere CI-Integration)

```yaml
# .github/workflows/android-emulator-test.yml
name: Android Emulator Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      
      - name: Enable KVM
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm
      
      - name: Run Unit Tests
        run: |
          cd flowrep/app
          flutter pub get
          flutter test
      
      # Integration-Tests mit Emulator (optional, langsam):
      # - name: Run Integration Tests
      #   uses: reactivecircus/android-emulator-runner@v2
      #   with:
      #     api-level: 34
      #     arch: x86_64
      #     script: cd flowrep/app && flutter test integration_test/ -d emulator-5554
```

**WICHTIG**: Emulator-Tests in CI sind LANGSAM (5-10 Min).
Für schnelle Feedback: Nur Unit-Tests in CI.
Emulator-Tests: Nächtlich oder vor Release.

---

## 9. Commit

```bash
cd flowrep
git add docs/Version1.0/09_CV_ANDROID_SIMULATOR.md
git commit -m "docs(cv): Android Simulator Setup & Testing Guide (CV-06)"
git push
```

---

## 10. Checkliste

- [ ] Android Studio installiert
- [ ] Emulator erstellt (Pixel 7, API 34)
- [ ] Kamera konfiguriert (Webcam0 oder VirtualScene)
- [ ] `flutter devices` zeigt Emulator
- [ ] `flutter run` startet App im Emulator
- [ ] App startet ohne Crash (auch ohne Kamera)
- [ ] Kamera-Permission wird korrekt angefragt
- [ ] Pose Detection funktioniert (CPU-Modus, langsam)
- [ ] Rep-Counter-Logik funktioniert
- [ ] Commit + Push

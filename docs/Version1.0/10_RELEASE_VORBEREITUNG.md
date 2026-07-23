# Release-Vorbereitung — FlowRep 1.0

> **Voraussetzung**: Alle P0-, P1-, P2-Features sind implementiert und getestet.
> **Ziel**: Reproduzierbarer Release-Build, APK-Signing, Versionierung.
> **Ergebnis**: Signierte APK die auf jedem Android-Gerät installierbar ist.

---

## 1. Versionierung

### 1.1 pubspec.yaml aktualisieren

**Datei**: `app/pubspec.yaml`

**VORHER**:
```yaml
version: 0.1.0
```

**NACHHER**:
```yaml
version: 1.0.0+1
```

**Format**: `MAJOR.MINOR.PATCH+BUILD_NUMBER`
- `1.0.0` = Version Name (für Benutzer sichtbar)
- `+1` = Version Code (für Android intern, muss bei jedem Release steigen)

### 1.2 Version-Code-Regeln

| Release | version |
|---------|---------|
| 1.0.0 (erstes Release) | `1.0.0+1` |
| 1.0.1 (Hotfix) | `1.0.1+2` |
| 1.1.0 (neues Feature) | `1.1.0+3` |
| 2.0.0 (Breaking Change) | `2.0.0+4` |

**WICHTIG**: Der Build-Number (nach `+`) darf NIEMALS sinken. Android lehnt Updates ab wenn der neue Build-Number ≤ dem installierten ist.

---

## 2. Pre-Release-Checkliste

### 2.1 Automatische Checks (KI führt aus)

```bash
cd flowrep/app

# 1. Alle Tests grün
flutter test
# ERWARTET: "All tests passed!" — 0 Failures

# 2. Statische Analyse
flutter analyze
# ERWARTET: "No issues found!"

# 3. Release-Build kompiliert
flutter build apk --release
# ERWARTET: "Built build\app\outputs\flutter-apk\app-release.apk"

# 4. Build-Größe prüfen
# ERWARTET: < 30 MB (ohne CV), < 50 MB (mit CV)
```

### 2.2 Manuelle Checks (Adi führt aus)

| # | Check | Bestanden? |
|---|-------|-----------|
| 1 | App startet ohne Crash | ☐ |
| 2 | BLE verbindet sich mit M5StickC Plus2 | ☐ |
| 3 | Kalibrierung läuft durch (5 Reps) | ☐ |
| 4 | Zählung funktioniert (10 Bicep Curls) | ☐ |
| 5 | Korrektur-UI erscheint nach Satzende | ☐ |
| 6 | Pausen-Timer startet nach Korrektur | ☐ |
| 7 | Session-Beenden zeigt Zusammenfassung | ☐ |
| 8 | Dark Mode ist lesbar | ☐ |
| 9 | Bildschirm sperren → Verbindung bleibt | ☐ |
| 10 | BLE-Verlust → Auto-Reconnect | ☐ |

### 2.3 Code-Qualität

| # | Check | Bestanden? |
|---|-------|-----------|
| 1 | Keine `TODO(hardware)`-Marker mehr (außer Gyro-Gate) | ☐ |
| 2 | Keine `print()`-Statements (nur `AppLogger`) | ☐ |
| 3 | `_useNewPipeline` ist immer noch `false` | ☐ |
| 4 | Alle neuen Dateien haben Doc-Comments | ☐ |
| 5 | Keine hardcodierten Strings in UI (nur Konstanten) | ☐ |

---

## 3. APK-Signing (Release)

### 3.1 Keystore erstellen (einmalig)

```bash
# Windows PowerShell
keytool -genkey -v -keystore $env:USERPROFILE\flowrep-release-key.jks `
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 `
  -alias flowrep
```

**Eingaben**:
- Keystore-Passwort: (sicher wählen, NICHT ins Repo!)
- Vorname/Nachname: Adi
- Organisation: FlowRep
- Stadt/Land: (optional)

**WICHTIG**: Die `.jks`-Datei NIEMALS ins Git-Repository committen!

### 3.2 key.properties erstellen

**Datei**: `app/android/key.properties` (NICHT committen!)

```properties
storePassword=DEIN_KEYSTORE_PASSWORT
keyPassword=DEIN_KEY_PASSWORT
keyAlias=flowrep
storeFile=C:\\Users\\adini\\flowrep-release-key.jks
```

### 3.3 .gitignore erweitern

**Datei**: `app/.gitignore` — folgende Zeilen hinzufügen:

```gitignore
# Release Signing (NIEMALS committen!)
android/key.properties
*.jks
*.keystore
```

### 3.4 build.gradle konfigurieren

**Datei**: `app/android/app/build.gradle`

**VOR** der `android {`-Block einfügen:

```groovy
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
```

**INNERHALB** `android {` — VOR `buildTypes`:

```groovy
    signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
                storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
                storePassword keystoreProperties['storePassword']
            }
        }
    }
```

**INNERHALB** `buildTypes`:

```groovy
    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
```

### 3.5 ProGuard-Regeln

**Datei**: `app/android/app/proguard-rules.pro` (erstellen falls nicht vorhanden):

```proguard
# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# flutter_blue_plus
-keep class com.lib.flutter_blue_plus.** { *; }

# Drift / SQLite
-keep class app.cash.sqldelight.** { *; }

# MediaPipe / flutter_pose_detection (falls CV aktiv)
-keep class com.google.mediapipe.** { *; }
-keep class dev.fluttercommunity.flutter_pose_detection.** { *; }
```

---

## 4. Release-Build erstellen

### 4.1 APK bauen

```bash
cd flowrep/app

# Release APK (signiert, minified, shrunk)
flutter build apk --release

# Ergebnis:
# build\app\outputs\flutter-apk\app-release.apk
```

### 4.2 APK-Größe prüfen

```powershell
# Windows
(Get-Item "build\app\outputs\flutter-apk\app-release.apk").Length / 1MB
```

**Erwartete Größe**:
- Ohne CV: 15-25 MB
- Mit CV (flutter_pose_detection): 30-45 MB

### 4.3 APK auf Gerät installieren

```bash
# Via ADB
adb install build\app\outputs\flutter-apk\app-release.apk

# Oder: APK auf Handy kopieren und im Dateimanager öffnen
```

---

## 5. Build-Varianten

### 5.1 Debug vs. Release

| Eigenschaft | Debug | Release |
|-------------|-------|--------|
| Logging | Voll (AppLogger verbose) | Nur Errors |
| Performance | Langsam (JIT) | Schnell (AOT) |
| APK-Größe | ~80 MB | ~20 MB |
| Signing | Debug-Keystore | Release-Keystore |
| Minification | Nein | Ja (R8/ProGuard) |

### 5.2 Build-Befehle

```bash
# Debug (für Entwicklung)
flutter build apk --debug

# Release (für Distribution)
flutter build apk --release

# Split per ABI (kleinere APKs pro Architektur)
flutter build apk --release --split-per-abi
# Ergebnis:
#   app-armeabi-v7a-release.apk  (~15 MB, ältere Geräte)
#   app-arm64-v8a-release.apk    (~18 MB, moderne Geräte)
#   app-x86_64-release.apk       (~20 MB, Emulatoren)
```

---

## 6. App-Permissions prüfen (Release)

### 6.1 AndroidManifest.xml

**Datei**: `app/android/app/src/main/AndroidManifest.xml`

Folgende Permissions müssen vorhanden sein:

```xml
<!-- BLE -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

<!-- Foreground Service (P0-5) -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- Kamera (nur wenn CV aktiv) -->
<uses-permission android:name="android.permission.CAMERA" />
```

### 6.2 Permissions zur Laufzeit

Ab Android 12 (API 31+) müssen BLE-Permissions zur Laufzeit angefragt werden.
`flutter_blue_plus` macht das automatisch. Falls nicht:

```dart
// In EngineNotifier.create() oder beim ersten Connect-Versuch:
await Permission.bluetoothScan.request();
await Permission.bluetoothConnect.request();
```

---

## 7. Release-Tag und Changelog

### 7.1 Git-Tag erstellen

```bash
# NACH erfolgreichem Release-Build:
git tag -a v1.0.0 -m "FlowRep 1.0.0 — Erstes offizielles Release"
git push origin v1.0.0
```

### 7.2 Changelog (für GitHub Release)

```markdown
## FlowRep 1.0.0

### Features
- Automatisches Rep-Counting via BLE/IMU (M5StickC Plus2)
- Guided Calibration Wizard (5 Referenz-Reps)
- Manuelle Korrektur (+/−) nach jedem Satz
- Pausen-Timer (90s Countdown)
- Session-Zusammenfassung beim Beenden
- BLE Auto-Reconnect (exponentielles Backoff)
- Foreground Service (Zählen bei gesperrtem Bildschirm)
- Dark Mode
- Haptic + Audio Feedback

### Bekannte Einschränkungen
- Nur Bicep Curls (weitere Übungen in 1.1)
- Nur Android (iOS in 1.1)
- Shadow-Pipeline noch nicht aktiv (_useNewPipeline = false)
```

---

## 8. Häufige Fehler beim Release-Build

| Fehler | Ursache | Lösung |
|--------|---------|--------|
| `Execution failed: R8` | ProGuard entfernt Flutter-Klassen | ProGuard-Regeln prüfen (§3.5) |
| `Keystore was tampered with` | Falsches Passwort | key.properties prüfen |
| `minSdkVersion` Fehler | flutter_blue_plus braucht ≥21 | `minSdkVersion 21` in build.gradle |
| `Duplicate class` | sqlite3 + sqlite3_flutter_libs Konflikt | `exclude group: 'org.jetbrains.kotlin'` |
| APK > 100 MB | Debug-Build statt Release | `--release` Flag prüfen |
| `flutter_pose_detection` Crash | Fehlende ML-Modelle | Internet beim ersten Start nötig |

---

## 9. Definition of Done — Release

- [ ] `version: 1.0.0+1` in pubspec.yaml
- [ ] `flutter test` → alle grün
- [ ] `flutter analyze` → 0 Issues
- [ ] `flutter build apk --release` → kompiliert
- [ ] APK < 30 MB (ohne CV)
- [ ] APK installiert auf Testgerät
- [ ] Manueller Test: Verbinden → Kalibrieren → Zählen → Korrigieren → Beenden
- [ ] Foreground Service: Bildschirm sperren → Zählung läuft weiter
- [ ] BLE-Reconnect: Sensor aus → an → App verbindet automatisch
- [ ] Dark Mode: alle Screens lesbar
- [ ] Git-Tag `v1.0.0` erstellt und gepusht
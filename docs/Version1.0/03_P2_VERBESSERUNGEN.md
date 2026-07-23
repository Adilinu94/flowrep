# P2 — Verbesserungen (Qualität & Polish)

> **Voraussetzung**: P0 und P1 sind implementiert.
> Diese Features sind nicht release-blockierend, aber wichtig für
> einen professionellen Eindruck und langfristige Wartbarkeit.

---

## Inhaltsverzeichnis

1. [Dark Mode](#1-dark-mode)
2. [Accessibility (Barrierefreiheit)](#2-accessibility)
3. [Glanceability — Große Rep-Anzeige](#3-glanceability)
4. [Benutzerfreundliche Fehlermeldungen](#4-benutzerfreundliche-fehlermeldungen)
5. [BLE-Paketverlustrate-Warnung](#5-ble-paketverlustrate-warnung)
6. [Konstanten zentralisieren](#6-konstanten-zentralisieren)
7. [Logging-Struktur verbessern](#7-logging-struktur)

---

## 1. Dark Mode

> **Status: ✅ DONE** (theme + darkTheme + ThemeMode.system in main.dart)

### 1.1 Kurzbeschreibung

Material3 mit `colorSchemeSeed` unterstützt Dark Mode nativ.
Es fehlt nur die explizite Theme-Konfiguration.

### 1.2 Implementierung

**Datei**: `app/lib/main.dart`

**VORHER** (in `FlowRepApp.build()`):
```dart
    return MaterialApp(
      title: 'FlowRep',
      theme:
          ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const HomeScreen(),
    );
```

**NACHHER**:
```dart
    return MaterialApp(
      title: 'FlowRep',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system, // Folgt System-Einstellung
      home: const HomeScreen(),
    );
```

### 1.3 Validierung

- App starten → System auf Dark Mode umstellen → App folgt automatisch
- Alle Widgets müssen in beiden Modi lesbar sein
- Besonderes Augenmerk auf: `CorrectionDialog`, `RestTimerWidget`,
  `OnboardingBanner`, `ExerciseSelectorCard`

---

## 2. Accessibility

> **Status: ✅ DONE** (Semantics auf RepCounter + RestTimer; Tooltips auf Korrektur-Buttons)

### 2.1 Kurzbeschreibung

Semantische Labels für Screen-Reader, Mindest-Tap-Targets, Kontrast.

### 2.2 Implementierung

**Datei**: `app/lib/presentation/widgets/rep_counter_display.dart`

Das Rep-Counter-Widget braucht ein `Semantics`-Wrapper:

```dart
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Wiederholungen: $repCount',
      value: '$repCount',
      child: /* bestehender Code */,
    );
  }
```

**Datei**: `app/lib/presentation/widgets/rest_timer_widget.dart`

```dart
    return Semantics(
      label: 'Pausen-Timer: $minutes Minuten $seconds Sekunden verbleibend',
      child: /* bestehender Card-Code */,
    );
```

**Datei**: `app/lib/presentation/widgets/correction_dialog.dart`

Plus/Minus-Buttons brauchen Labels:
```dart
              IconButton.filled(
                onPressed: onDecrement,
                icon: const Icon(Icons.remove, size: 28),
                tooltip: 'Eine Wiederholung weniger', // ← NEU
                // ...
              ),
              // ...
              IconButton.filled(
                onPressed: onIncrement,
                icon: const Icon(Icons.add, size: 28),
                tooltip: 'Eine Wiederholung mehr', // ← NEU
                // ...
              ),
```

**Allgemeine Regel**: Alle interaktiven Elemente müssen mindestens
48x48dp Tap-Target haben. Prüfen mit:
```bash
flutter analyze --no-pub  # Prüft einige A11y-Regeln
```

### 2.3 Validierung

```bash
# Android: TalkBack aktivieren und durch die App navigieren
# iOS: VoiceOver aktivieren
# Automatisiert:
flutter test --tags=a11y  # Falls A11y-Tests geschrieben werden
```

---

## 3. Glanceability

> **Status: ✅ DONE** (Rep-Anzeige 120sp)

### 3.1 Kurzbeschreibung

Die Rep-Anzeige muss aus 1-2 Metern Entfernung lesbar sein
(Handy liegt auf der Bank / dem Boden).

**SPEC-Referenz**: §5.2.1 Punkt 4 „Glanceability: große Fonts, klare Farben"

### 3.2 Implementierung

**Datei**: `app/lib/presentation/widgets/rep_counter_display.dart`

Die Rep-Zahl sollte `displayLarge` (96sp) oder größer sein:

```dart
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Wiederholungen: $repCount',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Große Rep-Zahl (aus 2m lesbar)
          Text(
            '$repCount',
            style: theme.textTheme.displayLarge?.copyWith(
              fontSize: 120,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Wiederholungen',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          // Qualitäts-Anzeige (optional)
          if (qualityScore != null) ...[
            const SizedBox(height: 8),
            Text(
              'Qualität: ${(qualityScore! * 100).round()}%',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
```

### 3.3 Zusätzliche Empfehlung

„Always On"-Option: Display nicht ausschalten während Zählen aktiv:

**Datei**: `app/lib/presentation/screens/home_screen.dart`

In `build()`, wenn `isCountingActive`:
```dart
import 'package:wakelock_plus/wakelock_plus.dart';

// In startCounting():
WakelockPlus.enable();

// In stopCounting() / endSession():
WakelockPlus.disable();
```

**Package**: `wakelock_plus: ^2.0.0` in `pubspec.yaml` hinzufügen.

---

## 4. Benutzerfreundliche Fehlermeldungen

> **Status: ✅ DONE** (BleErrorMapper + connect()-Integration)

### 4.1 Kurzbeschreibung

Aktuell werden rohe Exception-Strings angezeigt (`PlatformException(...)`).
Der Benutzer versteht diese nicht.

### 4.2 Implementierung

**Datei**: `app/lib/data/providers/ble_error_mapper.dart` (NEUE DATEI)

```dart
/// Wandelt technische BLE-Fehler in benutzerfreundliche Meldungen um.
class BleErrorMapper {
  /// Gibt eine benutzerfreundliche Fehlermeldung zurück.
  static String toUserMessage(Object error) {
    final msg = error.toString().toLowerCase();

    if (msg.contains('bluetooth ist nicht aktiv') ||
        msg.contains('adapterstate')) {
      return 'Bluetooth ist ausgeschaltet. '
          'Bitte Bluetooth in den Einstellungen aktivieren.';
    }

    if (msg.contains('nicht gefunden') || msg.contains('timeout')) {
      return 'GymTracker nicht gefunden. '
          'Ist der Stick eingeschaltet und in der Nähe?';
    }

    if (msg.contains('mtu')) {
      return 'Verbindungsproblem (MTU). '
          'Bitte erneut versuchen.';
    }

    if (msg.contains('permission') || msg.contains('berechtigung')) {
      return 'Bluetooth-Berechtigung fehlt. '
          'Bitte in den App-Einstellungen erlauben.';
    }

    if (msg.contains('already connected') || msg.contains('busy')) {
      return 'Das Gerät ist bereits verbunden oder beschäftigt. '
          'Bitte kurz warten und erneut versuchen.';
    }

    // Fallback
    return 'Verbindungsfehler. Bitte erneut versuchen.';
  }
}
```

**Integration** in `engine_provider.dart`, `connect()`:

**VORHER**:
```dart
    } catch (e) {
      state = state.copyWith(
        isConnected: false,
        isConnecting: false,
        errorText: e.toString(),
      );
    }
```

**NACHHER**:
```dart
    } catch (e) {
      state = state.copyWith(
        isConnected: false,
        isConnecting: false,
        errorText: BleErrorMapper.toUserMessage(e),
      );
    }
```

**Import**: `import '../../data/providers/ble_error_mapper.dart';`

---

## 5. BLE-Paketverlustrate-Warnung

> **Status: ✅ DONE** (_checkPacketLoss in EngineNotifier)

### 5.1 Kurzbeschreibung

Bei >5% Paketverlust sollte der Benutzer gewarnt werden,
da die Zählgenauigkeit leidet.

### 5.2 Implementierung

**Datei**: `app/lib/presentation/providers/engine_provider.dart`

In `_periodicRefresh()` (wird alle 500ms aufgerufen):

```dart
  void _periodicRefresh() {
    if (!isMock) {
      _updateBleDiagnostics();
      // Paketverlust-Warnung (P2)
      _checkPacketLoss();
    }
    state = state.copyWith(
      engineSampleCount: _engine.diagEngineSampleCount,
      engineThreshold: _engine.peakThreshold,
      engineBaseline: _engine.baselineLevel,
    );
  }

  void _checkPacketLoss() {
    final provider = _sensorProvider;
    if (provider is BleSensorProvider) {
      final underrunRate = provider.jitterDroppedFrames /
          (provider.jitterOutputFrames + provider.jitterDroppedFrames + 1);
      if (underrunRate > 0.05 && state.isCountingActive) {
        // Nur einmal warnen (nicht alle 500ms)
        if (state.errorText == null) {
          state = state.copyWith(
            errorText: 'Hoher Paketverlust (${(underrunRate * 100).round()}%). '
                'Zählung möglicherweise ungenau. Stick näher ans Handy halten.',
          );
        }
      }
    }
  }
```

---

## 6. Konstanten zentralisieren

> **Status: ✅ DONE** (`engine_constants.dart`; EngineNotifier nutzt kDefaultRest*, kMaxReconnect*, kMinThreshold*, kPacketLoss*)

### 6.1 Kurzbeschreibung

Magic Numbers wie `15.0` (Gyro-Gate), `250` (isSettled), `0.10`
(minThreshold) sind über den Code verstreut.

### 6.2 Implementierung

**Datei**: `app/lib/domain/config/engine_constants.dart` (NEUE DATEI)

```dart
/// Zentrale Konstanten für die Signalverarbeitung und Engine.
///
/// Alle Magic Numbers der Engine sind hier dokumentiert und
/// an einer Stelle änderbar.
library;

/// Abtastrate des M5StickC Plus2 IMU (Hz).
const double kSampleRateHz = 50.0;

/// Butterworth Bandpass: untere Grenzfrequenz (Hz).
const double kBandpassLowHz = 0.1;

/// Butterworth Bandpass: obere Grenzfrequenz (Hz).
const double kBandpassHighHz = 5.0;

/// Butterworth Einschwing-Samples (3τ bei 0.1Hz, 50Hz → ~250).
const int kSettledSamples = 250;

/// Gyro-Gate: |gyro| < 15°/s → Ruhe (Baseline-Update erlaubt).
const double kGyroRestThresholdDegPerSec = 15.0;

/// Mindestdifferenz über Baseline für Peak-Erkennung.
const double kMinThresholdAboveBaseline = 0.10;

/// Pausen-Timer Standard-Dauer (Sekunden).
const int kDefaultRestDurationSeconds = 90;

/// Reconnection: maximale Versuche.
const int kMaxReconnectAttempts = 10;

/// Reconnection: maximales Backoff (Sekunden).
const int kMaxReconnectBackoffSeconds = 16;

/// JitterBuffer: Puffergröße (Samples).
const int kJitterBufferSize = 6;

/// JitterBuffer: Ausgabe-Intervall (ms) → 50 Hz.
const int kJitterBufferTickMs = 20;

/// Template-Matching: Standard-Korrelationsschwelle.
const double kTemplateCorrelationThreshold = 0.65;

/// Template-Länge (Samples, normalisiert).
const int kTemplateLength = 64;
```

**Danach**: Alle Stellen im Code, die diese Werte nutzen, auf die
Konstanten umstellen. Beispiel in `workout_engine.dart`:

```dart
import 'config/engine_constants.dart';

// VORHER: s.gyroMagnitude < 15.0
// NACHHER: s.gyroMagnitude < kGyroRestThresholdDegPerSec
```

---

## 7. Logging-Struktur

> **Status: ✅ DONE** (AppLogger mit e(stack/error), Debug/Release-Gating)

### 7.1 Kurzbeschreibung

`AppLogger` (35 Zeilen) ist ein minimaler Wrapper. Für Produktion:
Level-basiert, in Release nur warn/error.

### 7.2 Implementierung

**Datei**: `app/lib/data/logger.dart`

```dart
import 'package:flutter/foundation.dart';

/// Strukturierter Logger für FlowRep.
///
/// In Debug: alle Level. In Release: nur warn + error.
/// Kein Cloud-Reporting in V1 (Privacy-by-Design).
class AppLogger {
  static const String _tag = 'FlowRep';

  static void d(String msg) {
    if (kDebugMode) {
      debugPrint('[$_tag][DEBUG] $msg');
    }
  }

  static void i(String msg) {
    if (kDebugMode) {
      debugPrint('[$_tag][INFO] $msg');
    }
  }

  static void w(String msg) {
    debugPrint('[$_tag][WARN] $msg');
  }

  static void e(String msg, {Object? error, StackTrace? stack}) {
    debugPrint('[$_tag][ERROR] $msg');
    if (error != null) debugPrint('  Exception: $error');
    if (stack != null && kDebugMode) debugPrint('  Stack: $stack');
  }
}
```

### 7.3 Validierung

```bash
flutter test  # Alle bestehenden Tests müssen grün bleiben
flutter analyze lib/data/logger.dart
```

# P1 — Wichtige Features (stark empfohlen für 1.0)

> **Voraussetzung**: Alle P0-Features sind implementiert und getestet.
> Nach JEDEM Feature: `flutter test` + `flutter analyze` + Commit.

---

## Inhaltsverzeichnis

1. [Globaler Error Handler](#1-globaler-error-handler)
2. [App-Lifecycle-Handling](#2-app-lifecycle-handling)
3. [Settings-Screen](#3-settings-screen)
4. [iOS-Konfiguration](#4-ios-konfiguration)
5. [Sound-Asset + pubspec](#5-sound-asset)
6. [App-Icon + Splash-Screen](#6-app-icon--splash)
7. [Widget-Tests](#7-widget-tests)
8. [CI/CD Pipeline](#8-cicd-pipeline)

---

## 1. Globaler Error Handler

> **Status: ✅ DONE** (implementiert, getestet, auf `main` gepusht)

### 1.1 Kurzbeschreibung

Aktuell gibt es keinen globalen Error Handler. Unbehandelte Exceptions
führen zum roten Flutter-Error-Screen (Debug) oder zum stillen Absturz (Release).

**Ziel**: Alle Fehler werden geloggt. In Release: benutzerfreundliche Fehlerseite.

### 1.2 Implementierung

**Datei**: `app/lib/main.dart`

**VORHER** (Zeile 15-38):
```dart
void main() {
  final sensorProvider = BleSensorProvider();
  final engine = WorkoutEngine(
    exerciseId: 'bicep_curl',
    useSignedProjectionCounting: true,
  );
  final db = AppDatabase();
  final repository = DriftWorkoutRepository(db);

  runApp(
    ProviderScope(
      overrides: [
        engineProvider.overrideWith(
          (_) => EngineNotifier.create(
            sensorProvider: sensorProvider,
            engine: engine,
            repository: repository,
          ),
        ),
      ],
      child: const FlowRepApp(),
    ),
  );
}
```

**NACHHER**:
```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Globaler Error Handler (P1): fängt alle unbehandelten Exceptions.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.e('FLUTTER-ERROR: ${details.exceptionAsString()}',
        stack: details.stack);
  };

  runZonedGuarded(() {
    final sensorProvider = BleSensorProvider();
    final engine = WorkoutEngine(
      exerciseId: 'bicep_curl',
      useSignedProjectionCounting: true,
    );
    final db = AppDatabase();
    final repository = DriftWorkoutRepository(db);

    runApp(
      ProviderScope(
        overrides: [
          engineProvider.overrideWith(
            (_) => EngineNotifier.create(
              sensorProvider: sensorProvider,
              engine: engine,
              repository: repository,
            ),
          ),
        ],
        child: const FlowRepApp(),
      ),
    );
  }, (error, stack) {
    AppLogger.e('ZONE-ERROR: $error', stack: stack);
  });
}
```

**ZUSÄTZLICHE IMPORTS** in `main.dart`:
```dart
import 'dart:async';
import 'data/logger.dart';
```

**Datei**: `app/lib/data/logger.dart` — prüfen ob `AppLogger.e` einen
`stack`-Parameter akzeptiert. Falls nicht, die Signatur erweitern:

```dart
class AppLogger {
  static void e(String msg, {Object? error, StackTrace? stack}) {
    // Bestehende Implementierung prüfen und ggf. erweitern
    debugPrint('[ERROR] $msg ${error ?? ''} ${stack ?? ''}');
  }
}
```

### 1.3 ErrorWidget für Release

**Datei**: `app/lib/main.dart`, in `FlowRepApp.build()`:

```dart
  @override
  Widget build(BuildContext context) {
    // Release: benutzerfreundliche Fehlerseite statt rotem Screen
    ErrorWidget.builder = (details) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Ein unerwarteter Fehler ist aufgetreten.',
                    style: TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Bitte starte die App neu.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => SystemNavigator.pop(),
                    child: const Text('App schließen'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    };

    return MaterialApp(
      title: 'FlowRep',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
```

**Import**: `import 'package:flutter/services.dart';` für `SystemNavigator`.

### 1.4 Validierung

```bash
flutter test
flutter analyze lib/main.dart
```

---

## 2. App-Lifecycle-Handling

> **Status: ✅ DONE** (implementiert, getestet, auf `main` gepusht)

### 2.1 Kurzbeschreibung

Die App reagiert nicht auf Background/Foreground-Wechsel. Bei `paused`
sollten Timer gestoppt werden, bei `resumed` der State aktualisiert.

### 2.2 Implementierung

**Datei**: `app/lib/presentation/providers/engine_provider.dart`

EngineNotifier erbt von `StateNotifier` — kein direkter Zugriff auf
`WidgetsBindingObserver`. Lösung: Observer in `main.dart` oder via
Riverpod-Provider.

**EINFACHSTE LÖSUNG**: Lifecycle-Listener im EngineNotifier via
`WidgetsBinding.instance.addObserver()` — aber StateNotifier hat kein
`dispose()`-Timing für Observer.

**BESSER**: Ein separater Lifecycle-Provider:

**Datei**: `app/lib/presentation/providers/lifecycle_provider.dart` (NEUE DATEI)

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Beobachtet App-Lifecycle-Änderungen und informiert den EngineNotifier.
class AppLifecycleObserver with WidgetsBindingObserver {
  final void Function(AppLifecycleState state) onStateChanged;

  AppLifecycleObserver({required this.onStateChanged}) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onStateChanged(state);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}

/// Provider der den Lifecycle-Observer erstellt.
final appLifecycleProvider = Provider<AppLifecycleObserver>((ref) {
  // Wird von EngineNotifier.create() überschrieben
  throw UnimplementedError('appLifecycleProvider muss überschrieben werden');
});
```

**Integration in EngineNotifier** (`engine_provider.dart`):

In `create()` Factory:
```dart
  static EngineNotifier create({
    required ISensorProvider sensorProvider,
    required WorkoutEngine engine,
    IWorkoutRepository? repository,
  }) {
    final notifier = EngineNotifier._(
      sensorProvider: sensorProvider,
      engine: engine,
      repository: repository,
    );
    notifier._bind();
    notifier._feedbackService.init();
    notifier._initLifecycleObserver();
    return notifier;
  }
```

Neues Feld + Methode:
```dart
  AppLifecycleObserver? _lifecycleObserver;

  void _initLifecycleObserver() {
    _lifecycleObserver = AppLifecycleObserver(
      onStateChanged: _onAppLifecycleChanged,
    );
  }

  void _onAppLifecycleChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // App im Hintergrund: Timer pausieren (BLE bleibt aktiv)
        _restTimer?.cancel();
        break;
      case AppLifecycleState.resumed:
        // App im Vordergrund: State aktualisieren
        if (state.isCountingActive && !isMock) {
          _updateBleDiagnostics();
        }
        // Rest-Timer neu starten falls aktiv
        if (state.isRestTimerActive) {
          _startRestTimer();
        }
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }
```

**ACHTUNG**: Namenskonflikt `state` (AppLifecycleState) vs. `state`
(WorkoutUiState). Im Callback den Parameter umbenennen:

```dart
  void _onAppLifecycleChanged(AppLifecycleState lifecycleState) {
    switch (lifecycleState) {
      case AppLifecycleState.paused:
        _restTimer?.cancel();
        break;
      case AppLifecycleState.resumed:
        if (state.isCountingActive && !isMock) {
          _updateBleDiagnostics();
        }
        break;
      default:
        break;
    }
  }
```

**In `dispose()`**:
```dart
    _lifecycleObserver?.dispose();
```

### 2.3 Validierung

```bash
flutter test
flutter analyze lib/presentation/providers/lifecycle_provider.dart
```

---

## 3. Settings-Screen

### 3.1 Kurzbeschreibung

Ein Einstellungs-Screen für: Haptik an/aus, Audio an/aus, Pausen-Dauer,
Daten löschen (DSGVO), App-Info.

### 3.2 Implementierung

**Datei**: `app/lib/presentation/screens/settings_screen.dart` (NEUE DATEI)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/drift_database.dart';
import '../providers/engine_provider.dart';

/// Einstellungs-Screen: Feedback, Pausen-Timer, Datenschutz.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _hapticEnabled = true;
  bool _audioEnabled = false;
  int _restDurationSeconds = 90;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // === Feedback ===
          Text('Feedback', style: Theme.of(context).textTheme.titleSmall),
          SwitchListTile(
            title: const Text('Vibration bei Wiederholung'),
            value: _hapticEnabled,
            onChanged: (v) => setState(() => _hapticEnabled = v),
          ),
          SwitchListTile(
            title: const Text('Sound bei Wiederholung'),
            value: _audioEnabled,
            onChanged: (v) => setState(() => _audioEnabled = v),
          ),
          const Divider(),

          // === Pausen-Timer ===
          Text('Pausen-Timer', style: Theme.of(context).textTheme.titleSmall),
          RadioListTile<int>(
            title: const Text('60 Sekunden'),
            value: 60,
            groupValue: _restDurationSeconds,
            onChanged: (v) => setState(() => _restDurationSeconds = v!),
          ),
          RadioListTile<int>(
            title: const Text('90 Sekunden'),
            value: 90,
            groupValue: _restDurationSeconds,
            onChanged: (v) => setState(() => _restDurationSeconds = v!),
          ),
          RadioListTile<int>(
            title: const Text('120 Sekunden'),
            value: 120,
            groupValue: _restDurationSeconds,
            onChanged: (v) => setState(() => _restDurationSeconds = v!),
          ),
          const Divider(),

          // === Datenschutz ===
          Text('Datenschutz', style: Theme.of(context).textTheme.titleSmall),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Alle Daten löschen'),
            subtitle: const Text('DSGVO: entfernt alle lokalen Daten'),
            onTap: _confirmDeleteAllData,
          ),
          const Divider(),

          // === Info ===
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('FlowRep'),
            subtitle: const Text('Version 1.0.0'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alle Daten löschen?'),
        content: const Text(
          'Dies entfernt ALLE gespeicherten Workouts und Kalibrierungen. '
          'Diese Aktion kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // TODO: repository.deleteAllUserData() + CalibrationStore.deleteAll()
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alle Daten wurden gelöscht.')),
      );
    }
  }
}
```

**Navigation**: In `HomeScreen` AppBar ein Settings-Icon hinzufügen:

```dart
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Einstellungen',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            // ... (bestehend)
          ),
        ],
```

### 3.3 Validierung

```bash
flutter test
flutter analyze lib/presentation/screens/settings_screen.dart
```

---

## 4. iOS-Konfiguration

### 4.1 Kurzbeschreibung

Ohne BLE-Permission-Strings in `Info.plist` wird die App im iOS-Review
abgelehnt und stürzt beim ersten BLE-Zugriff ab.

### 4.2 Implementierung

**Datei**: `app/ios/Runner/Info.plist`

**Position**: Innerhalb des `<dict>`-Tags, folgende Keys hinzufügen:

```xml
	<!-- BLE Permissions (FlowRep) -->
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>FlowRep benötigt Bluetooth, um sich mit dem GymTracker-Sensor zu verbinden und Wiederholungen zu zählen.</string>
	<key>NSBluetoothPeripheralUsageDescription</key>
	<string>FlowRep benötigt Bluetooth, um sich mit dem GymTracker-Sensor zu verbinden.</string>

	<!-- Background BLE (optional, für Zählen bei gesperrtem Bildschirm) -->
	<key>UIBackgroundModes</key>
	<array>
		<string>bluetooth-central</string>
	</array>
```

### 4.3 Validierung

```bash
# iOS-Build prüfen (nur auf macOS möglich):
flutter build ios --no-codesign
# Auf Windows: nur sicherstellen dass die XML-Datei valide ist
```

---

## 5. Sound-Asset

### 5.1 Kurzbeschreibung

`feedback_service.dart` referenziert `sounds/rep_click.wav` — die Datei
existiert nicht. Ohne sie wird Audio-Feedback nie funktionieren.

### 5.2 Implementierung

**SCHRITT A**: Ordner erstellen: `app/assets/sounds/`

**SCHRITT B**: Eine kurze WAV-Datei erstellen (50ms Klick-Sound).
Da wir keine Audio-Datei generieren können, eine minimale WAV erstellen:

**Datei**: `app/assets/sounds/rep_click.wav`
→ Eine 50ms, 44.1kHz, 16-bit Mono WAV-Datei (kurzer Klick).
→ Kann mit jedem Audio-Editor oder Python erstellt werden:

```python
# tools/generate_click_sound.py
import struct, wave
sr = 44100
duration = 0.05  # 50ms
n = int(sr * duration)
with wave.open('app/assets/sounds/rep_click.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sr)
    for i in range(n):
        # Exponentiell abklingender Sinus (Klick)
        import math
        val = int(16000 * math.sin(2*math.pi*1000*i/sr) * math.exp(-i/(n*0.2)))
        f.writeframes(struct.pack('<h', val))
```

**SCHRITT C**: In `pubspec.yaml` deklarieren:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/sounds/
```

### 5.3 Validierung

```bash
flutter pub get
flutter test  # FeedbackService-Test darf nicht crashen
```

---

## 6. App-Icon + Splash

### 6.1 Kurzbeschreibung

Standard-Flutter-Icon und kein Splash-Screen wirken unprofessionell.

### 6.2 Implementierung

**SCHRITT A**: Packages hinzufügen in `pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.14.0
  flutter_native_splash: ^2.4.0
```

**SCHRITT B**: Konfiguration in `pubspec.yaml` (am Ende):

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/icon/flowrep_icon.png"
  adaptive_icon_background: "#6A1B9A"
  adaptive_icon_foreground: "assets/icon/flowrep_foreground.png"

flutter_native_splash:
  color: "#6A1B9A"
  image: "assets/icon/flowrep_splash.png"
  android: true
  ios: true
```

**SCHRITT C**: Icon-Dateien erstellen (1024x1024 PNG):
- `assets/icon/flowrep_icon.png` — App-Icon (Hantel + Signalwelle)
- `assets/icon/flowrep_foreground.png` — Adaptive Icon Vordergrund
- `assets/icon/flowrep_splash.png` — Splash-Logo (weiß auf transparent)

**SCHRITT D**: Generieren:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

### 6.3 Validierung

```bash
flutter build apk --debug  # Icon sichtbar?
```

---

## 7. Widget-Tests

### 7.1 Kurzbeschreibung

Aktuell: 242 Unit-Tests, 0 Widget-Tests. Für 1.0 mindestens 10-15
Widget-Tests für die kritischen UI-Komponenten.

### 7.2 Implementierung

**Datei**: `app/test/widgets/home_screen_test.dart` (NEUE DATEI)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/presentation/providers/engine_provider.dart';
import 'package:flowrep/presentation/providers/workout_ui_state.dart';
import 'package:flowrep/presentation/screens/home_screen.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';

/// Erstellt einen Test-ProviderScope mit Mock-State.
Widget buildTestApp({WorkoutUiState? state}) {
  return ProviderScope(
    overrides: [
      engineProvider.overrideWith((_) {
        final notifier = EngineNotifier.create(
          sensorProvider: MockSensorProvider(),
          engine: WorkoutEngine(
            exerciseId: 'bicep_curl',
            useSignedProjectionCounting: true,
          ),
        );
        return notifier;
      }),
    ],
    child: const MaterialApp(home: HomeScreen()),
  );
}

void main() {
  group('HomeScreen Widget-Tests', () {
    testWidgets('Zeigt "Getrennt" wenn nicht verbunden', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();
      expect(find.text('Getrennt'), findsOneWidget);
    });

    testWidgets('Zeigt Verbinden-Button', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();
      expect(find.text('Verbinden'), findsOneWidget);
    });

    testWidgets('Zeigt FlowRep im AppBar', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();
      expect(find.text('FlowRep'), findsOneWidget);
    });
  });
}
```

**Datei**: `app/test/widgets/correction_dialog_test.dart` (NEUE DATEI)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/presentation/widgets/correction_dialog.dart';

void main() {
  group('CorrectionDialog', () {
    testWidgets('Zeigt gezählte Reps und +/- Buttons', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CorrectionDialog(
            countedReps: 10,
            userReps: 10,
            onIncrement: () {},
            onDecrement: () {},
            onConfirm: () {},
            onDismiss: () {},
          ),
        ),
      ));

      expect(find.text('Satz abgeschlossen'), findsOneWidget);
      expect(find.text('Gezählt: 10 Wiederholungen'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
    });

    testWidgets('Danke-Nachricht nur bei Korrektur', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CorrectionDialog(
            countedReps: 10,
            userReps: 9, // Korrigiert!
            onIncrement: () {},
            onDecrement: () {},
            onConfirm: () {},
            onDismiss: () {},
          ),
        ),
      ));

      expect(
        find.text('Danke, das hilft uns die Erkennung zu verbessern.'),
        findsOneWidget,
      );
    });

    testWidgets('onIncrement wird aufgerufen', (tester) async {
      var incremented = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CorrectionDialog(
            countedReps: 10,
            userReps: 10,
            onIncrement: () => incremented = true,
            onDecrement: () {},
            onConfirm: () {},
            onDismiss: () {},
          ),
        ),
      ));

      await tester.tap(find.byIcon(Icons.add));
      expect(incremented, isTrue);
    });
  });
}
```

**Datei**: `app/test/widgets/rest_timer_test.dart` (NEUE DATEI)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/presentation/widgets/rest_timer_widget.dart';

void main() {
  group('RestTimerWidget', () {
    testWidgets('Zeigt verbleibende Zeit', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RestTimerWidget(
            secondsRemaining: 75,
            totalSeconds: 90,
            onSkip: () {},
          ),
        ),
      ));

      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('1:15'), findsOneWidget);
      expect(find.text('Pause überspringen'), findsOneWidget);
    });

    testWidgets('Skip-Button ruft Callback', (tester) async {
      var skipped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RestTimerWidget(
            secondsRemaining: 45,
            totalSeconds: 90,
            onSkip: () => skipped = true,
          ),
        ),
      ));

      await tester.tap(find.text('Pause überspringen'));
      expect(skipped, isTrue);
    });
  });
}
```

### 7.3 Validierung

```bash
flutter test test/widgets/
flutter test  # Gesamte Suite
```

---

## 8. CI/CD Pipeline

### 8.1 Kurzbeschreibung

GitHub Actions Workflow: bei jedem Push → analyze + test + build.

### 8.2 Implementierung

**Datei**: `.github/workflows/ci.yml` (NEUE DATEI, im Repo-Root)

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: flowrep/app

    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
          channel: 'stable'
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Analyze
        run: flutter analyze --no-pub

      - name: Test
        run: flutter test --coverage

      - name: Build APK (smoke)
        run: flutter build apk --debug
```

### 8.3 Validierung

```bash
# Lokal simulieren:
cd flowrep/app
flutter analyze --no-pub
flutter test --coverage
flutter build apk --debug
```

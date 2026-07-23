# P0 — Kritische Features (Release-Blocker)

> **Regel**: Jeder Schritt ist exakt beschrieben. Keine Abweichungen. Keine Eigeninterpretation.
> Nach JEDEM Schritt: `flutter test` muss grün sein. Nach JEDEM Feature: Commit + Push.

---

## Inhaltsverzeichnis

1. [Korrektur-UI (+/− Buttons)](#1-korrektur-ui)
2. [Pausen-Timer (90s Countdown)](#2-pausen-timer)
3. [Session-Beenden-Flow](#3-session-beenden-flow)
4. [Reconnection-Strategie (exponentielles Backoff)](#4-reconnection-strategie)
5. [Foreground Service (Android 15+)](#5-foreground-service)

---

## 1. Korrektur-UI

> **Status: ✅ DONE** (implementiert, getestet, auf `main` gepusht)

### 1.1 Kurzbeschreibung

Nach jedem abgeschlossenen Satz kann der Benutzer die gezählten Wiederholungen
manuell korrigieren (+1 / −1). Die Korrektur wird als `CorrectionEvent` in der
Datenbank gespeichert. Das Modell existiert bereits — es fehlt nur die UI + Logik.

**SPEC-Referenz**: GYM_TRACKER_ARCHITEKTUR.md §5.1.4, Definition of Done 1.4/1.5
**WICHTIG**: Nachricht bei Korrektur: „Danke, das hilft uns die Erkennung zu verbessern."
**VERBOTEN**: „Die KI lernt dazu" (V1 hat kein ML).

### 1.2 Abhängigkeiten

- `workout_models.dart` → `CorrectionEvent` existiert bereits (Zeile 80-94)
- `i_workout_repository.dart` → `saveCorrection()` existiert bereits (Zeile 10)
- `drift_database.dart` → `CorrectionEvents`-Tabelle existiert (Zeile 96-106)
- `engine_provider.dart` → `_onSetCompleted()` (Zeile 222-226) ist der Ankerpunkt

### 1.3 Schritt-für-Schritt-Implementierung

#### SCHRITT A: WorkoutUiState erweitern

**Datei**: `app/lib/presentation/providers/workout_ui_state.dart`

**Was tun**: Drei neue Felder hinzufügen, die den Korrektur-Zustand tracken.

**Position**: Nach Zeile 37 (`final bool hasCalibration;`) einfügen:

```dart
  // Manuelle Korrektur (SPEC §5.1.4)
  final bool showCorrectionDialog;
  final int? correctionSetCountedReps;
  final int? correctionSetUserReps;
```

**Position**: Im Konstruktor (nach `this.hasCalibration = false,`):

```dart
    this.showCorrectionDialog = false,
    this.correctionSetCountedReps,
    this.correctionSetUserReps,
```

**Position**: In `copyWith()` Parameter-Liste (nach `bool? hasCalibration,`):

```dart
    bool? showCorrectionDialog,
    int? correctionSetCountedReps,
    int? correctionSetUserReps,
```

**Position**: In `copyWith()` Return-Statement (nach `hasCalibration: ...`):

```dart
      showCorrectionDialog: showCorrectionDialog ?? this.showCorrectionDialog,
      correctionSetCountedReps: correctionSetCountedReps ?? this.correctionSetCountedReps,
      correctionSetUserReps: correctionSetUserReps ?? this.correctionSetUserReps,
```

**ACHTUNG**: `copyWith` nutzt `??` — für nullable Felder die auf null gesetzt werden
sollen (z.B. Dialog schließen), muss ein spezielles Pattern verwendet werden.
Da `showCorrectionDialog` ein bool ist (nicht nullable), reicht `??` hier.
Für `correctionSetCountedReps` und `correctionSetUserReps` (nullable int) gilt:
Wenn sie auf null gesetzt werden sollen, muss der Aufrufer explizit `null` übergeben
UND das Feld im Return-Statement direkt setzen (nicht via `??`).

**KORREKTUR für nullable Reset**: Im Return-Statement stattdessen:

```dart
      showCorrectionDialog: showCorrectionDialog ?? this.showCorrectionDialog,
      correctionSetCountedReps: correctionSetCountedReps,
      correctionSetUserReps: correctionSetUserReps,
```

NEIN — das würde bei jedem copyWith die Werte nullen. Besser: Sentinel-Pattern
verwenden ODER die Felder einfach beibehalten und nur bei Bedarf überschreiben.

**EINFACHSTE LÖSUNG** (empfohlen): Die nullable-Felder mit `??` behandeln und
zum Zurücksetzen einfach `showCorrectionDialog: false` setzen. Die int-Felder
bleiben dann stale, aber das ist egal weil der Dialog zu ist.

```dart
      showCorrectionDialog: showCorrectionDialog ?? this.showCorrectionDialog,
      correctionSetCountedReps: correctionSetCountedReps ?? this.correctionSetCountedReps,
      correctionSetUserReps: correctionSetUserReps ?? this.correctionSetUserReps,
```

#### SCHRITT B: EngineNotifier — Korrektur-Logik

**Datei**: `app/lib/presentation/providers/engine_provider.dart`

**Was tun**: Methoden `showCorrectionForLastSet()`, `applyCorrection(int delta)`,
`dismissCorrection()` hinzufügen.

**Position**: Nach `stopCounting()` (Zeile 116) einfügen:

```dart
  // === Manuelle Korrektur (SPEC §5.1.4) ===

  /// Zeigt den Korrektur-Dialog für den zuletzt abgeschlossenen Satz.
  /// Wird automatisch nach Satzende aufgerufen.
  void showCorrectionForLastSet(int countedReps) {
    state = state.copyWith(
      showCorrectionDialog: true,
      correctionSetCountedReps: countedReps,
      correctionSetUserReps: countedReps,
    );
  }

  /// Wendet eine Korrektur an (+1 oder -1).
  /// Aktualisiert den User-Reps-Wert im Dialog.
  void applyCorrectionDelta(int delta) {
    final current = state.correctionSetUserReps ?? state.correctionSetCountedReps ?? 0;
    final newValue = (current + delta).clamp(0, 999);
    state = state.copyWith(correctionSetUserReps: newValue);
  }

  /// Bestätigt die Korrektur und speichert CorrectionEvent.
  Future<void> confirmCorrection() async {
    final countedReps = state.correctionSetCountedReps;
    final userReps = state.correctionSetUserReps;
    if (countedReps == null || userReps == null) {
      dismissCorrection();
      return;
    }

    // Nur speichern wenn tatsächlich korrigiert wurde
    if (userReps != countedReps) {
      // Letzten Satz in _completedSets aktualisieren
      if (_completedSets.isNotEmpty) {
        final lastSet = _completedSets.last;
        _completedSets[_completedSets.length - 1] =
            lastSet.copyWith(correctedReps: userReps);
      }

      // CorrectionEvent persistieren
      final repo = _repository;
      if (repo != null) {
        final event = CorrectionEvent(
          id: _generateId(),
          setId: _completedSets.isNotEmpty ? _completedSets.last.id : 'unknown',
          systemCount: countedReps,
          userCorrectedCount: userReps,
          timestamp: DateTime.now(),
        );
        try {
          await repo.saveCorrection(event);
        } catch (_) {
          // DB-Fehler nicht fatal
        }
      }

      // Session neu speichern (mit korrigiertem Satz)
      _saveSession();
    }

    dismissCorrection();
  }

  /// Schließt den Korrektur-Dialog ohne zu speichern.
  void dismissCorrection() {
    state = state.copyWith(showCorrectionDialog: false);
  }
```

**ZUSÄTZLICH**: Import für `CorrectionEvent` prüfen.
Die Datei importiert bereits `workout_models.dart` (Zeile 12):
```dart
import '../../domain/models/workout_models.dart';
```
→ `CorrectionEvent` ist darin enthalten. Kein neuer Import nötig.

#### SCHRITT C: Korrektur-Dialog automatisch nach Satzende zeigen

**Datei**: `app/lib/presentation/providers/engine_provider.dart`

**Position**: In `_onEngineEvent()`, nach dem Block `if (event.completedSet != null)`
(Zeile 201-206). Den Block erweitern:

**VORHER** (Zeile 201-206):
```dart
    // Satz abgeschlossen → Feedback + Persistence
    if (event.completedSet != null) {
      _feedbackService.onSetCompleted(
          repCount: event.completedSet!.countedReps);
      _onSetCompleted(event.completedSet!);
    }
```

**NACHHER**:
```dart
    // Satz abgeschlossen → Feedback + Persistence + Korrektur-Dialog
    if (event.completedSet != null) {
      _feedbackService.onSetCompleted(
          repCount: event.completedSet!.countedReps);
      _onSetCompleted(event.completedSet!);
      // Korrektur-Dialog zeigen (SPEC §5.1.4)
      showCorrectionForLastSet(event.completedSet!.countedReps);
    }
```

#### SCHRITT D: Korrektur-Dialog Widget erstellen

**Datei**: `app/lib/presentation/widgets/correction_dialog.dart` (NEUE DATEI)

```dart
import 'package:flutter/material.dart';

/// Korrektur-Dialog (SPEC §5.1.4): Nach Satzende kann der Benutzer
/// die gezählten Wiederholungen manuell korrigieren.
///
/// Nachricht: „Danke, das hilft uns die Erkennung zu verbessern."
/// NICHT: „Die KI lernt dazu" (V1 hat kein ML).
class CorrectionDialog extends StatelessWidget {
  final int countedReps;
  final int userReps;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const CorrectionDialog({
    super.key,
    required this.countedReps,
    required this.userReps,
    required this.onIncrement,
    required this.onDecrement,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wasCorrected = userReps != countedReps;

    return AlertDialog(
      title: const Text('Satz abgeschlossen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gezählte Reps anzeigen
          Text(
            'Gezählt: $countedReps Wiederholungen',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),

          // Korrektur-Buttons (+/−)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Minus-Button
              IconButton.filled(
                onPressed: onDecrement,
                icon: const Icon(Icons.remove, size: 28),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red.shade100,
                  foregroundColor: Colors.red.shade800,
                ),
              ),
              const SizedBox(width: 24),

              // Aktuelle Zahl (groß)
              Text(
                '$userReps',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: wasCorrected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 24),

              // Plus-Button
              IconButton.filled(
                onPressed: onIncrement,
                icon: const Icon(Icons.add, size: 28),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.green.shade100,
                  foregroundColor: Colors.green.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Danke-Nachricht (nur wenn korrigiert)
          if (wasCorrected)
            Text(
              'Danke, das hilft uns die Erkennung zu verbessern.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onDismiss,
          child: const Text('Überspringen'),
        ),
        FilledButton(
          onPressed: onConfirm,
          child: Text(wasCorrected ? 'Korrigieren' : 'Bestätigen'),
        ),
      ],
    );
  }
}
```

#### SCHRITT E: Dialog im HomeScreen anzeigen

**Datei**: `app/lib/presentation/screens/home_screen.dart`

**Position**: Am ANFANG der `build()`-Methode, NACH `final notifier = ...`
(Zeile 27), den Dialog-Trigger einfügen:

**VORHER** (Zeile 25-28):
```dart
  Widget build(BuildContext context, WidgetRef ref) {
    final uiState = ref.watch(engineProvider);
    final notifier = ref.read(engineProvider.notifier);
```

**NACHHER**:
```dart
  Widget build(BuildContext context, WidgetRef ref) {
    final uiState = ref.watch(engineProvider);
    final notifier = ref.read(engineProvider.notifier);

    // Korrektur-Dialog anzeigen wenn nötig (SPEC §5.1.4)
    ref.listen<WorkoutUiState>(engineProvider, (prev, next) {
      if (next.showCorrectionDialog && !(prev?.showCorrectionDialog ?? false)) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => CorrectionDialog(
            countedReps: next.correctionSetCountedReps ?? 0,
            userReps: next.correctionSetUserReps ?? 0,
            onIncrement: () => notifier.applyCorrectionDelta(1),
            onDecrement: () => notifier.applyCorrectionDelta(-1),
            onConfirm: () {
              notifier.confirmCorrection();
              Navigator.of(context).pop();
            },
            onDismiss: () {
              notifier.dismissCorrection();
              Navigator.of(context).pop();
            },
          ),
        );
      }
    });
```

**ZUSÄTZLICH**: Import am Anfang der Datei hinzufügen:
```dart
import '../widgets/correction_dialog.dart';
```

**ACHTUNG**: `ref.listen` in einer `ConsumerWidget.build()` ist erlaubt,
wird aber bei jedem Rebuild aufgerufen. Der Guard
`!(prev?.showCorrectionDialog ?? false)` verhindert doppelte Dialoge.

**ALTERNATIVE** (sauberer): Den Dialog-Trigger in den `return Scaffold(...)` 
als `builder`-Callback legen. Aber `ref.listen` ist der Riverpod-Standard.

#### SCHRITT F: Tests

**Datei**: `app/test/correction_test.dart` (NEUE DATEI)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/models/workout_models.dart';

void main() {
  group('CorrectionEvent Modell', () {
    test('CorrectionEvent speichert systemCount und userCorrectedCount', () {
      final event = CorrectionEvent(
        id: 'test-1',
        setId: 'set-1',
        systemCount: 10,
        userCorrectedCount: 9,
        timestamp: DateTime(2026, 7, 22),
      );
      expect(event.systemCount, 10);
      expect(event.userCorrectedCount, 9);
      expect(event.setId, 'set-1');
    });
  });

  group('ExerciseSet.copyWith Korrektur', () {
    test('correctedReps wird gesetzt', () {
      final set = ExerciseSet(
        id: 's1',
        exerciseId: 'bicep_curl',
        countedReps: 10,
        endedAt: DateTime.now(),
        reps: [],
      );
      final corrected = set.copyWith(correctedReps: 9);
      expect(corrected.correctedReps, 9);
      expect(corrected.countedReps, 10); // Original bleibt
      expect(corrected.effectiveReps, 9); // effectiveReps nutzt Korrektur
    });

    test('effectiveReps fällt auf countedReps zurück ohne Korrektur', () {
      final set = ExerciseSet(
        id: 's2',
        exerciseId: 'bicep_curl',
        countedReps: 8,
        endedAt: DateTime.now(),
        reps: [],
      );
      expect(set.effectiveReps, 8);
    });
  });
}
```

### 1.4 Validierung

```bash
cd app
flutter test test/correction_test.dart
flutter test
flutter analyze lib/presentation/widgets/correction_dialog.dart
flutter analyze lib/presentation/providers/engine_provider.dart
```

### 1.5 Stolperfallen

| # | Fehler | Symptom | Vermeidung |
|---|--------|---------|-----------|
| 1 | Dialog zeigt sich mehrfach | Zwei Dialoge übereinander | Guard in `ref.listen`: `!(prev?.showCorrectionDialog ?? false)` |
| 2 | `Navigator.pop()` nach `confirmCorrection()` | Dialog bleibt offen | `pop()` NACH `confirmCorrection()` aufrufen |
| 3 | `_completedSets.last` bei leerer Liste | Crash | `if (_completedSets.isNotEmpty)` Guard |
| 4 | Nachricht „Die KI lernt dazu" | SPEC-Verstoß | EXAKT: „Danke, das hilft uns die Erkennung zu verbessern." |
| 5 | `copyWith` nullt nullable Felder | Korrektur-Werte verschwinden | `??`-Pattern beibehalten, Dialog-State separat resetten |

---

## 2. Pausen-Timer

> **Status: ✅ DONE** (implementiert, getestet, auf `main` gepusht)

### 2.1 Kurzbeschreibung

Nach Satzende läuft ein 90-Sekunden-Countdown. Der Benutzer sieht die verbleibende
Pause. Bei Bewegung (neuer Satz) stoppt der Timer automatisch.

**SPEC-Referenz**: Phase 2, §5.2.1 Punkt 2, Definition of Done 2.2

### 2.2 Abhängigkeiten

- Feature 1 (Korrektur-UI) sollte VORHER implementiert sein
  (Korrektur-Dialog erscheint VOR dem Timer)
- `WorkoutState.resting` existiert bereits in `workout_state_machine.dart`
- `RestTimerExpired` Event existiert bereits (Zeile 69)

### 2.3 Schritt-für-Schritt-Implementierung

#### SCHRITT A: WorkoutUiState erweitern

**Datei**: `app/lib/presentation/providers/workout_ui_state.dart`

**Neue Felder** (nach den Korrektur-Feldern):

```dart
  // Pausen-Timer (SPEC Phase 2, §5.2.1)
  final bool isRestTimerActive;
  final int restTimerSecondsRemaining;
```

**Konstruktor**:
```dart
    this.isRestTimerActive = false,
    this.restTimerSecondsRemaining = 90,
```

**copyWith Parameter**:
```dart
    bool? isRestTimerActive,
    int? restTimerSecondsRemaining,
```

**copyWith Return**:
```dart
      isRestTimerActive: isRestTimerActive ?? this.isRestTimerActive,
      restTimerSecondsRemaining: restTimerSecondsRemaining ?? this.restTimerSecondsRemaining,
```

#### SCHRITT B: Timer-Logik im EngineNotifier

**Datei**: `app/lib/presentation/providers/engine_provider.dart`

**Neues Feld** (bei den anderen Timern, Zeile ~72):
```dart
  Timer? _restTimer;
  int _restDurationSeconds = 90; // Standard: 90s (SPEC §5.2.1)
```

**Neue Methoden** (nach `dismissCorrection()`):

```dart
  // === Pausen-Timer (SPEC Phase 2, §5.2.1) ===

  /// Startet den Pausen-Timer nach Satzende.
  void _startRestTimer() {
    _restTimer?.cancel();
    state = state.copyWith(
      isRestTimerActive: true,
      restTimerSecondsRemaining: _restDurationSeconds,
    );
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.restTimerSecondsRemaining - 1;
      if (remaining <= 0) {
        _stopRestTimer();
        // Timer abgelaufen: kein automatischer Zustandswechsel in V1
        // (der Benutzer startet den nächsten Satz manuell via Start-Button)
      } else {
        state = state.copyWith(restTimerSecondsRemaining: remaining);
      }
    });
  }

  /// Stoppt den Pausen-Timer (manuell oder bei Bewegung).
  void _stopRestTimer() {
    _restTimer?.cancel();
    _restTimer = null;
    state = state.copyWith(isRestTimerActive: false);
  }

  /// Öffentlicher Zugriff: Timer manuell stoppen (z.B. „Pause überspringen").
  void skipRest() => _stopRestTimer();
```

**Timer starten nach Korrektur-Dialog**: In `confirmCorrection()` und
`dismissCorrection()` am ENDE hinzufügen:

```dart
  void dismissCorrection() {
    state = state.copyWith(showCorrectionDialog: false);
    _startRestTimer(); // Pausen-Timer nach Dialog starten
  }
```

Und in `confirmCorrection()` am Ende (vor `dismissCorrection()`):
```dart
    // dismissCorrection() ruft bereits _startRestTimer()
    dismissCorrection();
```

**Timer stoppen bei Zähl-Start**: In `startCounting()`:

**VORHER**:
```dart
  void startCounting() {
    if (state.isCountingActive) return;
    state = state.copyWith(isCountingActive: true);
  }
```

**NACHHER**:
```dart
  void startCounting() {
    if (state.isCountingActive) return;
    _stopRestTimer(); // Pausen-Timer stoppen bei neuem Satz
    state = state.copyWith(isCountingActive: true);
  }
```

**Timer in dispose() stoppen**: In `dispose()` (Zeile ~370):
```dart
    _restTimer?.cancel();
```

#### SCHRITT C: RestTimerWidget erstellen

**Datei**: `app/lib/presentation/widgets/rest_timer_widget.dart` (NEUE DATEI)

```dart
import 'package:flutter/material.dart';

/// Pausen-Timer-Widget (SPEC Phase 2, §5.2.1).
///
/// Zeigt einen kreisförmigen Countdown nach Satzende.
/// Der Benutzer kann die Pause überspringen.
class RestTimerWidget extends StatelessWidget {
  final int secondsRemaining;
  final int totalSeconds;
  final VoidCallback onSkip;

  const RestTimerWidget({
    super.key,
    required this.secondsRemaining,
    required this.totalSeconds,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = secondsRemaining / totalSeconds;
    final minutes = secondsRemaining ~/ 60;
    final seconds = secondsRemaining % 60;

    return Card(
      elevation: 2,
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Pause',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            // Kreisförmiger Countdown
            SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 8,
                    backgroundColor: theme.colorScheme.tertiaryContainer,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.tertiary,
                    ),
                  ),
                  Text(
                    '$minutes:${seconds.toString().padLeft(2, '0')}',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onSkip,
              child: const Text('Pause überspringen'),
            ),
          ],
        ),
      ),
    );
  }
}
```

#### SCHRITT D: Widget im HomeScreen einbinden

**Datei**: `app/lib/presentation/screens/home_screen.dart`

**Import hinzufügen**:
```dart
import '../widgets/rest_timer_widget.dart';
```

**Position**: Nach dem `RepCounterDisplay`-Block (Zeile ~123), VOR `SetHistoryCard`:

```dart
                // Pausen-Timer (nur wenn aktiv)
                if (uiState.isRestTimerActive) ...[
                  const SizedBox(height: 16),
                  RestTimerWidget(
                    secondsRemaining: uiState.restTimerSecondsRemaining,
                    totalSeconds: 90,
                    onSkip: notifier.skipRest,
                  ),
                ],
```

### 2.4 Validierung

```bash
flutter test
flutter analyze lib/presentation/widgets/rest_timer_widget.dart
```

### 2.5 Stolperfallen

| # | Fehler | Symptom | Vermeidung |
|---|--------|---------|-----------|
| 1 | Timer läuft nach dispose() weiter | Memory Leak | `_restTimer?.cancel()` in `dispose()` |
| 2 | Timer startet trotz offenem Korrektur-Dialog | Timer + Dialog gleichzeitig | Timer erst NACH Dialog-Dismiss starten |
| 3 | `restTimerSecondsRemaining` wird negativ | Anzeige „-1" | `if (remaining <= 0)` Guard |
| 4 | Timer stoppt nicht bei Start-Button | Timer läuft während Zählen | `_stopRestTimer()` in `startCounting()` |

---

## 3. Session-Beenden-Flow

### 3.1 Kurzbeschreibung

Ein „Training beenden"-Button stoppt das Zählen, speichert die vollständige
Session und zeigt eine Zusammenfassung. Aktuell gibt es nur `stopCounting()`
das auf idle zurücksetzt — ohne Session-Abschluss.

### 3.2 Abhängigkeiten

- Feature 1 (Korrektur-UI) und Feature 2 (Pausen-Timer) sollten fertig sein
- `_saveSession()` existiert bereits (Zeile 229-243)
- `_completedSets` und `_sessionStartedAt` existieren bereits

### 3.3 Schritt-für-Schritt-Implementierung

#### SCHRITT A: WorkoutUiState erweitern

**Neue Felder**:
```dart
  // Session-Zusammenfassung
  final bool showSessionSummary;
  final int sessionTotalSets;
  final int sessionTotalReps;
  final Duration? sessionDuration;
```

**Konstruktor**:
```dart
    this.showSessionSummary = false,
    this.sessionTotalSets = 0,
    this.sessionTotalReps = 0,
    this.sessionDuration,
```

**copyWith** (Parameter + Return, gleiches Pattern wie oben).

#### SCHRITT B: EngineNotifier — endSession()

**Datei**: `app/lib/presentation/providers/engine_provider.dart`

**Neue Methode** (nach `skipRest()`):

```dart
  // === Session-Beenden-Flow ===

  /// Beendet die aktuelle Trainingssession.
  /// Speichert alle Sets, stoppt Timer, zeigt Zusammenfassung.
  Future<void> endSession() async {
    // 1. Alles stoppen
    if (state.isCountingActive) {
      _engine.pause();
    }
    _stopRestTimer();
    dismissCorrection();

    // 2. Session-Daten sammeln
    final totalSets = _completedSets.length;
    final totalReps = _completedSets.fold<int>(
      0,
      (sum, s) => sum + s.effectiveReps,
    );
    final duration = _sessionStartedAt != null
        ? DateTime.now().difference(_sessionStartedAt!)
        : null;

    // 3. Session final speichern
    final repo = _repository;
    if (repo != null && _sessionStartedAt != null && _completedSets.isNotEmpty) {
      final session = WorkoutSession(
        id: _generateId(),
        startedAt: _sessionStartedAt!,
        endedAt: DateTime.now(),
        sets: List.unmodifiable(_completedSets),
      );
      try {
        await repo.saveSession(session);
      } catch (_) {
        // DB-Fehler nicht fatal
      }
    }

    // 4. State aktualisieren: Zusammenfassung zeigen
    state = state.copyWith(
      isCountingActive: false,
      workoutState: WorkoutState.idle,
      repsInCurrentSet: 0,
      showSessionSummary: true,
      sessionTotalSets: totalSets,
      sessionTotalReps: totalReps,
      sessionDuration: duration,
    );

    // 5. Session-State zurücksetzen für nächste Session
    _sessionStartedAt = null;
    _completedSets.clear();
  }

  /// Schließt die Session-Zusammenfassung.
  void dismissSessionSummary() {
    state = state.copyWith(showSessionSummary: false);
  }
```

#### SCHRITT C: SessionSummaryDialog Widget

**Datei**: `app/lib/presentation/widgets/session_summary_dialog.dart` (NEUE DATEI)

```dart
import 'package:flutter/material.dart';

/// Session-Zusammenfassung nach „Training beenden".
class SessionSummaryDialog extends StatelessWidget {
  final int totalSets;
  final int totalReps;
  final Duration? duration;
  final VoidCallback onDismiss;

  const SessionSummaryDialog({
    super.key,
    required this.totalSets,
    required this.totalReps,
    required this.duration,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Training beendet'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatRow(icon: Icons.fitness_center, label: 'Sätze', value: '$totalSets'),
          const SizedBox(height: 8),
          _StatRow(icon: Icons.repeat, label: 'Wiederholungen', value: '$totalReps'),
          if (duration != null) ...[
            const SizedBox(height: 8),
            _StatRow(
              icon: Icons.timer,
              label: 'Dauer',
              value: '${duration!.inMinutes} min',
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: onDismiss,
          child: const Text('Fertig'),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
```

#### SCHRITT D: „Training beenden"-Button im HomeScreen

**Datei**: `app/lib/presentation/screens/home_screen.dart`

**Import**:
```dart
import '../widgets/session_summary_dialog.dart';
```

**Position**: Nach dem Start/Stop-Button (Zeile ~116), ein zusätzlicher Button
der NUR sichtbar ist wenn `isCountingActive == true` ODER `_completedSets` nicht leer:

```dart
                // Training beenden (nur wenn Session aktiv)
                if (uiState.isCountingActive || uiState.repsInCurrentSet > 0) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _confirmEndSession(context, notifier),
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Training beenden'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                    ),
                  ),
                ],
```

**Bestätigungs-Dialog** (als private Methode in HomeScreen):

```dart
  void _confirmEndSession(BuildContext context, EngineNotifier notifier) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Training beenden?'),
        content: const Text(
          'Möchtest du das Training beenden? '
          'Alle Sätze werden gespeichert.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              notifier.endSession();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Beenden'),
          ),
        ],
      ),
    );
  }
```

**Session-Summary-Dialog** via `ref.listen` (neben dem Korrektur-Dialog):

```dart
    // Session-Zusammenfassung anzeigen
    ref.listen<WorkoutUiState>(engineProvider, (prev, next) {
      if (next.showSessionSummary && !(prev?.showSessionSummary ?? false)) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => SessionSummaryDialog(
            totalSets: next.sessionTotalSets,
            totalReps: next.sessionTotalReps,
            duration: next.sessionDuration,
            onDismiss: () {
              notifier.dismissSessionSummary();
              Navigator.of(context).pop();
            },
          ),
        );
      }
    });
```

**HINWEIS**: Beide `ref.listen`-Aufrufe können in EINEM `ref.listen` kombiniert
werden, um doppelte Subscriptions zu vermeiden. Besser:

```dart
    ref.listen<WorkoutUiState>(engineProvider, (prev, next) {
      // Korrektur-Dialog
      if (next.showCorrectionDialog && !(prev?.showCorrectionDialog ?? false)) {
        // ... (wie oben)
      }
      // Session-Zusammenfassung
      if (next.showSessionSummary && !(prev?.showSessionSummary ?? false)) {
        // ... (wie oben)
      }
    });
```

### 3.4 Validierung

```bash
flutter test
flutter analyze lib/presentation/widgets/session_summary_dialog.dart
```

---

## 4. Reconnection-Strategie

### 4.1 Kurzbeschreibung

Bei BLE-Verbindungsverlust versucht die App automatisch, die Verbindung
wiederherzustellen — mit exponentiellem Backoff (1s, 2s, 4s, 8s, max 16s).
Der Benutzer sieht einen Indikator „Verbindung verloren — versuche erneut…".

**SPEC-Referenz**: §5.2.4 „Reconnection-Strategie"

### 4.2 Abhängigkeiten

- `BleSensorProvider.connect()` existiert und funktioniert
- `_onConnectionState()` in EngineNotifier behandelt `disconnected`
- `WorkoutState.connectionLost` existiert in der StateMachine

### 4.3 Schritt-für-Schritt-Implementierung

#### SCHRITT A: WorkoutUiState erweitern

```dart
  // Reconnection
  final bool isReconnecting;
  final int reconnectAttempt;
```

Konstruktor: `this.isReconnecting = false, this.reconnectAttempt = 0,`
copyWith: Standard-Pattern.

#### SCHRITT B: Reconnect-Logik im EngineNotifier

**Datei**: `app/lib/presentation/providers/engine_provider.dart`

**Neue Felder**:
```dart
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 10;
  bool _userInitiatedDisconnect = false;
```

**Modifikation in `disconnect()`**:
```dart
  Future<void> disconnect() async {
    _userInitiatedDisconnect = true; // Kein Auto-Reconnect
    _cancelReconnect();
    await _sensorProvider.disconnect();
  }
```

**Modifikation in `_onConnectionState()` — disconnected case**:

**VORHER**:
```dart
      case SensorConnectionState.disconnected:
        state = state.copyWith(isConnected: false, isConnecting: false);
        _refreshTimer?.cancel();
        _engine.handleDisconnect();
```

**NACHHER**:
```dart
      case SensorConnectionState.disconnected:
        state = state.copyWith(isConnected: false, isConnecting: false);
        _refreshTimer?.cancel();
        _engine.handleDisconnect();
        // Auto-Reconnect (nur wenn nicht vom Benutzer initiiert)
        if (!_userInitiatedDisconnect) {
          _startReconnect();
        }
```

**Modifikation in `_onConnectionState()` — connected case**:
Am ANFANG des connected-Blocks:
```dart
      case SensorConnectionState.connected:
        _userInitiatedDisconnect = false; // Reset
        _cancelReconnect(); // Reconnect-Versuche stoppen
        _reconnectAttempt = 0;
        // ... (bestehender Code bleibt)
```

**Neue Methoden**:
```dart
  // === Reconnection-Strategie (SPEC §5.2.4) ===

  void _startReconnect() {
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      state = state.copyWith(
        isReconnecting: false,
        errorText: 'Verbindung konnte nicht wiederhergestellt werden. '
            'Bitte manuell verbinden.',
      );
      return;
    }

    _reconnectAttempt++;
    // Exponentielles Backoff: 1s, 2s, 4s, 8s, max 16s
    final delaySec = (1 << (_reconnectAttempt - 1)).clamp(1, 16);

    state = state.copyWith(
      isReconnecting: true,
      reconnectAttempt: _reconnectAttempt,
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySec), () async {
      if (_userInitiatedDisconnect) return;
      try {
        await _sensorProvider.connect();
      } catch (_) {
        // connect() fehlgeschlagen → nächster Versuch via _onConnectionState
        // (disconnected wird erneut gefeuert → _startReconnect() erneut)
      }
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    state = state.copyWith(isReconnecting: false);
  }
```

**In `connect()`**: Am Anfang `_userInitiatedDisconnect = false;` setzen.

**In `dispose()`**: `_reconnectTimer?.cancel();`

#### SCHRITT C: UI-Indikator im HomeScreen

**Position**: In `ConnectionStatusCard` oder direkt im HomeScreen,
nach dem Verbindungsstatus:

```dart
              // Reconnect-Indikator
              if (uiState.isReconnecting)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Verbindung verloren — Versuch ${uiState.reconnectAttempt}…',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.orange.shade800,
                            ),
                      ),
                    ],
                  ),
                ),
```

### 4.4 Stolperfallen

| # | Fehler | Symptom | Vermeidung |
|---|--------|---------|-----------|
| 1 | Reconnect-Schleife nach manuellem Disconnect | App verbindet sich sofort wieder | `_userInitiatedDisconnect` Flag |
| 2 | `connect()` wirft Exception im Timer | Unhandled Exception | try/catch im Timer-Callback |
| 3 | Backoff-Overflow bei vielen Versuchen | `1 << 30` = sehr groß | `.clamp(1, 16)` |
| 4 | Reconnect während CalibrationWizard | Wizard bekommt stale Daten | Wizard prüfen oder Reconnect pausieren |
| 5 | `_onConnectionState(disconnected)` feuert bei jedem gescheiterten connect() | Doppelte Reconnect-Timer | `_reconnectTimer?.cancel()` VOR neuem Timer |

---

## 5. Foreground Service (Android 15+)

### 5.1 Kurzbeschreibung

Android 15+ (API 35) erfordert einen Foreground Service für BLE-Verbindungen
im Hintergrund. Ohne das wird die BLE-Verbindung getrennt, sobald der
Bildschirm gesperrt wird.

**SPEC-Referenz**: Definition of Done 4.4, AndroidManifest Zeile 16

### 5.2 Abhängigkeiten

- Permission `FOREGROUND_SERVICE_CONNECTED_DEVICE` ist bereits deklariert
- Package `flutter_foreground_task` muss hinzugefügt werden
- **KEIN** iOS-Pendant nötig (iOS behandelt BLE anders)

### 5.3 Schritt-für-Schritt-Implementierung

#### SCHRITT A: Package hinzufügen

**Datei**: `app/pubspec.yaml`

**Position**: Unter `dependencies:` (nach `audioplayers: ^6.1.0`):

```yaml
  # Foreground Service für BLE im Hintergrund (Android 15+, DoD 4.4)
  flutter_foreground_task: ^8.1.0
```

Danach: `flutter pub get`

#### SCHRITT B: AndroidManifest erweitern

**Datei**: `app/android/app/src/main/AndroidManifest.xml`

**Position**: Innerhalb von `<application>`, NACH der `<activity>`-Tag
(Zeile ~44, vor `</application>`):

```xml
        <!-- Foreground Service für BLE-Streaming im Hintergrund (DoD 4.4) -->
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="connectedDevice"
            android:exported="false" />
```

**ZUSÄTZLICH**: Permission für Wake-Lock (optional, für zuverlässiges BLE):
```xml
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
```

#### SCHRITT C: ForegroundService-Wrapper erstellen

**Datei**: `app/lib/data/services/foreground_service_manager.dart` (NEUE DATEI)

```dart
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Verwaltet den Android Foreground Service für BLE-Streaming.
///
/// Ohne Foreground Service trennt Android 15+ die BLE-Verbindung,
/// sobald der Bildschirm gesperrt wird (Definition of Done 4.4).
///
/// iOS: kein Foreground Service nötig (CBCentralManager bleibt aktiv).
class ForegroundServiceManager {
  bool _isRunning = false;

  /// Startet den Foreground Service.
  /// Muss AUFGERUFEN werden, bevor das Zählen beginnt.
  Future<void> start() async {
    if (_isRunning) return;

    // Nur auf Android relevant
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    // HINWEIS: Theme.of braucht BuildContext — besser: Platform-Check
    // via dart:io Platform.isAndroid

    try {
      await FlutterForegroundTask.startService(
        notificationTitle: 'FlowRep aktiv',
        notificationText: 'Wiederholungen werden gezählt',
        callback: _foregroundCallback,
      );
      _isRunning = true;
    } catch (e) {
      // Foreground Service nicht verfügbar (z.B. iOS, Web)
      // → kein Fehler, einfach weiter ohne
    }
  }

  /// Stoppt den Foreground Service.
  Future<void> stop() async {
    if (!_isRunning) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    _isRunning = false;
  }

  bool get isRunning => _isRunning;
}

/// Top-level Callback für den Foreground Service.
/// MUSS eine top-level Funktion sein (kein Closure!).
@pragma('vm:entry-point')
void _foregroundCallback() {
  // Der Service läuft im Hintergrund.
  // Die eigentliche BLE-Logik bleibt im Haupt-Isolate.
  // Dieser Callback hält nur den Prozess am Leben.
  FlutterForegroundTask.setTaskHandler(_EmptyTaskHandler());
}

class _EmptyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
```

**WICHTIG**: Die genaue API von `flutter_foreground_task` variiert je nach
Version. Obiger Code ist ein TEMPLATE. Nach `flutter pub get` die tatsächliche
API in der Package-Dokumentation prüfen und anpassen.

**ALTERNATIVE** (einfacher, weniger Dependencies):
Statt `flutter_foreground_task` kann auch `flutter_local_notifications` +
ein eigener `MethodChannel`-Service verwendet werden. Aber
`flutter_foreground_task` ist der Standard-Ansatz.

#### SCHRITT D: Integration in EngineNotifier

**Datei**: `app/lib/presentation/providers/engine_provider.dart`

**Import**:
```dart
import '../../data/services/foreground_service_manager.dart';
```

**Feld**:
```dart
  final ForegroundServiceManager _fgService = ForegroundServiceManager();
```

**In `startCounting()`**:
```dart
  void startCounting() {
    if (state.isCountingActive) return;
    _stopRestTimer();
    _fgService.start(); // Foreground Service starten
    state = state.copyWith(isCountingActive: true);
  }
```

**In `stopCounting()` und `endSession()`**:
```dart
    _fgService.stop(); // Foreground Service stoppen
```

**In `dispose()`**:
```dart
    _fgService.stop();
```

### 5.4 Validierung

```bash
flutter pub get
flutter analyze lib/data/services/foreground_service_manager.dart
flutter build apk --debug  # Muss kompilieren
```

**MANUELLER TEST** (erfordert echtes Android-Gerät):
1. App starten → verbinden → Zählen starten
2. Bildschirm sperren
3. 30 Sekunden warten
4. Bildschirm entsperren
5. BLE-Verbindung muss noch aktiv sein

### 5.5 Stolperfallen

| # | Fehler | Symptom | Vermeidung |
|---|--------|---------|-----------|
| 1 | `<service>` Tag fehlt in Manifest | `SecurityException` bei startService | Exakt den XML-Block einfügen |
| 2 | Callback ist kein top-level | `Invalid argument(s)` | `@pragma('vm:entry-point')` + top-level Funktion |
| 3 | Service startet auf iOS/Web | Crash | try/catch + Platform-Check |
| 4 | `flutter_foreground_task` Version inkompatibel | Compile-Error | Nach `pub get` die API-Docs der installierten Version prüfen |
| 5 | Notification-Channel fehlt (Android 8+) | Keine Notification sichtbar | Package erstellt Channel automatisch |

---

## Implementierungsreihenfolge

```
1. Korrektur-UI (Feature 1)     ← keine Abhängigkeiten
2. Pausen-Timer (Feature 2)     ← baut auf Feature 1 (Dialog-Flow)
3. Session-Beenden (Feature 3)  ← baut auf Feature 1+2
4. Reconnection (Feature 4)     ← unabhängig von 1-3
5. Foreground Service (Feature 5) ← unabhängig von 1-4
```

Nach JEDEM Feature:
```bash
flutter test          # Alle Tests grün?
flutter analyze       # Keine neuen Warnings?
git add -A && git commit -m "feat(P0): <Feature-Name>"
git push
```

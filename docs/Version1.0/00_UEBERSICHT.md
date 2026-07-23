# FlowRep 1.0 — Implementationspläne Übersicht

> **Stand**: 22. Juli 2026
> **Basis**: Gap-Analyse vom 22.07.2026, aktueller Commit `0e419b6`
> **Test-Suite**: 242 Tests grün (Stand vor P0-Implementierung)

---

## Dateistruktur

```
docs/Version1.0/
├── 00_UEBERSICHT.md          ← Diese Datei
├── 01_P0_KRITISCHE_FEATURES.md   ← Release-Blocker (5 Features)
├── 02_P1_WICHTIGE_FEATURES.md    ← Stark empfohlen (8 Features)
└── 03_P2_VERBESSERUNGEN.md       ← Quality & Polish (7 Features)
```

---

## Abhängigkeitsgraph

```
P0-1 Korrektur-UI ─────────────────────────────────────────┐
    │                                                       │
    ▼                                                       │
P0-2 Pausen-Timer ──────────────────────────────────────────┤
    │                                                       │
    ▼                                                       │
P0-3 Session-Beenden ───────────────────────────────────────┤
                                                            │
P0-4 Reconnection (unabhängig) ─────────────────────────────┤
                                                            │
P0-5 Foreground Service (unabhängig) ───────────────────────┤
                                                            │
    ════════════════════════════════════════════════════════ │
    ALLE P0 FERTIG → P1 starten                            │
    ════════════════════════════════════════════════════════ │
                                                            │
P1-1 Global Error Handler (unabhängig) ─────────────────────┤
P1-2 App-Lifecycle (unabhängig) ────────────────────────────┤
P1-3 Settings-Screen (unabhängig) ──────────────────────────┤
P1-4 iOS-Konfiguration (unabhängig) ────────────────────────┤
P1-5 Sound-Asset (unabhängig) ──────────────────────────────┤
P1-6 App-Icon + Splash (unabhängig) ────────────────────────┤
P1-7 Widget-Tests (braucht P0-Widgets) ─────────────────────┤
P1-8 CI/CD (unabhängig) ────────────────────────────────────┤
                                                            │
    ════════════════════════════════════════════════════════ │
    ALLE P1 FERTIG → P2 starten                            │
    ════════════════════════════════════════════════════════ │
                                                            │
P2-1 Dark Mode (unabhängig) ────────────────────────────────┤
P2-2 Accessibility (braucht P0-Widgets) ────────────────────┤
P2-3 Glanceability (unabhängig) ────────────────────────────┤
P2-4 Error-Messages (unabhängig) ───────────────────────────┤
P2-5 Paketverlust-Warnung (unabhängig) ─────────────────────┤
P2-6 Konstanten (unabhängig, aber VOR anderen P2 besser) ───┤
P2-7 Logging (unabhängig) ──────────────────────────────────┘
```

---

## Empfohlene Implementierungsreihenfolge

### Phase 1: P0 (Release-Blocker) — ~3-4 Tage

| # | Feature | Aufwand | Abhängigkeit |
|---|---------|---------|--------------|
| 1 | Korrektur-UI (+/−) | 2-3h | keine |
| 2 | Pausen-Timer (90s) | 1-2h | P0-1 (Dialog-Flow) |
| 3 | Session-Beenden-Flow | 2h | P0-1 + P0-2 |
| 4 | Reconnection-Strategie | 2-3h | keine |
| 5 | Foreground Service | 2-3h | keine |

**Commit-Regel**: Nach JEDEM Feature einzeln committen.

### Phase 2: P1 (Qualität) — ~2-3 Tage

| # | Feature | Aufwand | Abhängigkeit |
|---|---------|---------|--------------|
| 1 | Global Error Handler | 1h | keine |
| 2 | App-Lifecycle | 1h | keine |
| 3 | Settings-Screen | 2h | keine |
| 4 | iOS-Konfiguration | 30min | keine |
| 5 | Sound-Asset | 30min | keine |
| 6 | App-Icon + Splash | 1h | keine |
| 7 | Widget-Tests | 2-3h | P0-Widgets |
| 8 | CI/CD Pipeline | 1h | keine |

### Phase 3: P2 (Polish) — ~1-2 Tage

| # | Feature | Aufwand | Abhängigkeit |
|---|---------|---------|--------------|
| 1 | Dark Mode | 30min | keine |
| 2 | Accessibility | 1-2h | P0-Widgets |
| 3 | Glanceability | 1h | keine |
| 4 | Error-Messages | 1h | keine |
| 5 | Paketverlust-Warnung | 30min | keine |
| 6 | Konstanten zentralisieren | 1h | keine |
| 7 | Logging-Struktur | 30min | keine |

---

## Globale Regeln für ALLE Implementierungen

### Vor jedem Feature

```bash
cd flowrep/app
flutter test          # Muss grün sein BEVOR du anfängst
git status            # Sauberer Working Tree?
```

### Nach jedem Feature

```bash
flutter test          # ALLE Tests grün?
flutter analyze       # Keine neuen Warnings?
git add -A
git commit -m "feat(<Priorität>): <Feature-Name>"
git push
```

### Commit-Message-Format

```
feat(P0): Korrektur-UI mit +/- Buttons nach Satzende
feat(P0): Pausen-Timer 90s Countdown
feat(P0): Session-Beenden-Flow mit Zusammenfassung
feat(P0): BLE Reconnection mit exponentiellem Backoff
feat(P0): Android Foreground Service für BLE im Hintergrund
feat(P1): Globaler Error Handler + ErrorWidget
feat(P1): App-Lifecycle Observer
feat(P1): Settings-Screen (Feedback, Timer, DSGVO)
feat(P1): iOS BLE Permissions in Info.plist
feat(P1): Sound-Asset rep_click.wav
feat(P1): App-Icon + Splash-Screen
test(P1): Widget-Tests für HomeScreen, CorrectionDialog, RestTimer
ci(P1): GitHub Actions CI Pipeline
feat(P2): Dark Mode Support
feat(P2): Accessibility (Semantics, Tooltips)
feat(P2): Glanceability (120sp Rep-Anzeige)
feat(P2): Benutzerfreundliche BLE-Fehlermeldungen
feat(P2): Paketverlust-Warnung bei >5%
refactor(P2): Engine-Konstanten zentralisieren
refactor(P2): Logging-Struktur verbessern
```

### Verbotene Aktionen

- NIEMALS bestehende Tests löschen oder abschwächen
- NIEMALS `_useNewPipeline = true` setzen (Shadow-Mode bleibt)
- NIEMALS `correctedReps` in `countedReps` zurückschreiben
- NIEMALS „Die KI lernt dazu" als Nachricht verwenden
- NIEMALS Force-Push auf main

---

## Bestehende Architektur-Referenz

| Datei | Rolle | Zeilen |
|-------|-------|--------|
| `lib/presentation/providers/engine_provider.dart` | Zentrale Business-Logik | 389 |
| `lib/presentation/providers/workout_ui_state.dart` | Immutable UI-State | 117 |
| `lib/presentation/screens/home_screen.dart` | Haupt-UI | 256 |
| `lib/domain/workout_engine.dart` | Legacy Engine (autoritativ) | 1352 |
| `lib/data/providers/ble_sensor_provider.dart` | BLE-Kommunikation | 393 |
| `lib/domain/models/workout_models.dart` | Domain-Modelle | 95 |
| `lib/domain/repositories/i_workout_repository.dart` | Repo-Interface | 16 |
| `lib/data/repositories/drift_database.dart` | Drift DB + Tabellen | 326 |
| `lib/data/services/feedback_service.dart` | Haptic + Audio | 73 |
| `lib/domain/exercise_registry.dart` | Übungs-Katalog | 170 |

---

## Test-Strategie

| Ebene | Anzahl (aktuell) | Ziel (1.0) |
|-------|------------------|------------|
| Unit-Tests (Engine/Pipeline) | 242 | 260+ |
| Widget-Tests | 0 | 15+ |
| Integration-Tests | 0 | 3-5 (manuell) |
| E2E (Hardware) | 0 | Manuell auf M5StickC |

**Test-Befehl**:
```bash
cd flowrep/app
flutter test                    # Alle Unit + Widget Tests
flutter test test/widgets/      # Nur Widget-Tests
flutter test --coverage         # Mit Coverage-Report
```

---

## Definition of Done (1.0 Release)

- [ ] Alle P0-Features implementiert und getestet
- [ ] Alle P1-Features implementiert
- [ ] Mindestens 10 Widget-Tests
- [ ] `flutter analyze` → 0 Errors, 0 Warnings
- [ ] `flutter test` → alle grün
- [ ] `flutter build apk --release` → kompiliert
- [ ] Manueller Test auf echtem M5StickC Plus2:
  - [ ] Verbinden → Kalibrieren → Zählen → Korrigieren → Beenden
  - [ ] Bildschirm sperren während Zählen → Verbindung bleibt
  - [ ] BLE-Verlust → Auto-Reconnect funktioniert
  - [ ] Dark Mode lesbar
- [ ] Keine TODO(hardware)-Marker mehr (außer Gyro-Gate)

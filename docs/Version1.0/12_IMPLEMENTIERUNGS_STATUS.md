# Implementierungs-Status — FlowRep 1.0

> **Stand**: 22. Juli 2026
> **Letzter Commit**: `9755dc9` (nur Dokumentation)
> **Status**: ❌ KEINE Implementierung gestartet

---

## Legende

| Symbol | Bedeutung |
|--------|-----------|
| ⬜ | Nicht begonnen |
| 🔄 | In Arbeit |
| ✅ | Fertig + getestet |
| ❌ | Blockiert / Problem |

---

## Phase 1: P0 — Release-Blocker

> **Doc**: `01_P0_KRITISCHE_FEATURES.md`
> **Ziel**: App ist ohne diese Features NICHT release-fähig.

| # | Feature | Status | Commit | Tests |
|---|---------|--------|--------|-------|
| P0-1 | Korrektur-UI (+/− Buttons) | ⬜ | — | — |
| P0-2 | Pausen-Timer (90s Countdown) | ⬜ | — | — |
| P0-3 | Session-Beenden-Flow | ⬜ | — | — |
| P0-4 | Reconnection-Strategie | ⬜ | — | — |
| P0-5 | Foreground Service | ⬜ | — | — |

**Verifikation nach jedem Feature**:
```bash
cd flowrep/app
flutter test          # Alle Tests grün?
flutter analyze       # Keine neuen Warnings?
```

---

## Phase 2: P1 — Wichtige Features

> **Doc**: `02_P1_WICHTIGE_FEATURES.md`
> **Voraussetzung**: Alle P0-Features fertig.

| # | Feature | Status | Commit | Tests |
|---|---------|--------|--------|-------|
| P1-1 | Globaler Error Handler | ⬜ | — | — |
| P1-2 | App-Lifecycle-Handling | ⬜ | — | — |
| P1-3 | Settings-Screen | ⬜ | — | — |
| P1-4 | iOS-Konfiguration | ⬜ | — | — |
| P1-5 | Sound-Asset + pubspec | ⬜ | — | — |
| P1-6 | App-Icon + Splash-Screen | ⬜ | — | — |
| P1-7 | Widget-Tests | ⬜ | — | — |
| P1-8 | CI/CD Pipeline | ⬜ | — | — |

---

## Phase 3: P2 — Verbesserungen

> **Doc**: `03_P2_VERBESSERUNGEN.md`
> **Voraussetzung**: P0 und P1 fertig.

| # | Feature | Status | Commit | Tests |
|---|---------|--------|--------|-------|
| P2-1 | Dark Mode | ⬜ | — | — |
| P2-2 | Accessibility | ⬜ | — | — |
| P2-3 | Glanceability (120sp) | ⬜ | — | — |
| P2-4 | Benutzerfreundliche Fehlermeldungen | ⬜ | — | — |
| P2-5 | BLE-Paketverlustrate-Warnung | ⬜ | — | — |
| P2-6 | Konstanten zentralisieren | ⬜ | — | — |
| P2-7 | Logging-Struktur | ⬜ | — | — |

---

## Phase 4: CV — Computer Vision (optional)

> **Docs**: `04_CV_ARCHITEKTUR.md` bis `09_CV_ANDROID_SIMULATOR.md`
> **Voraussetzung**: P0-1 (Korrektur-UI) fertig. Parallel zu P1/P2 möglich.
> **WICHTIG**: CV ist OPTIONAL. Die App funktioniert vollständig ohne Kamera.

| # | Feature | Status | Commit | Tests |
|---|---------|--------|--------|-------|
| CV-01 | Architektur verstehen (nur lesen) | ⬜ | — | — |
| CV-02 | Kamera-Setup (flutter_pose_detection) | ⬜ | — | — |
| CV-03 | Rep-Counter Winkel (Bicep Curl) | ⬜ | — | — |
| CV-04 | Sensor Fusion (IMU+Kamera) | ⬜ | — | — |
| CV-05 | Webcam-Testing (Python-Tool) | ⬜ | — | — |
| CV-06 | Android Simulator Setup | ⬜ | — | — |

---

## Phase 5: Release

> **Doc**: `10_RELEASE_VORBEREITUNG.md`
> **Voraussetzung**: Alle P0 + P1 fertig, P2 empfohlen.

| # | Aufgabe | Status |
|---|---------|--------|
| R-1 | Version auf 1.0.0+1 setzen | ⬜ |
| R-2 | APK-Signing konfigurieren | ⬜ |
| R-3 | Release-Build erstellen | ⬜ |
| R-4 | Hardware-QA (Doc 11) | ⬜ |
| R-5 | Git-Tag v1.0.0 erstellen | ⬜ |

---

## Test-Übersicht

| Kategorie | Aktuell | Ziel (1.0) | Status |
|-----------|---------|------------|--------|
| Unit-Tests (Engine/Pipeline) | 242 | 260+ | ⬜ |
| Widget-Tests | 0 | 15+ | ⬜ |
| Integration-Tests | 0 | 3-5 | ⬜ |
| Hardware-Tests | 0 | Doc 11 | ⬜ |

---

## Commit-Historie (V1.0-relevant)

| Commit | Beschreibung | Phase |
|--------|-------------|-------|
| `9755dc9` | CV-Implementationspläne (Docs) | Docs |
| `8cfa524` | V1.0 Implementationspläne P0/P1/P2 (Docs) | Docs |
| `0e419b6` | Exercise-Selection, Onboarding, Pipeline-Tests | Pre-V1.0 |
| `a603b03` | Baseline-Gate + Zähl-Gating | Pre-V1.0 |

---

## Nächste Schritte

1. **P0-1 starten**: Korrektur-UI implementieren (Doc 01, §1)
2. Nach jedem Feature: Commit + Push
3. Nach allen P0: P1 starten
4. Nach P1+P2: Release-Build (Doc 10)
5. Hardware-QA (Doc 11) → Go/No-Go

---

## Aktualisierungs-Regel

> **WER**: Die implementierende KI aktualisiert dieses Dokument nach JEDEM Feature.
> **WIE**: Status-Symbol ändern + Commit-Hash eintragen.
> **WANN**: Im gleichen Commit wie das Feature selbst.

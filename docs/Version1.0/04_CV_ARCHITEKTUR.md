# CV-01 — Pose Estimation: Architektur & Grundlagen

> **Modul**: Computer-Vision-Erweiterung für FlowRep
> **Status**: ✅ FOUNDATION DONE — domain/vision scaffold (VisionConfig, AngleCalculator, PoseRepCounter); IMU unverändert autoritativ
> **Voraussetzung**: P0-1 (Korrektur-UI) muss fertig sein
> **Widerspruchsfreiheit**: Dieses Modul ERGÄNZT die IMU-Pipeline, ersetzt sie NICHT.
> Die IMU-Pipeline bleibt autoritativ. Kamera ist ein zusätzlicher Validator.

---

## 1. Was ist Pose Estimation?

Pose Estimation erkennt **33 Körperpunkte** (Landmarks) in einem Kamerabild:
- Schultern, Ellenbogen, Handgelenke, Hüften, Knie, etc.
- Jeder Punkt hat X/Y-Koordinaten + Konfidenz (0.0–1.0)
- Aus den Punkten werden **Gelenkwinkel** berechnet (z.B. Ellenbogen-Winkel)

**Für FlowRep relevant:**
- Bicep Curl → Ellenbogen-Winkel (Shoulder-Elbow-Wrist)
- Winkel < 90° = "oben" (kontrahiert)
- Winkel > 160° = "unten" (gestreckt)
- Übergang unten→oben = 1 Rep

---

## 2. Technologie-Entscheidung

### 2.1 Warum `flutter_pose_detection`?

| Kriterium | flutter_pose_detection | Alternative (TFLite manuell) |
|-----------|----------------------|------------------------------|
| Einrichtung | 1 Dependency, fertig | Modell laden, Interpreter, Preprocessing |
| GPU/NPU | Automatisch | Manuell konfigurieren |
| Winkel-Berechnung | Eingebaut | Selbst schreiben |
| Flutter-nativ | Ja | Platform Channels nötig |
| Wartung | Package-Autor | Selbst |

**Entscheidung**: `flutter_pose_detection: ^0.4.0`

### 2.2 Performance (Referenz: Galaxy S25 Ultra)

| Modus | Latenz | Strom | Anwendungsfall |
|-------|--------|-------|----------------|
| GPU | ~3ms | Hoch | Kurze Sessions, max. FPS |
| NPU (Snapdragon) | ~13-16ms | Niedrig | Lange Sessions |
| CPU | ~17ms | Mittel | Fallback |

**Für FlowRep**: GPU-Modus (Sessions sind kurz, 5-30 Min).

### 2.3 Plattform-Unterstützung

| Plattform | Funktioniert? | Hinweis |
|-----------|---------------|---------|
| Android (physisch) | ✅ Voll | GPU/NPU/CPU |
| Android Emulator | ⚠️ Eingeschränkt | Nur CPU, keine echte Kamera → Virtual Scene |
| iOS (physisch) | ✅ Voll | CoreML/Metal |
| Windows (Webcam) | ❌ Nicht direkt | Workaround nötig (siehe Doc 08) |
| Linux (Webcam) | ❌ Nicht direkt | Workaround nötig (siehe Doc 08) |

---

## 3. Architektur: Wie passt CV in FlowRep?

### 3.1 Prinzip: Ensemble-Entscheidung

```
┌─────────────────────────────────────────────────────────┐
│                    FlowRep Engine                         │
│                                                          │
│  ┌──────────────┐         ┌──────────────────┐          │
│  │ IMU-Pipeline │         │ Kamera-Pipeline   │          │
│  │ (M5StickC)   │         │ (Pose Estimation) │          │
│  │              │         │                   │          │
│  │ Gyro → Filter│         │ Frame → Landmarks │          │
│  │ → Peak → NCC │         │ → Winkel → State  │          │
│  │ → Rep?       │         │ → Rep?            │          │
│  └──────┬───────┘         └────────┬──────────┘          │
│         │                          │                      │
│         ▼                          ▼                      │
│  ┌─────────────────────────────────────────┐             │
│  │         FUSION ENGINE (NEU)             │             │
│  │                                         │             │
│  │  Beide einig → Rep bestätigt            │             │
│  │  Nur IMU → Rep wahrscheinlich (zählen)  │             │
│  │  Nur Kamera → Rep unsicher (verwerfen)  │             │
│  │  Keiner → Keine Rep                     │             │
│  └─────────────────────────────────────────┘             │
│         │                                                │
│         ▼                                                │
│  ┌──────────────┐                                        │
│  │ RepEvent     │ → UI, Datenbank, Feedback              │
│  └──────────────┘                                        │
└─────────────────────────────────────────────────────────┘
```

### 3.2 WICHTIG: Keine Änderung an bestehender Pipeline

- `exercise_engine.dart` bleibt UNVERÄNDERT
- `workout_engine.dart` bleibt UNVERÄNDERT
- `engine_provider.dart` bekommt einen NEUEN optionalen Kamera-Pfad
- Die IMU-Pipeline zählt WEITER wie bisher
- Die Kamera liefert einen ZUSÄTZLICHEN Datenstrom

### 3.3 Neue Dateien (werden in den folgenden Docs erstellt)

```
app/lib/
├── domain/
│   └── vision/
│       ├── pose_rep_counter.dart      ← Winkel-basierter Rep-Counter
│       ├── angle_calculator.dart      ← Gelenkwinkel-Berechnung
│       ├── fusion_engine.dart         ← IMU + Kamera Fusion
│       └── vision_config.dart         ← Konfiguration (Schwellen, etc.)
├── data/
│   └── providers/
│       └── camera_pose_provider.dart  ← Kamera-Stream + Pose Detection
├── presentation/
│   ├── providers/
│   │   └── vision_provider.dart       ← Riverpod Provider für CV
│   ├── screens/
│   │   └── camera_calibration_screen.dart ← Kamera-Kalibrierung
│   └── widgets/
│       ├── camera_preview_overlay.dart    ← Live-Vorschau + Skelett
│       └── fusion_status_badge.dart       ← Anzeige: IMU/Kamera/Beide
```

---

## 4. Modi der Kamera-Nutzung

### 4.1 Modus A: Kamera als Kalibrierungs-Hilfe

- Während der Guided Calibration läuft die Kamera
- Bestätigt visuell: "Ja, das war eine vollständige Rep"
- Verbessert die Template-Qualität
- **Kamera muss NICHT dauerhaft laufen**

### 4.2 Modus B: Kamera als Echtzeit-Validator

- Kamera läuft parallel zur IMU-Pipeline
- Jede IMU-Rep wird durch Kamera-Winkel bestätigt/verworfen
- Höchste Genauigkeit
- **Hoher Batterieverbrauch** → nur optional

### 4.3 Modus C: Kamera-Only (ohne M5StickC)

- Für Testing ohne Hardware
- Zählt Reps NUR über Kamera
- Nützlich für: Entwicklung, Demo, Android-Simulator
- **Kein BLE nötig**

---

## 5. Abhängigkeiten zum V1.0-Plan

| V1.0-Feature | Bezug zu CV | Konflikt? |
|--------------|-------------|-----------|
| P0-1 Korrektur-UI | Korrektur gilt für BEIDE Quellen | Nein |
| P0-2 Pausen-Timer | Timer pausiert auch Kamera | Nein |
| P0-3 Session-Beenden | Kamera stoppt mit Session | Nein |
| P0-4 Reconnection | Bei BLE-Verlust: Kamera zählt weiter | Nein (Feature!) |
| P0-5 Foreground Service | Kamera braucht eigenen FGS | Erweiterung |
| P1-3 Settings | Kamera-Einstellungen (an/aus, Modus) | Erweiterung |
| P2-3 Glanceability | Skelett-Overlay optional | Nein |

**WICHTIG**: CV ist ein OPTIONALES Feature. Die App funktioniert weiterhin
vollständig ohne Kamera. Die IMU-Pipeline ist und bleibt der Primärpfad.

---

## 6. Reihenfolge der Implementierung

```
Doc 05: Kamera-Setup (flutter_pose_detection + Permissions)
    ↓
Doc 06: Rep-Counter via Winkel (Bicep Curl State Machine)
    ↓
Doc 07: Sensor Fusion (IMU + Kamera Ensemble)
    ↓
Doc 08: Webcam-Modus (PC-Testing ohne Android)
    ↓
Doc 09: Android Simulator (Virtual Scene + Testing)
```

Jedes Doc ist UNABHÄNGIG umsetzbar nach seinem Vorgänger.
Nach JEDEM Doc: `flutter test` + `flutter analyze` + Commit.

---

## 7. Glossar

| Begriff | Bedeutung |
|---------|-----------|
| Landmark | Ein Körperpunkt (z.B. "linkes Handgelenk") |
| Pose | Alle 33 Landmarks zusammen |
| Gelenkwinkel | Winkel zwischen 3 Landmarks (z.B. Schulter-Ellenbogen-Handgelenk) |
| Konfidenz | Wie sicher die Erkennung ist (0.0–1.0) |
| NPU | Neural Processing Unit (Hardware-Beschleuniger) |
| Ensemble | Entscheidung aus mehreren Quellen kombiniert |
| Fusion | Verschmelzung von IMU- und Kamera-Daten |
| Virtual Scene | Android Emulator: Simulierte Kamera-Umgebung |

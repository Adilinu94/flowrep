# CV-07 — Skelett-Overlay & Pose-Sichtbarkeit (Implementierungsplan)

> **Status**: ✅ CODE DONE (MVP + E1–E7, E9, E10; E8 out) — Geräte-QA optional  
> **Stand**: 2026-07-23  
> **Bezug**: Screenshot-Referenz (Fitness-App mit gelben Gelenkpunkten + grünen Knochenlinien)  
> **Voraussetzung**: CV-01…06 Code-Scaffold (`CameraPoseProvider`, `PoseFrame`, `AngleCalculator`, Fusion)  
> **Priorität**: Optional CV-Track — **kein** 1.0 Release-Blocker  
> **Living Tracker**: nach Umsetzung in `12` / `13` abhaken  
> **Out**: **E8 Privacy-Blur** — bewusst **nicht** im Scope (User-Entscheidung)

---

## 0. Zielbild

Die App soll wie im Referenz-Screenshot:

1. Das **Live-Kamerabild** zeigen.
2. Den Körper des Users als **Skelett** erkennen (Arme, Gelenke, optional ganzer Körper).
3. **Punkte** (Gelenke) und **Linien** (Knochenverbindungen) darüber zeichnen.
4. Form-/Tracking-Hinweise: aktiver Arm, Winkel-Farbe, Tracking-Badge, Framed-Guide, Fusion-Pulse.

**Produktprinzip bleibt unverändert:**

- IMU (M5StickC) ist **autoritativ** fürs Zählen.
- Kamera ist **optionaler** Validator / Trust-UI / Demo-Pfad.
- App funktioniert vollständig ohne Kamera.
- Verarbeitung **nur lokal** (kein Upload) — ohne E8-Blur-UI.

---

## 0.1 Scope-Matrix (verbindlich)

| ID | Feature | Im Plan? | Phase |
|----|---------|----------|--------|
| MVP | Live-Skelett (Bones + Joints) über Preview | **ja** | A–C |
| **E1** | Aktiven Arm hervorheben | **ja** | B + C |
| **E2** | Winkel-Farbcodierung am Ellenbogen | **ja** | C + E |
| **E3** | Tracking-Quality-Badge | **ja** | C |
| **E4** | Framed-Guide / „Person nicht erkannt“ | **ja** | C + D |
| **E5** | Confidence-Hysterese (weniger Flackern) | **ja** | D |
| **E6** | Skeleton-Modi Full / Upper / Arm-only | **ja** | A + B + Settings |
| **E7** | Fusion-Visual Sync (Pulse bei bestätigter Rep) | **ja** | E |
| **E8** | Privacy Mode (Blur / nur Stickfigure) | **nein** | — out of scope |
| **E9** | Landmark-CSV/JSON Debug (opt-in, lokal) | **ja** | F |
| **E10** | Multi-Exercise Joint Maps (vorbereiten) | **ja** | A + F |

---

## 1. Ist-Zustand (Code)

| Baustein | Datei / Ort | Status |
|----------|-------------|--------|
| Pose-Detection Dependency | `flutter_pose_detection` in `app/pubspec.yaml` | ✅ |
| Kamera + Image-Stream → Detector | `app/lib/data/providers/camera_pose_provider.dart` | ✅ |
| 33 Landmarks + Confidence | `PoseFrame`, `FlowPoseLandmark`, `PoseFrameMapper` | ✅ |
| Ellenbogen-Winkel | `domain/vision/angle_calculator.dart` | ✅ |
| Pose-Rep-Counter | `domain/vision/pose_rep_counter.dart` | ✅ |
| IMU↔Kamera Fusion | `domain/vision/fusion_engine.dart` | ✅ |
| Config-Flag Overlay | `VisionConfig.showSkeletonOverlay` | ✅ (Flag da, UI nutzt es nicht) |
| Session-Screen | `presentation/screens/camera_session_screen.dart` | ✅ Winkel/Text, **kein** Skelett |
| Preview-Widget | `presentation/widgets/camera_preview_overlay.dart` | ⚠️ nur `CameraPreview` |
| Desktop-Skelett (Python) | `tools/webcam_rep_counter.py` | ✅ Referenz für Look & Landmark-Indizes |

**Lücke:** Kein `CustomPainter` / Overlay, der Landmarks auf das Preview mappt.  
Erweiterungen E1–E7/E9/E10 bauen darauf auf — ohne diese Schicht „sieht“ der User die Erkennung nicht.

---

## 2. Technologie-Entscheidung (bestätigt)

| Entscheidung | Wahl | Begründung |
|--------------|------|------------|
| Pose-Modell | Bestehendes `flutter_pose_detection` (MediaPipe-ähnlich, 33 Punkte) | Schon integriert, getestet, Mapper vorhanden |
| Rendering | Flutter `CustomPaint` + `Stack` über `CameraPreview` | Kein nativer Extra-Layer; testbar; Theme-fähig |
| Koordinaten | Normalisierte Landmark-`x/y` (0…1) → Widget-Pixel | MediaPipe-Standard; Aspect-Ratio / Mirror |
| Neue Dependencies | **Keine** für Overlay + E1–E7 | Vermeidet Doppel-Pipeline |
| Cloud-Vision | **Nein** | Privacy, Offline-Gym, Latenz |
| E8 Blur | **Nicht bauen** | Explizit aus Scope genommen |

---

## 3. Architektur: Overlay-Datenfluss

```
┌─────────────────┐     ImageStream      ┌──────────────────────┐
│ CameraController│ ──────────────────► │ NpuPoseDetector      │
└────────┬────────┘                      │ (flutter_pose_det.)  │
         │                               └──────────┬───────────┘
         │ Preview                                   │ PoseFrame
         ▼                                           ▼
                    ┌────────────────────────────────┐
                    │ Confidence smoother (E5)       │
                    │ + TrackingQuality (E3)         │
                    └───────────────┬────────────────┘
                                    ▼
┌─────────────────────────────────────────────────────────────┐
│ CameraPreviewOverlay (Stack)                                │
│  ┌────────────────────┐  ┌────────────────────────────────┐ │
│  │ CameraPreview      │  │ SkeletonPainter (E1,E2,E6)     │ │
│  │ + Framed-Guide E4  │  │ bones/joints + arm highlight   │ │
│  └────────────────────┘  └────────────────────────────────┘ │
│  ┌────────────────────┐  ┌────────────────────────────────┐ │
│  │ Tracking badge E3  │  │ Fusion pulse E7 (kurz)         │ │
│  └────────────────────┘  └────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
         │
         ├──→ camera_session_screen (HUD, toggles)
         ├──→ FusionEngine (Decision → E7, Winkel → E2)
         └──→ optional LandmarkRecorder (E9, debug only)
```

### 3.1 Neue / geänderte Dateien

| Aktion | Pfad | Verantwortung | Features |
|--------|------|----------------|----------|
| **NEU** | `app/lib/domain/vision/pose_skeleton.dart` | Bone-Listen, `SkeletonDrawMode`, Joint-Maps | MVP, **E6**, **E10** |
| **NEU** | `app/lib/domain/vision/tracking_quality.dart` | Enum Tracking/Partial/Lost + Hysterese-State | **E3**, **E5** |
| **NEU** | `app/lib/domain/vision/vision_focus.dart` | `VisionFocus` (primary joints/angles pro Übung) | **E10** |
| **NEU** | `app/lib/presentation/widgets/skeleton_painter.dart` | CustomPainter: Bones, Joints, Farben | MVP, **E1**, **E2**, **E6** |
| **NEU** | `app/lib/presentation/widgets/framed_guide_overlay.dart` | Silhouette/Rahmen + Empty-State-Copy | **E4** |
| **NEU** | `app/lib/data/repositories/landmark_session_recorder.dart` | Opt-in CSV/JSON Landmarks lokal | **E9** |
| **NEU** | Tests unter `app/test/vision/` + `app/test/widgets/` | Unit/Widget | alle |
| **ÄNDERN** | `camera_preview_overlay.dart` | Stack + Skeleton + Guide + Badge-Slot | MVP, E3, E4 |
| **ÄNDERN** | `camera_session_screen.dart` | Frame-State, HUD, Toggle, Pulse-Trigger | C–E |
| **ÄNDERN** | `vision_config.dart` | `drawMode`, `highlightArm`, `recordLandmarks`, … | E1, E6, E9 |
| **ÄNDERN** | `vision_focus.dart` (statt Profil-JSON) | `VisionFocus.forExercise(id)` | **E10** |
| **ÄNDERN** | `fusion` / session feedback hook | Pulse nur UI, keine Zähllogik | **E7** |
| **ÄNDERN** | Docs `12` / `13` | Checkboxen nach Implementierung | — |

**Nicht ändern (Guardrails):**

- `workout_engine.dart` / `exercise_engine.dart` Zähllogik
- `_useNewPipeline` (bleibt `false`)
- IMU-autoritative Fusion-Regeln (nur UI-Feedback erweitern)
- **Kein** Preview-Blur / Privacy-Stickfigure-Modus (**E8**)

---

## 4. Detailplan — Phasen (inkl. aller Scope-Features)

### Phase A — Domain: Skelett-Topologie + Joint Maps (E6, E10)

**Ziel:** Stabil definieren, *welche* Punkte verbunden und *pro Übung* primär sind.

**Tasks:**

1. `PoseSkeleton` mit MediaPipe-Indizes:
   - **Full**: Torso + Arme + Beine (ohne Gesicht, Noise im Gym)
   - **Upper** (**E6**): Schultern, Ellenbogen, Handgelenke, Hüfte
   - **ArmOnly** (**E6**): nur aktive Armkette (Shoulder–Elbow–Wrist ± Gegenschulter)
2. `List<(int, int)> bonesFor(SkeletonDrawMode mode, {ArmSide? active})`
3. Helper `visibleEnough`, `toCanvasOffset(..., {bool mirrorX})`
4. **E10:** `VisionFocus` Modell:
   ```text
   primaryAngle: elbow | shoulder | knee | …
   primaryLandmarks: [shoulderIdx, elbowIdx, wristIdx]
   secondaryBones: optional dimmed
   ```
5. Default-Map nur für **Bicep Curl** verdrahten; andere Übungen: Enum/Platzhalter ohne Produkt-Zwang Squats.
6. Unit-Tests: Indizes 0…32; Modi; Curl-Focus zeigt Elbow-Kette.

**DoD Phase A:**

- [x] Unit-Tests Bones/Modi/Mapping grün
- [x] `VisionFocus` für Curl definiert und getestet
- [x] Kein UI nötig

---

### Phase B — Painter + Overlay-UI (MVP + E1 + E6)

**Ziel:** Screenshot-ähnliches Live-Skelett mit Arm-Highlight und Zeichen-Modi.

**Tasks:**

1. `SkeletonPainter`:
   - Input: landmarks, `minConfidence`, `SkeletonDrawMode`, `ArmSide highlight`, optional elbow angle color
   - Zuerst Bones, dann Joints
   - **E1:** aktive Armkette volle Opacity/Farbe; Rest gedimmt (~0.35)
   - **E6:** nur Bones des gewählten Modus zeichnen
   - `shouldRepaint` streng
2. `CameraPreviewOverlay`: Stack Preview + CustomPaint; gleiche Aspect-Box
3. Frontkamera: `mirrorX: true`
4. Leere Pose: kein Crash

**DoD Phase B:**

- [x] Analyze 0; Widget-Test leere Landmarks
- [x] Unit/Widget: Highlight-Arm und DrawMode ändern sichtbare Bone-Menge (über testbare pure API)

---

### Phase C — Session-Anbindung + E3 Tracking-Badge + E2 Winkel-Farbe (Grund)

**Ziel:** End-to-end Live-Pfad.

**Tasks:**

1. `_lastFrame` / smoothed quality state im Session-Screen
2. Overlay mit live landmarks + config
3. **E3:** `TrackingQuality` aus `armConfidence`:
   - `tracking` ≥ minConfidence (z. B. 0.5)
   - `partial` zwischen low und min
   - `lost` darunter oder keine Pose
   - Badge im Overlay (wie Referenz „Tracking“)
4. **E2 (Grund):** Ellenbogen-Joint-Farbe:
   - grün: Winkel im sinnvollen Curl-ROM-Pfad (zwischen up/down thresholds mit Hysterese der SM)
   - gelb: außerhalb / grenzwertig
   - rot: confidence zu niedrig **oder** klar partial (konfigurierbar)
5. Copy: „Validierung — Zählen über Sensor“
6. Soft-fail ohne Kamera unverändert

**DoD Phase C:**

- [x] Person im Bild (Code; Geräte-QA optional) → Skelett + Badge
- [x] Stop cleared frame
- [x] Bestehende Vision/Fusion-Tests grün

---

### Phase D — E4 Framed-Guide + E5 Hysterese + Polish

**Ziel:** Nutzbarkeit im Gym + stabiles Overlay.

**Tasks:**

1. **E4:** `FramedGuideOverlay`
   - Rahmen / stilisierte Oberkörper-Silhouette solange `lost` oder noch nie getrackt
   - Text: „Oberkörper mittig, Arme im Bild“
   - Nach N Frames ohne Pose während Detection: Warn-Chip (nicht spammen: max 1× / 3 s)
2. **E5:** Confidence-Glättung
   - EMA oder einfacher One-Euro auf `armConfidence` (bestehende Filter-Idee nutzen)
   - Hysterese: z. B. 3 Frames under threshold → `lost`; 2 Frames good → `tracking`
   - Verhindert Skelett-Flackern
3. Skeleton Toggle + **E6** Mode-Picker (SegmentedButton oder Settings-Eintrag)
4. Debug FPS nur `kDebugMode`
5. Mapping-QA (Letterbox)

**DoD Phase D:**

- [x] Unit-Tests Hysterese-Übergänge
- [x] Guide sichtbar wenn lost; weg wenn tracking
- [ ] Manuell: weniger Flackern (env-optional) bei Grenz-Licht

---

### Phase E — E2 Feinschliff + E7 Fusion-Pulse

**Ziel:** Form-Feedback und IMU↔Kamera Trust.

**Tasks:**

1. **E2 Feinschliff:** Farben an `PoseRepCounter`-Phase koppeln (down/up/transition), nicht nur Rohwinkel
2. **E7:** Bei Fusion-Decision „beide einig / rep confirmed“:
   - 200–400 ms Scale-Pulse am primären Ellenbogen-Punkt (oder kurzer Glow)
   - **Kein** Einfluss aufs Zählen; nur UI
   - Optional: bestehende Haptik/Sound unverändert mitnutzen
3. Widget/Unit: Pulse-Flag wird gesetzt und nach Timeout cleared

**DoD Phase E:**

- [x] Pulse nur bei bestätigter Fusion-Rep (simuliert in Test)
- [x] Zählstand IMU unverändert durch Pulse-Code

---

### Phase F — E9 Debug-Recorder + E10 Registry-Verdrahtung

**Ziel:** Entwickler-Repro + skalierbare Fokus-Maps.

**Tasks:**

1. **E9:** `LandmarkSessionRecorder`
   - Opt-in Flag `VisionConfig.recordLandmarks` (Default **false**)
   - Pro Frame (throttled, z. B. 10 Hz): `timestampMs, conf, x0,y0,…` oder JSONL
   - Pfad unter App-Documents / `data/` — **gitignore** beachten; **kein** Netzwerk
   - UI: nur Debug-Menü oder Long-Press Settings „Landmark-Log“
2. **E10:** `ExerciseProfile.visionFocus` (optional nullable)
   - Curl-Profil füllt Elbow-Focus
   - Painter/Highlight liest Focus wenn gesetzt, sonst Default Curl
   - Keine neuen Übungen implementieren — nur Hook + Docs
3. Kurze README-Notiz in Doc 14 / hardware session: wie man Log startet

**DoD Phase F:**

- [x] Recorder-Unit-Test (in-memory sink)
- [x] Curl-Focus via `VisionFocus.forExercise('bicep_curl')`
- [x] Default: Recording aus

---

## 5. Implementierungsreihenfolge

```
A Domain (E6/E10 models)
    → B Painter (MVP + E1 + E6 draw)
        → C Session + E3 + E2 basic
            → D E4 Guide + E5 Hysterese + Toggle
                → E E2 polish + E7 Pulse
                    → F E9 Recorder + E10 wire
```

| Phase | Scope | Aufwand (Richtwert) |
|-------|--------|---------------------|
| A | Topology, Modi, VisionFocus | 2–3 h |
| B | Painter, Overlay, E1, E6 | 3–5 h |
| C | Live-Bind, E3, E2 basic | 2–3 h |
| D | E4, E5, Polish | 3–4 h |
| E | E2 polish, E7 | 2–3 h |
| F | E9, E10 | 2–3 h |
| **Summe** | **ohne E8** | **ca. 2–3 Arbeitstage** (+ Geräte-QA) |

---

## 6. Feature-Spezifikation (E1–E7, E9, E10)

### E1 — Aktiven Arm hervorheben

- Quelle: Settings Arm-Seite **oder** höhere `armConfidence` links vs. rechts (Auto, optional)
- Painter: volle Farbe aktive Kette; Rest Alpha reduziert
- Bei `ArmOnly`-Modus: nur aktive Kette sichtbar

### E2 — Winkel-Farbcodierung

- Primärgelenk = Elbow (Curl) bzw. `VisionFocus.primaryAngle` (E10)
- Farblogik an Thresholds + optional Phase der Pose-SM
- Nicht mit IMU-Rep-Count verwechseln: Farbe = Form-Hinweis, kein Zähl-Veto in der UI-Schicht

### E3 — Tracking-Quality-Badge

- Drei Zustände: Tracking / Teilweise / Verloren
- Sichtbar während Detection; Farbe success / warning / error (Theme)
- Speist sich aus geglätteter Confidence (E5), nicht Roh-Frame allein

### E4 — Framed-Guide

- Nur wenn tracking lost / first-run
- Kein permanentes Clutter wenn gut getrackt
- Copy DE: klar, kurz, ohne Jargon

### E5 — Confidence-Hysterese

- Glättung + Frame-Counts für Zustandswechsel
- Verhindert Blinken bei visibility ~threshold
- Unit-Tests für Übergangsmatrix

### E6 — SkeletonDrawMode

```dart
enum SkeletonDrawMode { full, upper, armOnly }
```

- Default für Curl: `upper` oder `armOnly` (Empfehlung: **`upper`**)
- Persistenz über `VisionConfig` / Settings

### E7 — Fusion-Visual Sync

- Trigger: Fusion bestätigt Rep (beide Quellen / policy laut bestehender Engine)
- UI-only Pulse; Engine-API nicht umbauen außer lesendem Hook auf Decision-Stream/Snapshot

### E8 — **OUT OF SCOPE**

- Kein Blur, kein „nur Stickfigure auf Schwarz“, kein extra Privacy-Video-Modus
- Lokale Verarbeitung + kein Upload bleiben implizite Privacy-Story; kein zusätzliches UI-Feature

### E9 — Landmark Debug Record

- Opt-in, lokal, throttled
- Format dokumentieren (CSV-Header oder JSONL schema)
- Nie in Release-UI prominent; Debug/Dev-Schalter

### E10 — Multi-Exercise Joint Maps

- Datenmodell + Curl verdrahtet
- Zukünftige Übungen erweitern `VisionFocus` ohne Painter-Rewrite
- **Nicht** Squats/Deadlifts als 1.0-Produkt liefern

---

## 7. Manuelle Abnahme-Checkliste (Gerät)

| # | Check | Feature | Erwartung |
|---|--------|---------|-----------|
| M1 | Kamera-Permission | MVP | Preview erscheint |
| M2 | Person im Bild | MVP | Skelett an Schultern/Armen |
| M3 | Arm beugen | MVP, E2 | Ellenbogen wandert; Farbe/Winkel plausibel |
| M4 | Aus dem Bild | E3, E4 | Badge Verloren; Guide/Hinweis; kein Crash |
| M5 | Front vs. Back | MVP | Mirror korrekt |
| M6 | Skeleton Toggle aus | MVP | Nur Video; IMU unberührt |
| M7 | DrawMode Upper/ArmOnly | E6 | Weniger/ andere Bones |
| M8 | Aktiver Arm | E1 | Eine Seite dominant |
| M9 | Schlechtes Licht / Rand | E5 | Weniger Flackern als Roh-Frames |
| M10 | Bestätigte Fusion-Rep | E7 | Kurzer Pulse (wenn IMU+CV Session) |
| M11 | Debug-Record an | E9 | Datei lokal wächst; Default aus |
| M12 | Ohne Kamera | Soft-fail | Home/IMU ok |
| M13 | `flutter test` + `analyze` | alle | grün / 0 |

---

## 8. Risiken & Mitigation

| Risiko | Mitigation |
|--------|------------|
| Landmark versetzt (Letterbox) | Painter in gleicher Aspect-Box; Mapping-Tests |
| Frontkamera falsch gespiegelt | `mirrorX` an Lens |
| FPS-Drop | `shouldRepaint`; E6 ArmOnly; UI max ~30 Hz |
| User denkt Kamera ersetzt IMU | Screen-Copy + E7 nur Bestätigungs-Feedback |
| Feature-Creep | E8 gestrichen; E10 nur Hook; keine neuen Übungen |
| Debug-Daten versehentlich committed | gitignore `data/`; Recording default off |
| Package ändert Landmark-Layout | zentrale Indizes in `pose_skeleton.dart` |

---

## 9. Explizit out of scope

- **E8 Privacy-Blur / Stickfigure-only Preview**
- Store-Listing / iOS Archive (C1/C2/C4)
- `_useNewPipeline = true` freischalten
- Cloud ML / Server-Side Pose
- Multi-Person
- Kamera-Only als Default-Zähler
- Neue Übungen (Squat/Deadlift) als fertiges Produkt-Feature

---

## 10. Definition of Done (gesamter Scope dieses Plans)

1. [x] Live-Skelett über Preview (MVP A–C).  
2. [x] **E1** Arm-Highlight, **E3** Badge, **E2** Winkel-Farbe.  
3. [x] **E4** Framed-Guide bei lost, **E5** Hysterese.  
4. [x] **E6** drei Draw-Modi wählbar.  
5. [x] **E7** Fusion-Pulse UI-only.  
6. [x] **E9** opt-in lokaler Landmark-Log.  
7. [x] **E10** `VisionFocus` + Curl verdrahtet.  
8. [x] **E8 nicht** implementiert.  
9. [x] Tests + analyze grün; Docs `12`/`13` abgehakt; Changelog-Eintrag.  

---

## 11. Commit-Plan bei Umsetzung

1. `feat(cv): pose skeleton topology, draw modes, vision focus` (A, E6/E10 models)  
2. `feat(cv): skeleton painter + arm highlight overlay` (B, E1)  
3. `feat(cv): live skeleton, tracking badge, elbow color` (C, E2/E3)  
4. `feat(cv): framed guide + confidence hysteresis` (D, E4/E5)  
5. `feat(cv): fusion rep pulse on skeleton` (E, E7)  
6. `feat(cv): optional landmark session recorder` (F, E9)  
7. `docs(cv): skeleton overlay scope done; QA notes`

Jeder Commit: passende Tests grün.

---

## 12. Changelog dieses Docs

| Datum | Änderung |
|-------|----------|
| 2026-07-23 | Erster Plan: Overlay-MVP + E1–E10 als Ergänzungen |
| 2026-07-23 | **Scope-Update:** E8 gestrichen; E1–E7, E9, E10 fest in Phasen A–F integriert; DoD/Commits/Checkliste erweitert |
| 2026-07-23 | **Implementiert:** Phasen A–F Code + Tests; E10 via `VisionFocus.forExercise` (kein ExerciseProfile-JSON); Geräte-QA optional |
| 2026-07-23 | Fix: no-pose frames always emitted (`fromPoseResultOrEmpty`); E9 `FileLandmarkSink` under app docs; CHANGELOG CV-07 |

---

## 13. Referenzen

- `docs/Version1.0/04_CV_ARCHITEKTUR.md` — Ensemble-Prinzip  
- `docs/Version1.0/05_CV_KAMERA_SETUP.md` — Kamera + Permissions  
- `docs/Version1.0/06_CV_REP_COUNTER_WINKEL.md` — Winkel-SM  
- `docs/Version1.0/07_CV_SENSOR_FUSION.md` — IMU autoritativ  
- `tools/webcam_rep_counter.py` — Desktop-Skelett-Referenz  
- MediaPipe Pose Landmarker: 33 Landmarks (Google AI Edge Docs)

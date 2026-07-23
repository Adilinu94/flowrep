# CV-07 — Skelett-Overlay & Pose-Sichtbarkeit (Implementierungsplan)

> **Status**: 📋 PLAN (noch nicht implementiert)  
> **Stand**: 2026-07-23  
> **Bezug**: Screenshot-Referenz (Fitness-App mit gelben Gelenkpunkten + grünen Knochenlinien)  
> **Voraussetzung**: CV-01…06 Code-Scaffold (`CameraPoseProvider`, `PoseFrame`, `AngleCalculator`, Fusion)  
> **Priorität**: Optional CV-Track — **kein** 1.0 Release-Blocker  
> **Living Tracker**: nach Umsetzung in `12` / `13` abhaken  

---

## 0. Zielbild

Die App soll wie im Referenz-Screenshot:

1. Das **Live-Kamerabild** zeigen.
2. Den Körper des Users als **Skelett** erkennen (Arme, Gelenke, optional ganzer Körper).
3. **Punkte** (Gelenke) und **Linien** (Knochenverbindungen) darüber zeichnen.
4. Optional Form-/Tracking-Hinweise (z. B. „Tracking“, Winkel, good/bad).

**Produktprinzip bleibt unverändert:**

- IMU (M5StickC) ist **autoritativ** fürs Zählen.
- Kamera ist **optionaler** Validator / Trust-UI / Demo-Pfad.
- App funktioniert vollständig ohne Kamera.

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
Ohne diese Schicht „sieht“ der User die Erkennung nicht — obwohl die Pipeline Daten liefert.

---

## 2. Technologie-Entscheidung (bestätigt)

| Entscheidung | Wahl | Begründung |
|--------------|------|------------|
| Pose-Modell | Bestehendes `flutter_pose_detection` (MediaPipe-ähnlich, 33 Punkte) | Schon integriert, getestet, Mapper vorhanden |
| Rendering | Flutter `CustomPaint` + `Stack` über `CameraPreview` | Kein nativer Extra-Layer; testbar; Theme-fähig |
| Koordinaten | Normalisierte Landmark-`x/y` (0…1) → Widget-Pixel | MediaPipe-Standard; mit Aspect-Ratio / Mirror korrigieren |
| Neue Dependencies | **Keine** für MVP-Overlay | Vermeidet Doppel-Pipeline |
| Cloud-Vision | **Nein** | Privacy, Offline-Gym, Latenz |

---

## 3. Architektur: Overlay-Datenfluss

```
┌─────────────────┐     ImageStream      ┌──────────────────────┐
│ CameraController│ ──────────────────► │ NpuPoseDetector      │
└────────┬────────┘                      │ (flutter_pose_det.)  │
         │                               └──────────┬───────────┘
         │ Preview                                   │ PoseFrame
         ▼                                           ▼
┌─────────────────────────────────────────────────────────────┐
│ CameraPreviewOverlay (Stack)                                │
│  ┌────────────────────┐  ┌────────────────────────────────┐ │
│  │ CameraPreview      │  │ SkeletonOverlay (CustomPaint)  │ │
│  │ (live video)       │  │ points + bones + optional HUD  │ │
│  └────────────────────┘  └────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
  camera_session_screen: last PoseFrame, angle, fusion badge
```

### 3.1 Neue / geänderte Dateien

| Aktion | Pfad | Verantwortung |
|--------|------|----------------|
| **NEU** | `app/lib/presentation/widgets/skeleton_painter.dart` | `CustomPainter`: Punkte, Linien, Confidence-Filter |
| **NEU** | `app/lib/domain/vision/pose_skeleton.dart` | Reine Daten: Bone-Liste (Index-Paare), MediaPipe-Konstanten |
| **NEU** | `app/test/vision/pose_skeleton_test.dart` | Unit: Bone-Indizes, Mapping-Hilfen |
| **NEU** | `app/test/widgets/skeleton_painter_test.dart` | Widget/Pump: Overlay malt ohne Crash bei leeren Landmarks |
| **ÄNDERN** | `camera_preview_overlay.dart` | `Stack` + optionale `landmarks` / `showSkeleton` / `mirror` |
| **ÄNDERN** | `camera_session_screen.dart` | Letzten `PoseFrame` halten und an Overlay reichen |
| **ÄNDERN** | `vision_config.dart` (optional) | `highlightActiveArm`, `skeletonStyle` später |
| **ÄNDERN** | Docs `12` / `13` | Checkbox nach Implementierung |

**Nicht ändern (Guardrails):**

- `workout_engine.dart` / `exercise_engine.dart` Zähllogik
- `_useNewPipeline` (bleibt `false`)
- IMU-autoritative Fusion-Regeln (nur UI-Feedback erweitern)

---

## 4. Detailplan — Phasen

### Phase A — Domain: Skelett-Topologie (rein, testbar)

**Ziel:** Stabil definieren, *welche* Punkte verbunden werden.

**Tasks:**

1. `PoseSkeleton` mit MediaPipe-Indizes (bereits in `PoseLandmarkIndex` / AngleCalculator genutzt):
   - Oberkörper-Core: 11–16 (Schultern, Ellenbogen, Handgelenke), 23–24 (Hüfte)
   - Optional Beine: 25–28 (Knie, Knöchel)
   - Gesicht optional weglassen (Noise im Gym)
2. `List<(int, int)> bones` als const — Paare nur gültige Indizes 0…32.
3. Helper `visibleEnough(landmark, minConf)` für Filter.
4. Helper `toCanvasOffset(landmark, Size canvas, {bool mirrorX})`.

**DoD Phase A:**

- [ ] Unit-Tests: alle Bone-Indizes in 0…32
- [ ] Unit-Tests: Mapping (0,0)→links-oben, (1,1)→rechts-unten; Mirror invertiert X
- [ ] `flutter test` grün, kein UI

---

### Phase B — Painter + Overlay-UI

**Ziel:** Screenshot-ähnliches Live-Skelett.

**Tasks:**

1. `SkeletonPainter extends CustomPainter`:
   - Input: `List<FlowPoseLandmark>?`, `minConfidence`, `highlightArm` (left/right/both/none), Farben
   - Zeichne erst **Bones** (Linien), dann **Joints** (Kreise) — wie im Referenzbild
   - Punkt-Radius ~4–6 dp, Linie Stroke ~2–3 dp
   - Default-Farben: Gelenke accent/gelb, Knochen primary/grün (Theme-aware optional)
   - `shouldRepaint`: nur wenn landmarks/config sich ändern
2. `CameraPreviewOverlay` erweitern:
   ```dart
   // konzeptionell
   Stack(
     fit: StackFit.expand,
     children: [
       CameraPreview(controller!),
       if (showSkeleton && landmarks != null)
         CustomPaint(
           painter: SkeletonPainter(...),
           size: Size.infinite,
         ),
       // optional: Tracking-Badge unten
     ],
   )
   ```
3. Aspect-Ratio / Letterboxing: Painter muss **dieselbe** Box wie Preview nutzen (nicht Full-Screen verzerren).
4. Frontkamera: `mirrorX: true` wenn Lens front (User-Spiegel).
5. Leere/fehlende Pose: kein Skelett, kein Crash; Status-Text „Person nicht erkannt“ optional.

**DoD Phase B:**

- [ ] Overlay kompiliert; Analyze 0 Issues
- [ ] Widget-Test: leere Landmarks → kein Exception
- [ ] Manuell am Gerät: Skelett sitzt ungefähr auf Schultern/Armen (erste grobe QA)

---

### Phase C — Session-Screen-Anbindung

**Ziel:** Live-Datenfluss end-to-end.

**Tasks:**

1. In `_CameraSessionScreenState`:
   - `PoseFrame? _lastFrame`
   - In `_onPoseFrame`: Frame speichern + Winkel wie bisher
2. `CameraPreviewOverlay(..., landmarks: _lastFrame?.landmarks, showSkeleton: config.showSkeletonOverlay)`
3. `VisionConfig.showSkeletonOverlay` aus Provider/Settings lesen (falls Settings schon CV-Flags haben; sonst vorerst hart `true` wenn detecting).
4. Kleines HUD:
   - „Tracking“ wenn `armConfidence >= min`
   - „Niedrige Sichtbarkeit“ wenn confidence niedrig
   - optional Ellenbogen-Winkel als Chip (schon Text vorhanden — optisch näher ans Preview)

**DoD Phase C:**

- [ ] Start Detection → bei Person im Bild Skelett sichtbar
- [ ] Stop → Overlay aus / letzte Frame cleared
- [ ] Soft-fail ohne Kamera unverändert
- [ ] Fusion/Winkel-Pfad unverändert grün in Unit-Tests

---

### Phase D — Polish & QA

**Tasks:**

1. FPS-Label optional (debug only, `kDebugMode`)
2. Skeleton Toggle im Camera-Screen (IconButton), schreibt lokal / Config
3. Screenshot-Vergleich: Punkte auf Gelenken, nicht versetzt (Mapping-Bug fixen falls Letterbox)
4. Dokumentieren in `docs/hardware/sessions/…` bei Geräte-Test
5. `12_IMPLEMENTIERUNGS_STATUS` + `13_OFFENE_PUNKTE` updaten

**DoD Phase D:**

- [ ] Manuelle Checkliste (unten §7) grün oder ehrlich env-deferred
- [ ] Commit + Push mit Doc-Update

---

## 5. Implementierungsreihenfolge (empfohlen)

```
A Domain Bones/Mapping  →  B Painter/Overlay  →  C Session bind  →  D Polish/QA
         │                        │                     │
         └──── unit tests ────────┴── widget smoke ─────┘
```

Geschätzter Aufwand:

| Phase | Aufwand |
|-------|---------|
| A | 1–2 h |
| B | 2–4 h |
| C | 1–2 h |
| D | 1–2 h + Gerätezeit |
| **Summe MVP** | **ca. 1 Arbeitstag** (+ HW) |

---

## 6. Zehn sinnvolle Ergänzungen / Verbesserungen

Über das reine Skelett hinaus — priorisiert nach Nutzen für FlowRep (nicht Feature-Creep).

### E1 — Aktiven Arm hervorheben

**Was:** Primärer Curl-Arm (links/rechts aus Settings oder Auto-Detect) in voller Farbe; Gegenseite und Beine gedimmt.  
**Warum:** Reduziert visuelle Last; User sieht sofort, was die App „zählt“.  
**Anker:** `PoseFrameMapper.primaryElbow` / Settings Arm-Seite.

### E2 — Winkel-Farbcodierung am Ellenbogen

**Was:** Gelenkfarbe nach Winkel: grün (ROM ok, z. B. zwischen up/down-Schwellen-Pfad), gelb (grenzwertig), rot (zu flach / partial rep).  
**Warum:** Wie „Rejects Bad Reps“ im Referenz-Screenshot — sofortiges Form-Feedback ohne Text wälzen.  
**Anker:** `VisionConfig.angleUpThreshold` / `angleDownThreshold`.

### E3 — Tracking-Quality-Badge

**Was:** Persistentes Badge: Tracking / Teilweise / Verloren (aus mittlerer Landmark-Confidence Armkette).  
**Warum:** Erklärt, warum Kamera-Fusion „unsicher“ ist; baut Vertrauen.  
**Anker:** `armConfidence`, `FusionEngine` Diagnostics.

### E4 — Auto-Kamerawahl & Framed-Guide

**Was:** Onboarding-Overlay: Silhouette / Rahmen „Oberkörper mittig, Arme im Bild“; Warnung wenn >N Frames ohne Pose.  
**Warum:** Häufigster Fail: Person nicht im Bild / zu nah / Gegenlicht — nicht das Modell.  
**Anker:** Doc 05 Permissions + Session-Screen Empty-State.

### E5 — Low-Light & Confidence-Hysterese

**Was:** Confidence-Glättung (z. B. One-Euro oder einfaches EMA) + Mindest-Frames bevor „Tracking lost“.  
**Warum:** Flackerndes Skelett zerstört Trust; Gym-Licht ist oft schlecht.  
**Anker:** Bestehende Filter-Patterns in `domain/filters/`.

### E6 — Skeleton-Modi: Full / Upper / Arm-only

**Was:** Drei Zeichen-Modi in Settings: ganzer Körper, nur Torso+Arme, nur aktive Armkette.  
**Warum:** Bizeps-Curl braucht keine Knie; weniger Clutter und etwas weniger Paint-Kosten.  
**Anker:** `VisionConfig` erweitern (`SkeletonDrawMode` enum).

### E7 — Fusion-Visual Sync

**Was:** Bei bestätigter IMU+CV-Rep kurzer Pulse am Ellenbogen-Punkt / Confetti-frei: 1× Scale-Animation.  
**Warum:** Verknüpft haptisches/IMU-Count mit dem, was die Kamera „sieht“.  
**Anker:** `FusionEngine` Decision + FeedbackService (ohne Zähllogik zu ändern).

### E8 — Privacy Mode (Preview blur, Pose only)

**Was:** Optional Hintergrund stark unscharf / abdunkeln, nur Skelett scharf (oder nur Stickfigure auf dunklem Grund).  
**Warum:** Nutzer filmen sich im Gym; weniger „Video von mir“, mehr „Stickfigure“. DSGVO-Story.  
**Anker:** Settings + Overlay-Stack (Blur-Filter teuer → erst nach FPS-Messung).

### E9 — Record-for-Debug (opt-in, lokal)

**Was:** Debug-only: kurze Landmark-CSV/JSON pro Session (Timestamps + 33 Punkte), **kein** Video-Upload.  
**Warum:** Repro von Mapping-Bugs und schlechten Winkeln ohne personenbezogene Videos im Repo.  
**Anker:** `CsvSessionRecorder`-Muster; gitignore `data/`.

### E10 — Multi-Exercise Joint Maps

**Was:** Pro ExerciseProfile definieren, welche Bones/Winkel primär sind (Curl: Elbow; später Overhead: Shoulder; Squats: Knee — wenn Scope wächst).  
**Warum:** Ein generisches Skelett skaliert; die *Semantik* pro Übung macht CV nützlich.  
**Anker:** `exercise_registry` / `ExerciseProfile` optional `visionFocus` Feld — **nur vorbereiten**, Squats nicht in 1.0 erzwingen.

---

### Priorisierung der 10 Ergänzungen

| Prio | ID | Wann |
|------|-----|------|
| P0 (mit Overlay-MVP) | E1, E3 | direkt nach Phase C |
| P1 (nächster Sprint CV) | E2, E4, E6 | nach stabilem Mapping |
| P2 (Qualität) | E5, E7 | wenn Flackern / Trust-Themen |
| P3 (später / optional) | E8, E9, E10 | Privacy, Debug, Multi-Exercise |

---

## 7. Manuelle Abnahme-Checkliste (Gerät)

| # | Check | Erwartung |
|---|--------|-----------|
| M1 | Kamera-Permission erteilen | Preview erscheint |
| M2 | Person im Bild, Oberkörper sichtbar | Skelett an Schultern/Armen |
| M3 | Arm beugen (Curl-Geste) | Ellenbogen-Punkt wandert; Winkel-Text ändert sich |
| M4 | Aus dem Bild gehen | Skelett weg / Badge „Verloren“; App crasht nicht |
| M5 | Front vs. Back | Mapping gespiegelt korrekt bei Front |
| M6 | Skeleton Toggle aus | Nur Video, Zähllogik IMU unberührt |
| M7 | Ohne Kamera / Soft-fail | Home/IMU weiter nutzbar |
| M8 | `flutter test` + `analyze` | grün / 0 Issues |

---

## 8. Risiken & Mitigation

| Risiko | Mitigation |
|--------|------------|
| Landmark-Koordinaten versetzt (Letterbox) | Painter in **derselben** AspectRatio-Box wie Preview; Tests mit bekannten Sizes |
| Frontkamera gespiegelt falsch | `mirrorX` an `cameraLens` koppeln |
| FPS-Drop durch Paint | `shouldRepaint` streng; nur Arm-Bones (E6); max. 30 Hz UI-Update throttlen |
| User denkt Kamera ersetzt IMU | Copy im Screen: „Validierung — Zählen über Sensor“ |
| Privacy-Bedenken | Lokale Verarbeitung betonen; E8 später; kein Upload |
| Package-API ändert Landmark-Layout | Mapper-Tests; Indizes zentral in `pose_skeleton.dart` |

---

## 9. Explizit out of scope (dieses Plan-Doc)

- Store-Listing / iOS Archive (C1/C2/C4)
- `_useNewPipeline = true` freischalten
- Cloud ML / Server-Side Pose
- Vollständige Multi-Person-Erkennung
- Ersatz der IMU-Pipeline durch Kamera-Only als Default
- Neue Übungen (Squat/Deadlift) als Produkt-Scope 1.0

---

## 10. Definition of Done (Overlay-MVP = Phasen A–C)

1. Live-Skelett (Punkte + Linien) über Kameravorschau bei erkannter Pose.  
2. Confidence-Filter; kein Crash ohne Person.  
3. Anbindung an bestehenden `PoseFrame`-Stream; Winkel/Fusion ungebrochen.  
4. Unit- (+ optional Widget-)Tests für Topology und leeres Overlay.  
5. `flutter analyze` 0, `flutter test` grün.  
6. Doc-Update in `12`/`13` + kurzer Changelog-Eintrag.  
7. E1/E3 idealerweise schon grob (Highlight + Badge); E2–E10 als Backlog in diesem Doc.

---

## 11. Commit-Plan bei Umsetzung

Empfohlene atomare Commits:

1. `feat(cv): pose skeleton topology + coordinate mapping`  
2. `feat(cv): skeleton CustomPainter + preview stack overlay`  
3. `feat(cv): wire live PoseFrame into camera session skeleton`  
4. `docs(cv): mark skeleton overlay done; QA notes`

Jeder Commit: nur passende Dateien, Tests grün.

---

## 12. Changelog dieses Docs

| Datum | Änderung |
|-------|----------|
| 2026-07-23 | Erster detaillierter Plan: Overlay-MVP + 10 Ergänzungen (E1–E10), Phasen A–D, DoD |

---

## 13. Referenzen

- `docs/Version1.0/04_CV_ARCHITEKTUR.md` — Ensemble-Prinzip  
- `docs/Version1.0/05_CV_KAMERA_SETUP.md` — Kamera + Permissions  
- `docs/Version1.0/06_CV_REP_COUNTER_WINKEL.md` — Winkel-SM  
- `docs/Version1.0/07_CV_SENSOR_FUSION.md` — IMU autoritativ  
- `tools/webcam_rep_counter.py` — Desktop-Skelett-Referenz  
- MediaPipe Pose Landmarker: 33 Landmarks (Google AI Edge Docs)

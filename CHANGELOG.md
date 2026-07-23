# Changelog

All notable changes to FlowRep are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/). Versioning: SemVer.

## [1.0.0-rc.1] — 2026-07-23

Release-candidate line for FlowRep 1.0 **code freeze** (product IMU path). Physical A-path HW validation and store admin remain open (see `docs/Version1.0/13_OFFENE_PUNKTE.md`).

### Added

- P0–P2 product features: correction UI + rule-based θ learning, rest timer, session end/summary, BLE reconnect, foreground service, settings, lifecycle, dark mode, sound/icon/splash
- Manual set end: `autoEndSetEnabled: false`, UI „Satz beenden“, `correctedReps` without rewriting `countedReps`
- CV optional track: camera soft-fail, pose angle / rep counter, fusion engine (IMU authoritative)
- Real pose landmark confidence into fusion (`PoseFrameMapper.armConfidence` / `primaryElbow`; no live `0.8` placeholder)
- **CV-07 skeleton overlay** (optional): live bones/joints over preview, active-arm highlight (E1), elbow form color (E2), tracking badge (E3), framed guide (E4), confidence hysteresis (E5), draw modes full/upper/arm-only (E6), fusion rep pulse UI-only (E7), opt-in local landmark CSV under app documents (E9), `VisionFocus.forExercise` (E10). No E8 privacy blur. Empty no-pose frames keep tracking quality honest when person leaves frame.
- Living docs: `docs/Version1.0/10`–`14`, hardware session notes
- Post-1.0 backlog: `docs/Version1.0/15_VERBESSERUNGEN_EXTERNE_REPOS.md` (external-repo research + ticket IDs)

### Changed

- gP counting hardened against wiggle (θ-floor 50, 0.70×θ, duration ≥15 samples, peak ≥1.2×θ)
- Docs reorganized under `docs/reference/`, `docs/hardware/`, `docs/design/`, `docs/archive/`
- Doc 15 code-review pass: A2 battery marked DONE, A1 on gP product path, slim V1.1, Already/Delta, B11–B16; cross-links in 00/12/13

### Fixed

- Rest-gate / false auto set end removed from product path
- Wiggle false-counts reduced via duration + peak gates (unit evidence; HW retest still recommended)

### Known open (not blocking this RC tag)

| ID | Topic | Notes |
|----|--------|--------|
| A1–A5 | Physical core session | User + M5 motion DoD |
| B1–B4, B6–B9 | Optional HW QA | Needs body motion / long sessions |
| B5 | `_useNewPipeline = true` | **Forbidden** without Shadow G5/G6 DoD — stays `false` |
| C1 | iOS Archive | Lab has no iOS device |
| C2 | Play Console / Signing | Outside code scope |
| C4 | Store listing / privacy final | DSGVO settings exist in app |
| D1 device / D3 / D4 | Live NPU / webcam / emulator | Optional; code soft-fail ready |
| D5 | Native YUV→RGB opt | Deferred — Dart already feeds `yuv420` |

### Verified at tag

- `flutter analyze lib` clean (re-run on tag commit)
- `flutter test` green (incl. vision D2 confidence path)
- `_useNewPipeline = false`
- `origin/main` parity after push

## [0.1.0] — prior development

Early BLE/IMU product development before RC packaging.

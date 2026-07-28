# gP-Shadow: Branch-Bereinigung nach Mehrfach-Implementierung

**Datum:** 2026-07-28
**Anlass:** Drei unabhängige Claude-Sessions haben parallel am selben P0-Vorschlag
(richtungsbewusster Schatten-Zählpfad für gP, siehe
`docs/design/IMU_REP_COUNTER_VERIFICATION_2026-07-26.md`) gearbeitet, ohne
voneinander zu wissen — das bekannte Multi-Agent-Kollisionsrisiko dieses
Projekts, diesmal konkret auf drei Branches verteilt.

## Was existierte

| Branch | Ansatz | Ergebnis |
|---|---|---|
| `agent/directional-gp-shadow` | Eigene `DirectionalGpShadow`-Klasse, Mount-Erkennung über "unpaired opposite cycles" | **Gemerged nach main** (Commit `9f128b3`, Merge `8416564`) |
| `p0-directional-gp-shadow` | Eigene `DirectionalGpShadow`-Klasse, Mount-Erkennung über Rotations-/Projektions-Verhältnis | Geschlossen (dieser Chat-Thread) — funktional redundant zur gemergten Version |
| `fix/direction-aware-counting-shadow` | Phasen-Logik direkt inline in `workout_engine.dart`, plus eigene Python-Referenz (`DirShadow`, `run_direction_aware_shadow_verification` in `tools/workout_engine_simulation.py`) | Geschlossen — hätte mit der bereits gemergten Version kollidiert/dupliziert |

## Warum die gemergte Version behalten wurde

Vor der Entscheidung wurde die gemergte Version tatsächlich verifiziert, nicht
nur die Merge-Message geglaubt:

- Vollständiger `flutter test`-Lauf auf echter Toolchain (Desktop Commander):
  **466/477 grün.** Alle 11 Fehlschläge unabhängig als vorbestehend
  identifiziert (4× `dsp_verification_test.dart`, 3×
  `exercise_engine_pipeline_test.dart`, 1× `p1_assets_structural_test.dart`,
  1× `reconnect_test.dart`, 2× `workout_engine_test.dart` ROM-Gate — Letztere
  explizit gegen den Stand *vor* jeder gP-Shadow-Änderung gegengeprüft:
  identischer Fehlschlag, also nicht durch dieses Feature verursacht).
- Der große Diff-Fußabdruck in `workout_engine.dart` (321+/108-) ist zu
  ca. 95% reines `dart format`-Reformatting, keine Logikänderung. Die
  tatsächliche Verdrahtung ist additiv (neues Feld, zwei neue Getter,
  ein zusätzlicher Aufruf, korrektes Nullen bei Rekalibrierung auf
  Nicht-gP).
- Die Mount-Mismatch-Erkennung der gemergten Version (unpaired opposite
  cycles) trifft den im Verifikationsbericht bewiesenen Fall (invertierte
  Montage → 0/10 im Signed-Modus) präziser als der Ansatz auf
  `p0-directional-gp-shadow` (Rotations-/Projektions-Verhältnis).

## Was NICHT verloren geht

- `fix/direction-aware-counting-shadow`s Python-Referenz (`DirShadow`,
  `run_direction_aware_shadow_verification`) wurde inhaltlich gegen dieselbe
  Faktenbasis wie die gemergte Dart-Version geprüft — keine widersprüchlichen
  Erkenntnisse gefunden, nur eine andere Code-Organisation. Nichts davon war
  nötig, um die Merge-Entscheidung zu treffen.
- Alle drei ursprünglichen Design-Dokumente (P0-Verifikationsbericht,
  `DIRECTIONAL_GP_SHADOW_ROLLOUT_2026-07-27.md` der gemergten Version,
  `p0-directional-gp-shadow`s eigenes Rollout-Dokument) bleiben über die
  Commit-Historie der geschlossenen Branches referenzierbar, auch nach dem
  Löschen der Branch-Referenzen selbst (Commits sind über die main-Historie
  bzw. bei Bedarf über die Reflogs/den Fork weiterhin auffindbar).

## Bewusst NICHT angefasst

`feature-exercise-selection-start-button` (1 Commit, `fb10ce9`, von Adi
selbst am 2026-07-22, „Übungsauswahl + Start-Knopf mit Countdown") ist
**kein Teil dieser Kollision** — ein eigenständiges, echtes Feature, keine
KI-Dopplung. Bewusst nicht gelöscht oder sonst angefasst; das ist eine
Produkt-/Roadmap-Entscheidung, keine Aufräumarbeit.

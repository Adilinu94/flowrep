# Externe KI-Analyse — Status (2026-07-12)

**Quelle:** Externe KI (komplette Repo-Analyse + Forschung)
**Letztes Update:** 2026-07-12 (Punkte B-G bearbeitet)

---

## A. Datenpfad-Unsicherheit 🟡

**Status:** Teilweise verifiziert
- Serial zeigt echte IMU-Werte (mag ~0.99, Gyro bei Curl bis 344 deg/s)
- BLE-Pfad: App zeigt Batches steigend + 18.4 Hz Rate
- No-CCCD-Ansatz (ADR-017) erzwingt echte Over-the-Air GATT Reads
- App-DIAG-Logs mit Serial parallel noch nicht capturet

---

## B. Dart-Bug: `late final _engine` Doppelzuweisung ✅

**Status:** GEFIXT (2026-07-12)
- `final` vom `late final WorkoutEngine _engine` entfernt
- `_bindEngine()`-Methode eingefuehrt fuer sauberes Stream-Subscription-Management
- `_samplesSub`/`_eventsSub` Felder fuer Cleanup in `dispose()`
- Verhindert `LateInitializationError` beim zweiten Verbinden nach Kalibrierung

---

## C. "Fuer Diagnose gesenkte" Parameter ✅

**Status:** GEFIXT (2026-07-12)
- `_minPeakHeight`: 1.05 → 1.2 (ueber Rausch-Floor)
- `_minPeakDistanceSamples`: 8 → 12 (verhindert Doppel-Peaks, ~164ms Minimum)
- `_minGyroPeakDegPerS`: 10.0 → 50.0 (erfordert echte Rotation)
- Zwei-Faktor-Filter: Accel >= 1.2g UND Gyro >= 50 deg/s

---

## D. Ruhephase ist keine echte Ruhephase ✅

**Status:** GEFIXT (2026-07-12)
- `startGuidedCalibration()` von `_startRest()` nach `_startRecording()` verschoben
- Engine zaehlt jetzt erst ab "Mach 10 Bizeps-Curls!"
- 8s Ruhephase (3s rest + 5s countdown) laesst EMA-Filter auf Baseline konvergieren
- `_cancel()` vereinfacht (kann `cancelCalibration()` immer aufrufen, no-op in idle)

---

## E. Gyro fliesst in Alltagsbetrieb ein (ADR-004) ✅

**Status:** DOKUMENTIERT (2026-07-12)
- ADR-004 um Update ergaenzt: Gyro-Beitrag (gyroWeight=0.05) begruendet
- Reiner Accel nur ~0.2g Exkursion, Gyro verstaerkt um Faktor 5-20
- Kein Code-Fix noetig — aktuelle Implementierung ist korrekt

---

## F. Sicherheitsnetz nicht synchron ✅

**Status:** GEFIXT (2026-07-12) — Adi hat dem Fix zugestimmt ("kümmere dich um die letzten Punkte")
- `_findPeaksWithIndices()` in `workout_engine.dart` jetzt tie-tolerant (`>=`
  statt `>` auf einer Seite) — behebt das Plateau-Problem unten
- Entsprechender Dart-Test in `workout_engine_test.dart` von `skip:` befreit
  und in einen aktiven Regressionstest umgewandelt
- `tools/workout_engine_simulation.py`: `GuidedCalibrationSim` (Standard)
  spiegelt jetzt den gefixten Stand; `GuidedCalibrationSimStrictLegacy` bewahrt
  das alte Verhalten nur noch zu Vergleichszwecken auf
- Ursache war ein Median-Filter-Plateau: bei sauberen, kontrollierten
  Wiederholungen erzeugte der 5-Sample-Median-Filter ein mehrere Samples
  breites Plateau exakt am Scheitelpunkt. Die vorherige strikte
  Lokal-Maximum-Pruefung (`smoothed[i] > beide Nachbarn`) konnte darin
  strukturell KEINEN Punkt als Peak erkennen — auch wenn der Peak eindeutig
  war. Bei der realen App-Datenrate (~14-20 Hz) fuehrte das in der Simulation
  zu 0 von 30 abgeschlossenen Kalibrierungen; nach dem Fix 30 von 30.
- Noch zu erledigen: auf dem echten Geraet verifizieren, nicht nur in der
  Simulation — naechster Kalibrierungslauf sollte deutlich zuverlaessiger sein
- CALIB-Logs aus einem echten Lauf mitschneiden steht weiterhin aus (Punkt A)

---

## G. Doku-Hygiene ✅

**Status:** GEFIXT (2026-07-12)
- ADR-015 auf `flutter_secure_storage` korrigiert (war fälschlich Drift/SQLCipher)
- ADR-004 um Gyro-Rationale ergaenzt
- ADR-017/018 waren bereits in der ADR-Datei vorhanden
- Diese Analyse-Datei als zentrale TODO-Liste erstellt

---

## Zusammenfassung

| Punkt | Status |
|-------|--------|
| A Datenpfad | 🟡 Teilweise |
| B late final Bug | ✅ Gefixed |
| C Diagnose-Parameter | ✅ Restauriert |
| D Ruhephase | ✅ Gefixed |
| E Gyro/ADR-004 | ✅ Dokumentiert |
| F Simulation + Plateau-Fix | ✅ Gefixt, auf echtem Gerät noch zu verifizieren |
| G Doku-Hygiene | ✅ Gefixed |

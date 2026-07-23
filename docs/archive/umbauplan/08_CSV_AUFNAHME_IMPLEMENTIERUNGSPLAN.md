# 08 – Implementierungsplan: CSV-Aufnahmefunktion (Dokument 07)

**Status:** Rechercheergebnis + Plan, noch nicht implementiert. Session Claude-9936160f, 2026-07-15.
**Bezug:** Setzt `07_STRATEGISCHES_ARBEITSDOKUMENT_DATENAKQUISITION.md` technisch um (Szenen A–G).
**Bewusst ausgeklammert:** Die Firmware-Frage aus `STATUS_FORTSCHRITT.md` Abschnitt B (main.cpp / Streaming-Autostart) ist NICHT Teil dieses Plans – wird laut Adi von einer anderen Session bearbeitet. Diese Aufnahmefunktion setzt voraus, dass Streaming funktioniert; falls die Firmware-Frage sich als das eigentliche "0 Reps"-Problem herausstellt, ist das unabhängig von hier.

---

## 1. Architektur-Fund: Wo die Aufnahme einhakt

`ISensorProvider.samples` (`lib/data/providers/sensor_provider.dart`) ist ein `Stream<SensorSample>` aus einem `StreamController.broadcast()`. `home_screen.dart` hört diesen Stream bereits an einer Stelle ab:

```dart
_samplesSub = widget.sensorProvider.samples.listen(_engine.processSample);
```

Weil es ein Broadcast-Stream ist, kann ein zweiter, unabhängiger Listener denselben Strom anzapfen, ohne `WorkoutEngine` oder `SignalProcessor` anzufassen – das entspricht genau dem in `signal_processor.dart` dokumentierten Prinzip ("Pure signal processing... No state machine logic"). Die Aufnahmefunktion braucht also **keine** Änderung an Engine, SignalProcessor oder BLE-Provider, nur einen zusätzlichen Listener auf denselben Stream. Das reduziert das Risiko, etwas an der ohnehin fragilen Zähl-Logik zu beschädigen, auf praktisch null.

`SensorSample` (`workout_engine.dart`) liefert bereits alles Rohe: `timestamp, ax, ay, az (g), gx, gy, gz (°/s)`.

## 2. Diskrepanz zu Dokument 07s Spalten-Spec

Dokument 07 nennt als Spalten: `timestamp_ms, raw_accel_x/y/z, raw_gyro_x/y/z, filtered_accel_x/y/z, dyn_magnitude`.

**Problem:** `filtered_accel_x/y/z` (gefilterte Beschleunigung PRO ACHSE) setzt eine Gravitationskompensation pro Achse voraus – das gibt es in der aktuell deployten Pipeline nicht. `SignalProcessor.process()` liefert nur einen einzigen skalaren Wert (`accelMagnitude + gyroMagnitude*gyroWeight`, EMA-gefiltert), keine Pro-Achsen-Werte. Diese Spalte stammt vermutlich aus der Zeit, als noch von der Komplementärfilter-Architektur (ADR-019) ausgegangen wurde – die laut Phase-2-Untersuchung (siehe `STATUS_FORTSCHRITT.md` Abschnitt C, Skript 1c in Dokument 04) aktuell nicht weiterverfolgt wird.

**Empfehlung:** `filtered_accel_x/y/z` jetzt WEGLASSEN statt mit Platzhaltern zu füllen, die nichts bedeuten würden. Stattdessen `dyn_magnitude` (= `SignalProcessor.process()`-Rückgabewert, exakt der Wert, den die Produktions-Pipeline auch nutzt) als einzige abgeleitete Komfort-Spalte behalten – für schnelles visuelles Prüfen in Excel, **nicht** als Grundlage für die eigentliche DSP-Analyse. Jeder Vergleich alt vs. neu (Phase 2/4) sollte immer aus den Rohspalten neu berechnet werden (wie in `tools/dsp_lab_phase2_extended.py`), nicht aus dieser Komfort-Spalte – sonst schleicht sich unbemerkt die aktuelle Formel als Vorannahme in einen Vergleich ein, der gerade prüfen soll, ob eine andere Formel besser ist.

**Empfohlenes finales Format:**
```
timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,dyn_magnitude,workout_state
```
`workout_state` zusätzlich aufgenommen (nicht in Dokument 07 vorgesehen) – kostet nichts, aber macht spätere Auswertung einfacher (z. B. nur `active`-Phasen für Peak/Pause-Analyse herausfiltern, ohne die Zeitfenster manuell wieder zu suchen wie in Skript 1).

## 3. Speicherort – Recherche (aktuell, Stand heute geprüft)

Web-Recherche zu `path_provider` (aktuelle Version 2.1.6, publiziert 2026-06-15, `flutter.dev` als Publisher) und Androids aktuellen Scoped-Storage-Regeln:

- **`getApplicationDocumentsDirectory()`** – App-privater interner Speicher. Ohne Root/`adb run-as` nicht einsehbar. Ungeeignet, wenn die CSV danach z. B. für die Python-Analyse auf den PC soll.
- **`getExternalStorageDirectory()`** (Android-exklusiv, in `path_provider` als "External Storage" geführt) – **app-spezifischer** externer Speicher (`/Android/data/com.flowrep.flowrep/files/...`), **kein** `MANAGE_EXTERNAL_STORAGE` oder sonstige Laufzeit-Permission nötig (anders als der veraltete, geteilte externe Speicher), über Dateimanager/USB-MTP direkt einsehbar. Das ist die von Google aktuell empfohlene Lösung für genau diesen Fall (app-eigene Dateien, die der Nutzer trotzdem manuell abholen soll). `minSdk` ist über `flutter.minSdkVersion` gesetzt (Flutter-Default, liegt über der von `path_provider` geforderten SDK 24 – passt ohne Änderung).
- **`MANAGE_EXTERNAL_STORAGE`** (voller Zugriff auf geteilten Speicher) bewusst NICHT verwendet – Google Play schränkt diese Permission seit 2021 stark ein, und für app-eigene Aufnahmedateien ist sie unnötig.

**Empfehlung:** `getExternalStorageDirectory()` → Unterordner `recordings/`. Zusätzlich optional ein "Teilen"-Button über `share_plus` (öffnet den normalen Android-Share-Sheet – direkt zu Drive, E-Mail, etc.), falls Adi die Datei nicht per USB abholen will. Beides zusammen kostet nur eine zusätzliche, sehr verbreitete Dependency (`share_plus`), keine neue Permission.

## 4. CSV-Erzeugung: kein neues Package nötig

Format ist trivial (nur Zahlen/Timestamps, keine Kommas/Anführungszeichen in den Werten) → manuelles Zusammenbauen über `StringBuffer` reicht, spart die zusätzliche Abhängigkeit `csv` (dieses Projekt hat mit `flutter_blue_plus`-Versionskonflikten schon genug Dependency-Ärger gehabt – jede vermeidbare zusätzliche Abhängigkeit ist ein Pluspunkt). Bei Bedarf später leicht auf das `csv`-Package umstellbar, falls doch mal Freitext-Spalten dazukommen.

## 5. UI-Integration

- Neuer Button analog zum bestehenden "Dummy Stream"-Button-Stil (`ElevatedButton`, eigene `backgroundColor`), Beschriftung z. B. "Aufnahme starten"/"Aufnahme stoppen (N Samples)".
- **Sichtbarkeit:** In `home_screen.dart` existiert aktuell KEIN `kReleaseMode`/`kDebugMode`-Gate für irgendeinen Button – diese Funktion führt das Muster neu ein (`import 'package:flutter/foundation.dart' show kReleaseMode;`, Button nur wenn `!kReleaseMode`). Entspricht Dokument 07s Vorgabe ("wird im Produktiv-Build versteckt") und dem Grundgedanken von ADR-010 (Rohbewegungsdaten vorsorglich wie Gesundheitsdaten behandeln) – auch wenn ADR-010 sich konkret auf Einwilligungs-UI bezieht und hier aktuell nur Adi selbst testet (`00_ENTSCHEIDUNGEN_ERFORDERLICH.md`), ist "Funktion gar nicht erst im Produktiv-Build sichtbar" die einfachste Art, im Sinne der ADR zu handeln, ohne eine Einwilligungs-UI für ein Ein-Personen-Dev-Tool zu bauen.
- Platzierung: im bestehenden `if (!_isMock) Row(...)`-Block neben "Trennen"/"Dummy Stream", da Aufnahme nur mit echter Hardware sinnvoll ist (Mock-Daten sind bereits synthetisch, dafür gibt es `tools/*.py`).

## 6. Geplante Dateien

| Datei | Änderung |
|---|---|
| `app/lib/data/repositories/csv_session_recorder.dart` | **Neu.** Klasse `CsvSessionRecorder`: `start()`/`stop()`, hört `ISensorProvider.samples`, eigene `SignalProcessor()`-Instanz (Standardwerte = Produktionswerte), sammelt Zeilen im Speicher, schreibt beim Stop als eine Datei. |
| `app/lib/presentation/screens/home_screen.dart` | Neuer State (`CsvSessionRecorder`, `_isRecording`, `_recordedSampleCount`), neuer Button + Statuszeile, `kReleaseMode`-Gate. |
| `app/pubspec.yaml` | `share_plus` ergänzen (für den optionalen Teilen-Button). `path_provider` prüfen, ob schon vorhanden – falls nicht, ergänzen. |

## 7. Offene Entscheidungen für Adi

1. **Speicherort bestätigen:** App-spezifischer externer Speicher + optionaler Share-Button (Empfehlung oben) – oder lieber nur Share-Button ohne dauerhafte Ablage auf dem Gerät?
2. **`workout_state`-Spalte:** mit aufnehmen (Empfehlung) oder beim Dokument-07-Format ohne diese Spalte bleiben?
3. **Soll ich direkt weiterbauen** (Recorder-Klasse + UI-Anbindung), oder erst diesen Plan freigeben?

---

*Nicht Teil dieses Dokuments: die konkreten Aufnahme-Szenarien A–G selbst (schon in Dokument 07 beschrieben) und die Firmware-Streaming-Frage (andere Session).*

# Contracts & Blueprints – FlowRep (korrigierte Version)

**Ersetzt:** `Contracts___Blueprints.txt` (vorherige KI-Sitzung)
**Verbindlichkeit:** Wie im Original – diese Definitionen sind für die ausführende KI verbindlich. Abweichungen erfordern eine neue ADR.
**Wichtiger Unterschied zum Original:** Dieses Dokument **erfindet das Wire-Protokoll nicht neu**, sondern übernimmt es unverändert aus der bestehenden, produktiv genutzten Quelle `docs/01_protocol.yaml` im echten Repository. Nur die DSP-Pipeline und die State-Machine-Korrektur sind neu.

---

## Abschnitt 1: Das BLE-Wire-Protokoll (unverändert, nur korrekt dokumentiert)

**Paketgröße:** 52 Byte pro BLE-Read/Notification (4 Samples × 12 Byte + 4 Byte Timestamp).

| Byte-Offset | Feld | Typ | Skalierung | Einheit |
|---|---|---|---|---|
| 0–3 | Timestamp | `uint32_t`, Little-Endian | – | ms seit Boot des ESP32 |
| 4–5 | Accel X (Sample 1) | `int16_t` | `× 0.001` | g |
| 6–7 | Accel Y (Sample 1) | `int16_t` | `× 0.001` | g |
| 8–9 | Accel Z (Sample 1) | `int16_t` | `× 0.001` | g |
| 10–11 | Gyro X (Sample 1) | `int16_t` | `× 0.01` | deg/s |
| 12–13 | Gyro Y (Sample 1) | `int16_t` | `× 0.01` | deg/s |
| 14–15 | Gyro Z (Sample 1) | `int16_t` | `× 0.01` | deg/s |
| 16–27 | Sample 2 | – | – | gleicher Aufbau |
| 28–39 | Sample 3 | – | – | gleicher Aufbau |
| 40–51 | Sample 4 | – | – | gleicher Aufbau |

### Korrekte Umrechnungsformeln

```
accel_g       = int16_wert * 0.001                     // Rohwert -> g
accel_m_s2    = accel_g * 9.80665                        // g -> m/s^2 (optional, falls SI-Einheiten gewuenscht)

gyro_deg_s    = int16_wert * 0.01                         // Rohwert -> deg/s  (NICHT direkt in rad/s umrechnen ohne diesen Schritt!)
gyro_rad_s    = gyro_deg_s * (PI / 180.0)                 // deg/s -> rad/s, ZWEISTUFIG
```

**Korrektur-Hinweis für die ausführende KI:** Ein früherer Entwurf dieses Dokuments enthielt die fehlerhafte Kurzformel `rad/s = int16_wert * (pi/180.0)` – das lässt den Skalierungsschritt `× 0.01` aus und ergibt Werte, die um Faktor 100 zu groß sind (rechnerisch bis zu 15.000 statt real ca. 150 Grad/Sekunde bei einer typischen Curl-Bewegung). **Immer zweistufig umrechnen: erst Rohwert → deg/s mit Faktor 0,01, dann erst bei Bedarf deg/s → rad/s.** Wenn die Ziel-Einheit ohnehin deg/s ist (wie im gesamten übrigen Projekt üblich), entfällt der zweite Schritt komplett – es besteht kein Zwang, überhaupt in rad/s umzurechnen.

Quelle der Wahrheit bleibt `docs/01_protocol.yaml` im echten Repository. Bei jeder Unklarheit gilt diese Datei, nicht dieses Dokument.

---

## Abschnitt 2: Bestehende Kern-Datenmodelle und Interfaces (nicht neu erstellen)

Die folgenden Klassen und Interfaces **existieren bereits** im echten Repository (`app/lib/domain/`, `app/lib/data/`) und sind hier nur zur Referenz aufgeführt, damit eine ausführende KI sie nicht versehentlich dupliziert:

- `SensorSample` – einzelner Messpunkt nach dem Parsen
- `ISensorProvider` – Interface für BLE- bzw. Mock-Datenquelle, mit `connect()`, `disconnect()`, `connectionStateStream`, `sensorStream`
- `BleSensorProvider`, `MockSensorProvider` – bestehende Implementierungen
- `WorkoutEngine` – bestehende State Machine (wird in Abschnitt 4 gezielt korrigiert, nicht neu geschrieben)
- `SignalProcessor` – bestehende DSP-Klasse (wird in Abschnitt 3 erweitert, nicht ersetzt)
- `IWorkoutRepository` / `DriftWorkoutRepository` – bestehende Persistenzschicht

**Regel für die ausführende KI:** Vor jeder neuen Klasse oder jedem neuen Interface zuerst im Repository suchen (`grep -rn "class NameX"` bzw. Verzeichnis-Listing von `app/lib/domain/` und `app/lib/data/`). Nur bei tatsächlichem Fehlen neu erstellen.

### Neu hinzuzufügende Datenstruktur

```dart
/// Ergaenzt SignalProcessor um einen persistenten Gravitations-Schaetzwert.
/// Wird NICHT als eigenstaendige Datenbank-Entitaet gespeichert, sondern lebt
/// nur innerhalb einer laufenden SignalProcessor-Instanz.
class GravityEstimate {
  double gY; // Gravitationskomponente auf Achse Y, in g
  double gZ; // Gravitationskomponente auf Achse Z, in g
  GravityEstimate({required this.gY, required this.gZ});
}
```

---

## Abschnitt 3: DSP-Pipeline-Bauplan – Gyro-gestützte Gravitationskompensation

Dieser Ablauf **ergänzt** die bestehende `SignalProcessor`-Klasse um eine neue Methode, er ersetzt die bestehende EMA-Filterung nicht vollständig, sondern fügt eine zusätzliche, physikalisch fundiertere Signalkomponente hinzu.

### Warum kein einfacher Tiefpass für die Gravitationsschätzung

Ein früherer Entwurf schlug vor, die Gravitation durch einen sehr langsamen Tiefpassfilter (0,2 Hz) auf den bereits gefilterten Beschleunigungsachsen zu isolieren, unter der Annahme "langsame Signalanteile = Gravitation". Das ist bei einer Rotation, die selbst mit vergleichbarer Frequenz stattfindet (ein Curl dauert typischerweise 1–3 Sekunden, das entspricht ca. 0,3–1 Hz Grundfrequenz), keine saubere Trennung. Empirische Prüfung (siehe Dokument 04) zeigt: Bei realistisch kurzen Pausen zwischen Reps (ca. 1 Sekunde) hat dieser Filter keine Zeit, sich neu einzuschwingen, und lässt in der Pause ein Residuum von rund 50 % des Bewegungs-Peaks stehen.

### Der korrigierte Ansatz: Rotationsgestütztes Gravitations-Tracking

**Kernidee:** Statt zu *schätzen*, was Gravitation ist (über Signalgeschwindigkeit), wird *gemessen*, wie stark sich der Sensor gedreht hat (Gyroskop), und der Gravitationsschätzwert wird um exakt diesen gemessenen Winkel mitgedreht. Nur wenn die Gesamtbeschleunigung nahe 9,81 m/s² liegt (also wenig dynamische Bewegung vorliegt und der Accelerometer als Referenz vertrauenswürdig ist), wird der Schätzwert zusätzlich sanft in Richtung der aktuellen Accelerometer-Messung korrigiert. Dies ist ein vereinfachter Komplementärfilter (Zwei-Achsen-Variante, da für den Bizeps-Curl die Rotation überwiegend um eine Achse – die Ellenbogenachse – erfolgt).

**Schritt 1 – Initialisierung.** Beim Start (oder nach `resetFilters()`) wird der Gravitationsschätzwert auf die Richtung des ersten Accelerometer-Messwerts gesetzt (unter der Annahme, dass die Bewegung in Ruhe beginnt):

```dart
gEstimate.gY = firstSample.accelY;
gEstimate.gZ = firstSample.accelZ;
// auf Betrag 9.81 m/s^2 normieren
final norm = sqrt(gEstimate.gY*gEstimate.gY + gEstimate.gZ*gEstimate.gZ);
if (norm > 1e-6) {
  gEstimate.gY = gEstimate.gY / norm * 9.80665;
  gEstimate.gZ = gEstimate.gZ / norm * 9.80665;
}
```

**Schritt 2 – Rotationsschritt (pro eintreffendem Sample).** Der Gravitationsschätzwert wird um den seit dem letzten Sample gemessenen Rotationswinkel gedreht (kleine Winkel zwischen aufeinanderfolgenden Samples bei ~74 Hz effektiver Rate erlauben die einfache 2D-Rotationsmatrix ohne Quaternion-Aufwand):

```dart
final dt = (currentSample.timestampMs - lastSample.timestampMs) / 1000.0;
// KORREKTUR: SensorSample hat kein gyroXRadPerS-Feld. gx liegt in Grad/Sekunde vor
// (siehe workout_engine.dart), Umrechnung erfolgt inline:
final dTheta = (currentSample.gx * pi / 180) * dt; // Rotation um die Ellenbogenachse, in rad
final c = cos(dTheta), s = sin(dTheta);
final gYPred = gEstimate.gY * c - gEstimate.gZ * s;
final gZPred = gEstimate.gY * s + gEstimate.gZ * c;
```

**Schritt 3 – Korrekturschritt (sanfte Nachführung zur Accelerometer-Referenz).**

```dart
final accelMag = sqrt(currentSample.accelY*currentSample.accelY
                     + currentSample.accelZ*currentSample.accelZ);
// weiche Vertrauensgewichtung: nahe 1 wenn accelMag nahe 9.81, sonst nahe 0
final deviation = accelMag - 9.80665;
final trust = exp(-(deviation*deviation) / (2 * 1.5 * 1.5));
const double baseAlpha = 0.02; // Basis-Korrekturrate, in Simulation validiert
final alpha = baseAlpha * trust;

double accelDirY = currentSample.accelY, accelDirZ = currentSample.accelZ;
final accelNorm = sqrt(accelDirY*accelDirY + accelDirZ*accelDirZ);
if (accelNorm > 1e-6) {
  accelDirY = accelDirY / accelNorm * 9.80665;
  accelDirZ = accelDirZ / accelNorm * 9.80665;
  gEstimate.gY = (1 - alpha) * gYPred + alpha * accelDirY;
  gEstimate.gZ = (1 - alpha) * gZPred + alpha * accelDirZ;
} else {
  gEstimate.gY = gYPred;
  gEstimate.gZ = gZPred;
}
```

**Schritt 4 – Dynamische, gravitationsfreie Beschleunigung und Magnitude.**

```dart
final linearY = currentSample.accelY - gEstimate.gY;
final linearZ = currentSample.accelZ - gEstimate.gZ;
final linearX = currentSample.accelX; // X-Achse hat in diesem Modell keine Gravitationskomponente
final dynMagnitude = sqrt(linearX*linearX + linearY*linearY + linearZ*linearZ);
```

**Wichtiger Hinweis zur Achsenwahl:** Die obige Herleitung geht vereinfachend davon aus, dass die Curl-Rotation ausschließlich um die X-Achse des Sensors erfolgt und Gravitation ausschließlich zwischen Y und Z wandert. Das ist eine Modellannahme, die von der tatsächlichen Trageposition und -orientierung des M5StickC Plus2 abhängt. **Vor der Implementierung ist anhand realer Serial-/CSV-Daten zu prüfen, welche Achse tatsächlich der Ellenbogen-Rotationsachse entspricht** (siehe Dokument 07, Datensammlung). Bei falscher Achsenzuordnung liefert dieses Verfahren keine sinnvollen Ergebnisse.

### Ausdrücklicher Validierungsvorbehalt

Die in Dokument 04 gezeigte Verbesserung (Pause/Peak-Verhältnis von ~0,50 auf ~0,14–0,23) beruht auf **synthetischen Daten mit bekannter, sauberer Rotationsachse**. Reale Daten enthalten zusätzliches Sensorrauschen, Gyro-Drift, unsaubere Rotationsachsen (Handgelenk dreht sich nicht perfekt um eine einzige Achse) und Trageschwankungen. Dieser Ansatz ist ein **deutlich besser begründeter Startpunkt** als der verworfene Tiefpass-Ansatz, aber **kein bewiesener Endzustand**. Er muss gegen real aufgezeichnete Hardware-Daten (Dokument 07) nachvalidiert werden, bevor er als abgeschlossen gilt.

---

## Abschnitt 4: State-Machine-Bauplan – Korrektur der Kalibrierungs-Persistenz

Dies ist eine gezielte Änderung an der bestehenden `WorkoutEngine`, keine Neuimplementierung.

### Aktuelles (fehlerhaftes) Verhalten

```dart
case WorkoutState.idle:
  if (combinedSignal > baselineLevel + (_peakThreshold - baselineLevel) * 0.5) {
    _state = WorkoutState.calibrating;  // <- IMMER, unabhaengig vom Kalibrierungsstatus
    ...
  }
```

### Korrigiertes Verhalten

```dart
/// Neues Feld auf Klassenebene, Default false, wird true sobald entweder
/// eine Guided Calibration abgeschlossen wurde ODER ein persistierter
/// Kalibrierungswert erfolgreich geladen wurde.
bool _hasValidCalibration = false;

case WorkoutState.idle:
  if (combinedSignal > baselineLevel + (_peakThreshold - baselineLevel) * 0.5) {
    if (_hasValidCalibration) {
      // Bereits kalibriert (Guided Calibration oder aus Persistenz geladen):
      // direkt in aktives Tracking wechseln, wie im paused-Zustand.
      _state = WorkoutState.active;
      _repsInSet.clear();
      _lastMovementAt = s.timestamp; // KORRIGIERT: _setStartedAt existiert nicht, richtig ist _lastMovementAt (siehe idle-Case-Muster im bestehenden Code)
    } else {
      // Noch nie kalibriert: alter Ein-Rep-Auto-Kalibrierungspfad greift.
      _state = WorkoutState.calibrating;
      _repsInSet.clear();
    }
    _detectPeak(s, combinedSignal);
  }
  break;
```

`_hasValidCalibration` wird an zwei Stellen auf `true` gesetzt: am Ende von `_finishGuidedCalibration()` und beim erfolgreichen Laden eines persistierten Kalibrierungswerts (`_loadCalibration()` in `home_screen.dart`, dort beim Erstellen der `WorkoutEngine` als Konstruktor-Flag übergeben).

### Verpflichtender Regressionstest

Sowohl in `app/test/workout_engine_test.dart` als auch in der erweiterten Python-Simulation (Dokument 04, ADR-022) muss folgender Testfall existieren: Guided Calibration mit 10 Reps abschließen, `_peakThreshold` notieren, einen weiteren Rep simulieren, prüfen, dass `_peakThreshold` unverändert geblieben ist.

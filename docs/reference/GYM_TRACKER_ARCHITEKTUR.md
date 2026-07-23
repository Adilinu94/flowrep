# Architekturdokumentation: Gym Tracker (Offline-First IMU-basiertes Wiederholungszählen)

**Version:** 2.0 — Konsolidiert
**Ersetzt:** `kompletter_bauplan.md` / `.odt` und `bauplan_projektgym.md`
**Stand:** Juli 2026

---

## 0. Über dieses Dokument

Die beiden ursprünglichen Planungsdokumente widersprachen sich in zentralen technischen Punkten (BLE-Byte-Protokoll, BLE-Package-Wahl, Referenzpfade). Dieses Dokument ist die **einzige verbindliche Quelle** ab sofort. Es löst folgende Konflikte auf und trifft folgende Entscheidungen:

| Konflikt in den Ursprungsdokumenten | Entscheidung in diesem Dokument | Begründung |
|---|---|---|
| 30 Byte/5 Samples (bauplan_projektgym) vs. 52 Byte/4 Samples (kompletter_bauplan) | **52 Byte/4 Samples, inkl. Gyroskop + Timestamp** | Forschung zu IMU-Wiederholungszählung zeigt durchgehend, dass Gyroskopdaten Segmentierung und Klassifikation verbessern; Timestamp ist für Jitter-Kompensation nötig |
| `flutter_blue_plus` vs. `flutter_reactive_ble` | **`flutter_blue_plus`** | Aktuelle Vergleichsquellen (2026) attestieren stärkere Community-Adoption und aktivere Wartung; deckt sich mit der ursprünglichen Wahl in bauplan_projektgym.md |
| `/docs/blueprints/` vs. `/docs/protocols/` | **`/docs/protocol/`** | Einheitlicher, eindeutiger Pfad |
| Keine explizite MVP-Grenze | **Abschnitt 2 dieses Dokuments** | Verhindert Scope Creep |
| Isar als Datenbank ohne Rückfallebene | **Finale Entscheidung: Drift statt Isar** (siehe ADR-006) | Isar-Kernentwicklung gilt 2026 als weitgehend eingestellt; Entscheidung an Claude delegiert und vor Phase 1 getroffen |
| M5StickC Plus2 ohne Hardware-Absicherung | **BLE-Vertrag als Abstraktionsgrenze, Migrationspfad zu M5StickS3 dokumentiert** | M5StickC Plus2 ist laut Hersteller End-of-Life |
| Fixer globaler Schwellenwert in der Workout Engine | **Adaptiver, pro Übung kalibrierter Schwellenwert** | Studienlage zeigt: pro-Übung-kalibrierte Amplituden-Schwellenwerte schlagen komplexere Verfahren (DTW, generische neuronale Netze) in publizierten Vergleichen |
| Nutzertest erst in Woche 7–8 | **Informeller Test bereits nach Meilenstein 1 (Abschnitt 6)** | Riskanteste Produktannahme muss früh validiert werden |

Alle folgenden Abschnitte bauen auf diesen Entscheidungen auf.

---

## 1. Architektur-Überblick

Das System besteht aus drei strikt getrennten Komponenten:

```
┌─────────────────┐      BLE-GATT       ┌──────────────────┐      Events      ┌──────────────────┐
│    Firmware      │ ───(52-Byte-Batch)──▶│   BleSensorProvider│ ────────────────▶│  Workout Engine   │
│  (C++/PlatformIO) │                     │  (Data Layer)      │                  │  (Domain Layer)   │
│  M5StickC Plus2   │◀──(Control Point)───│  flutter_blue_plus │                  │  State Machine    │
└─────────────────┘                      └──────────────────┘                  └────────┬─────────┘
                                                                                          │
                                                                                          ▼
                                          ┌──────────────────┐                 ┌──────────────────┐
                                          │   UI (Presentation)│◀───────────────│ IWorkoutRepository │
                                          │   Flutter Widgets   │                │  (Drift, final)    │
                                          └──────────────────┘                 └──────────────────┘
```

### 1.1 Kernprinzipien (erweitert gegenüber den Ursprungsdokumenten)

1. **Firmware bleibt dumm.** Keine Zähllogik auf dem Gerät. Grund: App-Updates sind trivial, OTA-Firmware-Updates sind fehleranfällig.
2. **Offline-First & Privacy-by-Design.** Rohdaten verlassen das Gerät standardmäßig nicht. Cloud-Sync ist opt-in und kommt erst in Phase 5.
3. **Hardware-Agnostizismus (NEU).** Die App kennt nur den BLE-GATT-Vertrag aus Abschnitt 3 — nicht das konkrete Board. Damit ein Wechsel auf M5StickS3 (Nachfolger des EOL-gesetzten M5StickC Plus2) später nur eine Firmware-, keine App-Änderung ist.
4. **Datenbank-Agnostizismus (NEU).** Der Domain-Layer kennt nur `IWorkoutRepository`, nie die konkrete DB-Technologie direkt. Finale Wahl: **Drift** (siehe ADR-006), aktiv gepflegt und sqlite3-basiert. Die Abstraktion bleibt dennoch bestehen, falls sich der Wartungsstatus je wieder ändert.
5. **Web-First Testing.** `MockSensorProvider` erlaubt Entwicklung ohne Hardware.
6. **Iterative KI-Kooperation.** Jede Phase wird einzeln umgesetzt, mit Erklärung und Test-Ziel.

---

## 2. MVP-Abgrenzung & Produktvision

### 2.1 Der Magic Moment — und seine technische Bedingung

Der Magic Moment ist die automatische, klicklose "1" beim ersten Satz. **Wichtig:** Ein rein schwellenwertbasiertes System braucht eine Referenz für die individuelle Bewegungsamplitude. Um den Magic Moment nicht durch einen separaten "Kalibrierungssatz" zu verzögern, gilt:

> **Der erste echte Satz IST die Kalibrierung.** Es gibt keinen separaten, leeren Kalibrierungssatz. Die App zeigt ab der ersten erkannten Wiederholung eine Zahl an — im Hintergrund verfeinert sich der Schwellenwert mit jeder weiteren Wiederholung (siehe Abschnitt 5.3).

### 2.2 Error-State-Philosophie (revidiert)

Manuelle Korrektur ist **kein Übergangs-Feature bis die Engine perfekt ist** — publizierte Bestwerte für IMU-basiertes Wiederholungszählen liegen je nach Verfahren zwischen ca. 61 % und 99,4 %, nie bei 100 %. Korrektur ist ein dauerhafter, erwarteter Teil des Produkts.

**Nutzer-Messaging (V1):** *"Danke, das hilft uns die Erkennung zu verbessern."*
**Nicht verwenden in V1:** *"Die KI lernt dazu"* — in V1 läuft keine ML-Komponente, die live nachlernt. Diese Formulierung erst ab Phase 5 (echtes Modelltraining) freischalten, sonst entsteht ein Vertrauensproblem, wenn sich nichts sichtbar verbessert.

### 2.3 V1-Scope (launchbares MVP)

- Firmware-Streaming über kanonisches Protokoll (Abschnitt 3)
- `BleSensorProvider` (Mock + echt) mit `flutter_blue_plus`
- Workout Engine mit adaptivem, pro-Übung-kalibriertem Schwellenwert
- Lokale Persistenz (`IWorkoutRepository`, Drift-Implementierung)
- History-Screen, Pausen-Timer mit Wake-on-Motion
- Manuelle Korrektur-UI + `CorrectionEvent`-Speicherung (ohne ML-Versprechen)

### 2.4 Explizit auf V2+ verschoben

- Dataset Builder / Parquet-Export
- Cloud-Sync (Supabase)
- On-Device ML (alle 5 Stufen)
- Formqualitäts-Erkennung (gute vs. schlechte Ausführung)

---

## 3. Kanonisches BLE-Kommunikationsprotokoll

### 3.1 GATT-Service "GymTracker"

| Characteristic | UUID-Rolle | Eigenschaft | Zweck |
|---|---|---|---|
| Battery Level | Standard 0x2A19 oder custom | Read/Notify | Akkustand (Prozent) |
| Sensor Data | Custom | Notify | IMU-Batch-Stream (siehe 3.2) |
| Control Point | Custom | Write | Steuerbefehle (siehe 3.3) |
| Device Status | Custom | Read/Notify | Verbindungs-/Streaming-Zustand |

### 3.2 Sensor-Data-Payload (VERBINDLICH — 52 Byte)

Batch von 4 Samples, Little-Endian:

| Feld | Typ | Bytes | Offset |
|---|---|---|---|
| Timestamp | uint32 | 4 | 0 |
| Sample 1: Accel X,Y,Z | int16 × 3 | 6 | 4 |
| Sample 1: Gyro X,Y,Z | int16 × 3 | 6 | 10 |
| Sample 2: Accel + Gyro | int16 × 6 | 12 | 16 |
| Sample 3: Accel + Gyro | int16 × 6 | 12 | 28 |
| Sample 4: Accel + Gyro | int16 × 6 | 12 | 40 |
| **Gesamt** | | **52** | |

**Skalierung:** Accel in `mg` (1000 = 1g), Gyro in `0.01°/s` — beide als int16, um Float-Encoding zu vermeiden.

**Wichtiger technischer Hinweis:** Der Standard-ATT-MTU von BLE beträgt 23 Byte (20 Byte Nutzlast). Für 52-Byte-Notifications **muss** das MTU beim Verbindungsaufbau auf mindestens 55 Byte verhandelt werden (`requestMtu` auf Android, automatisch auf iOS). Ohne diese Verhandlung schlägt die Notification fehl oder wird fragmentiert — dies explizit in Phase 0 testen, nicht erst in Phase 3 entdecken.

```cpp
// Firmware: Struct-Packing (main.cpp)
#pragma pack(push, 1)
struct SensorSample {
  int16_t ax, ay, az;
  int16_t gx, gy, gz;
};
struct SensorBatch {
  uint32_t timestamp;
  SensorSample samples[4];
}; // sizeof == 52
#pragma pack(pop)
```

```dart
// App: BleSensorProvider — Parsing
SensorBatch parseBatch(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final timestamp = data.getUint32(0, Endian.little);
  final samples = <SensorSample>[];
  for (int i = 0; i < 4; i++) {
    final offset = 4 + i * 12;
    samples.add(SensorSample(
      ax: data.getInt16(offset, Endian.little) / 1000.0,
      ay: data.getInt16(offset + 2, Endian.little) / 1000.0,
      az: data.getInt16(offset + 4, Endian.little) / 1000.0,
      gx: data.getInt16(offset + 6, Endian.little) / 100.0,
      gy: data.getInt16(offset + 8, Endian.little) / 100.0,
      gz: data.getInt16(offset + 10, Endian.little) / 100.0,
    ));
  }
  return SensorBatch(timestamp: timestamp, samples: samples);
}
```

### 3.3 Control-Point-Befehle

| Byte-Wert | Befehl | Wirkung |
|---|---|---|
| `0x01` | START_STREAM | Firmware aktiviert IMU, beginnt 50-Hz-Sampling |
| `0x02` | STOP_STREAM | Firmware reduziert Sampling, geht Richtung Wake-on-Motion (siehe 4.3 / Phase 2) |
| `0x03` | REQUEST_BATTERY | Einmalige Akkustand-Abfrage |

### 3.4 BLE-Package-Entscheidung

**`flutter_blue_plus`** ist der verbindliche Standard. `flutter_reactive_ble` bleibt eine valide Alternative (gepflegt vom ehemaligen Philips-Hue-Team), wird aber nicht parallel verwendet, um die im ersten Analyse-Durchgang gefundene Inkonsistenz nicht zu wiederholen.

---

## 4. Risiko-Register & Architektur-Absicherungen

| # | Risiko | Auswirkung | Mitigation | Wo umgesetzt |
|---|---|---|---|---|
| 1 | M5StickC Plus2 laut Hersteller End-of-Life | Beschaffungsproblem, erzwungener Wechsel | BLE-Vertrag als Abstraktionsgrenze; vor Serienbeschaffung Verfügbarkeit prüfen bzw. M5StickS3 direkt evaluieren | Phase 0 |
| 2 | Isar-Kernentwicklung 2026 weitgehend eingestellt | Langfristiges Wartungsrisiko für gesamte Persistenzschicht | **Gelöst:** finale Wahl Drift statt Isar (ADR-006) | Phase 1 |
| 3 | Zielkonflikt: Pausenerkennung vs. Akkulaufzeit (200 mAh) | Gerät hält keine volle Session durch | Wake-on-Motion: Firmware geht in Light Sleep, IMU-Interrupt weckt bei Bewegung über Schwellenwert; kein Dauer-Streaming in der Pause | Phase 2 |
| 4 | Kernhypothese (Regelbasiertes Zählen) ungetestet mit echten Nutzern | Späte Entdeckung, dass Zählung unzuverlässig ist | Informeller Test mit 3–5 Personen nach Meilenstein 1, nicht erst Woche 7–8 | Phase 3 / Abschnitt 6 |
| 5 | Fixer, nicht pro Übung kalibrierter Schwellenwert | Schlechtere Genauigkeit als technisch möglich | Adaptiver, pro-Übung-Schwellenwert (Envelope-Following) | Phase 1 |
| 6 | Zwei sich widersprechende Planungsdokumente im Umlauf | Implementierungsfehler durch falsche Referenz | Dieses Dokument ist ab sofort einzige Quelle; alte Dokumente archivieren, nicht mehr als Referenz verwenden | Sofort |

---

## PHASE 0 — Prototyp: Hardware-Fundament & Web-Mocking

**Ziel:** Firmware sendet das kanonische 52-Byte-Protokoll; die App läuft parallel im Browser mit Mock-Daten.

### 5.0.1 Repo-Struktur (verbindlich)

```
/gym_tracker
  /app                    # Flutter-App
    /lib
      /domain              # Entities, Repository-Interfaces, Workout Engine
      /data                # BleSensorProvider, MockSensorProvider, Drift-Implementierung
      /presentation         # Widgets, Screens
  /firmware               # PlatformIO-Projekt (M5StickC Plus2)
  /docs
    /protocol              # Dieses Dokument + BLE-Protokoll-Referenz (ggf. als .proto/.yaml)
    /decisions              # Architecture Decision Records
```

### 5.0.2 Aufgaben

1. PlatformIO-Projekt für M5StickC Plus2 aufsetzen (`platformio.ini` mit M5StickCPlus2-Bibliothek).
2. `src/main.cpp`: Display zeigt "Gym Tracker Bereit"; BLE-Server "GymTracker" mit Battery-Service (zunächst Fake-Wert).
3. Flutter-App-Grundstruktur mit Clean-Architecture-Ordnern anlegen.
4. `flutter_blue_plus` integrieren.
5. UI: Status-Text ("Getrennt") + Button ("Gerät verbinden").
6. `MockSensorProvider`: Klick auf Button → nach 2 Sekunden "Verbunden (Mock)".
7. Echte BLE-Verbindung (Android): Berechtigungen in `AndroidManifest.xml` (BLUETOOTH_SCAN, BLUETOOTH_CONNECT, ggf. ACCESS_FINE_LOCATION je nach Android-Version), Scan nach "GymTracker", Akku-Service auslesen.
8. Firmware erweitern: IMU auslesen (Accel+Gyro), gemäß Abschnitt 3.2 in 52-Byte-Batches packen, per Notification senden. **MTU-Verhandlung auf mind. 55 Byte nicht vergessen.**
9. `BleSensorProvider`: Notification abonnieren, Bytes gemäß 3.2 parsen.
10. UI: X/Y/Z-Werte live anzeigen (Mock im Web, echt auf Android).

### 5.0.3 Test-Ziel (User Action)

- App startet in Chrome, Button klickbar, Mock-Verbindung funktioniert.
- Firmware geflasht, Display zeigt Text, Handy findet Gerät.
- Akkustand wird auf echtem Handy angezeigt.
- Stick bewegen → Zahlen in der App ändern sich in Echtzeit, ohne Paketverlust (Log prüfen: kommen 50 Samples/Sekunde an?).

---

## PHASE 1 — Kernentwicklung: App-Architektur, Workout Engine, Datenmodell

### 5.1.1 Clean-Architecture-Schichten

- **Domain:** `WorkoutSession`, `ExerciseSet`, `Rep`, `CorrectionEvent` (reine Dart-Klassen, keine Framework-Abhängigkeit), `IWorkoutRepository` (abstrakt), `WorkoutEngine`.
- **Data:** `BleSensorProvider`, `MockSensorProvider`, `DriftWorkoutRepository` (implementiert `IWorkoutRepository`).
- **Presentation:** Screens, Widgets, State-Management.

```dart
// Domain: Abstraktion, damit die konkrete DB-Technologie austauschbar bleibt
abstract class IWorkoutRepository {
  Future<void> saveSession(WorkoutSession session);
  Future<List<WorkoutSession>> getHistory();
  Future<void> saveCorrection(CorrectionEvent event);
}

// Data: Konkrete Drift-Implementierung — einzige Stelle, die Drift kennt (finale Wahl, ADR-006)
class DriftWorkoutRepository implements IWorkoutRepository {
  final AppDatabase _db; // generierte Drift-Datenbankklasse
  DriftWorkoutRepository(this._db);
  // ... Implementierung
}
```

Sollte ein Wechsel zu Drift nötig werden, entsteht ausschließlich eine neue `DriftWorkoutRepository`-Klasse — der Rest der App bleibt unverändert.

### 5.1.2 Workout Engine — überarbeitete Zähllogik

Gegenüber der Ursprungsversion (fixer globaler Schwellenwert, nur Beschleunigung) werden zwei Verbesserungen eingearbeitet, die sich aus vergleichbarer Forschung zu IMU-basiertem Wiederholungszählen ableiten: **adaptive, pro Übung kalibrierte Schwellenwerte** statt eines einzigen fixen Werts, sowie die **Einbeziehung der Gyroskopdaten** zur robusteren Bewegungserkennung.

```dart
enum WorkoutState { idle, calibrating, active, paused }

class ExerciseThreshold {
  double peakThreshold;
  double envelopeDecayRate; // z.B. 0.95 — wie schnell sinkt die Referenz nach einem Peak

  static ExerciseThreshold defaultValue() =>
      ExerciseThreshold(peakThreshold: 1.3, envelopeDecayRate: 0.95); // g, konservativer Startwert
}

class WorkoutEngine {
  WorkoutState state = WorkoutState.idle;
  final ExerciseThreshold threshold = ExerciseThreshold.defaultValue();
  double _runningEnvelope = 0.0;
  int _repsInCurrentSet = 0;
  DateTime? _lastMovementAt;

  void processSample(SensorSample s) {
    final accelMagnitude = sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az);
    final gyroMagnitude = sqrt(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz);
    final combinedSignal = accelMagnitude + (gyroMagnitude * gyroWeight);

    // Envelope-Following: Referenzwert passt sich laufend an
    _runningEnvelope = max(combinedSignal, _runningEnvelope * threshold.envelopeDecayRate);

    switch (state) {
      case WorkoutState.idle:
        if (combinedSignal > threshold.peakThreshold * 0.5) {
          // WICHTIG: Das ist bereits der erste Satz — keine separate Kalibrierung.
          state = WorkoutState.calibrating;
          _lastMovementAt = DateTime.now();
        }
        break;

      case WorkoutState.calibrating:
        // Erste 2-3 Wiederholungen zählen normal UND verfeinern gleichzeitig den Schwellenwert
        _detectPeak(combinedSignal);
        if (_repsInCurrentSet >= 3) {
          threshold.peakThreshold = _runningEnvelope * 0.6; // aus beobachteten Peaks kalibriert
          state = WorkoutState.active;
        }
        break;

      case WorkoutState.active:
        _detectPeak(combinedSignal);
        if (DateTime.now().difference(_lastMovementAt!) > Duration(seconds: 4)) {
          state = WorkoutState.paused; // Satz-Ende, siehe Phase 2 für Wake-on-Motion
        }
        break;

      case WorkoutState.paused:
        if (combinedSignal > threshold.peakThreshold * 0.5) {
          state = WorkoutState.active; // nächster Satz beginnt automatisch
        }
        break;
    }
  }

  void _detectPeak(double signal) {
    if (signal > threshold.peakThreshold) {
      _lastMovementAt = DateTime.now();
      // Peak-Erkennung mit Rückflanke — Rep zählt beim Abfallen unter Schwelle nach Überschreiten
      _repsInCurrentSet++;
    }
  }
}
```

**Hinweis zu Erwartungen:** Publizierte Bestwerte für pro-Übung-kalibrierte Amplituden-Schwellenwerte liegen im hohen 90-%-Bereich, generalisierte (nicht individuell kalibrierte) Systeme typischerweise um 90–93 % (±1 Wiederholung). Das ist die realistische Zielmarke für die interne QA — nicht 100 %.

### 5.1.3 Datenmodell

```dart
class WorkoutSession { final DateTime start; final List<ExerciseSet> sets; }
class ExerciseSet { final String exerciseId; final int countedReps; final DateTime end; }
class Rep { final DateTime timestamp; final double peakMagnitude; }
class CorrectionEvent {
  final String setId;
  final int systemCount;
  final int userCorrectedCount;
  final DateTime timestamp;
  // Wird für spätere ML-Stufen als gelabeltes Trainingssignal verwendet (Phase 5)
}
```

### 5.1.4 Korrektur-UI

- Nach Satz-Ende: "+ / −"-Buttons zur Korrektur.
- Bei Korrektur: `CorrectionEvent` speichern, Nachricht gemäß Abschnitt 2.2 anzeigen.

### 5.1.5 Test-Ziel (User Action)

- Im Web (Mock): simulierte Wiederholung erhöht Zähler.
- Auf dem Handy: 10 Bizeps-Curls mit dem Stick → App zählt 1 bis 10, erster Satz erscheint automatisch ohne separate Kalibrierung.
- Absichtlich falsch zählen lassen, korrigieren, prüfen ob `CorrectionEvent` in der DB landet.

---

## PHASE 2 — Erweiterung: Persistenz, UX-Politur, Pausenmanagement

### 5.2.1 Aufgaben

1. History-Screen: Liste vergangener `WorkoutSession`s aus `IWorkoutRepository`.
2. Pausen-Timer: 90 Sekunden Countdown nach Satz-Ende.
3. **Wake-on-Motion (löst Risiko #3):** Nach 60 Sekunden Pause ohne Bewegung geht die Firmware in Light Sleep; ein IMU-Interrupt (Hardware-Interrupt bei Überschreiten eines groben Bewegungsschwellenwerts) weckt den Chip, statt durchgehend mit kurzem Connection Interval zu senden. Erst nach dem Aufwecken wird kurzzeitig auf volle Sample-Rate hochgeschaltet, um zu bestätigen, dass ein neuer Satz beginnt.
4. "Glanceability": große Fonts, klare Farben für die Rep-Anzeige.

### 5.2.2 User Journey (State-Flow)

```
App öffnen
   │
   ▼
BLE-Status prüfen ──(nicht verbunden)──▶ Verbindungsaufbau (max. 3 Taps bis zum ersten Satz)
   │ (verbunden)
   ▼
Warten auf Bewegung ("idle")
   │ (Bewegung über halbem Schwellenwert)
   ▼
Erster Satz = Kalibrierung ("calibrating") ──▶ Große Zahl erscheint ab Rep 1 (Magic Moment)
   │ (3+ Reps erkannt)
   ▼
Aktiver Satz ("active") ──(4s keine Bewegung)──▶ Pause ("paused", Wake-on-Motion aktiv)
   │                                                    │ (Bewegung erkannt)
   │                                                    ▼
   │◀───────────────────────────────────────── Nächster Satz automatisch
   ▼ (Nutzer beendet Session manuell)
Session-Ende → Speichern in IWorkoutRepository → History-Screen
```

Jeder Übergang in diesem Flow entspricht einem `WorkoutState` aus Abschnitt 5.1.2 — die UI reagiert rein auf Zustandsänderungen der Engine, enthält selbst keine eigene Ablauflogik.

### 5.2.3 Sicherheit & Datenschutz (Vertiefung)

- **BLE-Pairing:** "Just Works"-Bonding für V1, da der M5StickC Plus2 keine PIN-Anzeige besitzt. BLE Security Mode 1/Level 2 (verschlüsselter Link ohne Authentifizierung durch Anzeige) als Minimum aktivieren.
- **Lokale Verschlüsselung:** Drift unterstützt Verschlüsselung über SQLCipher (`sqlcipher_flutter_libs`) — für alle Nutzerdaten standardmäßig aktivieren, nicht als optionale Einstellung.
- **DSGVO-Löschrecht technisch verankern:** `IWorkoutRepository` erhält von Anfang an eine Methode `Future<void> deleteAllUserData()`, die konsistent alle lokalen (und später Cloud-)Daten löscht. Das nachträglich in Phase 5 einzubauen ist deutlich teurer, als es von Anfang an im Interface zu verankern.
- **Datenminimierung:** Rohdaten-Blobs (Phase 5, Dataset Builder) nur bei aktivem Opt-in speichern — nicht als Standardverhalten mit Opt-out.

### 5.2.4 Performance & Robustheit (BLE)

- **Reconnection-Strategie:** Bei Verbindungsabbruch exponentielles Backoff (1 s, 2 s, 4 s, 8 s, max. 16 s) statt permanenter Reconnect-Versuche — schont Akku und CPU.
- **Kurzzeit-Pufferung:** Verbindungsabbrüche unter 2 Sekunden sollten keine Wiederholung verschlucken. Die Firmware puffert die letzten Batches lokal und sendet sie nach Reconnect nach.
- **Diagnose-Logging:** Paketverlustrate lokal protokollieren (nicht cloud), um bei Nutzerbeschwerden über falsches Zählen unterscheiden zu können, ob die Ursache in der Engine-Logik oder in BLE-Paketverlust liegt.

### 5.2.5 Test-Ziel (User Action)

- Workout durchführen, Pause läuft automatisch ab, App schließen/öffnen → Historie sichtbar.
- Akkustand vor/nach einer vollständigen Trainingseinheit (Realwert) protokollieren, um Wake-on-Motion-Wirkung zu verifizieren.
- Bluetooth am Handy kurz deaktivieren/aktivieren während eines aktiven Satzes → prüfen, ob Reconnect ohne Datenverlust funktioniert.

---

## PHASE 3 — Teststrategie

### 5.3.1 Testarten

| Ebene | Was wird getestet | Womit |
|---|---|---|
| Unit | Workout-Engine-Logik (Peak-Detection, State-Transitions) | Dart-Unit-Tests, isoliert von BLE |
| Unit (mit externen Referenzdaten) | Zählgenauigkeit gegen bekannte Bewegungsmuster | Sofern zugänglich: öffentliche IMU-Übungsdatensätze zur Offline-Validierung, bevor eigene Daten in ausreichendem Umfang vorliegen |
| Integration | BleSensorProvider ↔ Workout Engine ↔ Repository | Mock-BLE-Layer |
| HIL (Hardware-in-the-Loop) | Echtes Timing, echter Akkuverbrauch, echte BLE-Stabilität | Echter M5StickC Plus2 + echtes Handy |
| Nutzertest (früh, informell) | Vertraut der Nutzer der automatischen Zählung? | 3–5 unterschiedliche Personen, unterschiedliche Übungen, **direkt nach Meilenstein 1** |
| Security/Privacy | Verschlüsselung, DSGVO-Löschanfragen | Manuelle Checkliste |

### 5.3.2 Warum der frühe Nutzertest wichtig ist

Die riskanteste Annahme des gesamten Projekts ist, ob regelbasiertes Zählen für echte, unterschiedliche Nutzer und Übungen vertrauenswürdig funktioniert. Ein Test erst in Woche 7–8 (nach Datenbank- und UX-Arbeit) würde diese Erkenntnis zu spät liefern. Der informelle Test nach Meilenstein 1 kostet wenig Zeit, verhindert aber, dass auf einem wackligen Fundament weitergebaut wird.

### 5.3.3 Test-Ziel (User Action)

- Testprotokoll für 3–5 Personen erstellen (unterschiedliche Übungen, Tempo, Körpergröße).
- Korrekturrate dokumentieren — Zielkorridor grob 90–95 % korrekt (siehe Abschnitt 5.1.2), nicht 100 %.

---

## PHASE 4 — Release & Deployment

### 5.4.1 Aufgaben

1. CI-Grundgerüst (Build + Unit-Tests bei jedem Commit).
2. Play-Store-Vorbereitung: Berechtigungs-Disclosure für Bluetooth/Standort in der Store-Beschreibung, da Google dies bei BLE-Apps explizit verlangt.
3. Opt-in-Crash-Reporting (offline-freundlich zwischenspeichern, erst bei Verbindung senden, keine Rohdaten ohne Zustimmung).
4. Gestaffelter Rollout (interner Test → kleine Nutzergruppe → volle Freigabe).

### 5.4.2 Test-Ziel (User Action)

- Signierten Release-Build installieren, vollständigen Workout-Flow ohne Debug-Tools durchspielen.

---

## PHASE 5 — Später (V2+): Dataset Builder, Cloud Sync, On-Device ML

*Explizit nicht Teil des MVP. Erst nach validiertem V1 angehen.*

### 5.5.1 Dataset Builder

- Rohdaten-Blobs zusätzlich zu aggregierten Sätzen speichern.
- Export als Parquet-Datei, inkl. `CorrectionEvent`-Labels.

### 5.5.2 Cloud Sync

- Supabase mit Row-Level-Security, Last-Write-Wins-Sync.

**Beispielhaftes Schema:**

| Tabelle | Wichtige Spalten | RLS-Grundprinzip |
|---|---|---|
| `workout_sessions` | `id`, `user_id`, `started_at`, `ended_at` | Nutzer sieht nur Zeilen mit `user_id = auth.uid()` |
| `exercise_sets` | `id`, `session_id`, `exercise_id`, `counted_reps`, `corrected_reps` | Join-Zugriff über `session_id` auf eigene Sessions beschränkt |
| `correction_events` | `id`, `set_id`, `system_count`, `user_count`, `created_at` | Wie oben; dient später als ML-Trainingsdatenquelle |

```sql
-- Beispiel RLS-Policy
create policy "Nutzer sehen nur eigene Sessions"
  on workout_sessions for select
  using (auth.uid() = user_id);
```

Sync-Konflikte (z. B. Workout auf zwei Geräten offline erfasst) werden nach Last-Write-Wins anhand `ended_at` aufgelöst — für den Anwendungsfall ausreichend, da Trainingsdaten selten gleichzeitig auf zwei Geräten bearbeitet werden.

### 5.5.3 ML-Roadmap (5 Stufen, unverändert in der Grundidee)

1. Regelbasiert (= V1, oben beschrieben)
2. Klassisches ML (Feature-Extraktion + Klassifikation)
3. Sequenzmodelle (personalisiert)
4. Transfer Learning zwischen Nutzern
5. Anomalie-Erkennung (Autoencoder) für Formqualität

**Hinweis:** Für Stufe 2 muss nicht zwingend auf ausreichend eigene `CorrectionEvent`-Daten gewartet werden — es existieren öffentlich zugängliche IMU-Übungsdatensätze (Beschleunigung + Gyroskop, armgetragener Sensor, hunderte Testpersonen), die sich zur Vorab-Validierung und zum Bootstrapping der Feature-Pipeline eignen, bevor genug eigene Daten vorliegen. Details dazu bei Bedarf gesondert ausführen.

---

## 6. Meilenstein-Zeitplan (überarbeitet)

| Woche | Meilenstein | Fokus | Validierungs-Checkpoint |
|---|---|---|---|
| 1–2 | M1 | Phase 0 vollständig (Firmware + Mock + echte BLE-Verbindung) | Protokoll läuft stabil, MTU-Verhandlung funktioniert |
| 3–4 | M2 | Phase 1 (Workout Engine + Datenmodell) | **Informeller Nutzertest mit 3–5 Personen** |
| 5–6 | M3 | Phase 2 (Persistenz, UX, Wake-on-Motion) | Akkulaufzeit über volle Session gemessen |
| 7–8 | M4 | Phase 3 (Testpyramide) + Phase 4 (Release-Vorbereitung) | Testprotokoll abgeschlossen, Store-Freigabe vorbereitet |
| 9+ | M5 | Soft Launch, danach Phase 5 (V2+) nach Bedarf | Reale Korrekturrate aus Produktivnutzung auswerten |

---

## 7. Anhang: Offene Entscheidungen für den Menschen im Loop

Diese Punkte sollten bewusst von dir (nicht von der KI) entschieden werden, bevor Code in Serie geht:

1. **Hardware-Beschaffung:** Ist der M5StickC Plus2 noch in ausreichender Stückzahl verfügbar, oder direkt mit M5StickS3 starten?
2. ~~**DB-Finalentscheidung:** Bei Isar bleiben oder direkt mit Drift starten?~~ **Gelöst:** Drift (siehe ADR-006, `00_ENTSCHEIDUNGEN_ERFORDERLICH.md` Abschnitt C).
3. **Freigabe der überarbeiteten Workout-Engine-Logik** (Abschnitt 5.1.2) vor Implementierung durch Claude Code.
4. **Umfang des V1-Datenschutz-Textes** für den Store-Eintrag (juristische Prüfung empfohlen, nicht KI-generiert).

---

## 8. Anhang: Coding-Standards & Dokumentationspraxis

Damit über mehrere KI-unterstützte Sessions hinweg Konsistenz erhalten bleibt:

- **Commit-Konvention:** `[Phase X] Kurzbeschreibung` (z. B. `[Phase 1] Adaptive Threshold-Logik implementiert`).
- **Architecture Decision Records:** Jede Abweichung von diesem Dokument wird als kurze Datei unter `/docs/decisions/ADR-XXX.md` festgehalten (Kontext, Entscheidung, Konsequenz — 10 Zeilen reichen).
- **Namenskonvention:** Domain-Klassen auf Englisch (`WorkoutSession`, nicht `Trainingseinheit`), UI-Texte auf Deutsch.
- **Bei jeder neuen Claude-Code-Session:** Zuerst dieses Dokument vollständig einlesen lassen, dann erst die Phase benennen, an der weitergearbeitet werden soll — nie nur einen Ausschnitt geben, um erneute Drift zwischen mehreren Planungsständen zu vermeiden.

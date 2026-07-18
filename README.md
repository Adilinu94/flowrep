# FlowRep

BLE/IMU-basiertes automatisches Wiederholungszählen für Krafttraining.
M5StickC Plus2 (Firmware) + Flutter-App.

> **Hinweis (2026-07-16/17):** Die Tabelle direkt unten ist eine Momentaufnahme
> von vor der Hardware-Ankunft und mittlerweile in mehreren Punkten überholt
> (u. a. `app/test/` läuft inzwischen real, 15/15 grün; `firmware/` kompiliert
> real via `pio run`; `android/` existiert inzwischen im Repo) - Details siehe
> Änderungsprotokoll in `docs/Umbauplan Flowrep/STATUS_FORTSCHRITT.md`. Dieses
> README als historischen Ausgangspunkt lesen, nicht als aktuellen Stand; für
> den aktuellen Stand ist `docs/Umbauplan Flowrep/STATUS_FORTSCHRITT.md` die
> lebendige Quelle.

## Aktueller Stand (siehe Commit-Historie für Details)

Dieser Stand wurde in Claude.ai geschrieben, **bevor die M5StickC-Plus2-Hardware
physisch verfügbar war**. Entsprechend gilt für jede Datei einzeln:

| Bereich | Status |
|---|---|
| `docs/` | Vollständig, reflektiert alle bisherigen Architektur-Entscheidungen |
| `app/lib/domain/` | Geschrieben, **keine Hardware nötig zum Prüfen** — reiner Dart-Code |
| `app/lib/data/protocol/` | Geschrieben, **keine Hardware nötig** — reine Byte-Logik |
| `app/lib/data/providers/sensor_provider.dart` (Mock) | Geschrieben, **direkt in Chrome testbar** |
| `app/lib/data/providers/ble_sensor_provider.dart` (echtes BLE) | Geschrieben, **NICHT hardware-getestet** — UUIDs sind Platzhalter, siehe Datei |
| `app/lib/data/repositories/drift_database.dart` | Geschrieben, **`build_runner` wurde nie ausgeführt** — die generierte `drift_database.g.dart` fehlt noch |
| `app/test/` | Geschrieben, **nie ausgeführt** — dieses Sandbox-Environment hatte kein Dart-SDK |
| `firmware/` | Geschrieben, **nie kompiliert** — kein ESP32-Toolchain in dieser Sandbox verfügbar |

## Erste Schritte, sobald ein echtes Dart/Flutter-Environment verfügbar ist

**Wichtig, zuerst:** Dieses Repo enthält nur `lib/`, `test/` und `pubspec.yaml` -
die plattformspezifischen Ordner (`android/`, `ios/`, `web/` usw.) wurden nie
generiert, weil `flutter create` ein echtes Flutter-SDK braucht, das in dieser
Sandbox nicht verfügbar war. Das ist der buchstäblich erste Befehl:

```bash
cd app
flutter create . --project-name flowrep --org com.flowrep --platforms android,web
flutter pub get
dart run build_runner build   # generiert drift_database.g.dart
flutter analyze               # erster echter Syntax-Check dieses gesamten Codes
flutter test                  # führt test/*.dart tatsächlich aus
flutter run -d chrome         # Mock-Modus, keine Hardware nötig
```

**Vorsicht:** `flutter create .` fragt je nach Flutter-Version möglicherweise
nach, ob bestehende Dateien überschrieben werden sollen (z. B. `pubspec.yaml`).
Im Zweifel `lib/`, `test/` und `pubspec.yaml` vorher sichern, den Befehl
ausführen, und danach die eigenen Dateien zurückkopieren, falls etwas
überschrieben wurde.

## Erste Schritte, sobald die Hardware ankommt

Siehe `docs/06_SETUP_ANLEITUNG.md` und `docs/10_ANLEITUNG_FUER_ADI.md`.

## Struktur

```
/app       Flutter-App (Clean Architecture: domain/data/presentation)
/firmware  PlatformIO-Projekt für den M5StickC Plus2
/docs      Vollständige Architektur- und Prozessdokumentation
```

## Wichtig für jede KI, die hier weiterarbeitet

Lies zuerst `docs/05_KI_ONBOARDING_PROMPT.md`, dann `docs/GYM_TRACKER_ARCHITEKTUR.md`
vollständig, bevor du Code änderst.

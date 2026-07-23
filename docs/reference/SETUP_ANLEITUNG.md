# Umgebungs-Setup-Anleitung

**Zweck:** Schritt-für-Schritt-Einrichtung der Entwicklungsumgebung, damit die ausführende KI nicht mitten in Phase 0 auf einen Versionskonflikt trifft und eigenmächtig Pakete wechselt.

**Hinweis zur Aktualität:** Die unten genannten Versionsbereiche sind Empfehlungen zum Zeitpunkt der Erstellung dieser Anleitung. Die ausführende KI soll die tatsächlich installierte Version zu Beginn von Phase 0 einmal ausgeben lassen und mit dem Team abgleichen (siehe `00_ENTSCHEIDUNGEN_ERFORDERLICH.md`), nicht blind von den hier genannten Zahlen ausgehen, falls seit Erstellung dieser Datei Zeit vergangen ist.

## 1. Firmware-Umgebung (M5StickC Plus2)

1. PlatformIO installieren (VS-Code-Extension oder CLI).
2. Board-Definition: `m5stick-c-plus2` in `platformio.ini` prüfen — falls nicht vorhanden, generische ESP32-Pico-Konfiguration mit M5StickCPlus2-Bibliothek verwenden.
3. Bibliotheken: `M5StickCPlus2`, BLE-Stack aus dem ESP32-Arduino-Core (im PlatformIO-Board-Package enthalten).
4. **Vor Phase 0 abschließend testen:** Ein minimaler "Hello World"-Sketch (nur Display-Text, kein BLE) muss erfolgreich flashen, bevor mit dem eigentlichen Protokoll begonnen wird.

## 2. App-Umgebung (Flutter)

1. Flutter-SDK-Version: aktuelle stabile Version zu Projektbeginn fixieren und in `pubspec.yaml` als Kommentar vermerken.
2. Pakete (siehe `ARCHITECTURE_DECISION_RECORDS.md`, ADR-006 für Begründung):
   - `flutter_blue_plus` (aktuelle stabile Version)
   - `drift` + `sqlite3_flutter_libs` + `drift_dev` (Build-Runner für Code-Generierung) — finale DB-Wahl, siehe ADR-006
3. **Vor Phase 0 abschließend testen:** Ein minimales Flutter-Projekt mit nur `flutter_blue_plus` importiert muss fehlerfrei bauen (`flutter run -d chrome` und `flutter build apk --debug`), bevor eigene Logik hinzukommt. Damit wird ein Kompatibilitätsproblem sofort sichtbar, nicht erst mitten in Phase 0.

## 3. Android-Konfiguration (recherchierte, aktuelle Anforderungen)

### 3.1 Zielversion
- `targetSdkVersion` sollte einer aktuellen, von Google Play akzeptierten Version entsprechen. Da sich diese Anforderung jährlich ändert, zum Projektstart einmal die aktuell von Google Play geforderte Mindest-Zielversion nachschlagen (Play Console → Richtlinien), nicht die zum Zeitpunkt dieser Anleitung gültige Zahl ungeprüft übernehmen.

### 3.2 BLE-Berechtigungen (Stand der Recherche: Juni 2026)
```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
                  android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- Legacy-Pfad für Android 11 und niedriger: -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
```
**Wichtig:** Das Flag `neverForLocation` ist zulässig, weil die App gezielt nach einem bekannten Servicenamen ("GymTracker") sucht und daraus keine Standortinformation ableitet (siehe ADR-007). Dadurch entfällt die sonst nötige `ACCESS_FINE_LOCATION`-Berechtigung auf Android 12+, was die erste Berechtigungsabfrage beim Nutzer deutlich weniger einschüchternd macht.

### 3.3 Hintergrund-BLE (Android 15+, siehe ADR-008)
Falls die App eine BLE-Verbindung bei gesperrtem Bildschirm/im Hintergrund halten soll (z. B. während einer Trainingspause, Handy in der Tasche):
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
```
Und im Service:
```xml
<service android:name=".BleForegroundService"
         android:foregroundServiceType="connectedDevice" />
```
**Ohne diese Deklaration:** Die Verbindung wird auf Android 15+ im Hintergrund möglicherweise ohne Fehlermeldung und ohne Absturz einfach beendet — ein Fehlerbild, das leicht als "Bug in der eigenen BLE-Logik" fehlinterpretiert wird, obwohl es eine Plattform-Anforderung ist. Bei einem entsprechenden Symptom zuerst hier nachsehen (siehe auch `ESKALATIONS_PLAYBOOK.md`).

## 4. Testgerät

- Android-Version des tatsächlichen Testgeräts vor Phase 0 feststellen (siehe `00_ENTSCHEIDUNGEN_ERFORDERLICH.md`) und gegen Abschnitt 3 abgleichen — insbesondere, ob das Gerät alt genug ist, dass der Legacy-Berechtigungspfad (Android ≤ 11) statt des modernen Pfads greift.

## 5. Reihenfolge der ersten Schritte (Zusammenfassung)

1. Firmware-Minimal-Sketch flashen und Display-Ausgabe verifizieren.
2. Flutter-Minimalprojekt mit `flutter_blue_plus` bauen (Web + Android-Debug-Build).
3. Android-Manifest gemäß Abschnitt 3 konfigurieren.
4. Erst danach mit der eigentlichen Phase-0-Implementierung aus dem Architekturdokument beginnen.

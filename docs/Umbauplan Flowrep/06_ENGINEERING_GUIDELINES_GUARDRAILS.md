# Engineering Guidelines und Guardrails – FlowRep (korrigierte Version)

**Ersetzt:** `Engineering_Guidelines___Guardrails.txt` (vorherige KI-Sitzung)
**Hinweis:** Der überwiegende Teil des Originals war handwerklich solide und wird hier unverändert oder nur leicht angepasst übernommen. Korrigiert wurden ausschließlich veraltete/falsche technische Fakten (Abschnitt 1) und es wurden neue, aus der Fehleranalyse abgeleitete Guardrails ergänzt (Abschnitt 5.6–5.7).

---

## Abschnitt 1: Technologie-Stack (Fakten korrigiert)

1.1 **Sprachen und Frameworks:** Mobile App in Dart 3.x / Flutter 3.x. Firmware in C++ via PlatformIO. ML-Skripte (falls relevant, siehe ADR-021) in Python 3.x.

1.2 **State Management:** Riverpod – **bereits produktiv im Einsatz**, nicht neu einzuführen.

1.3 **Datenbank:** Drift (SQLite) mit SQLCipher-Verschlüsselung – **bereits implementiert**.

1.4 **BLE:** Die App nutzt bereits eine funktionierende Lösung für das Xiaomi-HyperOS-Notification-Problem (Read-Polling ohne CCCD-Subscription statt eines pauschalen 30-ms-Polling-Loops). **Korrektur einer verbreiteten Fehlannahme:** Die effektive Datenrate, die tatsächlich bei der App ankommt, beträgt gemessen ca. **73,6 Samples/Sekunde** (nicht 14 Hz) – jeder Poll liefert einen Batch von 4 Samples, und die Batch-Polling-Rate liegt bei ca. 18,4 Hz. Alle Zeitfenster-Berechnungen (Filterfenster, Mindestabstände zwischen Reps etc.) müssen mit dieser tatsächlichen Rate rechnen, nicht mit 14 Hz.

1.5 **Paketmanagement:** Alle Abhängigkeiten exakt versioniert in `pubspec.yaml`. Vor jedem Commit: Code kompiliert ohne Warnungen.

---

## Abschnitt 2: Architektur-Regeln (Clean Architecture) – unverändert

2.1 **Domain Layer:** Reine Geschäftslogik (`SignalProcessor`, `WorkoutEngine`), Entitäten (`SensorSample`), Interfaces (`ISensorProvider`). Keine Abhängigkeiten zu Flutter-UI, BLE-Bibliotheken oder Datenbank-Paketen. Isoliert testbar.

2.2 **Data Layer:** Implementiert die Domain-Interfaces. `BleSensorProvider`, `MockSensorProvider`, `DriftWorkoutRepository` leben hier.

2.3 **Presentation Layer:** UI und Riverpod-Provider. Keine synchrone direkte Kommunikation mit dem Data-Layer. Keine Geschäftslogik in Widgets.

2.4 **Import-Regel:** Ein Import aus Presentation in Data oder Domain ist ein architektonischer Fehler.

---

## Abschnitt 3: Coding-Stil und Namenskonventionen – unverändert

3.1 Selbsterklärender Code, sprechende Namen (`dynMagnitude` statt `dynMag`).
3.2 Klassen/Enums: PascalCase. Methoden/Variablen: camelCase. Konstanten: lowerCamelCase (Dart) / SCREAMING_SNAKE_CASE (C++). Dateien: snake_case.dart.
3.3 Kommentare erklären das "Warum", nicht das "Was". Komplexe Logik (z. B. die Gravitationskompensation) braucht einen Kommentar, der den physikalischen Grund erläutert – **inklusive der in Dokument 03 dokumentierten Modellannahme zur Rotationsachse**, damit spätere Entwickler wissen, dass diese Annahme verifiziert werden muss, falls sich die Sensor-Trageposition ändert.
3.4 Strikte Null-Safety, keine wildcard-`dynamic`, `Optional`/`?` nur wenn ein Wert legitim fehlen kann.

---

## Abschnitt 4: Test-Strategie und Definition of Done

4.1 Test-First-Mentalität: Jede neue Domain-Logik (DSP-Filter, State Machine, Byte-Parser) bekommt einen Unit-Test, bevor sie in die UI integriert wird.
4.2 Flutter Test Framework, `mocktail` für Mocks.
4.3 Kernmodule (`WorkoutEngine`, `SignalProcessor`, Byte-Parser) zu 100 % durch synthetische Testdaten abgedeckt.
4.4 `flutter analyze` fehlerfrei, `flutter test` zu 100 % grün vor Abschluss jeder Phase.
4.5 Tests werden nie gelöscht, um sie grün zu machen – bei Fehlschlag wird die Logik korrigiert, es sei denn, eine neue ADR ändert die Anforderung explizit.
4.6 **Neu:** Kernmodul-Tests müssen sowohl isolierte Einzelfälle als auch Mehrfach-Ereignis-Sequenzen mit realistisch kurzen Zeitabständen abdecken (siehe ADR-022). Ein Test, der nur den Idealfall mit großzügigen Ruhezeiten prüft, gilt nicht als ausreichende Abdeckung für zeitkritische Logik.

---

## Abschnitt 5: Guardrails für die ausführende KI

5.1 **Kein Dead Code.** Keine ungenutzten Methoden, keine "TODO: implement later"-Platzhalter.
5.2 **Kein Over-Engineering.** Keine unnötigen Abstraktionsschichten oder Factory-Patterns für Klassen mit nur einer Implementierung.
5.3 **Keine Improvisation bei Fehlern.** Bei Paketproblemen oder BLE-Bugs: stoppen, analysieren, Product Manager um Anweisung bitten – nicht eigenmächtig auf ein anderes Paket wechseln.
5.4 **Strikte ADR-Treue.** ADRs sind kanonisch. Löst eine ADR ein Problem nicht, wird eskaliert, nicht ignoriert.
5.5 **Kommunikationsvorschrift.** Nach Abschluss eines Tasks: Prosa-Zusammenfassung + nummerierte "USER ACTION"-Liste.

**5.6 (Neu) Validierungspflicht vor Parameteränderungen.** Kein neuer Schwellenwert, keine neue Filter-Grenzfrequenz und keine neue Kalibrierungslogik wird nach Dart portiert, ohne vorher in der Python-Simulation gegen die in ADR-022 definierten Standard-Testszenarien gelaufen zu sein – insbesondere gegen das Mehrfach-Rep-mit-kurzer-Pause-Szenario. Ein Test, der nur mit einem isolierten Einzel-Rep und großzügiger Ruhezeit validiert wurde, gilt nicht als ausreichend validiert.

**5.7 (Neu) Bestandsprüfung vor Behauptungen über den Projektstand.** Bevor eine KI eine Aussage über den aktuellen Stand des Projekts trifft (z. B. "X ist noch nicht gelöst", "Y existiert noch nicht"), muss sie den tatsächlichen Code auf dem `master`-Branch geprüft haben. Pauschale Aussagen über den Projektstand, die nicht durch aktuelles Lesen des echten Repositories belegt sind, sind zu unterlassen bzw. explizit als ungeprüfte Annahme zu kennzeichnen.

---

## Abschnitt 6: Sicherheit und Fehlerbehandlung – unverändert, um einen Punkt ergänzt

6.1 Try-Catch-Blöcke nie leer oder nur mit `print(e)`. Fehler werden an die UI weitergereicht oder strukturiert geloggt.
6.2 Statt `print()`: Logger-Service, in Release-Builds stummgeschaltet.
6.3 Verschlüsselungs-Schlüssel nie im Code als Klartext, zur Laufzeit generiert, im Android Keystore abgelegt.
6.4 Minimalnötige Android-Berechtigungen (BLE, Foreground Service), keine Standort-/Kontaktzugriffe ohne zwingenden Grund.
6.5 **Neu:** Zugangs-Token (GitHub, APIs etc.) werden niemals im Klartext in Chat-Nachrichten, Commits, Issues oder Logs geteilt. Werden sie versehentlich geteilt, werden sie umgehend rotiert. Für lokale Entwicklung: Umgebungsvariablen oder ein Secrets-Manager, nicht Klartext im Code oder in Konversationen mit einer KI.

# Definition of Done — pro Phase

**Zweck:** Ersetzt vage "Test-Ziel"-Sätze durch prüfbare Kriterien. Eine Phase gilt erst als abgeschlossen, wenn **alle** Kriterien erfüllt UND das jeweilige Verifikationsartefakt (Datei, Log, Messwert) tatsächlich erzeugt wurde — nicht, wenn die ausführende KI meldet "sollte funktionieren".

**Grundregel für die ausführende KI:** Ein Kriterium gilt nur als erfüllt, wenn das genannte Verifikationsartefakt existiert und eingesehen werden kann. Selbsteinschätzung ("müsste jetzt gehen") zählt nicht als Erfüllung.

---

## Phase 0 — Prototyp

| # | Kriterium | Verifikationsartefakt |
|---|---|---|
| 0.1 | App startet in Chrome ohne Konsolenfehler | Screenshot der Browser-Konsole, keine roten Fehler |
| 0.2 | Mock-Verbindung: Klick auf "Gerät verbinden" → Text wechselt nach genau 2 s (±0,5 s) zu "Verbunden (Mock)" | Kurzes Bildschirmvideo oder Log-Zeitstempel |
| 0.3 | Firmware geflasht, Display zeigt "Gym Tracker Bereit" | Foto des Displays |
| 0.4 | Handy findet "GymTracker" im BLE-Scan | Screenshot der Geräteliste |
| 0.5 | MTU erfolgreich auf ≥ 55 Byte verhandelt | Log-Ausgabe des negotiated MTU-Werts |
| 0.6 | Akkustand wird auf echtem Handy korrekt angezeigt | Screenshot mit Prozentwert |
| 0.7 | 52-Byte-Batches kommen mit 50 Hz an, kein Parsing-Fehler über 60 Sekunden Dauerstream | Log: Sample-Rate-Zähler, Fehleranzahl = 0 |

## Phase 1 — Kernentwicklung

| # | Kriterium | Verifikationsartefakt |
|---|---|---|
| 1.1 | Web-Mock: simulierte Wiederholung erhöht Zähler sichtbar | Bildschirmvideo |
| 1.2 | Echtgerät: 10 Bizeps-Curls mit Stick ergeben Zählung zwischen 9 und 11 | Textprotokoll: manuell mitgezählt vs. App-Anzeige, 3 Wiederholungsdurchläufe |
| 1.3 | Erster Satz erscheint automatisch ohne separaten Kalibrierungsschritt (kein Extra-Tap nötig) | Bildschirmvideo ab App-Start bis erste angezeigte Zahl |
| 1.4 | Manuelle Korrektur (+/-) speichert `CorrectionEvent` mit korrektem `systemCount`/`userCorrectedCount` | Datenbank-Dump nach einer Korrektur |
| 1.5 | Korrektur-Nachricht zeigt den in Abschnitt 2.2 des Architekturdokuments festgelegten Text — NICHT "Die KI lernt dazu" | Screenshot |
| 1.6 | `IWorkoutRepository` hat keine Isar-Importe außerhalb der Isar-Implementierungsklasse | `grep -r "package:isar" lib/domain/` liefert keine Treffer |

## Phase 2 — Erweiterung

| # | Kriterium | Verifikationsartefakt |
|---|---|---|
| 2.1 | History-Screen zeigt vorheriges Workout nach App-Neustart | Bildschirmvideo: Workout machen → App killen → öffnen → Historie sichtbar |
| 2.2 | Pausen-Timer zählt automatisch von 90 s runter nach Satz-Ende | Bildschirmvideo |
| 2.3 | Nach 60 s Pause ohne Bewegung: Firmware-Stromverbrauch messbar reduziert (Wake-on-Motion aktiv) | Vorher/Nachher-Strommessung oder zumindest Log des Sleep-Modus-Eintritts |
| 2.4 | Vollständige Trainingseinheit (≥ 30 Min, ≥ 5 Sätze) verbraucht nachvollziehbar dokumentierten Akku-Prozentsatz | Akkustand-Log vor/nach |
| 2.5 | Bluetooth am Handy kurz aus/an während aktivem Satz → Reconnect ohne Zählungsverlust | Bildschirmvideo |

## Phase 3 — Teststrategie

| # | Kriterium | Verifikationsartefakt |
|---|---|---|
| 3.1 | Unit-Tests für Peak-Detection und State-Transitions vorhanden und grün | Testlauf-Ausgabe (`flutter test`) |
| 3.2 | Früher Nutzertest mit 3–5 Personen durchgeführt | Ausgefülltes `TESTPROTOKOLL_TEMPLATE.md` |
| 3.3 | Korrekturrate aus dem Test dokumentiert und mit dem in `00_ENTSCHEIDUNGEN_ERFORDERLICH.md` bestätigten Zielwert verglichen | Ausgefülltes Testprotokoll mit Auswertung |
| 3.4 | HIL-Test: mindestens 3 vollständige Sätze auf echter Hardware ohne Absturz | Log/Video |
| 3.5 | DSGVO-Löschfunktion (`deleteAllUserData()`) tatsächlich aufgerufen und danach leere lokale DB verifiziert | Vorher/Nachher-DB-Dump |

## Phase 4 — Release & Deployment

| # | Kriterium | Verifikationsartefakt |
|---|---|---|
| 4.1 | Signierter Release-Build installiert sich auf Testgerät | Installationsprotokoll |
| 4.2 | Vollständiger Workout-Flow ohne Debug-Tools durchgespielt | Bildschirmvideo |
| 4.3 | Store-Berechtigungs-Disclosure-Text vorhanden und von der in `00_ENTSCHEIDUNGEN_ERFORDERLICH.md` benannten Stelle geprüft (nicht KI-generiert final übernommen) | Bestätigungsvermerk |
| 4.4 | Bei Android-Zielversion ≥ 15: `foregroundServiceType="connectedDevice"` deklariert und Hintergrund-BLE-Verbindung bei gesperrtem Bildschirm getestet | Manifest-Auszug + Testprotokoll |
| 4.5 | Zusätzlich auf mindestens einem Gerät mit aggressivem OEM-Batteriemanagement (z. B. Xiaomi/MIUI) getestet: App bleibt im Hintergrund bei gesperrtem Bildschirm verbunden, oder es existiert eine dokumentierte Nutzeranleitung zur Akku-Ausnahme für dieses Gerät | Testprotokoll mit Gerätemodell + Android-/MIUI-Version |

## Phase 5 — Später (V2+)

*Kriterien werden erst definiert, wenn Phase 5 tatsächlich begonnen wird — bewusst nicht jetzt schon im Detail spezifiziert, um keine Scheingenauigkeit für einen noch nicht terminierten Abschnitt zu erzeugen.*

---

## Wichtiger Hinweis zur V1-Übungsliste

Diese Definition of Done geht davon aus, dass V1 **ausschließlich Bizeps-Curls** abdeckt (die einzige Übung, die im gesamten bisherigen Bauplan konkret durchgetestet wird). Falls in `00_ENTSCHEIDUNGEN_ERFORDERLICH.md` eine andere oder größere Übungsliste bestätigt wird, müssen die Kriterien 1.2 und 3.2–3.3 entsprechend für jede zusätzliche Übung wiederholt werden — nicht nur einmalig für eine Übung als repräsentativ für alle angenommen werden.

# Bauplan Agent 4: Firmware, Protokoll & Hardware-Verifikation

> Eigenständiges Arbeitspaket für das FlowRep-Projekt. Du brauchst keine anderen Baupläne, um diese Aufgabe zu erledigen.

## 0. Wer du bist – und was du NICHT kannst

Du bist einer von vier parallel arbeitenden KI-Agenten. Du bist zuständig für: **die Firmware-seitigen Fixes (ehrliche Zeitbasis, Skalierung) und ALLE physischen Tests am echten Gerät.**

**Kritisch, lies das zweimal:** Du hast keinen Körper. Du kannst keinen Bizeps-Curl machen, kein USB-Kabel einstecken, keinen Bildschirm ablesen, der nicht über deine Werkzeuge sichtbar ist. Wenn du Terminal-/Dateizugriff auf den Rechner hast, an dem das M5StickC Plus2 bereits per USB angeschlossen ist, kannst du Kompilieren und Flashen SELBST per Kommandozeile ausführen. Aber für alles, was "eine echte Bewegung machen" oder "auf das Telefon/Tablet schauen, auf dem die App läuft" bedeutet, brauchst du **Adi** als deine Hände und Augen. Deine Aufgabe in diesen Momenten ist, ihm eine EXAKTE, unmissverständliche Anleitung zu geben und dann sein berichtetes Ergebnis zu interpretieren – nicht, es zu erraten oder anzunehmen.

## 1. Auftrag in einem Satz

Behebe die zwei bekannten Firmware-seitigen Probleme (unehrliche Zeitbasis, Gyro-Clipping bei ±327,67°/s trotz realer Werte bis ~344°/s), liefere dafür früh eine Protokoll-Spezifikation für Agent 1, und führe – mit Adi als physischem Ausführenden – die seit mehreren Sessions offenen Hardware-Verifikationen durch, allen voran den `ENG:`/Sample-Test, der bisher NIE mit einem Ergebnis abgeschlossen wurde.

## 2. Repo-Zugriff & erstes Vorgehen (PFLICHT vor jeder Änderung)

1. `git checkout main && git pull origin main`.
2. Lies `docs/Umbauplan Flowrep/RECHERCHE_ZAEHLROBUSTHEIT_2026-07-16.md`, Abschnitte zu S3 (Zeitbasis), S4 (Gyro-Clipping) und P0.
3. Lies `docs/01_protocol.yaml` – das ist das aktuelle BLE-Protokoll, das du erweiterst (nicht ersetzt, sofern nicht zwingend nötig).
4. Lies `firmware/src/main.cpp` und `firmware/platformio.ini`. Firmware ist NimBLE-basiert (bereits migriert, nicht mehr die alte BLEDevice.h-Variante).
5. Lies in `docs/Umbauplan Flowrep/STATUS_FORTSCHRITT.md` den Abschnitt zum `ENG:`/Sample-Test – dort steht seit mehreren Sessions ein offener Punkt "höchste Priorität", auf dessen Ergebnis gewartet wird. Das ist dein wichtigster erster physischer Test (Abschnitt 6, Test 1).

## 3. Kontext, den du brauchst

Das M5StickC Plus2 (BMI270-IMU) sendet Gyro-/Beschleunigungsdaten per BLE (NimBLE) an die Flutter-App. Bekannte, noch offene Probleme, für die DU zuständig bist:

- **S3 – Zeitbasis ist fiktiv:** Die Firmware sendet Sample-Batches ohne eingebettetes echtes Timing; die App synthetisiert aktuell künstliche, gleichmäßige 20ms-Abstände. Das verzerrt jede zeitbasierte Berechnung. Deine Aufgabe: echte Zeitstempel (oder zumindest ein verlässliches, gleichmäßiges Pacing mit bekannter, konstanter Sample-Rate) ins Protokoll aufnehmen.
- **S4 – Gyro-Clipping:** Aktuell ±327,67°/s (das ist exakt 32767/100 – ein Hinweis, dass Gyro-Werte als int16, skaliert mit Faktor 100, übertragen werden). Echte, kräftige Curls erreichen bis zu ~344°/s. Werte darüber werden aktuell abgeschnitten (geclippt), was die Zählung bei kräftigen Wiederholungen verfälscht. Deine Aufgabe: Skalierung so anpassen, dass mindestens bis ±400°/s ohne Clipping übertragen wird (Sicherheitsspanne über den beobachteten 344°/s).

Jede Protokolländerung braucht eine **Versionsnummer-Erhöhung** (prüfe, ob `docs/01_protocol.yaml` bereits ein Versionsfeld hat; falls nicht, führe eines ein) – damit die App-Seite (Agent 1) erkennen kann, mit welcher Firmware-Version sie spricht, statt stillschweigend falsch zu parsen.

## 4. Dateien, die dir gehören

- `firmware/src/main.cpp`
- `firmware/platformio.ini`
- `docs/01_protocol.yaml`

## 5. Dateien, die du NICHT anfassen darfst

Alles unter `app/`, `tools/workout_engine_simulation.py`. Du LIEST App-Code, wenn du verstehen musst, wie die Gegenseite das Protokoll konsumiert, aber du SCHREIBST dort nichts – das ist Agent 1s Job (dein Protokoll-Update ist die Grundlage, auf der er aufbaut).

## 6. Aufgaben, Schritt für Schritt

### Schritt A – Protokoll-Spezifikation zuerst (schnell, damit Agent 1 nicht blockiert wird)
1. Aktualisiere `docs/01_protocol.yaml`: neues Feld/neue Felder für echten Zeitstempel oder verlässliches Sample-Timing, neue Gyro-Skalierung (mind. ±400°/s), neue Protokollversion.
2. Committe NUR diese Doku-Änderung als eigenen, schnellen ersten Commit (siehe Git-Workflow) – Agent 1 wartet darauf, um mit dem App-seitigen P0-Anteil weiterzumachen.

### Schritt B – Firmware-Implementierung
1. `firmware/src/main.cpp`: Zeitstempel/Pacing gemäß deiner neuen Spezifikation einbauen, Gyro-Skalierung anpassen.
2. Kompilier-Check: `pio run` im `firmware/`-Verzeichnis (falls du Terminalzugriff auf einen Rechner mit installiertem PlatformIO hast). Muss ohne Fehler durchlaufen, BEVOR du an einen physischen Test denkst.
3. Falls das M5StickC Plus2 bereits per USB an dem Rechner angeschlossen ist, an dem du arbeitest: Du kannst den Flash-Vorgang selbst versuchen (`pio run --target upload`). Falls das fehlschlägt (falscher Port, keine Rechte, Gerät nicht erkannt) oder du unsicher bist, ob das Gerät überhaupt angeschlossen ist: **frag Adi**, statt es zu erzwingen oder anzunehmen, dass es geklappt hat.

### Schritt C – Physische Verifikation mit Adi (der zentrale Teil deines Auftrags)

Für jeden Test unten: Gib Adi die Anleitung EXAKT so, wie sie hier steht (du darfst sie an den tatsächlichen Firmware-/App-Stand anpassen, falls nötig, aber sie muss so präzise bleiben, dass er sie ohne Rückfragen ausführen kann). Warte auf sein Ergebnis. Trage es dokumentiert ins Status-Dokument ein (Abschnitt 8). Interpretiere es, bevor du zum nächsten Schritt gehst.

**Test 1 – `ENG:`/Sample-Test (höchste Priorität, seit mehreren Sessions ohne Ergebnis offen):**
> "Bitte öffne die FlowRep-App, stelle sicher, dass der 'Dummy Stream'-Schalter AUS ist, und verbinde dich mit dem echten M5StickC Plus2. Mach eine einzelne, echte Bizeps-Curl-Wiederholung. Schau auf die Zeile, die mit `ENG:` beginnt (Home-Screen). Sag mir: (a) zählt der `samples=`-Wert während der Bewegung sichtbar hoch, (b) welchen ungefähren Wert erreicht er nach der einen Wiederholung, (c) zeigt die App danach `Reps: 1` oder bleibt sie bei `0`?"

Das Ergebnis dieses Tests entscheidet, wie ernst das ursprüngliche "0 Reps"-Problem noch ist: Wenn `samples` nicht hochzählt, liegt das Problem unterhalb der Zähl-Logik (BLE-Übertragung oder Firmware) – das ist DEIN Bereich, nicht Agent 1s. Wenn `samples` hochzählt, aber `Reps` bei 0 bleibt, liegt es in der Zähl-Logik – das ist Agent 1s Bereich, informiere ihn über das Status-Dokument.

**Test 2 – Nach Firmware-Update (Schritt B):**
> "Bitte flashe die neue Firmware [exakter Befehl, den du in Schritt B.3 genutzt/vorbereitet hast]. Danach: verbinde die App neu, mach 3 normale Wiederholungen. Funktioniert die Verbindung noch? Zählt die App weiterhin plausibel mit?"

**Test 3 – Guided Calibration 2.0 End-to-End (erst wenn Agent 2 UND Agent 3 gemerged sind, nicht vorher):**
> "Bitte durchlaufe die neue geführte Kalibrierung fünfmal, mit jeweils anderem Stil: (1) normal/sauber, (2) bewusst mit einem kleinen doppelten Zucken pro Wiederholung, (3) mit sehr kleiner/schwacher Bewegung, (4) sehr langsam, (5) mit wechselndem Tempo innerhalb der Serie. Sag mir für jeden Durchlauf, ob die Stufe B (5 bekannte Wiederholungen) das korrekte Ergebnis liefert und ob die Review-Stufe danach sinnvoll aussieht."

Vergleiche die Ergebnisse mit den Simulationswerten aus `tools/workout_engine_simulation.py` (MAE ≤ 0,5 pro Persona) – größere Abweichungen zwischen Simulation und echtem Gerät sind ein eigener, dokumentationswürdiger Befund, kein Grund, den Test als "bestanden" zu werten.

**Test 4 – CSV-Export (bisher nie am echten Gerät geprüft):**
> "Bitte zeichne eine kurze Trainingsserie auf, exportiere die CSV-Datei, und schick mir entweder die Datei oder die ersten paar Zeilen ihres Inhalts."

Prüfe die gemeldeten Werte auf Plausibilität (Zeitstempel monoton steigend, Werte in sinnvollem Bereich, keine leeren/NaN-Felder).

## 7. Definition of Done

- [ ] `docs/01_protocol.yaml` hat eine neue, dokumentierte Version mit echter Zeitbasis und erweiterter Gyro-Skalierung.
- [ ] `pio run` kompiliert fehlerfrei.
- [ ] Test 1 (`ENG:`/Sample) hat ein dokumentiertes Ergebnis – zum ersten Mal seit mehreren Sessions.
- [ ] Test 2 (Firmware-Update) bestätigt: Verbindung und Grundzählung funktionieren nach dem Flash weiterhin.
- [ ] Tests 3 und 4 haben dokumentierte Ergebnisse (auch wenn "nicht bestanden" – das ist ein valides, wichtiges Ergebnis, keine Fehlfunktion deinerseits).
- [ ] Alle vier Testergebnisse stehen im Status-Dokument, nicht nur im Chat mit Adi.

## 8. Git-Workflow (PFLICHT, keine Ausnahmen)

```
git checkout main
git pull origin main
git checkout -b agent4-firmware-hardware
# Schritt A zuerst, als eigener schneller Commit
git add docs/01_protocol.yaml
git commit -m "docs(protocol): Protokoll-v[X] – echte Zeitbasis, Gyro-Skalierung bis ±400°/s (P0 Vorbereitung fuer Agent 1)"
git push origin agent4-firmware-hardware
# Schritt B danach
git add firmware/src/main.cpp firmware/platformio.ini
git commit -m "fix(firmware): ehrliche Zeitbasis + Gyro-Clipping-Fix (RECHERCHE_ZAEHLROBUSTHEIT S3/S4)"
git push origin agent4-firmware-hardware
```

**Du merged NIEMALS selbst nach `main`.** Push deinen Branch nach jedem sinnvollen Zwischenschritt (nicht erst ganz am Ende – Schritt A insbesondere so früh wie möglich, damit Agent 1 nicht wartet), stoppe, warte auf Adi/Claude.

## 9. Fortschritt dokumentieren

Neuer Abschnitt am Ende von `docs/Umbauplan Flowrep/STATUS_FORTSCHRITT.md`, Kennung `Agent-4-FirmwareHardware`, bestehendes Format nutzen, nichts Bestehendes überschreiben. **Alle vier Testergebnisse aus Abschnitt 6, Schritt C gehören hier hinein, mit Datum und so wörtlich wie möglich, was Adi berichtet hat** – nicht nur deine Interpretation, auch die Rohaussage.

## 10. Wenn du blockiert bist

- Adi antwortet nicht sofort auf eine Testanfrage: nicht raten, was das Ergebnis gewesen sein könnte. Mit Schritt A/B weiterarbeiten (die brauchen kein Warten), Test später nachholen.
- Du hast keinen Terminalzugriff auf einen Rechner mit angeschlossenem Gerät: Schritt B (Kompilieren/Flashen) komplett an Adi delegieren – gib ihm die exakten Befehle, die er selbst ausführen soll, statt zu behaupten, du hättest es getan.
- Testergebnis widerspricht der Erwartung (z.B. `samples` zählt nicht hoch): das ist kein Fehler deinerseits, sondern ein wichtiger Befund. Dokumentieren, nicht schönreden, nicht nochmal denselben Test wiederholen in der Hoffnung auf ein anderes Ergebnis.

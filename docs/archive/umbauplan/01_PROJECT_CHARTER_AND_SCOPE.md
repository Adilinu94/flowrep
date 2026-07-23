# Project Charter and Scope – FlowRep (korrigierte Version)

**Ersetzt:** `PROJECT_CHARTER_AND_SCOPE_-_FLOWREP_.txt` (vorherige KI-Sitzung)
**Voraussetzung:** `00_UEBERBLICK_UND_AENDERUNGEN.md` gelesen

---

## Projekt-Vision und Elevator Pitch

FlowRep ist eine Offline-First Gym-Tracking-App für Android, die zusammen mit einem am Handgelenk getragenen ESP32-Sensor (M5StickC Plus2) Inertialsensordaten (IMU) erfasst, filtert und daraus automatisch Wiederholungen, Sätze und Pausen erkennt. Anders als der vorherige Charter-Entwurf ist dies **kein Neustart**, sondern die Fortführung eines bereits funktionierenden Prototyps: BLE-Verbindung, Firmware, Datenbank und eine erste Zähl-Logik existieren bereits und wurden real auf Hardware getestet. Ziel dieses Dokuments ist es, den nächsten, evidenzbasierten Entwicklungsschritt zu definieren – nicht, das Projekt neu zu erfinden.

## Das Kernproblem (präzisiert)

Die aktuelle Zähl-Logik zählt Wiederholungen mal zu häufig, mal zu selten. Eine unabhängige Code-Analyse hat einen konkreten Grund identifiziert: Ein sorgfältig kalibrierter Schwellenwert aus einer 10-Rep-Guided-Calibration wird durch eine Ein-Rep-Auto-Rekalibrierung überschrieben, sobald nach der Kalibrierung die erste echte Bewegung erkannt wird (Details in `02_ARCHITECTURE_DECISION_RECORDS.md`, ADR-020). **Korrektur (Cross-Check gegen Handoff-Dokumente vom 12.07.):** `calibrationReps` wurde an diesem Tag bewusst von 3 auf 1 gesenkt, vermutlich zur Beschleunigung manueller Tests – keine alte, vergessene Voreinstellung. Der Bug-Mechanismus selbst bleibt davon unberührt. Zusätzlich nutzt die aktuelle Engine die rohe Beschleunigungs-Magnitude als Signal, die sich bei einer Rotation um das Handgelenk (wie beim Bizeps-Curl) nur wenig ändert, da die Erdschwere zwischen den Achsen wandert, statt zu verschwinden. Beides sind konkrete, behebbare technische Probleme – kein Beleg dafür, dass regelbasierte Ansätze für dieses Problem grundsätzlich ungeeignet wären.

## Der Magic Moment (präzisiert)

Der Magic Moment – der Nutzer beginnt zu trainieren und sieht ohne Zutun eine korrekte Zählung – bleibt das Leitbild. Anders als im vorherigen Entwurf wird dafür aber **nicht** jede Kalibrierung abgeschafft: Eine **einmalige** Ersteinrichtung pro Nutzer (Guided Calibration, ca. 10 Wiederholungen) ist akzeptabel und bereits implementiert; sie muss nur zuverlässig funktionieren und darf nicht durch nachgelagerte Logik überschrieben werden. Nach dieser einmaligen Einrichtung soll jedes weitere Training ohne erneute Kalibrierung starten.

---

## In Scope für den nächsten Schritt

### 1. Bugfix: Kalibrierungs-Persistenz (höchste Priorität, geringstes Risiko)

Der in ADR-020 beschriebene Fehler wird behoben: Nach einer abgeschlossenen Guided Calibration darf die erste reale Bewegung nicht erneut eine Ein-Rep-Auto-Rekalibrierung auslösen, die den sorgfältig ermittelten Schwellenwert überschreibt. Dies ist eine lokale, gut abgegrenzte Änderung an der bestehenden `WorkoutEngine` – kein Architekturwechsel.

### 2. DSP-Verbesserung: Gyro-gestützte Gravitationskompensation

Ergänzend zur bestehenden Signalverarbeitung wird ein gyro-gestütztes Gravitations-Tracking eingeführt (siehe `03_CONTRACTS_AND_BLUEPRINTS.md` und `04_DSP_LABOR_PYTHON_VALIDIERUNG.md`). Im Unterschied zum verworfenen Vorschlag der vorherigen KI-Sitzung (naiver 0,2-Hz-Tiefpass zur "Gravitationsschätzung") wird die tatsächliche, vom Gyroskop gemessene Rotation genutzt, um die Gravitationsrichtung mitzudrehen, statt sie aus der Signalgeschwindigkeit zu erraten. Dieser Ansatz wurde in Python gegen realistische Mehrfach-Rep-Sequenzen mit kurzen Pausen getestet (nicht nur gegen isolierte Einzel-Reps mit langen Ruhephasen) und zeigt eine deutliche, aber nicht perfekte Verbesserung der Trennschärfe zwischen Ruhe und Bewegung.

### 3. Testinfrastruktur: Python-Simulation synchronisieren und erweitern

Die bestehende Python-Simulation (`tools/workout_engine_simulation.py`) kennt den Guided-Calibration-Pfad bisher nicht und hätte den in Punkt 1 beschriebenen Bug nicht automatisch gefunden. Sie wird um genau dieses Szenario erweitert (Guided Calibration abschließen → sofort ein Rep → prüfen, ob der Schwellenwert erhalten bleibt) sowie um realistische Mehrfach-Rep-Sequenzen mit kurzen Pausen (siehe `07_STRATEGISCHES_ARBEITSDOKUMENT_DATENAKQUISITION.md`).

### 4. Echte Datenerfassung (Vorbereitung für spätere Schritte, unabhängig nützlich)

Reale, gelabelte Sensor-Aufzeichnungen (nicht nur synthetische Sinuskurven) werden gesammelt, unabhängig davon, ob der nächste Schritt nach der DSP-Verbesserung eine weitere regelbasierte Verfeinerung oder ein klassischer ML-Klassifikator ist. Details in Dokument 07.

## Explizit zurückgestellt (nicht abgelehnt, aber nicht Teil dieses Schritts)

1. **Vollständiger Ersatz der Zähl-Logik durch ein Deep-Learning-Modell.** Literaturvergleich (RecoFit, ETH Zürich, MetaMotion-Referenzprojekt) zeigt, dass klassische Signalverarbeitung für eine einzelne, gut definierte Übung bereits im selben Genauigkeitsbereich liegt wie Deep-Learning-Ansätze. Ein Modellwechsel ist erst gerechtfertigt, wenn mehrere, morphologisch unterschiedliche Übungen gleichzeitig unterstützt werden sollen.
2. **Sample-genaue 5-Phasen-Sequenzsegmentierung.** Deutlich höherer Labeling-Aufwand als bei allen geprüften Referenzsystemen, ohne belegten Genauigkeitsvorteil für den aktuellen Umfang (eine Übung).
3. **Abschaffung der Guided Calibration.** Eine einmalige, korrekt funktionierende Kalibrierung ist kein Widerspruch zum Magic Moment.
4. **Multi-Exercise-Erkennung**, Cloud-Sync, Kamera-basiertes Tracking, iOS-Unterstützung, Mehrsensor-Setups – wie im ursprünglichen Charter bleiben diese für diesen Schritt explizit außerhalb des Scopes.

---

## Erfolgskriterien und Definition of Done

### 1. Genauigkeit

Statt eines pauschalen "99 %"-Ziels oder einer MAE<0,1-LOSO-Anforderung (die mangels Mehrpersonen-Datensatz ohnehin nicht prüfbar wäre) gilt ein zweistufiges, literaturgestütztes Kriterium:

- **Kurzfristig (nach Bugfix + DSP-Verbesserung):** Bei mindestens 8 von 10 Testsätzen (je 10–15 Reps, von derselben Person, über mehrere Tage und Tageszeiten verteilt) liegt die gezählte Anzahl innerhalb von ±1 Wiederholung der tatsächlichen Anzahl. Diese Schwelle orientiert sich an publizierten Vergleichswerten (RecoFit: ±1 Rep in 93 % der Fälle bei 114 Probanden; ETH Zürich: ±1 Rep in 91 % der Fälle) und ist damit ambitioniert, aber nicht unrealistisch.
- **Mittelfristig (falls auf mehrere Nutzer/Übungen erweitert):** Erst dann wird eine Leave-One-Subject-Out-Validierung sinnvoll, und erst dann ist ein MAE-Ziel wie im ursprünglichen Charter (mit realistischerem Wert, siehe Literaturvergleich) angebracht.

### 2. Performance

Die App läuft flüssig auf einem Android-Smartphone bei aktivem Tracking. Da (vorerst) kein TFLite-Modell zum Einsatz kommt, entfällt die 50-ms-Inferenzgrenze des ursprünglichen Charters für diesen Schritt; sie wird relevant, sobald Dokument 01, Abschnitt "explizit zurückgestellt", Punkt 1 angegangen wird.

### 3. Sicherheit

Unverändert gegenüber dem ursprünglichen Charter: lokale Verschlüsselung (Drift + SQLCipher), Schlüssel im Android Keystore, keine Klartext-Zugangsdaten im Code oder in Commits. **Ergänzung:** Zugangstoken (z. B. GitHub Personal Access Tokens) dürfen nicht im Klartext in Chats, Issues oder Commit-Nachrichten geteilt werden; bereits geteilte Tokens sind zu rotieren.

### 4. CI/CD und Testabdeckung

`flutter analyze` liefert keine Fehler, `flutter test` läuft zu 100 % grün. Zusätzlich zur ursprünglichen Anforderung: **Jede Änderung an Schwellenwerten, Filterparametern oder Kalibrierungslogik muss vorher gegen die in Dokument 04 beschriebenen Python-Testszenarien laufen** – insbesondere gegen das Mehrfach-Rep-mit-kurzer-Pause-Szenario, das den ursprünglichen Gravitationsfilter-Fehler aufgedeckt hat.

---

## Kommunikations- und Arbeitsregeln für die ausführende KI

Diese Regeln sind aus dem ursprünglichen Charter übernommen, da sie sich als sinnvoll erwiesen haben, und um zwei Punkte ergänzt:

1. **Iteratives Arbeiten.** Niemals mehr als eine Phase oder ein großes Modul auf einmal. Nach jedem Schritt: Erklärung in Prosa + nummerierte "USER ACTION"-Checkliste.
2. **Keine Improvisation.** Bei ungeklärten technischen Problemen: stoppen, Problem beschreiben, auf Anweisung warten.
3. **Dokumentationstreue.** ADRs sind kanonisch. `docs/reference/protocol.yaml` (im echten Repo) bleibt der Maßstab für das BLE-Protokoll – **nicht** neu definieren, nur referenzieren.
4. **Kein Dead Code**, sprechende Namen, keine unnötigen Abstraktionsschichten.
5. **Neu – Validierungspflicht:** Kein neuer Schwellenwert-, Filter- oder Kalibrierungsparameter wird nach Dart portiert, ohne vorher in der Python-Simulation gegen mindestens ein Szenario mit kurzen Pausen zwischen mehreren Reps getestet worden zu sein (nicht nur gegen isolierte Einzel-Reps).
6. **Neu – Bestandsprüfung vor Neubau:** Bevor eine KI eine Komponente "neu erstellt" (Interface, Provider, Datenbankschema etc.), muss sie zuerst im echten Repository prüfen, ob diese Komponente bereits existiert. Im Zweifel: existierenden Code lesen und erweitern, nicht duplizieren.

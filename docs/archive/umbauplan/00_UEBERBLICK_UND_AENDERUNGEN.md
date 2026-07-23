# FlowRep – Überblick und Änderungen gegenüber dem ursprünglichen KI-Plan

**Status:** Korrigierte, verifizierte Arbeitsgrundlage
**Ersetzt:** Den Dokumentensatz "Contracts & Blueprints", "Vorarbeit Offline DSP Labor", "Strategisches Arbeitsdokument", "Project Charter and Scope", "ADR-Protokoll", "Execution Plan" und "Engineering Guidelines" einer vorangegangenen KI-Sitzung (Datum unbekannt, vermutlich ohne Zugriff auf den echten Repository-Stand erstellt)
**Repository:** `github.com/Adilinu94/flowrep`, Branch `master` (nicht `main` – siehe Warnung unten)

> **Bevor du hier weiterliest:** Lies zuerst `STATUS_FORTSCHRITT.md` im selben Ordner. Dort steht, was bereits erledigt/in Arbeit ist (mehrere Claude-Instanzen arbeiten parallel an diesem Umbauplan) und welche Fragen noch offen sind – insbesondere, ob der ENG:/Dummy-Stream-Test am Gerät bereits gemacht wurde (höchste Priorität unter den offenen Fragen). Trage dort ein, woran du arbeitest, bevor du anfängst, und hake ab, was fertig ist.

---

## 1. Zweck dieses Dokuments

Dieses Dokument ist der Einstiegspunkt für jede KI (oder jeden Menschen), die im Anschluss an dieses Dokumentenset am FlowRep-Projekt arbeitet. Es erklärt, **warum** dieses Set existiert, **was** sich gegenüber dem vorherigen Plan geändert hat und **wie** die übrigen Dokumente zu benutzen sind.

Kurzfassung für Eilige: Ein vorheriger KI-Plan wollte die komplette regelbasierte Zähl-Logik durch ein Deep-Learning-Modell mit 5-Phasen-Segmentierung ersetzen und jede Nutzer-Kalibrierung abschaffen. Eine unabhängige Analyse (durchgeführt durch Klonen und Lesen des tatsächlichen Repository-Codes sowie durch empirische Nachrechnung der vorgeschlagenen Signalverarbeitung) hat gezeigt, dass dieser Plan (a) auf einem veralteten oder unvollständigen Bild des Projekts basierte, (b) einen konkreten Faktor-100-Rechenfehler im Sensor-Protokoll enthielt und (c) eine Kernannahme (die vorgeschlagene Gravitationstrennung) bei realistischer Rep-Kadenz empirisch nicht wie behauptet funktioniert. Dieses Dokumentenset ersetzt den Plan durch eine korrigierte, schrittweise Variante, die die guten Ideen des ursprünglichen Plans übernimmt, die Fehler behebt und auf dem tatsächlichen, bereits funktionierenden Projektstand aufbaut statt ihn zu verwerfen.

---

## 2. Wichtigste Tatsachenkorrektur: Der Projektstand

Die wichtigste Korrektur betrifft nicht Mathematik, sondern schlicht **den Ist-Zustand des Projekts**. Der vorherige Plan (insbesondere `Execution_Plan.txt`) beschreibt Phase 1 als "Initialisiere das Flutter-Projekt namens flowrep" – als wäre das Repository leer.

Das ist falsch. Der tatsächliche Stand (Branch `master`, nicht `main`) umfasst bereits:

- Eine vollständige Clean-Architecture-Struktur (Domain/Data/Presentation) mit Riverpod-State-Management
- Einen funktionierenden `BleSensorProvider` inklusive gelöstem HyperOS-Notification-Bug (Read-Polling ohne CCCD-Subscription, empirisch gemessene effektive Datenrate von **~73,6 Samples/Sekunde**, nicht 14 Hz)
- Eine verschlüsselte Drift-Datenbank
- Eine funktionierende, aber nachweislich fehlerhafte `WorkoutEngine` mit Guided-Calibration-Modus
- Eine Firmware (M5StickC Plus2, NimBLE), die das 52-Byte-Protokoll bereits stabil sendet
- Eine Python-Simulationsumgebung (`tools/workout_engine_simulation.py`) als etabliertes Test-Sicherheitsnetz
- 18 bereits vergebene ADR-Nummern (`ADR-001` bis `ADR-018`) in `docs/04_ARCHITECTURE_DECISION_RECORDS.md`

**Konsequenz für jede KI, die mit diesem Set arbeitet:** Bevor irgendetwas aus diesem Dokumentenset umgesetzt wird, muss der tatsächliche Stand von `master` gelesen werden – nicht angenommen werden. Wo dieses Set neue ADRs definiert, beginnt die Nummerierung bei **ADR-019**, um keine Kollision mit den bestehenden 18 ADRs zu erzeugen (der vorherige Plan hatte versehentlich eigene ADR-003, ADR-004, ADR-011 und ADR-012 mit völlig anderem Inhalt als die echten, bereits existierenden ADRs gleicher Nummer definiert).

---

## 3. Was konkret falsch war – mit Beleg

### 3.1 Faktor-100-Fehler in der Gyro-Skalierung

`Contracts & Blueprints.txt` definierte: `Wert in rad/s = (int16_Wert * (pi / 180.0))`.

Das reale, bereits produktiv gesendete Protokoll (`docs/reference/protocol.yaml`, Firmware `firmware/src/main.cpp:421`) skaliert Gyro-Rohwerte mit Faktor `0.01` auf deg/s. Ein realer Messwert von 150 deg/s wird als Rohwert `15000` übertragen. Die korrekte Umrechnung ist `15000 * 0.01 * (π/180) ≈ 2,62 rad/s`. Die im alten Plan angegebene Formel ergibt `15000 * (π/180) ≈ 261,8 rad/s` – rechnerisch ca. 15.000 Grad/Sekunde, physiologisch unmöglich. Der Faktor `0,01` fehlte schlicht. Siehe Dokument 03 (Contracts & Blueprints, korrigiert) für die richtige Formel.

### 3.2 Die vorgeschlagene Gravitationstrennung leckt bei realistischer Rep-Kadenz

Der alte Plan (`VORARBEIT_OFFLINE_DSP_LABOR...txt`) behauptete, ein Butterworth-Tiefpass bei 0,2 Hz auf die bereits gefilterten Beschleunigungsachsen isoliere sauber die statische Gravitation, und ein Python/Dart-Zahlenabgleich gebe "100%ige Sicherheit", dass die App später perfekt filtert.

Empirische Nachprüfung (Code und Ergebnisse in Dokument 04): Bei einem **isolierten** Rep mit 10 Sekunden Ruhe davor/danach kehrt das Signal tatsächlich nahe an das Rauschbodenrauschen zurück. Bei einer **realistischen Sequenz von 3 Reps mit nur 1 Sekunde Pause dazwischen** – wie sie in einem echten Satz vorkommt – bleibt das Signal in der Pause bei **~50 % der Peak-Höhe während der Bewegung**, weil der 0,2-Hz-Filter mehrere Sekunden zum Einschwingen braucht und diese Zeit zwischen echten Reps nicht hat. Das ist kein Rauschen, sondern strukturelles Filter-Leck. Die "100%ige Sicherheit"-Aussage war zudem methodisch fragwürdig: `filtfilt` (im Python-Beweis verwendet) ist nicht-kausal und für Echtzeit-Verarbeitung in Dart so nicht direkt portierbar; ein reiner Zahlenabgleich zwischen einer nicht-kausalen Python-Referenz und einer zwangsläufig kausalen Dart-Implementierung ist kein Korrektheitsbeweis.

Ein alternativer, in Dokument 04 empirisch getesteter Ansatz (gyro-gestütztes Gravitations-Tracking statt naivem Tiefpass) verbessert das Pause/Peak-Verhältnis im selben Testszenario von ~0,50 auf ~0,14–0,23 – eine deutliche, aber keine perfekte Verbesserung. Das ist die neue Grundlage für Dokument 03/04, **ausdrücklich mit dem Hinweis, dass echte Hardware-Daten die synthetische Validierung noch bestätigen müssen.**

### 3.3 Die Kernprämisse ("regelbasiert ist physikalisch am Ende") ist nicht belegt

`STRATEGISCHES_ARBEITSDOKUMENT...txt` behauptete als Tatsache, die regelbasierte Engine stoße "physikalisch an ihre Grenzen" und 99 % Genauigkeit sei "mit statischen Thresholds nicht erreichbar". Die tatsächliche Fehleranalyse des echten Codes (siehe Abschnitt 4) fand stattdessen einen konkreten, lokalisierten Implementierungsfehler: Die sorgfältig kalibrierte Schwelle aus der 10-Rep-Guided-Calibration wird durch eine ältere Ein-Rep-Auto-Rekalibrierung überschrieben, sobald nach der Kalibrierung die erste echte Bewegung erkannt wird. Das ist ein behebbarer Bug, kein Beleg für eine grundsätzliche physikalische Grenze regelbasierter Verfahren.

### 3.4 Das Erfolgskriterium war unrealistisch scharf und intern widersprüchlich

`PROJECT_CHARTER_AND_SCOPE...txt` forderte MAE < 0,1 Reps pro 10er-Satz auf einem per Leave-One-Subject-Out (LOSO) ungesehenen Nutzer. Veröffentlichte Vergleichswerte für dieses exakte Problem liegen deutlich darüber: RecoFit (Microsoft Research, 114 Probanden) erreicht ±1 Rep Genauigkeit in 93 % der Fälle, eine ETH-Zürich-Arbeit zu komplexen Übungen 91 %, ein direkt vergleichbares Referenzprojekt (MetaMotion-Datensatz) einen MAE von 1,02. Zusätzlich erfordert eine LOSO-Validierung zwangsläufig Daten von mehreren Personen – das im selben Dokument vorgeschlagene Datensammlungsprotokoll sah aber nur eine einzige Person vor. Dokument 01 (Charter) setzt stattdessen ein literaturgestütztes, in sich konsistentes Ziel.

### 3.5 Unnötige Komplexität: Sample-genaue 5-Phasen-Segmentierung

Das vorgeschlagene ML-Modell sollte jeden einzelnen Messpunkt in eine von 5 Phasen (idle/concentric/holdTop/eccentric/holdBottom) klassifizieren. Keines der geprüften Referenzsysteme (RecoFit, eine ETH-Zürich-Arbeit zu CrossFit-Übungen, ein Open-Source-Projekt mit vergleichbarer Hardware) verwendet eine derart granulare Segmentierung – alle nutzen einfachere Formulierungen (Peak-Detection auf gefiltertem Signal, oder eine binäre Fenster-Klassifikation "Rep-Ende erkannt: ja/nein"). Die 5-Phasen-Variante verlangt zudem deutlich aufwendigeres Labeling (jeder Messpunkt statt nur Rep-Grenzen), ohne dass ein Beleg für einen Genauigkeitsvorteil vorläge.

---

## 4. Was übernommen wurde

Nicht alles am alten Plan war falsch. Folgende Ideen sind in die korrigierten Dokumente eingeflossen:

- **Gravitationskompensation als Konzept.** Die *jetzige*, produktive Engine nutzt rohe Beschleunigungs-Magnitude, die sich bei einer Rotation kaum ändert. Eine echte Gravitationskompensation ist eine sinnvolle Verbesserung – nur eben mit einem Verfahren, das nachweislich mit realistischer Rep-Kadenz funktioniert (siehe 3.2).
- **Python-zuerst-Validierung.** Bevor irgendeine neue DSP- oder Kalibrierungslogik nach Dart portiert wird, wird sie zuerst in Python gegen synthetische *und* möglichst bald reale Daten geprüft. Das entspricht exakt der bereits im echten Projekt etablierten und erfolgreichen Praxis.
- **Systematische Szenario-Datensammlung** (langsame/schnelle/Teil-Wiederholungen, Pausen, Negativklasse). Sinnvoll unabhängig davon, ob am Ende ML zum Einsatz kommt – siehe Dokument 07.
- **Strukturierte Projektdisziplin** (ADRs, "USER ACTION"-Checklisten, iteratives Vorgehen, klare Eskalationsregeln). Diese Praxis war schon im echten Projekt etabliert und wird fortgeführt.

## 5. Was verschoben wurde (nicht verworfen, aber nicht jetzt)

- Vollständiger Wechsel zu einem Deep-Learning-Modell als Ersatz der Zähl-Logik
- Abschaffung jeder Nutzer-Kalibrierung
- Sample-genaue Mehrphasen-Segmentierung
- Multi-Exercise-Erkennung

Diese Punkte sind in Dokument 01 explizit als spätere, optionale Stufen vermerkt – nicht als grundsätzlich falsch, sondern als verfrüht angesichts des aktuellen Projektstands und der aktuell fehlenden Datenbasis.

## 6. Reihenfolge der Dokumente

| # | Dokument | Zweck |
|---|---|---|
| 01 | `PROJECT_CHARTER_AND_SCOPE.md` | Vision, Scope, Erfolgskriterien – die kanonische "Was und Warum"-Quelle |
| 02 | `ARCHITECTURE_DECISION_RECORDS.md` | Neue ADRs (ab ADR-019), die auf den bestehenden 18 aufbauen |
| 03 | `CONTRACTS_AND_BLUEPRINTS.md` | Verbindliche technische Spezifikation (Protokoll, Interfaces, DSP, State Machine) |
| 04 | `DSP_LABOR_PYTHON_VALIDIERUNG.md` | Lauffähiger, getesteter Python-Code samt Messergebnissen |
| 05 | `EXECUTION_PLAN.md` | Schrittweiser Bauplan, beginnend beim echten Ist-Zustand |
| 06 | `ENGINEERING_GUIDELINES_GUARDRAILS.md` | Coding-Standards und Leitplanken für die ausführende KI |
| 07 | `STRATEGISCHES_ARBEITSDOKUMENT_DATENAKQUISITION.md` | Datensammlungsprotokoll |

Jede ausführende KI sollte **zuerst dieses Dokument, dann Dokument 01 und 02** lesen, bevor sie Code anfasst – und in jedem Fall zuerst den echten `master`-Branch inspizieren, statt sich allein auf diese Dokumente zu verlassen.

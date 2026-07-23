# Strategisches Arbeitsdokument: Datenakquisition – FlowRep (korrigierte Version)

**Ersetzt:** `STRATEGISCHES_ARBEITSDOKUMENT_DATENAKQUISITION_UND_DSP_PROOF_OF_CONCEPT.txt` (vorherige KI-Sitzung)

---

## 1. Warum wir überhaupt Daten sammeln

Der ursprüngliche Entwurf begründete die Datensammlung damit, dass regelbasierte Logik "physikalisch an ihre Grenzen" stoße und durch Deep Learning ersetzt werden müsse. Diese Prämisse wird hier **nicht** übernommen (siehe `00_UEBERBLICK_UND_AENDERUNGEN.md`, Abschnitt 3.3). Die Datensammlung bleibt trotzdem sinnvoll – aus einem robusteren Grund:

1. Sie ist die einzige Möglichkeit, die in Dokument 04 rein synthetisch validierte Gravitationskompensation gegen reale Sensor-Charakteristika (Rauschen, Drift, tatsächliche Rotationsachse) zu prüfen.
2. Sie liefert unabhängig vom weiteren Verlauf (regelbasiert bleibt, oder ein klassischer ML-Klassifikator kommt später hinzu, gemäß ADR-021) eine wiederverwendbare Grundlage.
3. Sie ermöglicht Regressionstests mit echten Daten statt nur mit synthetischen Sinuskurven – der in ADR-020 gefundene Bug und der in ADR-019 gefundene Filterfehler wären beide mit realen, aber unauffällig wirkenden Aufnahmen schwer zu erkennen gewesen, wenn man nicht gezielt danach sucht.

---

## 2. Aufnahme-Voraussetzung

Die App benötigt einen einfachen Aufzeichnungsmodus: Start/Stop-Button, der die vom `SignalProcessor` verarbeiteten *und* die rohen Werte inklusive Timestamps in eine CSV-Datei schreibt (Spalten: `timestamp_ms, raw_accel_x, raw_accel_y, raw_accel_z, raw_gyro_x, raw_gyro_y, raw_gyro_z, filtered_accel_x, filtered_accel_y, filtered_accel_z, dyn_magnitude`). Diese Funktion ist ausschließlich für die Entwicklung gedacht und wird im Produktiv-Build versteckt (konsistent mit ADR-010 im echten Repo zu Gesundheitsdaten-Handling).

**Wichtig, im Unterschied zum ursprünglichen Entwurf:** Es werden sowohl die *rohen* als auch die mit der *bisherigen* Pipeline gefilterten Werte gespeichert – nicht nur eine neue, ungetestete Pipeline. Nur so lässt sich alt vs. neu auf denselben Rohdaten vergleichen (siehe Execution Plan, Phase 4).

---

## 3. Aufnahme-Szenarien

Die folgenden Szenarien sind aus dem ursprünglichen Dokument übernommen (sie waren methodisch sinnvoll) und um Szenario F ergänzt, das gezielt das in Dokument 04 empirisch gefundene Problem prüft.

**Szene A – Langsame, kontrollierte Reps.** 10 Bizeps-Curls, jeweils 3 Sekunden konzentrisch, 3 Sekunden exzentrisch, mit klarer Pause zwischen den Reps.

**Szene B – Schnelle, explosive Reps.** 10 Curls mit Schwung, deutlich kürzere Bewegungsdauer.

**Szene C – Teilwiederholungen (Partials).** 10 Wiederholungen, die nur die obere Hälfte der Bewegung ausführen.

**Szene D – Unterbrochener Satz.** 10 Curls, wobei die Hantel nach 5 Wiederholungen für 2 Sekunden abgesetzt und dann weitergemacht wird.

**Szene E – Negativklasse.** 20 Sekunden, in denen der Sensor getragen, aber kein Curl ausgeführt wird (Gehen, Gestikulieren, Gerät zurechtrücken).

**Szene F (neu) – Kurzpausen-Satz, gezielt zur Prüfung des Gravitationsfilters.** 10 Bizeps-Curls in normalem Trainingstempo, mit bewusst kurzer, realistischer Pause von ca. 1 Sekunde zwischen den einzelnen Wiederholungen (kein künstliches Warten auf vollständige Ruhe). Dies ist exakt das Szenario, in dem der ursprünglich vorgeschlagene Tiefpass-Filteransatz in der synthetischen Simulation versagte (Dokument 04). Diese Szene ist **Pflicht**, nicht optional, bevor die Gravitationskompensation als validiert gilt.

**Szene G (neu) – Achsen-Kalibrierungsaufnahme.** Der Sensor wird in der tatsächlichen, für den Nutzer bequemen Trageposition befestigt. Eine einzelne, sehr langsame und übertrieben saubere Curl-Bewegung wird aufgezeichnet, ausschließlich um zu bestimmen, welche Rohachse tatsächlich die größte Gyro-Amplitude zeigt (Verifikation der Modellannahme aus Dokument 03, Abschnitt 3).

---

## 4. Definition of Done für diesen Schritt

Realistisch neu gefasst gegenüber dem ursprünglichen Entwurf (der App-Absturzfreiheit, korrekte CSV-Struktur und einen unmittelbaren Rückgang auf 0,00 im Ruhezustand forderte – letzteres bleibt, ist aber, wie in Dokument 04 gezeigt, ein vergleichsweise leichter Testfall, der allein nicht ausreicht):

1. Die App stürzt während eines 60-sekündigen Recordings nicht ab, das BLE-Polling läuft ohne Verbindungsabbrüche.
2. Bei flach auf dem Tisch liegendem Sensor zeigt `dynMagnitude` einen Wert nahe 0,00 (notwendige, aber nicht hinreichende Bedingung – dieser Test allein hätte den in Dokument 04 gefundenen Fehler nicht aufgedeckt).
3. **Neu, hinreichende Bedingung:** Bei Szene F (Kurzpausen-Satz) liegt `dynMagnitude` in den Pausen zwischen den Reps sichtbar und messbar unter dem Peak-Wert während der Bewegung (konkretes Zielverhältnis wird nach den ersten realen Messungen festgelegt, siehe Execution Plan Phase 2).
4. Die CSV-Datei wird erfolgreich gespeichert, öffnet sich ohne Formatierungsfehler.
5. `flutter analyze` liefert keine Fehler.

Erst wenn alle fünf Punkte erfüllt sind, gilt die Datengrundlage als ausreichend, um die in Dokument 03 spezifizierte Gravitationskompensation gemäß Execution Plan, Phase 3, in Produktivcode zu überführen.

---

## 5. Wie die gesammelten Daten verwendet werden

Unmittelbar: Validierung und Nachkalibrierung des Komplementärfilters (Dokument 04, Execution Plan Phase 2). Mittelfristig, nur falls ADR-021 Stufe 2 relevant wird: Trainingsgrundlage für einen klassischen Übungs-Klassifikator. Die Daten werden so oder so nicht verschwendet, unabhängig vom weiteren technischen Weg – das war die zentrale Stärke des ursprünglichen Vorschlags und wird hier beibehalten.

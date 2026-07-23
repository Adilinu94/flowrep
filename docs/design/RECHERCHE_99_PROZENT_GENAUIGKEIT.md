
# RECHERCHE: Weg zu ~99% Rep-Erkennung & Multi-Exercise-Fähigkeit (2026-07-14)

**Auftrag von Adi:** Gründliche Recherche zu (1) warum die aktuelle Rep-Erkennung inkonsistent über-/unterzählt, (2) wie Test und Algorithmus verbessert werden können, (3) ob Deep Learning sinnvoll ist — insbesondere im Hinblick auf spätere, biomechanisch andere Übungen (z. B. Latzug), (4) Analyse von 5 externen GitHub-Repos, (5) Korrektheitsprüfung bestehender Annahmen im Projekt.

**Methodik:** Alle 5 Repos wurden lokal geklont und der tatsächliche Quellcode gelesen (nicht nur READMEs). GitHub war in dieser Sitzung über das bash-Tool erreichbar (anders als in der vorherigen Sitzung, siehe HANDOFF_CLAUDE_2026-07-12.md Abschnitt 5). Zusätzlich wurde gezielt nach Primärliteratur gesucht (RecoFit, ETH Zürich, weitere).

---

## 1. Kernfrage: Ist Deep Learning sinnvoll?

**Kurzantwort: Nein, nicht jetzt — und wenn später, dann nicht als Ersatz für saubere Signalverarbeitung, sondern als späterer Zusatz.**

Die Belege aus der Literatur zeichnen ein konsistentes Bild:

| Projekt | Ansatz | Ergebnis | Trainingsdaten |
|---|---|---|---|
| **RecoFit** (Morris, Saponas, Guillory, Kelner — Microsoft Research, CHI 2014) | Klassisch: SVM-Klassifikator auf **Autokorrelations-Features** aus Accel+Gyro, Dimensionsreduktion für Orientierungsinvarianz | Segmentierung >95% Precision/Recall, Erkennung 99/98/96% bei 4/7/13 Übungen im Zirkel, **Counting: ±1 Rep in 93% der Fälle** | 114 Teilnehmer, 146 Sessions |
| **Soro, Brunner, Tanner, Wattenhofer (ETH Zürich), Sensors 2019** | Deep Learning: End-to-End-CNN auf rohen Fenstern, **pro Übung eine eigene Counting-CNN** (Recognition-CNN routet zur passenden Counting-CNN) | Klassifikation 99.96%, **Counting: ±1 Rep in 91% der Sätze** | CrossFit, mehrere Teilnehmer (Setup mit dediziertem Datensammel-Protokoll) |
| **MetaMotion-Familie** (TrackFit-AI / SmartLift / ML-Project-Fitness-Tracker, siehe Abschnitt 4.1) | Klassisch: Random Forest auf Feature-Engineering (PCA, Tiefpass, Chauvenet-Ausreißerentfernung, Zeit-/Frequenzbereich), Counting via `scipy.argrelextrema` auf tiefpassgefiltertem Signal | Klassifikation 97–99.4%, Counting MAE ≈ 1.02, „Miscount-Rate" ~5% | **nur 5 Teilnehmer** |
| **Vein** (siehe 4.2) | Deep Learning: 1D-CNN, aber **pro Übung ein eigenes Modell** trainiert | Kein belastbarer Accuracy-Wert im Repo dokumentiert (README: „Machine Learning Model: TODO") | Einzelperson, handmarkiert |

**Die wichtigste Beobachtung, die sich durch alle fünf Projekte zieht — DL wie klassisch:** Es gibt **keine einzige** Referenzimplementierung, die ein universelles Modell/eine universelle Formel für mehrere biomechanisch unterschiedliche Übungen verwendet. Jede zählt pro Übung mit eigenen Parametern oder einem eigenen Modell. RecoFit ist die einzige, die eine gewisse Übungs-Generalisierung erreicht — aber auch dort ist „welche Übung" ein separater, vorgeschalteter Klassifikationsschritt, nicht dieselbe Zählfunktion für alles.

**Praktische Abwägung Datenmenge:** RecoFit hatte 114 Probanden, die ETH-Arbeit ein dediziertes Mehrpersonen-Protokoll, die MetaMotion-Studien „nur" 5 — und genau die 5-Personen-Studien zeigen in ihrem eigenen Fazit, dass Generalisierung auf neue Nutzer der Knackpunkt ist (ML-Project-Fitness-Tracker berichtet einen Abfall von 99.4% auf 98.6% beim Leave-One-Subject-Out-Test — bei nur 5 Personen ist das noch beeindruckend robust, aber jede weitere unbekannte Person ist ein Sprung ins Ungewisse). Ein Einzelentwickler-Projekt wie FlowRep hat realistisch **Trainingsdaten von 1–3 Personen**, nicht 100+. Ein CNN wird auf so wenig Daten entweder recht spezifisch auf Adis eigene Bewegungssignatur passen (schlechte Generalisierung) oder mangels Daten gar nicht sauber konvergieren. Klassische, featurebasierte Verfahren (auch die einfache Peak-Detection, die FlowRep schon nutzt) brauchen dagegen viel weniger Daten, um vernünftig zu funktionieren — das ist der Hauptgrund, warum praktisch jedes kleine/Hobby-Projekt in dieser Recherche (Vein eingeschlossen, trotz CNN) am Ende doch auf handgemachte Parameter oder Pro-Übung-Handanpassung zurückgreift.

**Empfehlung:** Deep Learning ist kein Fehler als Fernziel, aber aktuell die falsche nächste Investition. Die klassische Pipeline (die FlowRep im Kern schon hat) kann mit den unten beschriebenen Verbesserungen realistisch in den Bereich von RecoFit/MetaMotion (93–98%) kommen, mit einem Bruchteil des Aufwands.

---

## 2. Warum zählt FlowRep aktuell falsch? Diagnose + Verbesserungsvorschläge

Adis Beschreibung („mal zu viel, mal zu wenig") deckt sich fast wörtlich mit bekannten Fehlermodi derselben Algorithmusklasse in der Literatur:

### 2.1 Überzählen — vermutlich Doppel-Peaks
Ein einzelner Curl kann in einem naiven kombinierten Signal **zwei** lokale Maxima erzeugen (z. B. eines beim konzentrischen Hochziehen, eines beim exzentrischen Abbremsen). Das deckt sich mit dem „Doppel-Peak"-Testfall, der laut `HANDOFF_AN_NAECHSTE_KI_2026-07-12.md` bereits in der alten Simulation auffiel (`expected=10 counted=13`). RecoFit widmet diesem Problem explizit einen eigenen Baustein („false peak rejection"). Die `_minPeakDistanceSamples`-Entprellung (~164 ms) allein reicht dafür oft nicht, da ein ganzer Rep-Zyklus 1–3 s dauert — das Problem sitzt eher in der Signalform selbst als im Timing.

### 2.2 Unterzählen — vermutlich Schwelle/Filter zu grob für die tatsächliche Bewegungsamplitude
Ein zu hoher `peakThreshold` relativ zur individuellen Bewegungsgröße, oder ein EMA-Filter, der bei langsamen, kontrollierten Reps den Peak zu stark glättet. Interessant: Im synthetischen Test besteht „Langsame Reps" laut Simulation bereits (`expected=8 counted=8`) — das Unterzählen auf echter Hardware ist also vermutlich kein reines Filterproblem, sondern hängt mit der Diskrepanz zwischen synthetischen und echten Signalen zusammen (echtes Rauschen, echte Amplitudenschwankung), nicht mit der Filterlogik an sich.

### 2.3 Konkrete algorithmische Verbesserungen, mit Beleg

1. **Periodizitäts-Check per Autokorrelation als zweite Prüfebene** (nicht als Ersatz für Peak-Detection, sondern als Filter obendrauf): RecoFit baut seine Kern-Features genau darauf auf. Ein einfaches, embedded-taugliches Referenzbeispiel für den Ansatz „Magnitude → Autokorrelation → Periodizität validieren → erst dann zählen" ist der Schrittzähler-Algorithmus [nerajbobra/embedded_pedometer](https://github.com/nerajbobra/embedded_pedometer) (Fixed-Point, C, Embedded) — konzeptionell fast 1:1 auf FlowReps Situation übertragbar. Praktisch: Wenn die aktuelle Kadenz (aus der Autokorrelation der letzten ~3–5 Sekunden combinedSignal) bekannt ist, lässt sich ein Kandidaten-Peak, der nicht zur etablierten Rhythmik passt (zu früh, zu schwach), verwerfen — das würde sowohl Doppel-Peaks als auch Justier-/Zufallsbewegungen (Frage 8 aus `FRAGEN_FUER_SCHLAUE_KI.md`) abfangen, ohne die bestehende Peak-Logik zu ersetzen.
2. **Signal-Richtung statt nur Magnitude nutzen:** Ein echter Curl hat eine Gyro-Rotation, die zuerst in eine Richtung, dann zurück geht (nicht nur „hoch"). Aktuell fließt nur `gyroMagnitude` ein (Betrag, richtungslos). Ein vorzeichenbehaftetes Gyro-Signal um die Ellenbogen-Achse könnte einen sauberen Rep von einem Wackel-Doppelpeak unterscheiden — deckt sich mit Frage 3 aus `FRAGEN_FUER_SCHLAUE_KI.md`.
3. **Alternative Sequenzmodelle als Eskalationsstufe, falls Schwellenwerte weiter zu fragil bleiben:** Das RecoFit-Paper erwähnt selbst frühere Arbeiten (Chang et al.), die Counting über Matched Filter + Hidden Markov Model statt fixer Schwellen gelöst haben. Das ist mehr Aufwand als eine Schwelle, aber deutlich weniger als ein CNN, und würde Adis Wunsch nach Robustheit adressieren, ohne gleich zu Deep Learning zu springen.
4. **Pro-Übung-Parameter-Profile statt globaler Konstanten** — siehe Abschnitt 2.4/6, direkt durch den MetaMotion-Code belegt.

### 2.4 Wichtigster Architektur-Punkt: Pro-Übung-Profile jetzt einführen, nicht erst bei Übung #2

Der MetaMotion-Code (Abschnitt 4.1) verwendet **pro Übung unterschiedliche Filter-Cutoffs und teils sogar unterschiedliche Signalkanäle**: Bench/Squat/OHP/Deadlift nutzen `acc_r` (Beschleunigungs-Magnitude) mit Cutoff 0.35–0.4, aber **Row nutzt `gyr_x`** (Gyro-Achse, nicht Magnitude!) mit Cutoff 0.63–0.65. Das ist ein sehr konkreter, code-belegter Beweis dafür, dass „eine Formel für alles" strukturell nicht reicht, sobald Übungen dazukommen. FlowReps `combinedSignal = accelMag + gyroMag*0.05` ist für Bizeps-Curls plausibel getunt, aber es gibt keinen Grund anzunehmen, dieselbe Formel funktioniert für Latzug (ganz andere Bewegungsebene, andere Extremität-Rotation).

**Empfehlung:** Eine `ExerciseProfile`-Abstraktion (pro Übung: bevorzugter Kanal/Formel, Filter-Parameter, Schwellenwert-Perzentil, erwartete Rep-Dauer) jetzt einführen, solange es nur eine Übung gibt — das ist der günstigste Zeitpunkt dafür, und macht Übung #2 zu „ein Profil hinzufügen" statt „Pipeline umbauen".

---

## 3. Wie den Test verbessern?

1. **Ground-Truth aus echter Hardware, nicht nur synthetisch:** Die Python-Simulation testet aktuell nur konstruierte Signale. Ein einfacher Marker-Workflow wie in Veins `collectData.py`/`collectRepetitionMarkedData.py` (Taste drücken = Rep-Grenze) würde erlauben, echte M5StickC-Aufnahmen mit einem verlässlichen Ground-Truth-Rep-Count zu labeln — und diese dann als Regressionstests in die Simulation und/oder direkt in die Dart-Tests einzuspeisen. Das schließt die Lücke, die `HANDOFF_AN_NAECHSTE_KI_2026-07-12.md` explizit benennt: „Ohne CALIB-Logs/echte Daten ist jede Parameteränderung Ratespiel."
2. **MAE statt Pass/Fail als Metrik:** Alle drei MetaMotion-Repos und die ETH-Arbeit nutzen „Mean Absolute Error zwischen tatsächlichen und gezählten Reps" als Hauptmetrik, nicht nur bestanden/nicht bestanden. Das gibt ein kontinuierliches Signal, ob eine Änderung tatsächlich hilft, statt nur ob ein einzelner Testfall (10 Reps) zufällig durchläuft.
3. **Mehr als eine Testperson, sobald möglich:** ML-Project-Fitness-Tracker macht explizit den Punkt, dass Bewegungssignaturen zwischen Personen variieren (Armlänge, Tempo, Fitnesslevel) und ein auf eine Person kalibriertes System sich nicht automatisch generalisiert. FlowRep testet aktuell nur mit Adi selbst — schon 2–3 weitere Testpersonen (auch informell, Freunde/Familie) würden zeigen, ob der aktuell kalibrierte Threshold personenspezifisch overfittet ist.
4. **Stress-Test-Kategorien erweitern** (einiges davon existiert laut Simulation-Output schon — Cheat-Rep-Szenario, Robustheitssuite mit Zittrig/Ausreißer/Tempo/Fehlbewegung — das ist bereits ein guter Ausgangspunkt): gezielt Doppel-Peak-Reps, sehr langsame Reps, Justierbewegungen am Handgelenk und „Reps mit Pause in der Mitte" als eigene benannte Kategorien führen, damit ein Regressions-Report sofort zeigt, welche Kategorie durch eine Änderung besser/schlechter wird.

---

## 4. Repo-Analysen

### 4.1 TrackFit-AI, SmartLift-Analysis-Project, ML-Project-Fitness-Tracker — dieselbe Familie

**Bestätigt (war im vorherigen Handoff nur „Ersteindruck, nicht verifiziert"):** Alle drei sind unabhängige Nachbauten/Forks **desselben** Kursprojekts von Dave Ebbelaar (Vrije Universiteit Amsterdam / datalumina.com). Identischer Datensatz (MetaMotion-Wristband, 5 Teilnehmer A–E, Bench/Squat/OHP/Deadlift/Row, 12.5 Hz Accel / 25 Hz Gyro, auf 5 Hz aggregiert), identische Pipeline-Struktur (Dateinamen, Ordnerstruktur), identischer Kern-Algorithmus. Ein Diff der drei `count_repetitions.py`-Dateien zeigt: bis auf Formatierung/Variablennamen ist der Rep-Counting-Code **wortwörtlich identisch**.

- **Klassifikation:** Random Forest auf Feature-Engineering (Chauvenet/IQR/LOF-Ausreißerentfernung, Butterworth-Tiefpass, PCA, Zeit-/Frequenzbereichs-Features via Fourier). Ergebnisse across der drei Repos: 97% (TrackFit-AI) / 98.51% (SmartLift) / 99.4% Random-Split, 98.6% Leave-One-Subject-Out (ML-Project-Fitness-Tracker) — dieselbe Grunddatenbasis, leicht unterschiedliche Pipeline-Varianten und Zufallsseeds erklären die Differenz.
- **Rep-Counting:** `scipy.signal.argrelextrema` (lokale Maxima) auf Butterworth-tiefpassgefiltertem Signal, **pro Übung unterschiedlicher Cutoff und teils unterschiedlicher Kanal** (siehe 2.4). MAE ≈ 1.02, SmartLift nennt zusätzlich eine „Miscount-Rate von 5%" und den expliziten Hinweis: „für optimale Genauigkeit müssen Modelle pro Übung individuell zugeschnitten werden."

**Gefundener Bug (Korrektheits-Check):** In TrackFit-AI und SmartLift-Analysis-Project vergleicht die finale Benchmark-Schleife in `count_repetitions.py` `subset['category'].iloc[0]` gegen Übungsnamen wie `'squat'`/`'row'`/`'ohp'` — aber laut beider READMEs ist `category` die **Intensität** (heavy/medium), nicht der Übungsname (das ist `label`). Diese Bedingung dürfte strukturell nie zutreffen, wodurch die eigentlich pro Übung vorgesehene Cutoff-/Kanal-Anpassung in der finalen MAE-Berechnung vermutlich nie greift und für **jede** Übung der Default (`acc_r`, cutoff=0.4) verwendet wird — obwohl die weiter oben im Skript einzeln aufgerufenen `count_reps(...)`-Beispiele durchaus korrekt pro Übung parametrisiert sind. **ML-Project-Fitness-Tracker hat exakt diesen Punkt korrigiert** (`subset["label"]` statt `subset["category"]`). Das ist nicht sicher live nachgestellt (dafür fehlen die Rohdaten), aber aus dem Code und den README-Definitionen eindeutig ableitbar. Lehre: Die MAE-1.02-Zahl der ersten beiden Repos ist mit Vorsicht zu genießen — sie könnte auf einer effektiv nicht pro-Übung-optimierten Konfiguration beruhen und wäre mit korrekt greifender Pro-Übung-Anpassung potenziell sogar noch besser.

**Nützlichkeit für FlowRep: mittel.** Die Feature-Engineering-/Klassifikations-Pipeline (Ausreißerentfernung, PCA, Zeit-/Frequenzfeatures) ist ein sehr sauberes Vorbild, **falls/wenn** FlowRep später automatische Übungserkennung braucht (aktuell hardcoded `exerciseId='bicep_curl'`). Für das aktuelle Kernproblem (robustes Counting einer einzelnen Übung in Echtzeit) ist der Ansatz konzeptionell identisch zu dem, was FlowRep schon tut (Tiefpass + lokale-Maxima-Peak-Detection) — nützlich als Bestätigung, dass der grundsätzliche Ansatz richtig ist, aber kein Sprung nach vorne.

### 4.2 Vein — am nächsten an FlowReps eigener Situation

**Nützlichkeit: hoch — das relevanteste der fünf Repos**, weil es (anders als die MetaMotion-Familie) **eigene, selbstgebaute Hardware** verwendet (Arduino Nano + MPU6050 IMU + HC-05 Bluetooth) statt eines kommerziellen Forschungs-Wristbands — architektonisch die engste Analogie zu FlowReps M5StickC+BMI270-Aufbau.

- **Zwei getrennte Modelle**, beide 1D-CNN (Conv1D×2 → Dropout → MaxPooling → Dense → Softmax), Keras/TensorFlow:
  - *Exercise Recognition* (`exercise_recognition_model.py`): Fenstergröße 150 Samples, 6 Kanäle (Yaw/Pitch/Roll + 3-Achsen-Accel — kein rohes Gyro-Rate-Signal, sondern bereits fusionierte Orientierung).
  - *Repetition Counting* (`repetition_model.py`): **eigenes, kleineres Fenster (30 Samples)**, binäre Klassifikation „Rep" vs. „None" pro Sliding-Window-Ausschnitt — kein Peak-Detector, sondern ein Fenster-Klassifikator.
  - Beide Modelle werden **pro Übung einzeln trainiert** (`-e bicep-curl` Flag Pflicht) — bestätigt erneut den roten Faden aus Abschnitt 1.
- **Datensammlung:** Manuell per Tastatur live während der Aufnahme markiert (Shift = Start/Stop, Enter = Rep-Grenze) — ein pragmatischer, für ein Einzelperson-Projekt reproduzierbarer Ansatz, den FlowRep für den in Abschnitt 3 vorgeschlagenen Ground-Truth-Datensatz direkt adaptieren könnte.
- **Unterstützte Übungen aktuell:** Bicep Curl, Lateral Raises, Dumbbell Row — Bizeps-Curl ist also exakt FlowReps Startübung.
- **Einschränkung:** Das README selbst sagt unter „Machine Learning Model": „TODO" — es gibt keine dokumentierte Accuracy-Zahl fürs Repo, nur den Code. Kein Ersatz für eigene Verifikation, aber die Architektur ist eine gute Inspirationsquelle.
- Zitiert selbst ein einschlägiges Sensors-Paper (Soro et al., siehe Abschnitt 5) als Related Work — dessen Recherche hat sich für diese Analyse als sehr ergiebig herausgestellt.

### 4.3 whar-datasets (teco-kit) — Infrastruktur, aber kein Gym-Rep-Counting

**Bestätigt:** TECO = Lehrstuhl für Pervasive Computing Systems am KIT Karlsruhe (frühere Bezeichnung „Telecooperation Office"), Publikation bei UbiComp 2025 (Burzer, King, Riedel, Beigl, Röddiger).

- Es ist eine **generische HAR-Datensatz-Ladebibliothek** (Download, Parsing, Windowing, Splitting inkl. LOSO/K-Fold, PyTorch/TensorFlow-Adapter) für **37 öffentliche Alltagsaktivitäts-Datensätze** (WISDM, UCI-HAR, PAMAP2, MHEALTH, HHAR, usw.).
- **Explizit geprüft und bestätigt: keine der 37 Datensatzintegrationen und keine Codezeile in der Bibliothek behandelt Gym-Wiederholungszählung.** Der einzige Treffer für „repetition" im gesamten Quellcode ist ein Datei-Parsing-Feld für das Berkeley-MHAD-Datenformat (Anzahl Wiederholungen eines Aufnahme-Trials, nicht Gym-Reps).
- **Nützlichkeit: gering bis mittel.** Kein direkter Trainingsdatensatz für Gym-Übungen. Der Wert liegt eher in (a) der sauberen LOSO-Split-Methodik als Vorbild für „Generalisiert das auf eine neue Person?"-Tests (genau das, was ML-Project-Fitness-Tracker manuell einmalig gemacht hat), und (b) als möglicher Pretraining-/Transfer-Learning-Baustein, falls FlowRep irgendwann doch ein neuronales Netz trainieren will und mit generischen Bewegungsdaten vorwärmen möchte — aber das ist für die aktuelle Priorität (eine Übung robust zählen) nicht relevant.

---

## 5. Relevante Literatur (primäre Quellen, nicht nur Sekundärzitate)

- **Morris, D., Saponas, T. S., Guillory, A., & Kelner, I. (2014). RecoFit: Using a Wearable Sensor to Find, Recognize, and Count Repetitive Exercises. CHI 2014.** https://www.microsoft.com/en-us/research/publication/recofit-using-wearable-sensor-find-recognize-count-repetitive-exercises/ — SVM + Autokorrelations-Features, wrist-worn, 114 Teilnehmer. Shipped als Teil des Microsoft Band.
  - **Öffentlicher Datensatz** (Bonus-Fund, nicht in Adis ursprünglicher Liste): https://github.com/microsoft/Exercise-Recognition-from-Wearable-Sensors — Accel+Gyro von 200+ Teilnehmern, diverse Gym-Übungen, Handgelenk-getragen. Deutlich näher an FlowReps Setup (Handgelenk, viele Übungstypen) als der MetaMotion-Datensatz (5 Personen, nur Langhantel-Übungen). Könnte als externe Validierungs-/Trainingsquelle interessant sein, falls später doch Richtung ML/Multi-Exercise gegangen wird.
- **Soro, A., Brunner, G., Tanner, S., Wattenhofer, R. (2019). Recognition and Repetition Counting for Complex Physical Exercises with Deep Learning. Sensors 19(3), 714.** https://www.mdpi.com/1424-8220/19/3/714 (ETH Zürich) — von Vein zitiert. End-to-End-CNN, 10 CrossFit-Übungen, 99.96% Klassifikation, 91% Counting ±1 Rep über separate Pro-Übung-CNNs.
- **„Sensor-Based Gym Physical Exercise Recognition: Data Acquisition and Experiments" (2022), MDPI Sensors 22(7), 2489.** https://www.mdpi.com/1424-8220/22/7/2489 — LSTM auf Sliding-Windows, explizit mit separaten Modellen pro Muskelgruppe experimentiert.
- **Skawinski, K., Roca, F. M., Findling, R. D., Sigg, S. (2019). Workout Type Recognition and Repetition Counting with CNNs from 3D Acceleration Sensed on the Chest.** CNN-Ansatz mit einem einzelnen Brust-Beschleunigungssensor — andere Sensorposition als FlowRep, aber methodisch relevant für „reicht ein einzelner Sensor + CNN".
- **Autokorrelations-/Periodizitäts-Ansatz als Alternative zu reiner Peak-Detection:** konzeptionelles Referenzbeispiel (Embedded, Fixed-Point C) unter https://github.com/nerajbobra/embedded_pedometer — nicht gym-spezifisch, aber das Muster „Magnitude → Autokorrelation → Periodizität validieren → zählen" ist direkt übertragbar.

---

## 6. Korrektheits-Check bestehender Annahmen im Projekt

| Aussage | Status | Anmerkung |
|---|---|---|
| TrackFit-AI ≈ „Full Stack ML Tracker"-Kursprojekt, klassisches ML, ~97% | Bestätigt | Jetzt mit zwei weiteren unabhängigen Repos derselben Familie gegengeprüft, inkl. Ursprungsnennung (Dave Ebbelaar, VU Amsterdam) direkt in zwei der drei READMEs |
| whar-datasets = TECO Karlsruhe, Datensatz-/Benchmark-Repo | Bestätigt | Zusätzlich geprüft: keine Gym-Rep-Counting-Funktionalität enthalten (explizit im Code verifiziert) |
| RecoFit als möglicher Bezugspunkt für die 30.-Perzentil-Kalibrierungsfrage (Frage 5, `FRAGEN_FUER_SCHLAUE_KI.md`) | Teilweise | RecoFit selbst verwendet **keine** perzentilbasierte Schwellenkalibrierung, sondern gelernte Segmentierung (SVM). Für die konkrete „30. oder 25. oder 40. Perzentil"-Frage liefert die Literatur keine belastbare empirische Zahl — das bleibt ein Ingenieursentscheid, keine zitierbare Norm. Sollte im Projekt auch so behandelt werden (nicht als „literaturbelegt" hinstellen). |
| EMA-Zeitkonstante ≈ 120ms bei 14 Hz/α=0.6 (Frage 2) | Bestätigt | Rechnung 1/(14×0.6) ≈ 119ms ist die Standardnäherung τ≈Δt/α für EMA als Tiefpass, korrekt angewendet |
| Gyro-Gewichtung-Rechenbeispiel combinedSignal=6.5 (Frage 1) | Bestätigt | Arithmetik korrekt (1.5 + 100×0.05) |
| **Neu, nicht vorher im Projekt dokumentiert:** Bug in TrackFit-AI/SmartLift `count_repetitions.py` | Gefunden | Siehe Abschnitt 4.1 — betrifft nicht FlowRep direkt, aber relevant für die Bewertung, wie viel Vertrauen die MAE-Zahl dieser beiden Repos verdient |
| **Neu:** RecoFit ist klassisches ML, nicht Deep Learning | Präzisiert | Beantwortet Frage 10 aus `FRAGEN_FUER_SCHLAUE_KI.md` konkret mit Primärquelle — wichtig, weil RecoFit oft informell als „das Beispiel, das zeigt dass es geht" zitiert wird, ohne dass klar ist, dass es explizit *kein* Deep-Learning-System ist |

---

## 7. Priorisierte Roadmap (Empfehlung)

1. *(unabhängig von dieser Recherche, weiterhin offen)* Ausstehende lokale Verifikation + Commit (`flutter analyze/test`, Python-Simulation, Git).
2. *(weiterhin PRIO 1 aus dem Handoff)* „0 Reps nach 1 Curl im Normalbetrieb" diagnostizieren (`_diagEngineSampleCount` sichtbar machen).
3. Ground-Truth-Datensammlung vom echten Gerät (Abschnitt 3.1) + MAE-Metrik einführen — schafft die Grundlage, um jede weitere Änderung tatsächlich zu messen statt zu erraten.
4. Autokorrelations-/Periodizitäts-Check als zusätzliche Filterebene über der bestehenden Peak-Detection (Abschnitt 2.3.1) — adressiert Über-/Unterzählen direkt, ohne die bewährte Grundarchitektur zu verwerfen.
5. `ExerciseProfile`-Abstraktion einführen, **bevor** Übung #2 (Latzug) angegangen wird (Abschnitt 2.4).
6. Erst danach, falls gewünscht: klassisches ML (Random Forest o. ä., nach MetaMotion-Vorbild) für automatische Übungserkennung, sobald ≥2 Übungen + etwas Trainingsdaten existieren.
7. Deep Learning (CNN pro Übung, nach Vein/ETH-Vorbild) als spätere Eskalationsstufe, nur falls (a) klassische Verfahren trotz guter Daten an einer Genauigkeitsgrenze hängen bleiben UND (b) ein Trainingsdatensatz von realistischer Größe existiert (mehrere hundert gelabelte Reps, idealerweise >1 Person).

---

## 8. Reflexion: Was ich aus dieser Recherche mitnehme

Der mit Abstand wertvollste Fund ist nicht „Deep Learning ja/nein", sondern dass **jedes einzige** untersuchte System — klassisch oder DL, Forschungsprojekt oder Hobby-Repo — Wiederholungszählung pro Übung spezialisiert, nie universell. Das bestätigt Adis eigene Intuition (Bizeps-Curl ≠ Latzug) direkt und sollte die Roadmap stärker prägen als die DL-Frage: Die `ExerciseProfile`-Architektur jetzt zu bauen, solange es nur eine Übung gibt, ist die höchste Hebelwirkung pro Aufwand in dieser ganzen Recherche.

Zweitens: Die tatsächliche Code-Lektüre (statt nur READMEs) hat einen echten, bisher unbemerkten Bug in zwei der fünf Repos aufgedeckt und die informelle Vorstellung „RecoFit = das ML-Beispiel" auf „RecoFit = SVM + Autokorrelation, kein Deep Learning" präzisiert. Beides wäre bei einer oberflächlichen Zusammenfassung durchgerutscht — ein Argument dafür, bei „prüfe auf Korrektheit"-Anfragen wo möglich auf Primärquellen/Code zu gehen statt auf Sekundärzusammenfassungen zu vertrauen, auch im weiteren Projektverlauf.

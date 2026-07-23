# Architecture Decision Records – Fortsetzung ab ADR-019

**Ersetzt:** Die ADR-003, ADR-004, ADR-011 und ADR-012 aus dem Dokument `ARCHITEKTUR_ENTSCHEIDUNGSPROTOKOLL...txt` der vorherigen KI-Sitzung. **Diese vier Nummern sind im echten Repository bereits mit anderem Inhalt belegt** (`docs/04_ARCHITECTURE_DECISION_RECORDS.md`, Stand: `ADR-001` bis `ADR-018`). Sie dürfen nicht erneut vergeben werden.

**Regel für die ausführende KI (unverändert aus dem echten Repo-Prozess):** ADRs werden nie stillschweigend überschrieben. Eine neue Entscheidung erhält eine neue Nummer; eine ersetzte alte ADR wird als "Ersetzt durch ADR-XXX" markiert, nicht gelöscht. Bevor eine KI eine neue ADR anlegt, prüft sie `docs/04_ARCHITECTURE_DECISION_RECORDS.md` im echten Repo auf die aktuell höchste vergebene Nummer – dieses Dokument geht vom Stand ADR-018 aus, könnte also inzwischen veraltet sein.

---

## ADR-019: Gravitationskompensation via gyro-gestütztem Tracking statt naivem Tiefpass

**Kontext:** Die aktuelle `WorkoutEngine` zählt auf Basis der rohen Beschleunigungs-Magnitude. Bei einer Rotation um das Handgelenk (Bizeps-Curl) verschiebt sich die Erdschwerekomponente zwischen den Sensorachsen, wodurch die Magnitude nur schwach auf die eigentliche Bewegung reagiert (in realen Messungen nur ca. 0,2 g Exkursion). Ein früherer Vorschlag, dies durch einen zusätzlichen Tiefpassfilter (Grenzfrequenz 0,2 Hz) auf den bereits gefilterten Beschleunigungsachsen zu lösen ("langsame Signalanteile = Gravitation"), wurde geprüft und empirisch verworfen: Bei realistischer Rep-Kadenz (mehrere Reps mit nur ca. 1 Sekunde Pause dazwischen, wie in einem echten Satz) braucht dieser Filter mehrere Sekunden zum Einschwingen und lässt in der Pause zwischen zwei Reps ein Residuum von rund 50 % der Peak-Höhe stehen – er trennt Ruhe und Bewegung damit kaum besser als das bestehende Verfahren.

**Korrektur (Cross-Check gegen die im selben Repository bereits existierende ADR-004, nachträglich ergänzt):** Die Aussage "reagiert nur schwach, ca. 0,2g Exkursion" stimmt ausschließlich für die reine Beschleunigungs-Magnitude. Sie beschreibt NICHT das tatsächlich deployte `combinedSignal` aus `signal_processor.dart` (`accelMag + gyroMag × gyroWeight`, `gyroWeight=0.05`). ADR-004 dokumentiert bereits, dass genau dieses 0,2g-Problem am 12.07. durch diesen Gyro-Term behoben wurde (Verstärkung um Faktor 5–20 während echter Curls). Die Motivation dieser ADR ist damit nicht falsch, aber unvollständig – siehe ergänzte Validierung unten, die gegen die tatsächlich deployte Formel getestet wurde, nicht nur gegen den bereits verworfenen Tiefpass.

**Entscheidung:** Statt die Gravitationsrichtung aus der Signal-*Geschwindigkeit* zu schätzen (Tiefpass), wird sie aus der tatsächlich gemessenen *Rotation* (Gyroskop) verfolgt: Ein Schätzwert für den Gravitationsvektor wird bei jedem neuen Sample um den vom Gyroskop gemessenen Winkel mitgedreht (Rotationsschritt) und nur sanft in Richtung des aktuellen Accelerometer-Messwerts korrigiert – wobei diese Korrektur umso schwächer gewichtet wird, je weiter der aktuelle Beschleunigungsbetrag von 9,81 m/s² abweicht (also gerade dann schwach, wenn viel dynamische Beschleunigung vorliegt und der Accelerometer-Wert unzuverlässig als Gravitationsreferenz ist). Dies ist ein vereinfachter Komplementärfilter, wie er in der IMU-/AHRS-Literatur üblich ist – keine neue Erfindung, aber auch keine bloße Tiefpassfilterung.

**Validierung:** Siehe `04_DSP_LABOR_PYTHON_VALIDIERUNG.md`. Im selben Testszenario (3 Reps, 1 s Pause) sinkt das Verhältnis Pause-Residuum/Peak von ca. 0,50 (Tiefpass-Ansatz) auf ca. 0,14–0,23 (Komplementärfilter) – eine deutliche, quantifizierte Verbesserung, aber ausdrücklich **keine perfekte Trennung**. Dies ist eine synthetische Validierung; sie ersetzt keine Prüfung gegen real aufgezeichnete Hardware-Daten.

**Ergänzender, entscheidender Vergleich (nachträglich durchgeführt):** Der obige Vergleich testet nur "verworfener Tiefpass vs. neuer Komplementärfilter" – nicht den eigentlich relevanten Vergleich gegen die AKTUELL DEPLOYTE Formel (EMA-gefiltert, `accelMag + gyroMag×0.05`). Auf demselben synthetischen Testszenario erreicht die bereits laufende Formel ein Pause/Peak-Verhältnis von ca. **0,09** – besser als der hier vorgeschlagene Komplementärfilter (0,14–0,23). Grund: Gyro-Magnitude ist bereits ein direktes, verzögerungsfreies Maß für "dreht sich der Arm gerade", während der Komplementärfilter bei kurzen Pausen mit leicht veränderter Armhaltung erst neu einschwingen muss. **Konsequenz: Phase 2/3 (Dokument 05) dürfen erst fortgesetzt werden, wenn der Komplementärfilter auch gegen diese Baseline gewinnt – auf echten Daten, nicht nur synthetisch.** Details und Python-Code: Dokument 04, neues Skript 1b.

**Konsequenzen:** Die absolute Skala des resultierenden Magnitude-Signals unterscheidet sich von der bisherigen (deutlich niedrigere Peak-Werte, da weniger Gravitationsleck fälschlich als Bewegung gezählt wird). Alle bestehenden Schwellenwerte (`peakThreshold`, `minThresholdAboveBaseline` etc.) müssen nach Einführung dieses Filters neu kalibriert werden – sie sind nicht 1:1 übertragbar. Die Implementierung erfordert eine 2D-Rotation pro Sample (Sinus/Kosinus des inkrementellen Winkels), was mehr Rechenaufwand als ein einfacher IIR-Tiefpass bedeutet, aber bei ~74 Hz effektiver Sample-Rate auf einem modernen Smartphone unproblematisch ist.

---

## ADR-020: Bugfix – Guided-Calibration-Schwellenwert darf nicht durch Auto-Rekalibrierung überschrieben werden

**Kontext:** Code-Analyse der bestehenden `WorkoutEngine` (`app/lib/domain/workout_engine.dart`) zeigt: Der Konstruktor-Parameter `calibrationReps` hat den Default-Wert `1` und wird an keiner der beiden Instanziierungsstellen im App-Code (`home_screen.dart`, auch nicht beim Laden eines persistierten Kalibrierungswerts) überschrieben. Der `idle`-State-Handler unterscheidet nicht, ob bereits eine Guided Calibration stattgefunden hat: Jede Bewegung, die aus dem `idle`-Zustand heraus die Aktivierungsschwelle überschreitet, löst den `calibrating`-Zustand aus, der nach genau `calibrationReps` (= 1) Wiederholungen den Schwellenwert komplett neu setzt – basierend auf dem Peak dieser einen Wiederholung. Da der Zustand nach `_finishGuidedCalibration()` auf `idle` zurückgesetzt wird (ebenso nach jedem `handleReconnect()`), wird die sorgfältig aus 10 Reps ermittelte Guided-Calibration-Schwelle bei der ersten folgenden Bewegung durch einen Wert ersetzt, der nur auf einem einzigen, potenziell untypischen Rep beruht. Das Konzeptdokument `docs/CALIBRATION_MODE_CONCEPT.md` (echtes Repo) beschreibt explizit, dass nach der Kalibrierung *kein* separater Kalibrierungsschritt mehr folgen soll – der Code setzt das nicht um.

**Entscheidung:** Der `idle`-State-Handler wird um eine Prüfung ergänzt, ob bereits eine gültige (Guided- oder frühere) Kalibrierung vorliegt. Ist das der Fall, führt die erste Bewegung direkt in den `active`-Zustand (wie im `paused`-Zustand bereits implementiert), **nicht** in `calibrating`. Der Ein-Rep-Auto-Kalibrierungspfad bleibt ausschließlich für den Fall reserviert, dass tatsächlich noch nie kalibriert wurde.

**Konsequenzen:** Minimal-invasive Änderung an bestehendem Code (ein zusätzliches Zustandsflag, eine angepasste Bedingung), kein Architekturwechsel. Muss vor der Implementierung in der Python-Simulation reproduziert werden (siehe ADR-022) und nach der Implementierung dort als Regressionstest verbleiben.

---

## ADR-021: Gestufte Einführung von Machine Learning – klassisch vor Deep Learning

**Kontext:** Ein früherer Plan sah den sofortigen, vollständigen Ersatz der regelbasierten Zähl-Logik durch ein Deep-Learning-Modell (1D-CNN/LSTM, Sequence-to-Sequence-5-Phasen-Segmentierung) vor. Ein Literatur- und Referenzprojektvergleich zeigt: Für eine einzelne, gut definierte Übung erreichen rein klassische Verfahren (Butterworth-Filter + Peak-Detection, ergänzt um klassische ML-Klassifikatoren wie Random Forest für Übungserkennung) publizierte Genauigkeiten in derselben Größenordnung wie Deep-Learning-Ansätze (RecoFit: ±1 Rep in 93 % der Fälle ohne Deep Learning; ein Vergleichsfall in einer ETH-Zürich-Studie: klassischer Random Forest erreichte 99 % bei 5 Übungen, ein CNN bei 50 Übungen nur noch 92,1 %). Deep Learning zeigt seinen Vorteil vor allem bei wachsender Übungsvielfalt, nicht bei einer einzelnen Übung.

**Entscheidung:** Machine Learning wird, falls überhaupt, stufenweise eingeführt:
1. Regelbasiert + gyro-gestützte Gravitationskompensation für die aktuelle Einzelübung (Bizeps-Curl) – siehe ADR-019/020.
2. Bei Erweiterung auf mehrere Übungen: klassischer Klassifikator (z. B. Random Forest auf Zeit-/Frequenzbereichs-Features) zur Übungserkennung, der pro Übung unterschiedliche, bereits etablierte Zählparameter auswählt.
3. Nur falls Stufe 2 bei wachsender Übungsvielfalt nachweislich an Grenzen stößt: ein kompaktes 1D-CNN auf einem gleitenden Zeitfenster (keine sample-genaue 5-Phasen-Segmentierung, sondern eine einfachere, in der Literatur validierte Formulierung wie Rep-Boundary-Erkennung).

**Konsequenzen:** Kein TFLite-Modell, keine Python-Trainingspipeline und kein `IMlEngine`-Interface sind für den unmittelbar nächsten Schritt erforderlich. Diese ADR ersetzt inhaltlich die Absicht, die im ursprünglichen (kollidierenden) ADR-004-Entwurf der vorherigen Sitzung formuliert wurde, unter neuer Nummer.

---

## ADR-022: Testmethodik – Python-Simulation muss Mehrfach-Rep-Sequenzen mit kurzen Pausen abdecken

**Kontext:** Der ursprüngliche Fehler in ADR-019 (Gravitationsfilter-Leck) und der in ADR-020 beschriebene Kalibrierungs-Bug hätten beide durch eine ausreichend realistische Simulation vor der Implementierung gefunden werden können. Beide sind Musterbeispiele für Fehler, die nur bei **Interaktion mehrerer, zeitlich eng aufeinanderfolgender Ereignisse** auftreten (mehrere Reps mit kurzer Pause; Kalibrierung gefolgt von sofortiger Bewegung) und die bei isolierten Einzeltests mit großzügigen Ruhezeiten unsichtbar bleiben.

**Entscheidung:** Die bestehende Python-Simulation (`tools/workout_engine_simulation.py`) wird um folgende Standard-Testszenarien erweitert, die für jede zukünftige Änderung an Schwellenwerten, Filtern oder Kalibrierungslogik verpflichtend durchlaufen werden müssen:
1. Guided Calibration (10 Reps) unmittelbar gefolgt von einem einzelnen weiteren Rep – der Schwellenwert darf sich dabei nicht ändern.
2. Mindestens 3 Reps in Folge mit realistisch kurzer Pause (≤ 1–2 Sekunden) dazwischen – das Signal muss zwischen den Reps erkennbar unter die Zählschwelle fallen.
3. Mindestens ein Szenario mit langsamem Tempo (3 s konzentrisch, 3 s exzentrisch) und eines mit schnellem, explosivem Tempo – da unterschiedliche Filterparameter unterschiedlich auf Tempo reagieren können (siehe empirischer Befund in Dokument 04).

**Konsequenzen:** Höherer initialer Aufwand beim Erweitern der Simulation, aber signifikant geringeres Risiko, dass ein in der Simulation "erfolgreicher" Fix auf echter Hardware erneut versagt. Diese ADR macht die in `01_PROJECT_CHARTER_AND_SCOPE.md` formulierte Validierungspflicht technisch konkret.

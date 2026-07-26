# IMU Rep Counter: Verifikationsbericht und Aenderungsvorschlag

**Stand:** 2026-07-26  
**Scope:** Produktpfad fuer `ChosenSignal.gP`; keine produktive Zaehl-Logik in diesem Commit geaendert.  
**Policy:** Ueberzaehlen ist schlimmer als Unterzaehlen. Deshalb bleibt jede Lockerung ausserhalb des Produktpfads, bis gelabelte Hardware-Daten vorliegen.

## 1. Ergebnis in einem Satz

Das aktuelle Profilverhalten mit `abs(g_p)` ist ein reproduzierbarer Doppelzaehlfehler bei bipolarer Bewegung (`20/10`); der richtungsbewusste Pfad behebt diesen synthetisch (`10/10`), darf aber erst mit einer expliziten Re-Kalibrierungsstrategie fuer Montage-Inversion produktiv werden. Der bestehende Slow-Rep-Vorschlag ist abzulehnen: Er verbessert `0/8` nur auf `1/8`, fuehrt im schaerfsten Wiggle-Test aber zu `9/30` Fehlzaehlungen.

## 2. Verifikation gegen den aktuellen Code

### Bestaetigte Fakten

| Thema | Bestaetigter Befund |
| --- | --- |
| Projektion | `GpProjection.project()` bzw. der Kalibrierpfad berechnet die bias-korrigierte skalare Projektion `g_p` auf eine gelernte Achse. |
| Achse | `CalibrationController._axisAnalysis()` nutzt PCA auf der 3x3-Gyro-Kovarianzmatrix und dreht die Achse so, dass der groesste Ausschlag positiv ist. Die Kalibrierung ist also vorzeichenorientiert. |
| Profilpfad | `WorkoutEngine.applyCalibration()` setzt fuer `ChosenSignal.gP` `_gpThreshold = max(50.0, peakThreshold * 0.70)`, `_gpUseAbsProjection = true` und aktiviert den gP-Pfad als Autoritaet. |
| Live-Gates | `_detectPeakSigned()` verlangt mindestens 15 Samples, einen Peak von mindestens `1.2 * threshold` und bei einem Profil einen aktiven ROM-Floor (`prominenceMin`). |
| ROM-Gate | Das ROM-Gate ist ein absoluter Peak-Floor, kein Tal-relatives Prominenzmass. Es ist bei `prominenceMin <= 0` abwaertskompatibel deaktiviert. |
| Refraktaerzeit | Reale Profile erzwingen mindestens 0,7 Sekunden beziehungsweise 35 Samples; das verhindert enge Flicks, aber keine beiden weit genug auseinanderliegenden Lobes einer Doppelbuckelbewegung. |
| Slow shadow | `SlowRepShadow` ist korrekt rein diagnostisch: 0,85 mal Threshold und mindestens 10 Samples duerfen niemals `_commitRep()` ausloesen. |
| Datenbasis | `git ls-files '*.csv'` liefert keine gelabelten Trainings-CSVs. Synthetische Ergebnisse sind daher nur eine Vorentscheidung, keine Produktfreigabe. |

### Abweichung zur Ausgangsbeschreibung

Die Aussage, die PCA-artige Achsenwahl koenne den bipolaren Fall grundsaetzlich vermeiden, trifft nicht zu. Die PCA und ihre Vorzeichenkonvention erzeugen gerade eine sinnvolle positive Primaerbewegung. Der Profilpfad faltet anschliessend jedoch mit `abs(g_p)` die negative Rueckbewegung wieder auf die positive Seite. Damit gehen die bei der Kalibrierung gewonnene Richtung und der strukturelle Doppelbuckel-Schutz verloren.

### `useAbsProjection`-Historie

`git log -p -G'_gpUseAbsProjection|useAbsProjection|sign-agnostic|double-hump'` zeigt die Einfuehrung in Commit `2cbeaae` vom 2026-07-23. Die dokumentierte Absicht war:

1. Eine umgedrehte Montage beziehungsweise ein umgekehrtes Achsenzeichen soll weiter zaehlen.
2. Nach einem frueheren gP-Autoritaetsproblem darf der unsichere Combined-Pfad nicht wieder auf den Default von 1,2 g zurueckfallen.
3. Eine Sperrzeit von 0,7 Sekunden sollte den Gegenphasen-Hub unterdruecken.

Die ersten beiden Gruende sind produktlich nachvollziehbar. Der dritte ist durch die aktuelle Simulation widerlegt: Der Abstand der beiden Lobes ist gross genug, dass die Sperrzeit nicht greift.

## 3. Reproduktion

Ausgefuehrt wurde auf dem bestehenden Commit `cb812ad` des Branches `test/slow-rep-proposal-verification`:

```text
python -c "... sim.run_gp_engine_sim_validation(); sim.run_full_verification_2026_07_26()"
```

Wesentliche tatsaechliche Ergebnisse:

| Szenario | Aktueller Produktmodus (`gp_use_abs=True`) | Erwartung | Bewertung |
| --- | ---: | ---: | --- |
| clean | 10 | 10 | OK |
| double_bump | 20 | 10 | kritische Doppelzaehlung |
| weak, eigenkalibriert | 10 | 10 | OK |
| slow, eigenkalibriert | 0 | 8 | Unterzaehlung |
| slow nach clean-Kalibrierung | 0 | 8 | Unterzaehlung |
| inconsistent mit 20 Prozent Halb-Reps | 8 | 10 | gemaess Persona erwartbar |
| Alltagsbewegung, clean kalibriert | 0 | 0 | OK |

Weitere reproduzierte Werte aus `run_full_verification_2026_07_26()`:

| Versuch | Ergebnis | Schlussfolgerung |
| --- | --- | --- |
| Gelockerter Slow-Rep-Pfad, slow eigenkalibriert | 1/8 statt 0/8 | Zu geringe Wirkung |
| Gelockerter Slow-Rep-Pfad, slow nach clean | 0/8 | Keine Wirkung im Ermuedungsfall |
| Gelockerter Slow-Rep-Pfad, Alltagsbewegung, slow kalibriert | 9/30 false positives | Nicht produktfaehig |
| Ruherausch-Floor aus bestehendem Modell | etwa 62 Grad/s | Kein Beleg fuer einen niedrigeren sicheren Floor |
| Energieintegral | 12,2 statt der vorherigen Schaetzung 61 (Grad/s)*s | Die Rechteck-Schaetzung war um Faktor 5 zu hoch |

Zusatzexperiment, ausgefuehrt mit denselben Thresholds und aktivem ROM-Gate, aber `gp_use_abs=False`:

| Szenario | Richtungsbewusster Modus | Erwartung | Wirkung auf Risiko |
| --- | ---: | ---: | --- |
| clean | 10/10 | 10/10 | keine Regression in der Persona |
| double_bump | 10/10 | 10/10 | beseitigt die Doppelzaehlung |
| weak | 10/10 | 10/10 | keine Regression in der Persona |
| inconsistent | 8/10 | 8/10 persona-bedingt | unveraendert |
| slow, eigenkalibriert | 0/8 | 8/8 | Problem 1 bleibt offen |
| slow nach clean | 0/8 | 8/8 | Problem 1 bleibt offen |
| Alltagsbewegung, clean kalibriert | 0/30 | 0/30 | kein neuer Fehlzaehler im vorhandenen Test |
| clean bei invertierter bestehender Montage | 0/10 | 10/10 | bewusstes Unterzaehlen statt Ueberzaehlen; Re-Kalibrierung noetig |

## 4. Bewertung der verworfenen Slow-Rep-Ideen

Die Verwerfung des zweiten, gelockerten Pfads ist richtig. Er lockert Peak und Dauer genau in dem Bereich, in dem zufaellige Alltagsrotationen mit einer langsamen Kalibrierung ueberlappen. Das verstoesst direkt gegen die Ueberzaehl-Policy.

Auch ein dynamischer Floor ist aktuell nicht gerechtfertigt: Sein zugrundeliegendes Rauschmodell ist selbst synthetisch und liefert nicht den erhofften niedrigeren Wert. Das Energieintegral ist ebenfalls kein belastbarer Ersatz fuer den Peakpfad, weil seine bisherige Parameterannahme nicht zu den echten synthetischen Kurven passt.

Es gibt derzeit keine nachweislich sichere Variante, die Problem 1 produktiv loest. Der richtige naechste Schritt ist Messung und Shadow-Auswertung, nicht ein weiterer Live-Relaxationspfad.

## 5. Primaere Loesungsvorschlaege

### P0: Profilzaehlung richtungsbewusst machen

**Vorschlag:** Fuer frisch kalibrierte gP-Profile nicht `abs(g_p)`, sondern `g_p * direction` zaehlen. Die vorhandene PCA-Vorzeichenkonvention liefert die Richtung bereits. Eine anhaltend starke Gegenrichtung wird nicht als Rep gezaehlt, sondern als Montage-/Profilinkonsistenz markiert und fordert Re-Kalibrierung an.

**Beleg:** Das Zusatzexperiment liefert 10/10 statt 20/10 bei `double_bump` und 0/30 false positives bei Alltagsbewegung. Bei invertierter Montage entstehen 0/10, also ein sichtbares Unterzaehlen statt einer stillen Fehlzaehlung. Das entspricht der bindenden Policy, muss aber mit realer Hardware validiert werden.

**Auswirkung auf Problem 1:** Keine. Die langsamen Peaks bestehen die bestehenden Gates weiterhin nicht. Das ist gewollt; die Doppelzaehlungs-Korrektur darf nicht mit einer Lockerung der Schwellen gekoppelt werden.

**Vorgesehene Dateien fuer einen separaten Implementierungs-Branch:**

| Datei | Geplante Aenderung |
| --- | --- |
| `app/lib/domain/workout_engine.dart` | Profilpfad auf vorzeichenbehaftete Projektion umstellen; gegengerichtete, ausreichend starke Exkursionen als Re-Kalibrierungs-Signal erfassen, nie committen. |
| `app/test/workout_engine_test.dart` | Regressionen fuer Doppelbuckel, invertierte Montage und das Nicht-Committen gegengerichteter Exkursionen ergaenzen. |
| `tools/workout_engine_simulation.py` | Den hier ausgefuehrten signed-profile-Vergleich als feste Regression neben `run_full_verification_2026_07_26()` aufnehmen. |
| `app/lib/presentation/providers/engine_provider.dart` | Das Re-Kalibrierungs-Signal in einen expliziten UI-Zustand ueberfuehren. |
| `app/lib/presentation/screens/home_screen.dart` | Verstaendlichen Hinweis anbieten: Sensorlage geaendert, bitte kurz neu kalibrieren. |

**Aufwand:** Mittel. Keine neue Signalpipeline und keine ML-Komponente erforderlich.

### P1: Slow Reps nur messen, nicht live lockern

**Vorschlag:** Den bestehenden `SlowRepShadow` behalten und mit gelabelten Hardware-Saetzen auswerten. Erst wenn shadow hits in langsamen Saetzen zu echten verpassten Reps passen und Wiggle-Saetze praktisch keine Hits zeigen, wird eine gezielte, datengetriebene Regel diskutiert.

**Ueberzaehl-Risiko:** Unveraendert, weil der Shadow-Pfad nicht committet. Eine Live-Freischaltung ist aufgrund der 9/30-Regression aktuell ausgeschlossen.

**Vorgesehene Dateien fuer die Messphase:**

| Datei | Geplante Aenderung |
| --- | --- |
| `docs/hardware/PLAN_HARDWARE_VALIDIERUNG.md` | Protokoll fuer normale, langsame, ermuedete, Wiggle- und Remount-Saetze mit Video-/Tap-Labeln ergaenzen. |
| `tools/workout_engine_simulation.py` | CSV-Replay und Auswertung von Produktzaehler gegen Ground Truth ergaenzen, sobald mindestens ein anonymisierter Beispielsatz vorliegt. |
| `app/lib/domain/metrics/slow_rep_shadow.dart` | Erst nach Messphase nur dann anpassen, wenn ein klarer Schwelleneffekt aus den Daten folgt. |

**Aufwand:** Klein fuer Messprotokoll, mittel fuer CSV-Regression, hoch fuer belastbare Datenerhebung.

### P2: Kalibrierung auf Signalgueltigkeit pruefen

**Vorschlag:** Die vorhandene bekannte Satzkalibrierung als harte Eintrittsbedingung nutzen: Ein Profil wird nur als richtungsbewusst aktiv markiert, wenn die Hauptachsenvarianz, Vorzeichenkonsistenz und die bekannte Rep-Zahl ausreichend gut sind. Andernfalls keine Scheingenauigkeit; stattdessen Kalibrierung wiederholen.

**Ueberzaehl-Risiko:** Sinkt oder bleibt gleich, weil unsichere Profile strenger behandelt werden. Risiko ist zusaetzliche Unterzaehlung beziehungsweise ein Re-Kalibrierungs-Hinweis.

**Abhaengigkeit:** Erst nach P0 als Shadow/Diagnose auswerten; keine eigenstaendige Live-Threshold-Lockerung.

## 6. Allgemeine Verbesserungen

1. **Golden-CSV-Regression:** Anonymisierte, gelabelte Hardware-Saetze versionieren oder gesichert bereitstellen; CI soll Rep-Differenz, Wiggle-FPR, Re-Kalibrierungsrate und Slow-Shadow-Treffer auswerten.
2. **Sampling-Zeit ehrlicher machen:** Die vorhandene samplebasierte Sperrzeit ist wegen Burst-Transport begruendet. Sobald Firmware-Zeitstempel pro Sample verifiziert sind, Refraktaer- und Dauergates auf reale Dauer umstellen.
3. **Profil-Health sichtbar machen:** Achsenvarianz, Bias-Drift, Gegenrichtungs-Hits und schwache gP-Energie als Diagnose und Nutzerhinweis erfassen; niemals still auf Combined oder Vision zurueckfallen.
4. **Korrekturen als Label-Quelle:** Die bestehende Nutzerkorrektur um eine freiwillige Ursache ergaenzen (zu viel, zu wenig, Sensor verdreht). Das priorisiert Messsaetze, ersetzt aber keine Ground Truth.
5. **Entscheidungsprotokoll aktualisieren:** Die Annahme "Sperrzeit loest Doppelbuckel" explizit widerrufen und das Ergebnis als Guardrail im ADR/Eskalationsleitfaden verlinken.

## 7. Priorisierte Reihenfolge

1. **Sofort:** Dieser Bericht, der vorhandene Simulationstest und die 20/10-Regression als Produktblocker behandeln.
2. **Als naechster Code-Branch, nicht direkt auf `main`:** P0 als richtungsbewusster Shadow-/Re-Kalibrierungsmodus inklusive Dart- und Python-Regressionen implementieren.
3. **Parallel:** Hardware-Protokoll aus P1 ausfuehren und gelabelte Saetze sammeln, insbesondere langsame Reps, Wiggles und absichtliche Remounts.
4. **Nach Datenlage:** P0 nur dann produktiv schalten, wenn kein Ueberzaehlregressionsfall entsteht. Slow-Rep-Gates erst dann mit einer expliziten Akzeptanzgrenze bewerten.
5. **Danach:** Zeitbasis, Profil-Health und CSV-CI ausbauen.

## 8. Offene Unsicherheiten

- Alle Persona- und Rauschwerte sind synthetisch. Sie beweisen die strukturelle Schwachstelle, nicht ihre Haeufigkeit im Gym.
- Der inverse Montage-Test modelliert nur ein Vorzeichenwechsel-Szenario. Eine reale Neuorientierung kann auch Achsenmischung und Amplitudenverlust erzeugen.
- Es gibt keine gelabelten Hardware-CSVs, daher keine Aussage zur Genauigkeit oder zu einer sicheren Slow-Rep-Relaxation.
- Der aktuelle `prominenceMin`-Port in der Simulation ist fuer die Groessenordnung ausreichend, bildet den kompletten Known-Count-Sweep aber nicht 1:1 nach.

## 9. Aenderungen dieses Commits

Dieser Commit fuegt nur diesen Verifikationsbericht hinzu. Es gibt absichtlich keinen Dart-Diff und keine geaenderte Produktentscheidung. Das entspricht `docs/reference/ESKALATIONS_PLAYBOOK.md`: Zaehl-Logik mit neuer Evidenz wird erst auf einem separaten Branch vorbereitet und nach menschlicher Entscheidung weitergefuehrt.

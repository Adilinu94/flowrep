# Kalibrierungs-Session Analyse (2026-07-23 ~17:00)

## Ergebnis: erfolgreich gespeichert

| Feld | Vorher (App-Start) | Nach deiner Session |
|------|--------------------|---------------------|
| Signal | **gP** (Gyro-Projektion) | **gP** |
| theta (Schwelle) | 70,5 °/s | **87,2 °/s** |
| qualityScore | 0,93 | **0,95** |
| Rotationsachse | vorhanden | vorhanden |

Log-Evidenz:
```
16:59:55 Loaded profile: signal=gP theta=70.458 q=0.93 axis=true
17:01:39 Loaded profile: signal=gP theta=87.200 q=0.95 axis=true
```

Profil liegt verschlüsselt in `FlutterSecureStorage` (`calib_profiles_v2`).  
Shadow-Pipeline wurde aktiviert (Achse vorhanden).

## IMU während der Session (DIAG, ~alle 50 Batches)

| Klasse | n | gyro Ø | gyro max | accel mag Ø |
|--------|---|--------|----------|-------------|
| Ruhe (`gyro < 15`) | 40 | 2,0 °/s | — | 0,999 g |
| Bewegung (`gyro ≥ 15`) | 6 | 93 °/s | **198 °/s** | 1,06 g |

Bewegungs-Peaks (Zeitachse):

| Zeit | mag | gyro °/s | Interpretation |
|------|-----|----------|----------------|
| 17:00:03 | 1,01 | 18 | leichtes Bewegen |
| 17:00:55 | 1,30 | **198** | starke Curl |
| 17:01:03 | 1,10 | **146** | Curl |
| 17:01:08 | 1,14 | 44 | Absetzen / langsam |
| 17:01:29 | 0,95 | **99** | Curl (vermutl. langsam) |
| 17:01:33 | 0,88 | 55 | Curl / Absetzen |

## Bewertung

1. **Ruhe-Gate** passt: Ruhige Samples ~2 °/s Gyro, mag ≈ 1 g.
2. **Curls erkennbar**: klare Gyro-Peaks 50–200 °/s, deutlich über theta.
3. **Signalwahl gP** ist ideal für Bizeps (Achsen-Projektion statt reiner Magnitude).
4. **Qualität 0,95** = sehr regelmäßig (CV der Peak-Höhen niedrig); Rekalibrierung nicht nötig (`needsRecalibration` nur bei q < 0,5).
5. **theta 87 °/s** liegt unter deinen Peak-Amplituden (~100–200) → Zählen sollte greifen, ohne Alltags-Rauschen (~2 °/s) zu triggern.

## Lücken / nächste Schritte

- Roh-Samples der Wizard-Stufen werden **nicht** als CSV exportiert (nur DIAG-Snapshots + gespeichertes Profil).
- Empfehlung: einen echten Satz (z. B. 8–12 Curls) zählen und Korrektur-Dialog prüfen.
- Optional später: CSV-Export der Kalibrier-Puffer für Offline-Analyse.

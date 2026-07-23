# Testprotokoll-Template — Früher Nutzertest (nach Meilenstein 2)

**Zweck:** Sicherstellen, dass der kritischste Test des gesamten Projekts strukturiert stattfindet, statt informell zu verpuffen. Dieses Template wird für jede Testperson einmal ausgefüllt.

**Vorgeschlagenes Erfolgskriterium (bitte in `00_ENTSCHEIDUNGEN_ERFORDERLICH.md` bestätigen oder anpassen):**
> Korrekturrate unter 15 % bei mindestens 3 von 5 Testpersonen. Korrekturrate = (Anzahl korrigierter Sätze) / (Gesamtzahl der Sätze) × 100.

Dieser Wert orientiert sich an publizierten Vergleichswerten für automatisches IMU-basiertes Wiederholungszählen (grob 90–99 % Genauigkeit je nach Verfahren) und ist bewusst kein "100 %"-Anspruch.

---

## Kopfdaten

| Feld | Wert |
|---|---|
| Testperson (Name oder Kürzel) | |
| Datum | |
| Erfahrungslevel (Anfänger/Fortgeschritten/Erfahren) | |
| Getestete Firmware-/App-Version (Commit-Hash) | |

## Pro Satz

| Satz-Nr. | Übung | Von der App gezählt | Tatsächlich (manuell mitgezählt) | Korrigiert? (ja/nein) | Kommentar der Testperson |
|---|---|---|---|---|---|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |
| 4 | | | | | |
| 5 | | | | | |

*(Zeilen nach Bedarf ergänzen — mindestens 3 Sätze pro Testperson empfohlen.)*

## Zusätzliche qualitative Fragen

- Hat sich die erste automatische Zählung wie erwartet ("Magic Moment") angefühlt, oder gab es eine spürbare Verzögerung?
- Gab es eine Übung oder Bewegungsphase, bei der die Zählung auffällig oft danebenlag?
- Wie hat sich die Korrektur angefühlt — eher lästig oder unauffällig?
- Freitext für alles, was nicht in die obigen Felder passt:

## Auswertung (nach allen Testpersonen)

| Kennzahl | Wert |
|---|---|
| Gesamtzahl Sätze über alle Testpersonen | |
| Gesamtzahl korrigierter Sätze | |
| Korrekturrate gesamt | |
| Anzahl Testpersonen mit Korrekturrate < 15 % | |
| Kriterium erfüllt? (siehe oben, ≥ 3 von 5 Personen) | |

**Nächster Schritt abhängig vom Ergebnis:** Bei nicht erfülltem Kriterium siehe Abbruch-/Umplanungskriterium in `00_ENTSCHEIDUNGEN_ERFORDERLICH.md`, Abschnitt A — nicht automatisch mit Phase 2 fortfahren, ohne dieses Ergebnis bewusst gegen das dort festgelegte Kriterium geprüft zu haben.

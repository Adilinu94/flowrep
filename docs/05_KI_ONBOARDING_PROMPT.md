# KI-Onboarding-Prompt

**Zweck:** Dieser Text wird am Anfang **jeder neuen Session** mit der ausführenden KI unverändert eingefügt, bevor irgendeine Implementierungsanweisung folgt. Er beantwortet die Fragen aus Abschnitt F des Fragenkatalogs verbindlich — hier gibt es keine offenen Punkte für Adi, das ist Prozess-Design.

---

## Prompt-Text (wortwörtlich verwenden)

```
Bevor du mit der Arbeit beginnst, lies vollständig:
1. GYM_TRACKER_ARCHITEKTUR.md (die gesamte Datei, nicht nur den relevanten Abschnitt)
2. 01_protocol.yaml
3. 02_DEFINITION_OF_DONE.md
4. 03_GLOSSAR.md
5. 04_ARCHITECTURE_DECISION_RECORDS.md
6. 00_ENTSCHEIDUNGEN_ERFORDERLICH.md (prüfe, ob die für die aktuelle Phase relevanten
   Felder ausgefüllt sind — falls nicht, sag das explizit, bevor du weitermachst)

Du arbeitest an Phase [PHASE_NUMMER_HIER_EINTRAGEN].

Regeln, die für dich nicht verhandelbar sind:
- Du weichst NIEMALS vom kanonischen Protokoll in 01_protocol.yaml ab, auch nicht
  "testweise" oder "zur Vereinfachung". Jede Abweichung ist ein Stopp-Fall.
- Du änderst KEINE Sicherheits- oder Verschlüsselungslogik ohne Rückfrage.
- Du änderst KEINEN Schwellenwert oder Parameter in der Workout Engine ohne
  Rückfrage — auch nicht, wenn ein Test schlecht ausfällt und eine Anpassung
  "offensichtlich" hilfreich wirkt.
- Wenn du auf eine Situation triffst, die in keinem der oben genannten Dokumente
  abgedeckt ist (z. B. eine Bibliotheksfunktion verhält sich anders als
  dokumentiert), improvisierst du NICHT. Du beschreibst das Problem konkret und
  fragst nach, bevor du eine eigene Lösung implementierst.
- Du meldest eine Phase erst als abgeschlossen, wenn du JEDES Kriterium aus
  02_DEFINITION_OF_DONE.md für diese Phase tatsächlich verifiziert hast — mit
  dem dort genannten Verifikationsartefakt, nicht durch eigene Einschätzung.
- Du erstellst nach jedem sinnvollen Zwischenschritt einen eigenen Commit mit
  Nachricht im Format "[Phase X] Kurzbeschreibung" (siehe Abschnitt 8 des
  Architekturdokuments), damit ein einzelner fehlerhafter Schritt isoliert
  zurückgerollt werden kann.
- Wenn eine Abweichung von den Dokumenten nötig erscheint, schlägst du sie vor
  und wartest auf Bestätigung — du setzt sie nicht eigenständig um.

Am Ende deiner Antwort in dieser Session: Liste explizit auf, welche der
DEFINITION_OF_DONE-Kriterien für die aktuelle Phase du als erfüllt betrachtest,
mit Verweis auf das jeweilige Verifikationsartefakt, das du erzeugt hast.
```

---

## Warum dieser Prompt so und nicht anders aussieht

- **Vollständiges Dokument statt Ausschnitt (Abschnitt F, Frage 1):** Ein Ausschnitt lässt die KI Entscheidungen aus anderen Abschnitten nicht kennen — genau das war die Ursache der ursprünglichen 30-Byte/52-Byte-Diskrepanz zwischen den beiden ursprünglichen Plandokumenten.
- **Explizite Stopp-Regeln statt allgemeiner Sorgfaltsaufforderung (Frage 2):** "Sei vorsichtig" ist für eine KI kein umsetzbares Kriterium. Eine Liste konkreter Trigger ist es.
- **Verifikationspflicht statt Selbsteinschätzung (Frage 3):** Schwächere Modelle neigen dazu, ein Ziel als erledigt zu bewerten, ohne es tatsächlich geprüft zu haben. Die explizite Kopplung an ein Artefakt aus `02_DEFINITION_OF_DONE.md` reduziert diesen Effekt, verhindert ihn aber nicht vollständig — eine unabhängige Sichtprüfung durch dich bleibt sinnvoll, besonders bei Kriterien mit Hardware-Bezug.
- **Granulare Commits (Frage 4):** Ermöglicht Rollback einzelner fehlerhafter Schritte, ohne eine ganze Phase zu verwerfen.
- **Eskalation statt Improvisation (Frage 5):** Ohne diese Regel füllt eine KI eine Lücke im Zweifel mit einer plausibel klingenden, aber nicht abgestimmten Lösung — genau das Muster, das zu Session-zu-Session-Drift führt.

## Ergänzender Hinweis

Falls die ausführende KI in `00_ENTSCHEIDUNGEN_ERFORDERLICH.md` ein leeres Feld antrifft, das für die aktuelle Phase relevant ist (z. B. Übungsliste für Phase 1, Testpersonen für Phase 3), soll sie das explizit benennen und pausieren, statt eine Annahme zu treffen oder das Feld zu ignorieren.

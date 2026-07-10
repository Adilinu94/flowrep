# KI-Onboarding-Prompt (aktualisiert – Projekt ist bereits begonnen)

**Zweck:** Dieser Text wird am Anfang **jeder neuen Session** mit der ausführenden KI unverändert eingefügt, bevor irgendeine Implementierungsanweisung folgt. Diese Version unterscheidet sich von der ursprünglichen: Als der erste Onboarding-Prompt geschrieben wurde, existierte noch kein Code. Inzwischen ist ein erheblicher Teil von Phase 0/1 bereits geschrieben, per CI verifiziert und im Repo — die ausführende KI übernimmt kein leeres Projekt mehr, sondern eins mit Historie, die sie kennen muss.

---

## Prompt-Text (wortwörtlich verwenden)

```
Du übernimmst ein bereits begonnenes Projekt, kein leeres Blatt.

SCHRITT 1 — Zugriff und Repo:
Das Projekt liegt in einem privaten GitHub-Repo: github.com/Adilinu94/flowrep
Falls du keinen Zugriff hast, frag Adi danach, bevor du irgendetwas
vorschlägst - rate nicht, wie der Code aussehen könnte.

SCHRITT 2 — Lies in dieser Reihenfolge, vollständig, nicht nur Ausschnitte:
1. README.md im Repo-Root - enthält eine ehrliche Tabelle, welcher Teil des
   Codes CI-verifiziert ist und welcher nicht.
2. docs/GYM_TRACKER_ARCHITEKTUR.md (komplett)
3. docs/01_protocol.yaml
4. docs/02_DEFINITION_OF_DONE.md
5. docs/03_GLOSSAR.md
6. docs/04_ARCHITECTURE_DECISION_RECORDS.md — ALLE Einträge, auch die
   späteren zu Drift, Android-Berechtigungen und DSGVO-Einstufung, nicht
   nur die ersten aus der ursprünglichen Planungsphase.
7. docs/00_ENTSCHEIDUNGEN_ERFORDERLICH.md — prüfe, was bereits beantwortet
   ist, bevor du danach fragst.

SCHRITT 3 — Verstehe den bestehenden Code, BEVOR du etwas Neues schreibst:
- app/lib/domain/workout_engine.dart: Lies den Klassenkommentar
  VOLLSTÄNDIG. Dort ist ein bereits gefundener und behobener kritischer
  Bug dokumentiert (die Kalibrierung führte dazu, dass nach den ersten 3
  Wiederholungen nie wieder gezählt wurde) sowie eine zweite,
  nachträgliche Robustheits-Anpassung (Tiefpassfilter + Median-
  Kalibrierung gegen Rauschen und Ausreißer). Ändere Schwellenwert- oder
  Kalibrierungslogik NIE, ohne diesen Kommentar gelesen zu haben.
- tools/workout_engine_simulation.py: Ein Python-Werkzeug, das genau
  diese Probleme gefunden hat, BEVOR echte Hardware oder ein Dart-
  Compiler verfügbar waren. Jede künftige Änderung an der Zähl-Logik
  wird ZUERST hier gegengetestet, dann erst nach Dart übernommen - das
  ist etablierter Workflow in diesem Projekt, kein optionaler Schritt.
- git log --oneline (und bei Bedarf git log -p für einzelne Commits):
  Viele Entscheidungen sind ausführlich in Commit-Nachrichten begründet,
  nicht nur im Code selbst.
- .github/workflows/: Es gibt bereits funktionierende CI (App CI,
  Firmware CI). Nach jeder Änderung committen, pushen, und den
  Actions-Tab auf GitHub prüfen - du hast vermutlich echten
  Internetzugriff und kannst die Logs direkt einsehen, anders als die
  Umgebung, in der dieser Code ursprünglich geschrieben wurde.

STAND IN EINEM SATZ:
Domain-Modelle, Zähl-Logik (inkl. behobenem Bug + Robustheits-Fixes),
BLE-Protokoll-Parser, Mock-Provider, Basis-UI und Drift-Datenbankschema
sind geschrieben und CI-grün (flutter analyze + flutter test laufen
durch). Das android/-Verzeichnis existiert bereits mit den nötigen
BLE-Berechtigungen. NICHT verifiziert ist alles, was echte Hardware
braucht: die BLE-Service-/Characteristic-UUIDs in
ble_sensor_provider.dart und firmware/src/main.cpp sind Platzhalter und
müssen auf beiden Seiten synchron durch echte ersetzt werden, die
Firmware wurde nie geflasht, MTU-Verhandlung wurde nie in der Praxis
bestätigt.

DEINE WAHRSCHEINLICH ERSTE ECHTE AUFGABE, sobald der M5StickC Plus2
verfügbar ist: Phase 0 aus dem Architekturdokument abschließen, nicht
neu beginnen. Konkret: Firmware-Grundgerüst flashen, echte BLE-
Verbindung testen, Platzhalter-UUIDs durch funktionierende ersetzen,
MTU-Verhandlung auf ≥ 55 Byte bestätigen (siehe protocol.yaml
constraints). Danach: den in workout_engine.dart bereits kalibrierten
(aber nur simulationsgetesteten) Schwellenwert-Ansatz gegen echte
Bewegungsdaten prüfen — siehe 09_TESTPROTOKOLL_TEMPLATE.md.

Regeln, die für dich nicht verhandelbar sind:
- Du weichst NIEMALS vom kanonischen Protokoll in docs/01_protocol.yaml
  ab, auch nicht "testweise" oder "zur Vereinfachung". Jede Abweichung
  ist ein Stopp-Fall.
- Du überschreibst oder vereinfachst bestehenden, CI-getesteten Code
  NICHT, ohne vorher zu verstehen, warum er so geschrieben ist (Kommentare
  + git log). Vermutest du einen Fehler in der Workout Engine, prüfe
  zuerst, ob er sich in tools/workout_engine_simulation.py reproduzieren
  lässt, bevor du Dart-Code änderst.
- Du änderst KEINE Sicherheits- oder Verschlüsselungslogik ohne Rückfrage.
- Du änderst KEINEN Schwellenwert oder Filterparameter in der Workout
  Engine ohne Rückfrage — auch nicht, wenn ein Test schlecht ausfällt und
  eine Anpassung "offensichtlich" hilfreich wirkt. Diese Parameter sind
  bereits einmal mit Begründung angepasst worden; eine weitere Anpassung
  braucht dieselbe Sorgfalt (Simulation zuerst), nicht eine Vermutung.
- Wenn du auf eine Situation triffst, die in keinem der oben genannten
  Dokumente abgedeckt ist, improvisierst du NICHT. Du beschreibst das
  Problem konkret und fragst nach, bevor du eine eigene Lösung
  implementierst.
- Du meldest eine Phase erst als abgeschlossen, wenn du JEDES Kriterium
  aus docs/02_DEFINITION_OF_DONE.md für diese Phase tatsächlich
  verifiziert hast — mit dem dort genannten Verifikationsartefakt UND
  grüner CI, nicht durch eigene Einschätzung.
- Du erstellst nach jedem sinnvollen Zwischenschritt einen eigenen Commit
  mit Nachricht im Format "[Phase X] Kurzbeschreibung", inklusive kurzer
  Begründung im Body bei nicht-trivialen Änderungen (das bisherige
  Commit-Log dieses Projekts zeigt, wie ausführlich das sein sollte).
- Wenn eine Abweichung von den Dokumenten oder vom bestehenden Code nötig
  erscheint, schlägst du sie vor und wartest auf Bestätigung — du setzt
  sie nicht eigenständig um.

Am Ende deiner Antwort in dieser Session: Liste explizit auf, welche
DEFINITION_OF_DONE-Kriterien du als erfüllt betrachtest, mit Verweis auf
das Verifikationsartefakt UND den CI-Lauf, der das bestätigt.
```

---

## Was sich gegenüber der ursprünglichen Version geändert hat

- **Repo-Zugriff als expliziter erster Schritt**, weil es jetzt einen echten Ort gibt, an dem der Code liegt — vorher gab es nur Dokumente ohne Code.
- **Schritt 3 (bestehenden Code verstehen) ist komplett neu.** Die größte Gefahr ist jetzt nicht mehr "ohne Kontext starten", sondern "vorhandenen, bereits gehärteten Code für ein Problem halten und eigenmächtig 'reparieren'" — insbesondere die Workout-Engine-Kalibrierung, die schon einmal einen ernsten, nicht offensichtlichen Bug hatte.
- **CI-Nutzung ist jetzt Teil der Regeln, nicht nur eine Randnotiz.** Die ausführende KI hat vermutlich normalen Internetzugriff (anders als die Sandbox, in der der Code ursprünglich entstand) und sollte GitHub Actions aktiv zur Verifikation nutzen, nicht nur lokal testen.
- **Die "erste Aufgabe" ist jetzt konkret benannt**, statt einer Phasennummer zum Selbst-Ausfüllen — weil der tatsächliche nächste Schritt (Hardware-Validierung von Phase 0) aus dem aktuellen Stand ableitbar ist.
- **Parameteränderungen an der Workout Engine haben jetzt eine explizite Pflicht zur Simulation zuerst**, weil genau dieser Workflow bereits zweimal echte Probleme gefunden hat, bevor sie in Produktivcode oder auf Hardware sichtbar wurden.

## Ergänzender Hinweis

Falls die ausführende KI in `00_ENTSCHEIDUNGEN_ERFORDERLICH.md` ein leeres, für die aktuelle Aufgabe relevantes Feld antrifft, soll sie das explizit benennen und pausieren, statt eine Annahme zu treffen. Das gilt unverändert weiter.

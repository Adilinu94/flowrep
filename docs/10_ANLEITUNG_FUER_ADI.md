# Anleitung für Adi — Erster Kontakt mit der ausführenden KI

**Für wen:** Diese Datei ist für dich, nicht für die ausführende KI. Sie setzt keine Vorkenntnisse mit VS Code oder ESP-Hardware voraus.

---

## Teil 1: Software einmalig installieren (bevor du die KI überhaupt ansprichst)

1. **VS Code** installieren: [code.visualstudio.com](https://code.visualstudio.com) → herunterladen → normal installieren wie jedes Programm.
2. **PlatformIO-Erweiterung** installieren: In VS Code links in der Seitenleiste auf das Symbol mit den vier Quadraten (Extensions) klicken, "PlatformIO IDE" eingeben, installieren, VS Code danach einmal komplett neu starten.
3. **Flutter SDK** installieren: [flutter.dev](https://flutter.dev) → Installationsanleitung für dein Betriebssystem folgen (das ist der aufwendigste Einzelschritt — plane dafür 30–60 Minuten ein, auch für erfahrene Entwickler).
4. **USB-Treiber für den M5StickC Plus2:** Das Gerät nutzt den Chip **CH9102**. Treiber hier herunterladen: [docs.m5stack.com/en/download](https://docs.m5stack.com/en/download) — Datei "CH9102_VCP_SER_Windows" (Windows) bzw. die Mac-Version. **Nach der Installation den Computer einmal komplett neu starten**, nicht nur VS Code — das löst die meisten "Gerät wird nicht erkannt"-Probleme.
5. **USB-Kabel-Falle:** Manche USB-C-Kabel können nur laden, aber keine Daten übertragen (sehen identisch aus!). Falls der Stick am Computer nicht erkannt wird, zuerst ein anderes Kabel probieren, bevor du nach komplizierteren Ursachen suchst.

**Merke:** Wenn nach Schritt 4 der Stick am PC in der Geräteverwaltung (Windows) bzw. in den Systeminformationen (Mac) nicht auftaucht, ist das kein Software-Fehler in eurem Projekt — es ist fast immer entweder das Kabel (Schritt 5) oder ein fehlender Neustart.

## Teil 1b: Speziell für dein Xiaomi 11T

Dein Testhandy läuft auf HyperOS (Nachfolger von MIUI) und bleibt dauerhaft auf Android 14 — Xiaomi liefert dafür keine weiteren Versions-Updates mehr. Für die Entwicklung ist das kein Problem, aber HyperOS blockiert Hintergrund-Apps aggressiver als die meisten anderen Android-Varianten. Damit die BLE-Verbindung während einer Trainingspause nicht einfach stillschweigend abbricht, bitte **vor dem ersten echten Test** einmal einrichten:

1. Einstellungen → Apps → [App-Name] → **Akku sparen** → auf "Keine Beschränkungen" stellen.
2. Einstellungen → Apps → Berechtigungen → **Autostart** → für [App-Name] aktivieren (diese Berechtigung gibt es nur bei Xiaomi-Geräten, nicht bei Standard-Android).
3. In der Übersicht der zuletzt geöffneten Apps (die Kachel-Ansicht) auf die App-Kachel tippen und das kleine Schloss-Symbol aktivieren, damit sie beim "Alle schließen" nicht mit beendet wird.

Menüwortlaut kann je nach Sprache/Region leicht abweichen, die drei Einstellungen (Akku-Beschränkung, Autostart, Sperren in der App-Übersicht) sind aber bei HyperOS 1 stabil vorhanden. Falls die Verbindung trotzdem in der Pause abbricht: siehe `ESKALATIONS_PLAYBOOK.md`.

## Teil 2: Wie du die erste Session mit der ausführenden KI startest

1. Neue Unterhaltung mit der ausführenden KI (z. B. Claude Code) öffnen.
2. Den Text aus `05_KI_ONBOARDING_PROMPT.md` **unverändert** einfügen, dabei `[PHASE_NUMMER_HIER_EINTRAGEN]` durch `0` ersetzen (ihr beginnt bei Phase 0).
3. Alle zwölf Dateien hochladen: `GYM_TRACKER_ARCHITEKTUR.md`, `00` bis `09`, sowie diese Datei selbst muss die KI nicht bekommen — sie ist nur für dich.
4. Abwarten. Eine gut funktionierende Session sollte jetzt zuerst zusammenfassen, was sie verstanden hat, und ggf. Rückfragen stellen — **nicht sofort anfangen, Code zu schreiben.**

## Teil 3: Woran du erkennst, dass etwas schiefläuft — auch ohne Fachwissen

Du musst den Code nicht verstehen, um diese Warnzeichen zu erkennen:

| Warnzeichen | Was du tust |
|---|---|
| Die KI beginnt sofort mit Code, ohne die Dokumente zu erwähnen oder Rückfragen zu stellen | Stoppen, auf Teil 2 verweisen, neu starten lassen |
| Die KI meldet "Phase X ist fertig", aber du hast keins der in `02_DEFINITION_OF_DONE.md` genannten Verifikationsartefakte (Video, Screenshot, Log) gesehen | Nach genau diesem Artefakt fragen, bevor du weitermachst |
| Die KI schlägt vor, von `flutter_blue_plus`, dem 52-Byte-Protokoll oder Drift abzuweichen | Das ist laut `ESKALATIONS_PLAYBOOK.md` immer ein Stopp-Fall — nicht selbst beurteilen, sondern die Begründung hierher (zu mir) mitbringen, bevor du zustimmst |
| Die KI ändert einen Schwellenwert in der Workout Engine "weil der Test sonst schlecht aussieht" | Das ist explizit verboten (siehe Onboarding-Prompt) — anhalten |
| Ein Feld in `00_ENTSCHEIDUNGEN_ERFORDERLICH.md` ist leer und die KI trifft trotzdem eine Annahme, statt nachzufragen | Das ist ein Verstoß gegen die Eskalationsregeln — auf die Lücke hinweisen |

**Wichtig für dich als "Mensch im Loop":** Da niemand sonst benannt ist (siehe `00_ENTSCHEIDUNGEN_ERFORDERLICH.md`), bist du automatisch die Person, an die eskaliert wird. Du musst keine technische Bewertung selbst treffen — es reicht, die Frage der ausführenden KI hierher mitzunehmen und mich zu fragen, bevor du zustimmst.

## Teil 4: Dein erster Tag — Reihenfolge

1. Teil 1 dieser Datei abarbeiten (Software + Treiber).
2. Minimal-Test **vor** dem eigentlichen Projekt: Ein leeres PlatformIO-Projekt anlegen lassen und nur prüfen, ob der Stick überhaupt erkannt und ein Test-Sketch geflasht werden kann (siehe `06_SETUP_ANLEITUNG.md`, dort für die KI gedacht, aber das Ergebnis siehst du direkt am Gerät).
3. Erst wenn das funktioniert: Teil 2 dieser Datei (eigentliche Projekt-Session starten).
4. Bei jedem Stoppschild aus Teil 3: hierher zurückkommen, bevor du der ausführenden KI zustimmst.

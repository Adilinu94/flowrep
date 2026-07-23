# Fehler-/Eskalations-Playbook

**Zweck:** Konkrete "Wenn X, dann Y"-Regeln für vorhersehbare Problemfälle, damit die ausführende KI nicht mit generischen, nicht projektspezifischen Lösungen improvisiert (z. B. übermäßig aggressive Retry-Logik, die den Akku belastet).

**Grundprinzip:** Jede Zeile in der Spalte "Eskalation erforderlich?" mit "Ja" bedeutet: Problem beschreiben, Lösung vorschlagen, auf Bestätigung warten — nicht selbst umsetzen.

## BLE-Verbindung

| Situation | Vorgehen | Eskalation erforderlich? |
|---|---|---|
| Verbindung bricht während eines aktiven Satzes ab | Exponentielles Backoff (1 s, 2 s, 4 s, 8 s, max. 16 s), siehe Architekturdokument 5.2.4. Bereits gepufferte Batches nach Reconnect nachsenden. | Nein — Verhalten ist bereits spezifiziert |
| MTU-Verhandlung schlägt fehl (< 55 Byte) | Verbindung trennen, einmal neu aufbauen, MTU erneut verhandeln | Nein bei erstem Fehlschlag. **Ja**, wenn auch nach drei Versuchen keine ausreichende MTU zustande kommt — das deutet auf ein Gerätekompatibilitätsproblem hin |
| App findet "GymTracker" nicht im Scan trotz eingeschaltetem Bluetooth | Prüfen: `neverForLocation`-Flag korrekt gesetzt? Standort-Dienst des Handys aktiviert (auch bei `neverForLocation` auf manchen Geräten nötig)? | Nein bei bekannten Ursachen. **Ja**, wenn beide Prüfungen negativ sind und das Problem weiterhin besteht |
| Verbindung bricht nur bei gesperrtem Bildschirm ab | Zuerst prüfen: ist `foregroundServiceType="connectedDevice"` deklariert (siehe ADR-008)? | Nein, wenn die Deklaration fehlte und jetzt ergänzt wird. **Ja**, wenn sie bereits vorhanden war und das Problem trotzdem auftritt |
| Verbindung bricht bei gesperrtem Bildschirm ab, OBWOHL `foregroundServiceType="connectedDevice"` korrekt gesetzt ist, speziell auf Geräten mit aggressivem OEM-Batteriemanagement (bestätigt relevant für das Testgerät: Xiaomi 11T / HyperOS, Nachfolger von MIUI; ebenso bei Huawei, OnePlus u. a.) | Prüfen, ob die drei in `10_ANLEITUNG_FUER_ADI.md` beschriebenen Einstellungen (Akku-Beschränkung aufgehoben, Autostart aktiviert, App in der Übersicht "gesperrt") tatsächlich gesetzt sind — das ist eine Geräteeinstellung, kein Code-Fehler | **Ja**, falls das Problem auch nach allen drei Einstellungen weiterhin auftritt — das wäre dann kein bekanntes Muster mehr |

## Sensordaten

| Situation | Vorgehen | Eskalation erforderlich? |
|---|---|---|
| IMU liefert unplausible Werte (z. B. dauerhaft 0, oder Werte weit außerhalb ±16g) | Firmware-seitigen Sensor-Init-Code prüfen, nicht den App-seitigen Parser "reparieren" | **Ja**, sobald der Verdacht auf einen Hardwaredefekt besteht (siehe auch Frage zu Ersatz-Hardware in `00_ENTSCHEIDUNGEN_ERFORDERLICH.md`) |
| Zählung weicht bei bestimmten Übungen systematisch stark ab | NICHT eigenständig den Schwellenwert in der Workout Engine anpassen | **Ja, immer** — das ist explizit ein Stopp-Fall laut `KI_ONBOARDING_PROMPT.md` |
| Paketverlust sichtbar in den Diagnose-Logs (Abschnitt 5.2.4 des Architekturdokuments) | Paketverlustrate dokumentieren, nicht sofort als "Engine-Fehler" interpretieren | Nein für die Dokumentation selbst. **Ja**, falls daraus eine Protokolländerung folgen soll |

## Testgerät / Hardware

| Situation | Vorgehen | Eskalation erforderlich? |
|---|---|---|
| Testgerät reagiert gar nicht mehr (Firmware-Hang) | Neustart über Reset-Taste, danach Seriellen Monitor auf Absturzursache prüfen | Nein bei einfachem Neustart. **Ja**, wenn der Hang reproduzierbar unter denselben Bedingungen auftritt |
| Akku des Sticks während der Entwicklung ungewöhnlich schnell leer | Mit dokumentiertem Wert aus `02_DEFINITION_OF_DONE.md` Kriterium 2.4 vergleichen | **Ja**, wenn deutlich schlechter als erwartet — könnte auf fehlerhaftes Wake-on-Motion hindeuten |
| Nur ein Stick vorhanden und dieser fällt aus | — | **Ja, sofort** — ohne Ersatz-Hardware ist die Phase blockiert, das ist keine technische, sondern eine Beschaffungsfrage |

## Bibliotheken & Abhängigkeiten

| Situation | Vorgehen | Eskalation erforderlich? |
|---|---|---|
| `flutter_blue_plus` verhält sich anders als in der Dokumentation beschrieben oder hat einen bekannten Bug in der eingesetzten Version | Version prüfen, Changelog des Pakets konsultieren | **Ja**, bevor auf ein anderes Paket gewechselt wird — das würde ADR-002 widersprechen |
| Isar-Build schlägt fehl oder zeigt Wartungsprobleme während der Implementierung | Fehler dokumentieren | **Ja** — das ist genau das in ADR-006 als Risiko benannte Szenario, kein Fall für eigenständigen stillen Wechsel zu Drift |

## Generischer Fall

| Situation | Vorgehen | Eskalation erforderlich? |
|---|---|---|
| Eine Bibliotheksfunktion, ein Verhalten oder eine Situation, die in keinem der vorhandenen Dokumente beschrieben ist | Problem konkret in eigenen Worten beschreiben, mindestens eine Lösungsoption vorschlagen | **Ja, immer** — das ist der in `KI_ONBOARDING_PROMPT.md` festgehaltene Grundsatz gegen stille Improvisation |

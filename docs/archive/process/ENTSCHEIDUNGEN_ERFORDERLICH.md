# Offene Entscheidungen — NUR von Adi zu beantworten

**Zweck:** Diese Datei enthält alle Fragen aus dem Fragenkatalog, die keine Recherchefragen sind, sondern Tatsachen über dich, dein Budget, deine Zeit und deine Kontakte. Ich kann sie nicht recherchieren oder sinnvoll raten — jeder Versuch, hier plausible Antworten zu erfinden, würde der ausführenden KI eine falsche Tatsachengrundlage vorgaukeln. Bitte diese Datei ausfüllen, **bevor** Phase 0 beginnt, und dann zusammen mit den anderen neun Dateien an die ausführende KI übergeben.

Unausgefüllte Felder sind kein Beinbruch — aber die KI sollte angewiesen werden, bei einem leeren Feld **zu stoppen und nachzufragen**, statt eine Annahme zu treffen (siehe `KI_ONBOARDING_PROMPT.md`, Eskalationsregeln).

---

## A. Vision, Scope & Erfolgsdefinition

| Frage | Deine Antwort |
|---|---|
| Erfolgsmetrik nach 8–9 Wochen (Zahl oder klares Kriterium) | Keine — kein fixer Zeit-/Metrik-Zwang |
| Ist die V1/V2-Grenze aus dem Architekturdokument für dich persönlich bindend? (ja/nein) | Nein |
| Abbruch-/Umplanungskriterium, falls der frühe Test scheitert | Keins |
| Persönliches Projekt oder kommerzielles Vorhaben? | Persönliches Projekt, evtl. später kommerziell |

## B. Nutzer & Validierung

| Frage | Deine Antwort |
|---|---|
| Namen/Kontakte der 3–5 Testpersonen für Meilenstein 2 | Nur ich selbst (Einzeltester) |
| Übungsliste für V1 (Empfehlung: nur Bizeps-Curls zum Start — siehe `DEFINITION_OF_DONE.md`) | Am Anfang nur Bizeps-Curls |
| Bestätigst du das vorgeschlagene Erfolgskriterium für den Test (Korrekturrate < 15 % bei ≥ 3 von 5 Personen, siehe `TESTPROTOKOLL_TEMPLATE.md`)? | Bestätigt — **angepasst auf 1 Person statt 5** (siehe Hinweis unten) |

## C. Technische Ausgangslage

| Frage | Deine Antwort |
|---|---|
| M5StickC Plus2 bereits vorhanden? Wenn ja, wie viele Stück? | Ja — M5Stack M5StickC PLUS2 (ESP32-PICO-V3.0), bestätigt vorhanden |
| Testhandy vorhanden? Marke/Android-Version? | Ja — Xiaomi 11T. Läuft auf HyperOS 1 / Android 14 und bekommt laut Hersteller keine weiteren Android-Versions-Updates mehr (letztes Sicherheitsupdate war September 2025) — siehe Hinweis unten |
| Isar oder Drift — finale Entscheidung | **Drift** (an Claude delegiert — Begründung siehe ADR-006, jetzt aktualisiert) |

## D. Daten, Datenschutz & Recht

| Frage | Deine Antwort |
|---|---|
| Rechtsform/Anbieter-Identität für Impressum & Datenschutzerklärung | Nicht benötigt (kein Store-Release in Sicht) |
| Ist eine Rechtsberatung für die Einwilligungstexte eingeplant (ja/wann)? | Nein |
| Cloud-Sync (Phase 5) überhaupt gewünscht, oder bewusst rein lokal bleiben? | Ja, bitte einbauen (bleibt aber Phase 5 / V2+, ändert nicht die V1-Reihenfolge) |

## E. Ressourcen & Zeitplan

| Frage | Deine Antwort |
|---|---|
| Realistisch verfügbare Stunden/Woche | Vom Nutzer als nicht relevant eingestuft — kein Zeitdruck, siehe Hinweis unten |
| Budget für Zubehör (Ersatz-Stick, Testhandy, Supabase, Store-Gebühren) | Vom Nutzer als nicht relevant eingestuft |
| Name der Person "Mensch im Loop" für die vier Entscheidungen in Anhang 7 | Vom Nutzer als nicht relevant eingestuft — **siehe Hinweis unten, das ist nicht ganz folgenlos** |

## G. Go-Live & Betrieb

| Frage | Deine Antwort |
|---|---|
| Wer sichtet Crash-Reports/Korrekturdaten nach Soft Launch? | Adi selbst bzw. eine KI (Claude/Claude Code) |
| Vertretung für Bugfixes bei eigener Abwesenheit? | Keine Vertretung vorhanden |

---

## Hinweise zu drei Antworten (keine Kritik, nur Konsequenzen sichtbar machen)

1. **Testpersonen = nur du selbst:** Das ist für ein persönliches Projekt völlig in Ordnung, ändert aber die Aussagekraft des frühen Tests. "1 von 1" statt "3 von 5" bedeutet: Ihr testet, ob die Engine **für deinen eigenen Bewegungsstil** funktioniert, nicht, ob sie allgemein für unterschiedliche Körper/Techniken robust ist. Das ist bei einem Solo-Projekt der richtige Maßstab — nur explizit festgehalten, damit später niemand (auch keine KI) daraus fälschlich "funktioniert für alle Nutzer" ableitet.
2. **E komplett als irrelevant markiert:** Zeit und Budget als "kein Thema" zu behandeln ist bei einem druckfreien Hobbyprojekt vernünftig. Eine Sache bleibt davon nicht ganz unberührt: Abschnitt G und der Fragenkatalog gehen davon aus, dass es einen "Menschen im Loop" für kritische Eskalationen gibt. Da niemand explizit benannt ist, gilt implizit: **das bist du selbst.** Die KI wird also bei jeder Eskalation an dich persönlich adressieren, nicht an eine dritte Instanz.
3. **G.1 "Adi bzw. eine KI" sichtet Crash-/Korrekturdaten, G.2 keine Vertretung:** Zusammengenommen heißt das: Bei echten Nutzern (falls das Projekt doch kommerziell wird, siehe A.4) gäbe es keinen Backup-Menschen, falls du selbst mal nicht erreichbar bist. Für die aktuelle Phase (Einzeltester, kein Store-Release) ist das unkritisch — bei einem späteren kommerziellen Schritt sollte diese Zeile hier noch einmal aktiv neu beantwortet werden, nicht einfach so stehen bleiben.

4. **Xiaomi 11T als Testgerät:** Zwei Konsequenzen. Erstens: Das Gerät bleibt auf Android 14 (HyperOS 1) stehen, bekommt also die in `ARCHITECTURE_DECISION_RECORDS.md` (ADR-008) beschriebene Android-15-Anforderung (`foregroundServiceType="connectedDevice"`) beim lokalen Testen nie zu Gesicht — die Firmware-/App-Vorgabe bleibt trotzdem bestehen, weil sie für andere Nutzer mit neueren Geräten relevant wird, sobald es über den Einzeltest hinausgeht. Zweitens: HyperOS ist der direkte Nachfolger von MIUI und übernimmt dessen aggressives Akku-/Autostart-Management — das in `ESKALATIONS_PLAYBOOK.md` als "MIUI" beschriebene Verhalten betrifft dieses Gerät konkret, nicht nur hypothetisch. Konkrete Klick-Anleitung dafür steht jetzt in `10_ANLEITUNG_FUER_ADI.md`.

---

## Zur Einordnung: Was NICHT in dieser Datei steht

Alle Fragen aus **Abschnitt F** des Fragenkatalogs (Zusammenarbeit mit der ausführenden KI) fehlen hier absichtlich — die habe ich als Architekt dieses Prozesses selbst beantwortet und direkt in `KI_ONBOARDING_PROMPT.md` und `ESKALATIONS_PLAYBOOK.md` umgesetzt, da das Prozess-Design-Entscheidungen sind, keine Tatsachen über dich. Ebenso sind die recherchierbaren Rechts-/Technikfragen (DSGVO-Einordnung, Android-Berechtigungen, Supabase-Region) bereits in die jeweiligen Fachdateien eingearbeitet, nicht hier — sie brauchen keine Entscheidung von dir, nur Kenntnisnahme.

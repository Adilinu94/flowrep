# Bauplan: Von Prototyp zur polierten App — UI/UX & Feature-Vervollständigung

**Stand:** 2026-08-07 · **Methodik:** Ist-Zustand direkt am Code verifiziert (nicht angenommen), Wettbewerbsrecherche über 15+ Quellen, Design-Richtung nach Prinzip "aus dem eigentlichen Kern der App abgeleitet, nicht generisch". Ergänzt die bestehenden Bauplan-Dokumente (`BAUPLAN_FINALE_APP_2026-08-01.md`, Phase 1–4 abgeschlossen) um die Achse "fühlt sich wie ein fertiges Produkt an", nicht "zählt Reps korrekt" (das ist Problem 1/2, separat).

**Einordnung ins bestehende Prioritätssystem:** Nichts hier ist P0 (das sind die A1–A5-Hardwarechecks, siehe letzte Sessions). Das hier ist überwiegend P1/P2 — wichtig für "fühlt sich fertig an", blockiert aber keinen funktionalen Release.

---

## 1. Ist-Zustand — ehrlich, am Code geprüft

### Was schon da ist (und zwar mehr, als der optische Eindruck vermuten lässt)

FlowRep hat unter der Haube Funktionstiefe, die viele kommerzielle Apps nicht haben:

- Pro-Übung-Kalibrierung (PCA/Jacobi-Eigendecomposition, "Guided Calibration 2.0"), persistiert pro Übung + Gerät
- Zwei parallele Zähl-Pipelines (Legacy `WorkoutEngine` live, neue `ExerciseEngine`/`PeakDetector`/`PhaseValidator` im Schatten für spätere Ablösung)
- Velocity-Based-Training-Metriken (Velocity-Loss, adaptive Pausenzeit danach) — das bieten selbst Hevy/Strong nicht nativ
- Audio-First/Blind-Mode — Training ganz ohne Blick aufs Display, Haptik+Sound. Barrierefreiheits-Bewusstsein, das in dieser Kategorie selten ist
- Kamera + Pose-Detection als Gegenprobe ("Vision Agreement") zur Sensor-Zählung
- Korrektur-Dialog: Nutzer korrigiert Fehlzählungen, App lernt daraus
- CSV-Session-Aufnahme + Export, verschlüsselte lokale DB (Drift + SQLCipher)
- M5-Hardware-Tasten-Steuerung (BtnA zum Starten/Beenden ganz ohne Handy in die Hand zu nehmen)

Das ist die Substanz einer ernsthaften App. Was fehlt, ist fast ausschließlich die Oberfläche darüber und ein paar Lücken in der User Journey — kein Substanzproblem.

### Was fehlt — Screens/Navigation

6 Screens total: `home_screen.dart` (trägt fast alles), `calibration_wizard_screen.dart`, `history_screen.dart`, `settings_screen.dart`, `camera_session_screen.dart`, `sensor_placement_tutorial.dart`. Keine echte Navigationsstruktur (kein Bottom-Nav, keine Tabs) — alles hängt an einem Screen mit bedingten Widgets.

### Was fehlt — Design-System

`main.dart`: `ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true)`. Das ist die Flutter-Starter-Vorlage, wörtlich. Keine eigene Farbpalette, keine Typografie-Entscheidung, keine Komponentenvarianten, keine Spacing-Skala. Dark Mode läuft immerhin schon über `ThemeMode.system` — das eine Häkchen, das schon gesetzt ist.

`pubspec.yaml`: kein Charting-Package (der Trend-Chart in `history_screen.dart` ist handgemaltes `CustomPaint`), keine Animationsbibliothek über Flutter-Bordmittel hinaus, keine dedizierte Icon-Bibliothek.

### Was fehlt — konkrete Feature-Lücken (aus dieser Session + Wettbewerbsvergleich)

- Keine Anzeige "welche Übung ist kalibriert" (Daten sind da, siehe letzte Session — nur nicht sichtbar)
- M5-Hardwaretaste umgeht die Kalibrierungsprüfung komplett (siehe letzte Session, Fix vorgeschlagen, noch offen)
- Kein Plattenrechner, kein Warm-up-Generator, keine PR-Feier, kein "letztes Mal"-Geistertext bei der Gewichtseingabe, keine Supersätze, kein RPE/RIR
- `history_screen.dart`: nur eine flache Liste + 2 simple Trendlinien, keine Pro-Übung-Fortschrittskurve, kein Kalender, keine PR-Historie
- Kein echter Onboarding-Flow (nur ein Banner-Widget), kein "Dummy Stream"-Button-Cleanup (siehe letzte Session)
- Keine App-Icons/Branding-Assets erkennbar geprüft — vermutlich noch Flutter-Default

---

## 2. Wettbewerbsanalyse

### Kategorie A — Allgemeine Trainings-Logger (manuelle Eingabe)

| App | Positionierung | Stärke, die auffällt |
|---|---|---|
| **Hevy** | Breit, sozial, 10M+ Nutzer, 4,9★ | Sehr sauberes, modernes UI; Social Feed; Widgets; KI-Programmanpassung (Hevy Trainer); großzügiger Free-Tier |
| **Strong** | Minimalistisch, Powerlifter-nah | Reduziert aufs Wesentliche; präzise Pausensteuerung; Apple-Watch-Stärke; CSV-Export |
| **JEFIT** | Größte Übungsdatenbank | 1.300+ Übungen mit Animationen; Körpermaß-Tracking |
| **Fitbod** | KI-generierte Workouts | Personalisierte Trainingsvorschläge |
| **Stronger** | Kraft-Analytik | "Strength Score" — bewertet Kraft über 12 Muskelgruppen, Beginner→World Class. Ein einzelnes, einprägsames visuelles Differenzierungsmerkmal |

**Relevanteste Einzelfunktionen aus dieser Kategorie** (mit Belegen aus der Recherche): One-Tap-Logging (loggen → Pause startet automatisch → nächster Satz vorausgefüllt), "letztes Mal"-Platzhalter statt Nachschlagen, visueller Plattenrechner, Warm-up-Leiter (Zielgewicht eingeben → App baut Aufwärmsätze), PR-Konfetti bei neuem Rekord, Pausen-Timer mit interaktiven Lock-Screen-Buttons (−15s/Skip/+15s), RPE/RIR-Eingabe, Supersatz-Kopplung mit Auto-Weiterschaltung, mehrmodige interaktive Fortschrittscharts.

### Kategorie B — Automatisches Wiederholungszählen (die eigentlich relevante Vergleichsgruppe)

Das ist die Kategorie, in der FlowRep tatsächlich konkurriert — nicht Hevy/Strong, die zählen gar nichts automatisch:

| App | Ansatz | Bemerkenswert |
|---|---|---|
| **Motra (Train Fitness)** | Apple-Watch-Handgelenkbewegung | Beansprucht 470+ Übungen, unabhängig getestet 3/5 — "noch nicht zuverlässig genug, um bewusstes Loggen zu ersetzen" |
| **Gymatic** | Auto-Erkennung Übung + Reps | Arbeitszeit/Pausenzeit automatisch aus Bewegung erkannt (Pause startet, sobald Bewegung aufhört) |
| **Riven** | Zählt + benennt Übung + erkennt Muskelversagen | Einziger der Kategorie mit "war der Satz wirklich hart"-Einschätzung |
| **RepVision** | Kamera/Pose-Detection | On-Device, keine Cloud — ähnliches Prinzip wie FlowReps eigene Vision-Agreement-Funktion |

**Der wichtigste Einzelfund dieser Recherche:** Automatisches Wiederholungszählen ist branchenweit ein bekanntermaßen ungelöstes Problem — Durchschnittsgenauigkeit ca. 70 % bei Uhren-basierten Lösungen, unabhängige Tests bewerten die Kategorie-Führer mit 3/5. Das ist kein Nebenaspekt, sondern die Kernrechtfertigung für den ganzen Aufwand, den diese Konversation in Problem 1/2 gesteckt hat: ein **dediziertes** Sensor-Wearable mit sauberer DSP-Pipeline statt generischer Smartwatch-Heuristik ist ein echter, verteidigbarer Wettbewerbsvorteil — *wenn* die Präzision hält, was sie verspricht. Das gehört in jede Produktbeschreibung/Store-Listing, die je entsteht.

Ein Muster aus Gymatic verdient besondere Erwähnung, weil es fast geschenkt ist: **automatischer Pausen-Timer-Start, sobald die Bewegung aufhört** — FlowRep hat den Sensor-Stream schon, das wäre kein neuer Datenkanal, nur neue Logik auf bereits vorhandenen Daten.

---

## 3. Design-Richtung (Vorschlag, kein Dogma)

Kein generischer `colorSchemeSeed`, aber auch keiner der drei KI-Design-Klischees (Creme+Serife+Terracotta / Near-Black+Neongrün / Zeitungslayout). Stattdessen aus dem eigentlichen Kern abgeleitet: **FlowRep dreht sich um die Erkennung eines Peaks in einer rotatorischen Wellenform.** Das ist kein Zufall, das ist buchstäblich der ganze Sinn der App.

**Signatur-Element:** Die Gyro-Wellenform selbst als wiederkehrendes visuelles Motiv — aktuell existiert dafür keine Live-Visualisierung (der Zähler zeigt nur eine Zahl). Eine schlichte Live-Linie, die während des Zählens mitläuft und beim erkannten Peak kurz aufblitzt, wäre nicht nur Dekoration — sie zeigt dem Nutzer buchstäblich, *warum* die App gerade gezählt hat. Nebeneffekt: baut Vertrauen in die Zählgenauigkeit auf, für die diese ganze Konversation technisch gearbeitet hat.

**Palette (Vorschlag, 5 Werte):** Tiefes Graphit/Near-Black als Basis (`#14161A`) statt reinem Schwarz — schont Akku auf OLED, funktioniert im abgedunkelten Gym, wirkt nicht nach Rohentwurf. Ein einziger warmer Akzent, der exakt im Moment der erkannten Wiederholung feuert (`#FF6B4A`, warmes Koralle/Amber — bewusst *nicht* das Anthropic-Terracotta `#D97757`, das in KI-generiertem Design mittlerweile als Klischee gilt). Ein kühles Daten-Blau für Charts/Analytik (`#4A9EFF`). Neutralgrau-Skala für Text/Flächen (`#8B8F98`, `#E8E9EC`).

**Typografie:** Eine technische/tabellarische Zahlenschrift (z. B. JetBrains Mono oder Space Mono) *ausschließlich* für Messwerte — Reps, kg, m/s — gepaart mit einer klaren humanistischen Sans (z. B. Inter oder das Flutter-Default Roboto, bewusst gewählt statt zufällig belassen) für Labels und Fließtext. Zahlen sind der eigentliche Inhalt dieser App; sie sollten sich auch so anfühlen.

**Umsetzung:** Ein `theme/` Verzeichnis mit `app_colors.dart` (ColorScheme aus der Palette), `app_typography.dart` (TextTheme mit der Zahlenschrift für Displaygrößen), `app_spacing.dart` (4/8/12/16/24/32-Skala statt frei erfundener Werte wie aktuell `SizedBox(height: 12)` überall verstreut).

---

## 4. Priorisierter Bauplan

Reihenfolge = Abhängigkeit + Hebel. Jede Phase referenziert echte Dateien, keine Platzhalter.

### Phase A — Fundament: Design-System (Aufwand: mittel, ~1 Woche)
**Ziel:** Bevor irgendein Screen "poliert" wird, muss es etwas geben, wonach poliert wird — sonst entsteht Screen-für-Screen-Inkonsistenz.
- `theme/app_colors.dart`, `app_typography.dart`, `app_spacing.dart` anlegen (siehe Abschnitt 3)
- `main.dart`: `ThemeData(colorSchemeSeed: ...)` durch das eigene `ColorScheme` ersetzen
- Komponentenvarianten für die meistgenutzten Widgets definieren: Primärbutton (ist aktuell in `start_countdown_button.dart` inline gestylt), Card, ListTile-Varianten für `settings_screen.dart`
- → verify: alle 6 Screens rendern ohne visuellen Bruch, `flutter analyze` sauber

### Phase B — Onboarding & erste Nutzung (Aufwand: mittel)
**Ziel:** Laut Recherche die höchste Hebelwirkung für Retention — aktuell nur ein Banner-Widget (`onboarding_banner.dart`), kein geführter Flow.
- Geführter 3-Schritt-Einstieg: Verbinden → Kalibrieren → Erste Wiederholung. `sensor_placement_tutorial.dart` existiert schon, wird aber vermutlich isoliert erreicht statt als Teil eines Flows
- M5-Kopplung visuell begleiten (aktuell vermutlich reiner Verbindungsstatus-Chip, kein Schritt-für-Schritt)
- Ziel laut Recherche: unter 60 Sekunden bis zur ersten Wiederholung
- → verify: Testperson ohne Vorwissen schafft den kompletten Flow ohne Nachfragen

### Phase C — Kern-Trainingsflow (Home-Screen), Aufwand: groß, größter Einzelposten
**Ziel:** Der Screen, den man 95 % der Zeit sieht, bekommt die meiste Sorgfalt.
- Live-Wellenform-Visualisierung während des Zählens (Signatur-Element aus Abschnitt 3) — neue Komponente, nutzt den bereits vorhandenen Sample-Stream
- **Kalibrierungs-Status sichtbar machen** pro Übung (Häkchen/Symbol in der Übungsauswahl) — Daten sind da, nur nicht angezeigt (siehe letzte Session)
- **M5-BtnA-Kalibrierungsprüfung nachziehen** (`_onDeviceEvent()` in `engine_provider.dart`) — kleinster Einzel-Fix mit größtem Korrektheitseffekt, war letzte Session bereits als Ein-Zeilen-Änderung identifiziert
- "Letztes Mal"-Platzhalter im Gewichtsfeld (`weight_input_field.dart`) statt leerem Feld
- Automatischer Pausen-Timer-Start bei Bewegungsstillstand (Gymatic-Muster, siehe Abschnitt 2) — Erweiterung von `rest_timer_widget.dart`, nutzt vorhandene Sensordaten
- PR-Erkennung + kurze Feier-Animation bei neuem Rekord
- **Dummy-Stream-Button entfernen** aus der Normalansicht (siehe letzte Session — hinter `kDebugMode` verschieben, nicht ersatzlos streichen, bleibt fürs Testen nützlich)
- → verify: kompletter Satz (Verbinden → Zählen → Beenden) ohne UI-Bruch, mit sichtbarem Kalibrierungsstatus

### Phase D — Analytik & Fortschritt (`history_screen.dart`), Aufwand: mittel–groß
**Ziel:** Von "flache Liste + 2 Linien" zu echter Fortschritts-Ansicht.
- Charting-Package einführen (z. B. `fl_chart` — MIT-lizenziert, gut gepflegt) statt handgemaltem `CustomPaint`. Ersetzt `_TrendPainter`, keine Neuerfindung
- Pro-Übung-Fortschrittskurve (Gewicht/Volumen über Zeit), nicht nur aggregiert über alle Übungen
- PR-Historie pro Übung sichtbar
- Einfache Konsistenz-Ansicht ("X von 7 Tagen trainiert diese Woche") — bewusst *kein* schweres Gamification-System (Level/XP/Badges), da FlowRep ein persönliches Werkzeug ist, kein Social-Produkt; ein Wochenüberblick reicht für den Zweck
- → verify: Charts laden für eine Übung mit >5 aufgezeichneten Sätzen korrekt

### Phase E — Politur (Aufwand: klein pro Punkt, aber viele Punkte)
- Leer-Zustände mit Handlungsaufforderung statt nur Text (History-Screen hat schon einen ordentlichen Ansatz, als Vorlage für die anderen Screens nehmen)
- Fehler-Zustände in der Stimme der App, nicht technische Exception-Texte
- Lade-Zustände (Skeleton statt nur `CircularProgressIndicator`, `skeleton_painter.dart` existiert schon — konsequent einsetzen)
- App-Icon + Splash-Screen (aktuell vermutlich Flutter-Default, nicht geprüft — sollte verifiziert werden)
- Barrierefreiheits-Pass: Audio-First-Modus existiert schon als Grundlage, aber Screenreader-Labels/Kontrastwerte gegen das neue Farbschema aus Phase A prüfen

---

## 5. Was ich bewusst NICHT vorschlage

- Soziale Features (Feed, Freunde, Teilen) — Hevys stärkstes Differenzierungsmerkmal, aber FlowRep ist explizit ein persönliches Werkzeug
- Mehrwöchige Programm-Periodisierung (Accumulation/Intensification/Deload, wie bei RepCount) — mächtig, aber eigenes großes Feature-Fass, nicht Teil von "Politur"
- Schweres Gamification-System — passt nicht zum Ein-Personen-Nutzungskontext

---

## Quellen (Wettbewerbsrecherche)

- Strong vs. Hevy Vergleiche 2026: yourappland.com, sensai.fit (2x), strongermobileapp.com, aitoolsbakery.com, setgraph.app (2x), gymgod.app, gainframe.app, prpath.app
- Automatisches Zählen: riven.fit (Kategorie-Test 2026), mdpi.com (Multipurpose Wearable Sensor Paper), App-Store-Einträge Gymatic/RepVault Pro/RepVision/FitReps
- UX/Onboarding: stormotion.io, zfort.com, vson.ai, wearearch.com
- Feature-Details (Plattenrechner, PR-Feier, Pausen-Timer): getrepcount.app, everlift App-Store-Eintrag, strengthlog.com, hevyapp.com, setgraph.app

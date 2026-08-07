# FlowRep x DropSync Fusion: Alle Fragen und Antworten

**Datum:** 2026-08-07  
**Status:** Alle Entscheidungen abgestimmt, Basis für Design Dokument  
**Vision:** FlowRep (Rep Zählung) + DropSync Timer (Musik + Timer) vereint zu einer Gym App. Modern, übersichtlich, Apple like poliert.

---

## Kurzfassung aller Entscheidungen

| Bereich | Frage | Antwort |
|---|---|---|
| Basis | Tech Stack | A: Kotlin bleibt, Paket `com.dropsync`, Anzeige `FlowRep` |
| Basis | Satz zu Pause Flow | B: One Tap Satz fertig |
| Basis | Trainingsscreen | A + Swipe durch Modi |
| Basis | Musik in Pause vs Satz | A: Rest / Work Playlisten getrennt |
| Basis | App Navigation | A: 4 Tabs, Tiefe in Einstellungen |
| 1 | Sensor Pflicht | A: Ohne Stick voll nutzbar, mit Stick Premium |
| 1b | Kalibrierung | A: Pflicht pro Übung beim ersten Mal, jederzeit neu startbar |
| 2 | Falschzählung korrigieren | A: +/- direkt im Satz + Undo 5s |
| 3 | Satz Start | Hybrid: Manuell tappen oder auto wenn Rest Timer auf Go geht |
| 4 | Pausendauer | A: Pro Übung speicherbar + Chips |
| 5 | Timer Arten | A: Nur Pausen Timer |
| 6 | Musikquelle | A: Nur lokal offline per SAF |
| 7 | Playlisten Label | A: Label Rest / Work wie jetzt |
| 8 | Drop Marker setzen | A: Manuell + Auto Erkennung mit Review |
| 9 | Drop Landung Fallback | A: Fallback Kette, Import auto Waveform + Drop, manuell verschiebbar |
| 10 | Klang / EQ | A: Alles in Einstellungen versteckt |
| 11 | Übungen | C: Nur eigene, Start mit 5 aus FlowRep |
| 12 | Routinen | C: Keine Routinen |
| 13 | Gewicht Eingabe | A: Zahl + zuletzt Platzhalter + +/- 2,5 kg |
| 14 | Velocity | C: Gar nicht im Training anzeigen |
| 15 | RPE / RIR | A: Kein Feld |
| 16 | Ansagen | A: Minimal nur 3-2-1 + Go mit Ducking |
| 17 | Verlauf | A: Schlank Liste + Volumen Linie + PR Abzeichen |
| 18 | Herzfrequenz | C: Ganz weglassen |
| 19 | Hintergrund | A: Foreground Service + Notification |
| 20 | Erster Start | C: Kein Onboarding, direkt 4 Tabs |
| 21 | Name / Paket | A: Anzeige FlowRep, Paket com.dropsync |
| 22 | Daten Migration | C: Frischer Start, nichts migrieren |
| 23 | Theme | C: Schalter hell / dunkel / System |
| 24 | Sensor verbinden | A: Chip oben im Train Screen 1 Tap |
| 25 | Export | C: Kein Export |
| 26 | Berechtigungen | B: Alle beim ersten Start auf einmal + Prüfung + Sprung zu Einstellungen |
| 27 | Session Klammer | C: Keine Sessions + Button Übung abschließen |
| 28 | Übung wechseln | A: Chip oben + Sheet mit eigenen Übungen |
| 29 | Tabs | A: Train / Music / Verlauf / Einstellungen, Train ist Start |
| 30 | Kamera Pose | A: Raus für den Start |
| 31 | Lautstärke Pause | A: Fix leiser mit 3s Crossfade, einstellbar, muss vor Drop durch sein |
| 32 | Musik Bibliothek | A: Alles behalten wie jetzt |
| 33 | Rest zu kurz für Drop | C: Direkt zum Drop springen |
| 34 | Sensor Abriss | A: Zählung friert ein, weiter per +/- |
| 35 | M5 Hardware Taste | A: Behalten mit Kalibrier Check |
| 36 | Alten Satz korrigieren | A: Im Verlauf antippen ändern/löschen + 5s Undo |
| 37 | Mehrere Drops pro Song | B: Nächstgelegener passender Drop gewinnt |
| 38 | Manueller Eingriff | A: Du hast Vorrang + Schalter im Countdown für Drop Automatik |
| 39 | Reps ohne Sensor | A: Gleiche +/- als Haupteingabe |
| 40 | Pause Notification | A: Timer + Skip + +15s + Übung abschließen |
| 41 | Go Meldung | A: Einmal Go + Haptik + Drop, danach still |
| 42 | Bodyweight | C: Gibt es nicht, nur mit Gewicht |
| 43 | Gewicht Einheit | A: Nur kg |
| 44 | PR Definition | B: Höchstes Volumen kg x Reps |
| 45 | Kalibrier Status sichtbar | A: Häkchen direkt an der Übung |

---

## Detail: Alle Fragen und Antworten

### Basis Entscheidungen vor dem Grilling

**B0. Tech Basis**
Frage: Welcher Stack bleibt?
Optionen: A Kotlin Basis, B Flutter Basis, C Zwei Apps mit Brücke
Antwort: **A**
Details: DropSync Module bleiben (`:domain:audio`, `:data:audio`, `:feature:player`, `TrackAnalyzer`, `CrossfadeController` etc). FlowRep Logik wird portiert als neue Module `:domain:sensor` + `:data:sensor` (BleProtocolParser, PeakDetector, WorkoutEngine).

**B1. Satz zu Pause Wechsel**
Frage: Wie startet Pause?
Optionen: A Vollautomatik, B One Tap, C Music Lead
Antwort: **B**
Details: Tap Satz fertig löst alles aus. App rechnet `Start Work Song = Restende - (Marker - Intro)` und landet Drop exakt auf Go.

**B2. Aktiver Trainingsscreen**
Frage: Wie sieht der Screen aus?
Optionen: A Rep Hero, B 50/50 Split, C Swipe Modi
Antwort: **A + Swipe**
Details: Rep Hero groß in Mitte (Zahl + Waveform + Gewicht), Timer als Pille oben, Musik als Mini Bar unten. Swipe schaltet Train (Default) zu Music Fokus zu Stats.

**B3. Musik in Pause vs Satz**
Frage: Wie schaltet Musik?
Optionen: A Rest/Work Playlisten getrennt, B Eine Playlist durch, C Energie adaptiv
Antwort: **A**
Details: Label `Rest` / `Work` an Playlisten wie jetzt in DropSync. RestMusicCoordinator + DropLandingPlanner per crossfadeTo.

**B4. App Gefühl**
Frage: Wie tief ist die App?
Optionen: A 4 Tabs Tiefe versteckt, B Alles offen 5-6 Tabs, C Nur Workout
Antwort: **A**
Details: Train / Music / Progress / Einstellungen. Tiefe wie EQ, Bit Perfect, Health etc nur in Einstellungen.

---

### Bereich 1: Sensor Hardware

**Frage:** Muss die App mit M5Stick funktionieren oder auch ohne?
Optionen: A Ohne Stick voll nutzbar, B Stick Pflicht, C Zwei Modi im Launcher
Antwort: **A**
Details: Ohne Stick manueller Tracker per Tap, mit Stick Premium Auto Zählung. Timer und Musik laufen immer.

**Frage 1b: Kalibrierung**
Frage: Wie streng kalibrieren?
Optionen: A Pflicht pro Übung beim ersten Mal, B Mit Defaults starten, C Eine generische für alle
Antwort: **A + jederzeit neu**
Details: Erste Nutzung einer Übung mit Stick führt 20 bis 30s durch 3 langsame Reps. Danach Häkchen. Im Übungsdetail jederzeit neu kalibrieren.

### Bereich 2: Falschzählung korrigieren

**Frage:** Wie korrigierst du im Satz?
Optionen: A Direkt +/- im Satz, B Nur nach Satz Dialog, C Swipe
Antwort: **A**
Details: Große Rep Zahl, darunter kleine - und + Buttons. Tipp korrigiert sofort. Nach Satzende 5s Undo Snackbar.

### Bereich 3: Satz Start

**Frage:** Wie beginnt ein Satz?
Optionen: A Auto bei Bewegung, B Immer per Tap, C Timer Go startet Satz
Antwort: **Hybrid**
Details: Du kannst jederzeit Satz starten tappen. Wenn Rest Timer auf Go fällt startet Satz automatisch mit. So maximale Kontrolle ohne Extra Pflicht.

### Bereich 4: Pausendauer

**Frage:** Woher weiß App wie lange Pause?
Optionen: A Pro Übung speicherbar + Chips, B Adaptiv nach Velocity, C Jedes Mal frei wählen
Antwort: **A**
Details: Jede Übung merkt Standard (zB Bankdrücken 150s). Chips +/-15s, Skip. In Einstellungen editierbar.

### Bereich 5: Timer Arten

**Frage:** Brauchst du freie Timer außer Pausen Timer?
Optionen: A Nur Pausen Timer, B Plus freie Timer (Countdown/Stoppuhr/EMOM/AMRAP), C Volles Intervall (Tabata/HIIT)
Antwort: **A**
Details: Nur Pausen Timer mit 3-2-1 Pre Countdown und TTS.

### Bereich 6: Musikquelle

**Frage:** Woher kommt Musik?
Optionen: A Nur lokal offline, B Lokal plus Spotify extern, C Streaming integriert
Antwort: **A**
Details: SAF Ordner Scan, FFmpeg, M3U, alles offline. Kein Konto, kein Netz nötig im Gym.

### Bereich 7: Playlisten Rest/Work

**Frage:** Wie ordnest du Songs zu?
Optionen: A Label wie jetzt (additiv Rest/Work), B Strikte Trennung zwei Töpfe, C Pro Übung eigene Rest Playlist
Antwort: **A**
Details: Additive Spalte `label` in Playlisten, DB v3->v4. Flexibel und passt zu bestehender Logik.

### Bereich 8: Drop Marker setzen

**Frage:** Wie legst du Drop fest?
Optionen: A Beides manuell + Auto mit Review, B Nur manuell, C Nur automatisch
Antwort: **A**
Details: Waveform Long Press auf freie Fläche setzt Drop (Label Drop), nah am Tick löscht nach Bestätigung. Auto Erkennung per Song Menü erzeugt Top 5 Kandidaten als `AUTO_DETECTED isEnabled=false`, Review in Einstellungen zum Bestätigen.

### Bereich 9: Drop Landung Fallback + Import

**Frage:** Was wenn Rest Song keinen Marker hat? + Import Verhalten?
Optionen: A Fallback Kette, B Nur mit Marker, C Bei fehlendem Marker auto raten
Antwort: **A + Import auto Waveform und Drop, manuell verschiebbar**
Details: Fallback: 1 Marker vorhanden dann exakte Landung, 2 kein Marker dann normaler Übergang ab Songstart, 3 keine Rest Playlist dann nur ducking. Import generiert für jeden neuen Song automatisch Waveform + Drop Kandidaten (TrackAnalyzer + OnsetDetection). Jeder Drop jederzeit auf Waveform verschiebbar (Tap springt, Drag Vorschau).

### Bereich 10: Klang im Gym

**Frage:** Wie viel EQ im Alltag?
Optionen: A Alles in Einstellungen versteckt, B EQ direkt in Now Playing, C Einfach vs Pro Schalter
Antwort: **A**
Details: Standard Preset klingt ab Start gut. EQ 32 Bänder, Bass/Höhen, Stereo, Reverb, DVC, Bit Perfect nur in Einstellungen unter Audio und DSP. Now Playing nur Lautstärke und Play/Pause.

### Bereich 11: Übungen

**Frage:** Feste Liste oder eigene?
Optionen: A 50 Starter + eigene, B Nur große feste DB 300+, C Nur eigene
Antwort: **C**
Details: Nur eigene Übungen, Start mit 5 aus FlowRep. Slugs Muskel Mapping bleibt im Hintergrund.

### Bereich 12: Routinen

**Frage:** Willst du Workouts als Plan speichern?
Optionen: A Letzte Session wiederholen + einfache Routinen, B Voller Plan Builder, C Gar keine Routinen
Antwort: **C**
Details: Immer frei loggen was du gerade machst.

### Bereich 13: Gewicht Eingabe

**Frage:** Wie tippst du Gewicht?
Optionen: A Zahl + zuletzt Platzhalter +/-, B Plattenrechner visuell, C Beides
Antwort: **A**
Details: Feld zeigt zuletzt grau, +/- 2,5 kg. Intern Millikilogramm.

### Bereich 14: Velocity

**Frage:** Willst du Tempo pro Rep sehen?
Optionen: A Dezent unter Rep Zahl, B Nur nach Satz, C Gar nicht
Antwort: **C**
Details: Daten werden intern gespeichert für Verlauf, nie im Training gezeigt.

### Bereich 15: RPE / RIR

**Frage:** Willst du Anstrengung eintragen?
Optionen: A Gar kein Feld, B Optional RPE 6-10, C RIR 0-4
Antwort: **A**
Details: Nur Gewicht und Reps loggen.

### Bereich 16: Ansagen

**Frage:** Wie viel soll App sprechen?
Optionen: A Minimal, B Viel pro Rep, C Alles stumm nur Haptik
Antwort: **A**
Details: Nur 3-2-1 Countdown und Go per TTS mit Ducking via Preamp, nie während Reps.

### Bereich 17: Verlauf

**Frage:** Was siehst du nach Training?
Optionen: A Schlank motivierend, B Pro Übung tief, C Nur Liste
Antwort: **A**
Details: History Liste Datum + Übungen + Sätze, Gesamtvolumen pro Training, einfache Linie Volumen über Zeit, PR Abzeichen.

### Bereich 18: Herzfrequenz

**Frage:** Willst du Puls live sehen?
Optionen: A Kleines Badge im Train Screen, B Nur im Verlauf, C Ganz weglassen
Antwort: **C**
Details: Kein Health Connect für Start.

### Bereich 19: Hintergrund

**Frage:** Soll Timer/Musik weiterlaufen wenn App im Hintergrund/Screen aus?
Optionen: A Ja mit Foreground Service + Notification, B Nur wenn App offen
Antwort: **A**
Details: MediaLibrarySession + Timer Service. Handy kann in Hosentasche bleiben, Drop landet auch bei Screen aus.

### Bereich 20: Erster Start

**Frage:** Wie führt App beim ersten Öffnen?
Optionen: A 3 Schritte in 60s, B Getrennte Setups, C Kein Onboarding
Antwort: **C**
Details: Direkt leere App mit 4 Tabs, alles entdecken.

### Bereich 21: Name und Paket

**Frage:** Wie heißt vereinte App?
Optionen: A Anzeige FlowRep Paket com.dropsync, B Alles auf com.flowrep, C Doppelname
Antwort: **A**
Details: Kontinuität, keine Migration nötig. Room und DataStore bleiben.

### Bereich 22: Daten beim Zusammenführen

**Frage:** Was mit alten FlowRep Trainings?
Optionen: A Frischer Start + CSV Import, B Beide DBs migrieren, C Nichts migrieren History neu
Antwort: **C**
Details: Alte Drift/SQLCipher Daten bleiben als Archiv auf Handy falls vorhanden, neue App fängt bei 0 an. Keine Import Funktion.

### Bereich 23: Theme

**Frage:** Hell oder dunkel?
Optionen: A Hell Standard dunkel nach System, B Immer dunkel, C Schalter hell/dunkel/System
Antwort: **C**
Details: Designsystem Farben #0D0D0D / #FFFFFF / Lime #DFFF2F. Material 3 mit eigenem ColorScheme.

### Bereich 24: Sensor verbinden

**Frage:** Wie startest du Verbindung?
Optionen: A Chip oben 1 Tap, B Eigener Verbinden Screen, C Immer auto im Hintergrund
Antwort: **A**
Details: Pille Getrennt tippen zum Verbinden scannt nach FlowRep/GymTracker, zeigt Verbunden + Akku. Fehler auf Deutsch via BleErrorMapper.

### Bereich 25: Export

**Frage:** Brauchst du Export?
Optionen: A Nur CSV Export auf Wunsch, B Automatisches Backup File, C Gar kein Export
Antwort: **C**
Details: Daten nur in App, kein Teilen.

### Bereich 26: Berechtigungen

**Frage:** Wann fragt App Rechte ab?
Optionen: A Erst bei Nutzung, B Alles beim ersten Start auf einmal
Antwort: **B + Prüfung + Sprung zu Einstellungen**
Details: Beim ersten Start alle Dialoge nacheinander (BLUETOOTH_SCAN/CONNECT, POST_NOTIFICATIONS, SAF). Danach Prüfung ob erteilt, bei Xiaomi/HyperOS extra Check plus Button In Einstellungen öffnen falls verweigert.

### Bereich 27: Session Klammer

**Frage:** Wann startet/endet Training?
Optionen: A Explizit Start/Ende tippen, B Immer offen endet von selbst, C Gar keine Sessions
Antwort: **C + Button Übung abschließen**
Details: Flache Liste Satz = Zeitstempel + Übung + Gewicht + Reps. Nach jedem Satz startet Rest Timer auto. Button Übung abschließen stoppt Rest sofort, Musik zurück auf laut, nächste Übung wählen. Ohne Button läuft Rest bis Go.

### Bereich 28: Übung wechseln

**Frage:** Wie wählst du nächste Übung?
Optionen: A Eigenes Chip oben + Liste, B Suchfeld, C Swipe
Antwort: **A**
Details: Chip Bankdrücken ▼ oben tippen öffnet Sheet mit eigenen Übungen + Neue anlegen. Wechsel bricht laufenden Rest ab.

### Bereich 29: Tabs

**Frage:** Wie heißen 4 Tabs und Reihenfolge?
Optionen: A Train/Music/Verlauf/Einstellungen Train Start, B Train/Verlauf/Music/Einstellungen, C Andere Namen/5 Tabs
Antwort: **A**
Details: 4 feste Tabs unten, Train ist Start Tab.

### Bereich 30: Kamera Pose

**Frage:** Kamera als Gegenprobe behalten?
Optionen: A Raus für Start, B Drin optional, C Kamera ersetzt Sensor
Antwort: **A**
Details: Code bleibt im Repo nicht ausgeliefert. Keine CAMERA Berechtigung.

### Bereich 31: Lautstärke Pause

**Frage:** Wie laut in Pause und Übergang?
Optionen: A Fix leiser mit weichem Crossfade 3s, B Stumm, C Einstellbar in Einstellungen
Antwort: **A + einstellbar, muss vor Drop durch sein**
Details: Rest Musik ca 30% leiser via Preamp (nicht Player Volume, kollisionsfrei zu TTS Ducking). Übergang Equal Power sqrt(1 - fadeIn²) 3s. In Einstellungen einstellbar. Rechnung `Start Work = Restende - Markerzeit`, Crossfade wird abgezogen, Drop knallt voll.

### Bereich 32: Musik Bibliothek

**Frage:** Was willst du in Music sehen?
Optionen: A Alles wie jetzt, B Nur Titel + Playlisten + Suche
Antwort: **A**
Details: Titel, Alben, Künstler, Genres, Ordner, Suche, Favoriten, zuletzt/meistgespielt, Alphabet Scroller, Chips oben, Playlisten eigene Ansicht.

### Bereich 33: Rest zu kurz für Drop

**Frage:** Restdauer < Zeit bis Drop?
Optionen: A Normaler Übergang + Hinweis, B Besten anderen Song suchen, C Drop vorziehen direkt zum Drop springen
Antwort: **C**
Details: Springt direkt zum Drop statt Intro. Mit Regel Rest ab 60s greift Fall fast nie.

### Bereich 34: Sensor Abriss

**Frage:** BLE reißt mitten im Satz ab?
Optionen: A Satz läuft manuell weiter + Banner, B Satz sofort beenden, C Pause und warten
Antwort: **A**
Details: Zählung friert, Pille Sensor getrennt Reps per +/- weiter, bei Reconnect sofort auto weiter.

### Bereich 35: M5 Hardware Taste

**Frage:** Stick Taste behalten?
Optionen: A Behalten mit Kalibrier Check, B Ignorieren
Antwort: **A**
Details: Kurz Druck schaltet Satz wie Tap, langer Druck bricht ab. Prüft vorher Kalibrierung, sonst Vibrieren + Handy zeigt Erst kalibrieren.

### Bereich 36: Alten Satz korrigieren

**Frage:** Gewicht/Reps vertippt?
Optionen: A Im Verlauf antippen ändern/löschen + Undo, B Nur löschen dann neu, C Gar nicht ändern
Antwort: **A**
Details: Tap im Verlauf öffnet Sheet Gewicht/Reps ändern + Löschen, danach 5s Undo Snackbar, PRs still neu.

### Bereich 37: Mehrere Drops pro Song

**Frage:** Welche Drop Landung wenn mehrere Marker?
Optionen: A Ein Primary pro Song, B Nächstgelegener passender gewinnt, C Erster passender gewinnt
Antwort: **B**
Details: Planer wählt Drop der am besten zur Restdauer passt.

### Bereich 38: Manueller Eingriff während Rest Musik

**Frage:** Du drückst Skip/Pause während Automatik plant?
Optionen: A Du hast Vorrang Automatik bricht für Pause, B Automatik zieht durch, C App fragt nach
Antwort: **A + Schalter im Countdown**
Details: Dein Tap überschreibt Queue für diese Pause, Timer läuft weiter. Zusätzlich kleiner Schalter im Countdown um Drop Automatik pro Pause an/aus zu machen. Nächste Pause wieder auto an.

### Bereich 39: Reps ohne Sensor

**Frage:** Wie loggst du Reps ohne Stick?
Optionen: A Gleiche +/- als Haupt Eingabe, B Nur Zahl tippen, C Swipe
Antwort: **A**
Details: Große Rep Zahl, -/+ darunter, Tap auf Zahl öffnet Tastatur.

### Bereich 40: Pause Notification

**Frage:** Was zeigt Notification?
Optionen: A Timer + Skip + +15s + Übung abschließen, B Nur Timer + Skip/+15s, C Viel inkl Pause/Musik Skip
Antwort: **A**
Details: Zeile 1 Pause Übung Zeit, Action Buttons Skip, +15s, Übung abschließen.

### Bereich 41: Go Meldung

**Frage:** Wie meldet App Go bei 0?
Optionen: A Einmal Go + Haptik + Drop danach still, B Loop bis Reaktion, C Nur Haptik
Antwort: **A**
Details: Einmal TTS Go, starker Haptik Impuls, Work Song voll auf Drop. Danach Notification Bereit tippe Satz starten, wartet still.

### Bereich 42: Bodyweight

**Frage:** Übungen ohne Gewicht?
Optionen: A Gewicht optional + Zusatzgewicht Feld, B Schalter Bodyweight, C Immer Gewicht verlangen
Antwort: **C -> Gibt es nicht**
Details: Nur Übungen mit Gewicht.

### Bereich 43: Gewicht Einheit

**Frage:** kg oder lbs?
Optionen: A Nur kg, B Umschaltbar kg/lbs
Antwort: **A**
Details: Nur kg, Eingabe mit Komma, intern Millikilogramm.

### Bereich 44: PR Definition

**Frage:** Was zählt als PR?
Optionen: A Schwerstes Gewicht, B Höchstes Volumen, C Beides
Antwort: **B**
Details: Max kg x Reps je Übung.

### Bereich 45: Kalibrier Status sichtbar

**Frage:** Wo siehst du ob Übung kalibriert ist?
Optionen: A Häkchen direkt an Übung, B Eigener Status Screen, C Gar nicht
Antwort: **A**
Details: Grünes Häkchen am Chip und im Sheet, Untertext Kalibriert für FlowRep #A3, Link neu kalibrieren.

---

## Offene Punkte für Design Dokument

Alle 45 + 5 Basis Entscheidungen sind geklärt. Nächster Schritt ist das Design Dokument mit Architektur, Datenfluss, Screens, Musik Workout Kopplung und Implementierungsplan.

Vorschlag Nächster Schritt: Design Dokument in `docs/plans/YYYY-MM-DD-flowrep-dropsync-fusion-design.md` schreiben und danach per Plan Review abstimmen.

---

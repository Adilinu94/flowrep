# FlowRep x DropSync Fusion: Detail Design

**Datum:** 2026-08-07  
**Status:** Abgestimmt auf 50 Entscheidungen (5 Basis + 45 Grilling), bereit für Umsetzung  
**Basis:** `FLOWREP_DROPSYNC_FUSION_FRAGEN_ANTWORTEN_2026-08-07.md`  
**Ziel:** Eine Gym App. Offline, Apple like poliert, 4 Tabs. Sensor optional, Musik und Timer greifen exakt ineinander. Drop landet auf die Sekunde bei Go.

---

## 1. Vision und Prinzipien

**Was bauen wir:** FlowRep (Rep Zählung per M5Stick BLE) und DropSync Timer (Offline Musik Player mit Drop Sync) werden zu einer nativen Android App (Kotlin, Jetpack Compose, Media3).

**Prinzipien aus den Entscheidungen:**

1. Ohne Stick voll nutzbar, mit Stick Premium. Niemand wird ausgeschlossen.
2. One Tap löst alles. Tap Satz fertig startet Rest Timer und plant Drop Landung im Hintergrund.
3. Train ist Hero. Große Rep Zahl, Waveform, Gewicht. Alles andere ist Swipe oder Mini Bar.
4. Rest und Work Playlisten getrennt per Label. Rest leise, Work knallt auf Drop.
5. Tiefe versteckt. 4 Tabs klar, alles Power wie EQ und Bit Perfect nur in Einstellungen.
6. Nur mit Gewicht, nur kg, kein Onboarding, keine Sessions, keine Kamera, kein Export.
7. Rechnung vor Klang. `Start Work = Restende - Marker` muss fertig sein bevor Drop kommt.
8. Du hast immer Vorrang. Dein Skip bricht Automatik für diese Pause.

**Erfolg heißt:** Im Gym 95 Prozent der Zeit im Train Tab, ein Tap pro Satz, Musik trägt die Pause ohne Handgriff, Drop knallt bei Go, kein extra Setup pro Training.

---

## 2. Ist Stand beider Prototypen

### DropSync Timer (Kotlin, Gradl

e Multi Module, minSdk 26, target 37, JDK 17, Versionen nur in `gradle/libs.versions.toml`)

* Module: `:app` Navigation und Hilt, `:core:common` AppResult/AppError, `:core:model` Modelle, `:core:database` Room + Migrationen, `:core:designsystem` Theme + Komponenten, `:core:testing` Fakes, `:data:*` Repos, `:domain:*` Use Cases, `:feature:*` Compose Screens. Feature importiert nie anderes Feature, Domain nie Android UI/Room/Player. Architekturtest prüft Regeln.
* Offline Musik komplett: MediaStore Scan, Media3 Playback Service, `:domain:audio` + `:data:audio`, 32 Band EQ grafisch/parametrisch, Bass/Höhen, Stereo Breite, Reverb, Dither, Resampler, DVC, Presets, DSP Kette 64 Bit Double mit Float Output, Preamp + Limiter, MusicFX per useSystemEffects Bypass, Crossfade Dual Player 1 bis 12s mit 6 Presets (Fade/Rise/Blend/Wave/Melt/Slam) Equal Power `sqrt(1 - fadeIn^2)` plus Mikro Rampe für Slam, Gapless, Auto Resume onPlaybackResumption, Bit Perfect per AudioMixerAttributes API 34+, Profile je Ausgang DeviceProfileStore + OutputProfileController.
* Timer Kern: `:domain:timer` TimerEngine mit PREPARING 3-2-1, TTS Cues mit Ducking über Preamp Knoten (kollisionsfrei zu DVC), Haptik.
* Marker und Waveform: TrackAnalyzer Streaming Akkumulatoren Min/Max Buckets + RMS, Cache `track_analysis` DB v3 analyzer_version, MediaExtractor/MediaCodec, schiebbarer OneTimeWorkRequest dedupliziert `track_analysis_<songId>`, Waveform Compose Canvas Lime für gespielten Anteil, Tap springt Drag Vorschau, Fehlerfall bucket_count 0 fällt auf Zeitachse zurück. Manuelle Marker `createManualMarker`/`deleteMarker` als MANUAL mit Link in Transaktion, Long Press setzt/löscht. Auto OnsetDetection Novelty positive RMS Differenz, gleitender Schwellwert Mittel + k*Stdabw, Mindestabstand 5s Top 5 als `AUTO_DETECTED isEnabled=false`, Review in Einstellungen mit confirmMarker.
* Bibliothek: Room play_stats favorites playlists/playlist_items FTS4 song_fts genre Spalte, LibraryBrowseRepository Alben/Künstler/Genres/Ordner zuletzt/meistgespielt Favoriten Volltextsuche Playlisten CRUD/Move M3U Import, LibraryScreen mit Chips Suche Sort Filtern Format/Dauer/HiRes Schnellscroller HorizontalPager Drilldown, konfigurierbare Ansichten LibraryViewPreferencesRepository, Queue Editor Bottom Sheet am Mini Player, MediaLibraryService Browse Baum für Auto/BT.
* Workout Basis vorhanden: exercise_rest_prefs Rest Timer pro Übung DB v2, Übungen mit Slugs Muskel Mapping, Tausch KEEP/MOVE/DISCARD mit PR Neuberechnung, repeatLastSession, Routinen aus Session, ProgressSeriesBuilder + ProgressionClassifier, Charts LineChart/BarChart in designsystem, WorkoutFeature NavHost mit Prefill Rest Normal/DropSync Swap Dialog Track Chip, 18 Repo Tests plus Migration Tests. In Fusion fallen Routinen weg.
* Musik Workout Kopplung vorhanden: Playlisten Label Rest/Work additiv DB v3->v4, RestMusicBehavior reiner DropLandingPlanner in `:domain:timer`, RestMusicSettingsRepository/Store DataStore, RestMusicCoordinator in `:feature:player` beobachtet TimerEngine und Einstellung, setzt Rest Queue bei Pausenbeginn, terminiert Landung per `crossfadeTo` mit erweiterter CrossfadeController, Fallback Kette Nutzer Vorrang, Hardware Control via MediaLibrarySession + Doku `docs/hardware-control.md`, SmartShuffle, Rest Timer Presets, Get Ready Countdown.
* Herz via `:domain:health` + `:data:health` Health Connect HeartRateSource mit Permission Contract, connect-client 1.1.0, nur Foreground lesen, Badge in designsystem. Für Fusion nicht im Start.

### FlowRep (Flutter, M5StickC Plus2)

* 6 Screens: home_screen der fast alles trägt, calibration_wizard, history, settings, camera_session, sensor_placement_tutorial. Keine Bottom Nav, alles bedingt an home. Theme nur `colorSchemeSeed Colors.deepPurple`.
* Sensor: BLE GATT Service `0000fee0...` mit Chars fee1 SensorData 52/53 Byte, fee2 Control, fee3 Battery, fee4 DeviceEvent. Parser 4 Samples x 12 Byte ax ay az gx gy gz Skalen accel 0.001 gyro 0.01 v1 0.02 v2, 20ms Sample Abstand, JitterBuffer 6*20ms = 120ms Latenz, BatchDedupTracker duplicateSkips und estimatedMissedBatches. Scan Namen FlowRep bevorzugt und GymTracker legacy. Polling statt Notify wegen HyperOS 30Hz Poll vs 12.5Hz Batch 80ms. M5 BtnA Event löst Satz.
* Engine: Zwei Pipelines WorkoutEngine live und ExerciseEngine/PeakDetector/PhaseValidator im Schatten, PCA Jacobi Kalibrierung pro Übung und Gerät persistiert, Velocity Loss und adaptive Pause, Audio First Blind Mode Haptik+Sound, Kamera Vision Agreement, Korrektur Dialog, CSV Export, Drift+SQLCipher, M5 Tasten Steuerung.
* Lücken: Keine Anzeige kalibriert, BtnA umgeht Kalibrierprüfung, kein Plattenrechner, history nur flache Liste + CustomPaint Trend, kein Onboarding Flow, Dummy Stream Button, kein Branding.

---

## 3. Zielbild der fusionierten App

**Name Anzeige:** FlowRep  
**Paket:** `com.dropsync` bleibt, keine Migration, Room und DataStore bleiben Quelle.  
**Navigation:** 4 Tabs unten, Start Train. Kein Onboarding, direkt leere App.

| Tab | Inhalt | Swipe Modi im Train |
|---|---|---|
| Train | Hero Rep + Waveform + Gewicht, Chip Übung, Pille Timer, Mini Musik Bar | Train Default, Music Fokus, Verlauf Mini |
| Music | Bibliothek Titel/Alben/Künstler/Genres/Ordner, Chips, Suche, Favoriten, Playlisten (Label Rest/Work), Now Playing mit Cover Waveform Marker Scrubbing, Queue Bottom Sheet | - |
| Verlauf | Flache Liste Sätze zeitlich, Gruppe pro Tag, Volumen Linie über Zeit, PR Abzeichen | - |
| Einstellungen | Sensor Status, Musik Ordner, Audio und DSP (EQ Presets Klang DVC Bit Perfect Profile Crossfade Mix Presets), Theme, Berechtigungs Check | - |

**Offline:** Kein Konto, kein Netz, Auto Backup aus, Zeit UTC Epoch Millis, Gewicht Long Millikilogramm.

---

## 4. Architektur

### 4.1 Module neu und bleibend

```
:app                 Navigation + Hilt, keine Fachlogik
:core:common         AppResult, AppError, Clock, DispatcherProvider
:core:model          reine Modelle
:core:database       Room DAOs Migrationen JSON Schemas
:core:designsystem   Theme, Tokens, Komponenten, Charts
:core:testing        Fakes, Regeln
:data:audio          MediaStore, Media3, TrackAnalyzer Cache
:data:health         bleibt Code aber nicht genutzt in Start
:data:sensor   NEU   BleSensorProvider, Parser, JitterBuffer, Dedup
:data:timer          Timer Repos
:data:workout        Übungen, Sätze, Prefs, Play Stats
:domain:audio        DSP, Presets, Analyse, Onset
:domain:health       bleibt aber nicht verdrahtet Start
:domain:sensor NEU   Sensor Vertrag, Engine Port, Peak, Phase, Velocity
:domain:timer        TimerEngine, DropLandingPlanner, RestMusicBehavior
:domain:workout      Übungen Logik, Slugs, PR Volumen, Series
:feature:audio       EQ etc in Einstellungen
:feature:library     Bibliothek Screens
:feature:player      Playback, Now Playing, RestMusicCoordinator
:feature:settings    Einstellungen inkl Sensor + Rechte Check
:feature:train  NEU  Train Hero, Timer Pille, Mini Player, Verlauf
:feature:workout     bleibt teils, nutzt Domain Workout, keine Routinen UI
```

**Regeln bleibend:** Feature kennt kein Room/ExoPlayer, Domain kein Android UI/Room/Player, Architekturtest in `:core:testing` prüft.

### 4.2 Datenfluss Hauptfall One Tap

```
Tap Satz fertig (TrainViewModel)
  -> speichert Satz {exerciseId, weightMg, reps, timestamp}
  -> lädt Restdauer für Übung aus exercise_rest_prefs + Presets
  -> startet TimerEngine Rest mit PREPARING 3-2-1 falls an
  -> postet DropRestRequestBus Workout fordert Rest an
  -> RestMusicCoordinator beobachtet TimerEngine + RestMusicSettings
        wählt Rest Playlisten mit label Rest
        ruft reinen DropLandingPlanner.plan(Restende, markerSec)
            rechnet Start Work = Restende - markerSec
            prüft Restdauer >= markerSec, sonst Sprung direkt zum Drop
            wählt bei mehreren Markern nächsten passenden (B Entscheidung 37)
        setzt Rest Queue, duckt Preamp ca -8dB (30% leiser, einstellbar)
        plant crossfadeTo mit Dauer 3s Equal Power, fertig vor Drop
  -> TTS 3-2-1 über DSP Preamp Duck, Haptik, Notification mit Timer + Actions
  -> bei Go: TTS Go einmal + Haptik stark, Work Song voll auf Drop, Notification auf Bereit
  -> Tap Satz starten oder auto bei erster Rep mit Stick beginnt nächster Satz
  -> Manueller Skip/Pause bricht Coordinator für diese Pause ab (Vorrang A), Schalter im Countdown toggelt Drop Automatik pro Pause
```

### 4.3 Sensor Datenfluss

```
M5Stick -> BLE Batch 53 Byte -> BleProtocolParser.parseBatch -> 4 SensorSample
  -> JitterBuffer (6*20ms) -> dedup via BatchDedupTracker -> PeakDetector -> PhaseValidator -> WorkoutEngine
  -> State Reps + Confidence -> TrainViewModel (Live Zahl + Waveform Sampling)
  Korrektur +/- schreibt Delta, persistiert für Kalibrier Nachlernen
  BtnA DeviceEvent fee4 -> _onDeviceEvent prüft Kalibrierung, sonst Vibrieren + Banner Erst kalibrieren
  Abriss: Verbindung weg -> Banner Sensor getrennt Reps per +/- weiter, bei Reconnect sofort auto
```

---

## 5. Datenmodell

### 5.1 Room

* `songs` + `track_analysis` (buckets, rms, bpm, camelot_key, analyzer_version, bucket_count)
* `song_markers` (MANUAL/AUTO_DETECTED, isEnabled, label Drop, millis)
* `exercises` (id, name, slugs Muskel, createdAt, calibratedDeviceId nullable, calibratedAt)
* `sets` flach (id, exerciseId, weightMg Long, reps Int, timestamp UTC Millis, prsVerarbeitet bool)
* `exercise_rest_prefs` (exerciseId, restMs, presetId)
* `play_stats` `favorites` `playlists`/`playlist_items` (label Rest/Work) `song_fts`
* Migrationen 1->2->3->4->5 weiterführen, neue 6 für sets flach falls Umbau nötig, JSON Schemas pro Stufe.

### 5.2 DataStore Preferences

* `RestMusicSettings` (behavior, dropAuto pro Pause default an, duckDb)
* `RestTimerPreferences` (presets, lastUsed pro Übung)
* `DspConfig` (mixPreset, crossfadeMs default 3000, enabled, bitPerfect)
* `DeviceProfile` (pro Ausgang, key activeOutputProfile)
* `LibraryViewPrefs` (sichtbare Ansichten, Reihenfolge)
* `ThemePrefs` (mode hell/dunkel/system)

### 5.3 Keine Sessions

Kein `workouts` Table. History gruppiert nur per Datum beim Lesen. Volumen pro Tag Summe `weightMg * reps`. PR Volumen ist max Gruppe je Übung.

---

## 6. Designsystem

**Tokens aus UI/Design.txt + BAUPLAN_UI_UX_POLISH:**

* Farben: Primary Black #0D0D0D, White #FFFFFF, Lime #DFFF2F (Range #D7FF34 #DBFF2E #E0FF36), Soft Gray #F5F5F5, Border #EAEAEA, Text Gray #6B6B6B, plus Report Spec dunkles Graphit #14161A für Dark Mode Basis statt purem Schwarz. Ratios 60 White 25 Black 10 Lime 5 Gray.
* Typo: Raleway überall, 400/500/600/700/800, Headlines 600-800, Body leicht. JetBrains Mono nur für Messwerte Reps/kg/m/s in Verlauf, sonst Raleway.
* Spacing 4 8 12 16 24 32 48 64 80 96 120, Radius Buttons 999 Pill, Cards 24, große Bilder 32, Floating 40, Shadow 0 10 30 rgba 0 0 0 0.08 und 0 20 60 0.12.
* Motion: Button 250ms ease translateY -2, Cards scale 1.02, Progress Spring, Charts Line Draw, Counter Count Up.
* Dark Mode: System folgen per ThemeMode.system, Schalter hell/dunkel/system in Einstellungen. Dark Basis #14161A, Lime bleibt Akzent, Charts blau #4A9EFF wird in Dark zu Lime 70% für Kontrast.
* Umsetzung: `core/designsystem/theme` mit `AppColors.kt` `AppTypography.kt` `AppSpacing.kt`, Material 3 ColorScheme aus Palette, TextTheme mit Raleway + Mono für Display.

---

## 7. Musik Workout Kopplung im Detail

### 7.1 DropLandingPlanner rein und testbar

```
Input: restEndEpochMs, markerSec (zB 47.3s), crossfadeMs (3000), introMs optional 0
Plan:
  markerOffsetMs = markerSec * 1000
  startWorkMs = restEndMs - markerOffsetMs
  crossfadeStartMs = startWorkMs - crossfadeMs // wenn нехватка kürzen
  wenn restDurationMs < markerOffsetMs
    dann plan = DIRECT_TO_DROP at dropSec (Springe direkt zum Drop, kein Intro)
  sonst
    plan = CROSSFADE_TO at startWorkMs mit Equal Power sqrt(1 - fade^2)
  Regel: crossfadeEndMs <= restEndMs, Drop knallt voll bei Go
```

* Bei mehreren Markern wählt Planner nach Entscheidung 37 den mit kleinstem |restDuration - markerSec| wobei markerSec <= restDuration bevorzugt, nächster passender gewinnt.
* Work Song Vorhören: Work Queue als MediaItems mit seek auf 0, Rest Queue läuft leise, CrossfadeController Equal Power schiebt Work leise nach laut während Rest laut nach leise.
* Fallback Kette: 1 Marker -> exakt, 2 kein Marker -> normaler Übergang ab 0, 3 keine Rest Playlist -> nur ducking ohne Queue Wechsel.
* Einstellbarkeit: Rest Lautstärke -12 bis 0 dB (Default -8dB ca 30%), Crossfade 1000 bis 12000ms Default 3000, MixPreset 6 Chips mit Erklärung, Bit Perfect Hinweis wenn an -> DSP/Crossfade gebypassed.

### 7.1a Audio-Architektur (Zwei Player)

```
Ein MediaSessionService
  ├── RestPlayer (ExoPlayer)
  ├── WorkPlayer (ExoPlayer)
  ├── AudioFocusController
  ├── RouteMonitor
  └── UnderrunMonitor
        ↓
DropLandingPlanner (monotonic Go-Deadline, Marker-Frame, Route-Profil, Generation, EXACT/DEGRADED/BEST_EFFORT)
        ↓
GainController (ReplayGain optional, Rest-Duck, TTS-Duck, Crossfade-Gain, Limiter)
```

* **MVP:** Zwei ExoPlayer im selben MediaSessionService, gleicher Audio-Output, WorkPlayer frühzeitig vorbereiten (Preload), zunächst stumm, Volume-Rampen über zentralen Scheduler. Kein `MergingMediaSource`, kein `ConcatenatingMediaSource` fürs Mischen, kein MediaSource.Factory als Mixer.
* **Sample-Rate-Wechsel 48k->44.1k:** Kann AudioSink-Neukonfiguration + neuen Resampler bedeuten; nicht als sample-identisch annehmen, kurz testen, Preload der zweiten Datei vor Ende der ersten.
* **Später (Präzisionsstufe):** Gemeinsamer PCM-Mixer -> ein AudioSink (Decoder A + Decoder B), analog Poweramp Pipeline2. Nur wenn gemessen, nicht präventiv.
* **Gain-Rampen:** 5-10ms Zielpunkte über zentralen Audio-/Handler-Thread, nicht im Main-Thread, nicht per Coroutine-Handler, keine Lautstärkeänderung im Main-Thread.
* **Buffer:** Puffergröße gemeinsam mit Route-Latenzprofil kalibrieren, nicht blind vergrößern (größere Puffer = mehr Latenz).

### 7.1b AudioFocus im Gym

AudioFocus liegt im Playback-Service (nicht im Timer, nicht in Compose).

| Ereignis | Musik | Timer | Drop-Plan |
|---|---|---|---|
| LOSS_TRANSIENT_CAN_DUCK | ducken | weiter | weiter |
| LOSS_TRANSIENT | pausieren oder stark ducken | weiter | als unsicher markieren |
| permanenter LOSS | stoppen | Zustand speichern | abbrechen/neu planen |
| Fokus zurück | kontrolliert fortsetzen | weiter | nur fortsetzen wenn Zeitbasis gültig |

* Bei Anruf Musik normalerweise pausieren, bei kurzen Notifications reicht Ducking.
* Timer läuft auf monotonic weiter. Wenn Audio während des geplanten Drops pausiert: `EXACT -> DEGRADED -> REARM_REQUIRED`, nie so tun als wäre der Drop noch synchron.

### 7.1c Drop-Seek mit Preroll

* Bei MP3/AAC/Opus startet Decoder am nächsten Sync-Punkt. Pro Marker speichern:
  `markerFrame` (hörbarer Impact) + `seekPrerollFrame` (Decoder-Einstieg), damit der Direct-Drop-Sprung nicht am falschen Punkt landet.
* Vor Go WorkPlayer frühzeitig vorbereiten und bis zum Marker dekodieren lassen, nicht erst beim Countdown-Ende seeken.

### 7.2 Lautstärke Wege getrennt

* TTS Ducking läuft über DSP Preamp Knoten, nicht Player Volume, damit DVC und User Lautstärke nicht kollidieren.
* Rest Duck ist separater Preamp Node Wert, addiert sich nicht doppelt mit TTS, Coordinator pausiert TTS während Crossfade End Phase 500ms für sauberen Drop.
* Ducking: `effectiveDuckDb = min(restDuckDb, ttsDuckDb)`, nie additiv. Rampen Attack 20-50ms, Release 150-300ms. Kein Doppel-Ducking, Limiter am Master.
* ReplayGain ist NICHT in v1. Später als Option unter Audio in Einstellungen.

### 7.3 Countdown und Haptik

* Countdown-Piep-Töne statt TTS-Stimme: vorgerenderte Clips (Beep kurz x3, längerer Beep = Go), vor dem Countdown dekodieren, über Gain-/Mixer-Pfad auf feste Audio-Frames planen, Go ist ein echtes Audio-Event. (TTS später möglich, nicht Standard.)
* Haptik: Go-Zeit ist autoritativ, Haptik nicht auf TTS/onStart warten. Starker Puls 100-160ms, optional zweiter Puls 30-60ms später. `vibrator.hasAmplitudeControl()` prüfen, sonst One-Shot-Fallback. Keine feinen Amplitudenstufen voraussetzen.
* Underrun-Monitoring: `onPlaybackStateChanged`, `onAudioUnderrun` (AnalyticsListener), `getUnderrunCount` wo AudioTrack zugänglich. STATE_BUFFERING != AudioTrack-Underrun. Bei instabiler Audio-Clock -> BEST_EFFORT.
* MISSED_UNDERRUN: Wenn Drop am Go verpasst, nicht mehrfach nachtriggern, Work weiterlaufen lassen, automatisch nächsten passenden Drop anbieten, leiser Hinweis.

---

## 8. Screens im Detail

### 8.1 Train (Start Tab)

**Top:** Verbindungs Chip Pille. Zustände: Getrennt tippen zum Verbinden -> Scan -> Verbunden + Akku 78% -> Tippen zeigt Sheet mit Gerät wechseln/trennen. Fehler auf Deutsch via BleErrorMapper kurz unter Chip: Bluetooth ist ausgeschaltet bitte in Einstellungen aktivieren, Sensor nicht gefunden FlowRep/GymTracker, MTU, Berechtigung, busy.

**Mitte Hero:** Übungs Chip `Bankdrücken ▼` mit Häkchen grün wenn kalibriert für dieses Gerät, darunter Link `Kalibriert für FlowRep #A3 neu kalibrieren` -> Calibration Wizard. Große Rep Zahl 120sp Raleway ExtraBold, darunter Waveform Live Linie 120ms Latenz aus Sensor Stream, bei Peak Blitz Lime. Gewicht Feld `80 kg zuletzt 80 kg grau` plus Chips -2.5 / +2.5, Zahl tippen öffnet Ziffern Tastatur mit Komma. Darunter Rep Eingabe `- 12 +` groß 56h Pill, Tap auf 12 öffnet Ziffern Tastatur. Hinweis: Ohne Stick sind `-/+` Haupt Zähler, mit Stick Korrektur.

**Timer Pille:** Nach Tap Satz fertig erscheint Pille `Pause Bankdrücken 01:28 ▼` mit Mini Schalter rechts `Drop Auto an/aus` pro Pause, Chips `Skip` `+15s` `Übung abschließen`. Bei Rest zu kurz kleine Warn Zeile darunter normaler Text. Countdown TTS 3-2-1, bei 0 einmal Go + Haptik.

**Buttons:** `Satz fertig` Pill Lime schwarz, `Satz starten` schwarzer Ghost, `Übung abschließen` Text Button stoppt Timer sofort, setzt Musik laut, Chip wieder wählbar.

**Mini Musik Bar unten:** Cover 48dp, Titel + Künstler, nächster Drop Badge zB `Drop bei 0:47`, Tap öffnet Now Playing Vollbild.

**Swipe:** Horizontal Pager Train <-> Music Fokus <-> Verlauf Mini. Music Fokus zeigt Cover groß + Waveform mit Marker Ticks + Scrubbing, Queue als Liste.

**Fehlerfall Sensor Abriss:** Banner `Sensor getrennt Reps per +/- weiter` plus Chip wird grau.

### 8.2 Music

Chips oben Titel Alben Künstler Genres Ordner Playlisten, Suche mit FTS4, Filter Format/Dauer/HiRes, Favoriten Stern, Schnellscroller Alphabet, Swipe zwischen Ansichten, Drilldown Alben/Künstler, Playlisten CRUD + Label Badge Rest/Work + Switch Rest/Work pro Playlist, M3U Import, Titel Menü Zu Playlist hinzufügen, Waveform in Liste klein Lime gespielter Anteil, Song Kontextmenü Drops automatisch erkennen, Now Playing mit Cover via MediaMetadataRetriever embeddedPicture, Letterbox statt Thumbnail, WaveformPlaceholder pulsiert bei Analyse, Tap springt Drag Vorschau, Long Press setzt/löscht Marker nach Bestätigung, Marker Ticks Lime, Review Liste in Einstellungen für AUTO_DETECTED.

### 8.3 Verlauf

Liste Gruppiert nach Tag, je Satz Zeile `10:42 Bankdrücken 80 kg x 8 = 640 kg Volumen`, darüber Tagesvolumen Summe, oben Chart Linie Volumen über Zeit (Canvas animiert Line Draw), PR Abzeichen Lime wenn max Volumen je Übung geknackt, Tap auf Satz öffnet Sheet Gewicht/Reps ändern/löschen, nach Löschen Snackbar Undo 5s, danach PRs neu.

### 8.4 Einstellungen

* Sensor: Verbinden, kalibrieren pro Übung Liste mit Häkchen Datum neu kalibrieren, Jitter und Dedup Diagnose Werte optional hinter Entwickler Schalter.
* Musik Ordner: SAF wählen, Scan starten, Analyse Status.
* Audio und DSP: EQ 32 Bänder grafisch/parametrisch mit Presets seeder/CRUD, Klangregler Bass/Höhen Stereo Reverb Dither Resampler DVC, Crossfade an/aus Dauer 1-12s Stil 6 Chips, Mix Übergänge Erklärung, Bit Perfect Panel mit DAC Fähigkeiten Output Profil BT Hinweis Link zu System Ton, Battere Hinweis bei HiRes Resampling.
* Verhalten: Rest Musik in Pausen an/aus, Duck dB, Drop Auto Default.
* Darstellung: Theme hell/dunkel/system, Raleway/Mono Info.
* Berechtigungen: Liste BLUETOOTH_SCAN/CONNECT POST_NOTIFICATIONS SAF, Status grün/grau, Button In Einstellungen öffnen für Xiaomi.
* Datenschutz: Kein Konto Hinweis.

---

## 9. Phasenplan

### Phase 0 – Repo Merge und Fundament (Vorarbeit)

**Ziel:** DropSync bleibt Basis, FlowRep Archive wird lesbar, Build grün.

**Schritte:**

1. Neues Branch `fusion/foundation` ab main DropSync. FlowRep relevanten Ordner als `docs/archive/flowrep-import` spiegeln für Referenz (Parser Engine Screens Docs).
2. `gradle/libs.versions.toml` prüfen, Versions Katalog als alleinige Quelle belassen.
3. Android Manifest Paket `com.dropsync` bestätigen, Label `FlowRep` setzen, Launcher Icon Lime auf Schwarz provisorisch.
4. CI: `./gradlew test` + `spotlessCheck` + `assembleDebug` muss grün.

**Dateien:** `settings.gradle.kts`, `app/build.gradle.kts`, `gradle/libs.versions.toml`, `app/src/main/AndroidManifest.xml`

**Verifikation:** Build und Tests grün, App startet mit 4 leeren Tabs.

---

### Phase 1 – Designsystem Schwarz Weiß Lime (A)

**Ziel:** Vor jedem Screen Polish ein echtes System.

**Schritte:**

1. `core/designsystem/theme/AppColors.kt` mit Light und Dark ColorScheme aus Palette (#0D0D0D #FFFFFF #DFFF2F #F5F5F5 #EAEAEA #6B6B6B + Dark #14161A + Chart #4A9EFF).
2. `AppTypography.kt` Raleway 400-800 plus JetBrains Mono für Display Zahlen.
3. `AppSpacing.kt` Skala.
4. `Theme.kt` Material 3 ersetzen.
5. Komponenten Varianten Primary Lime 56h Pill, Secondary Schwarz, Ghost weiß Border, Card 24p Border 1dp #ECECEC optional Shadow.
6. Alle 6 alten FlowRep Farben entfernen, Tests für Theme Snapshot.

**Verifikation:** Alle Screens rendern hell/dunkel/system ohne Bruch, Kontrast AA.

---

### Phase 2 – Übungen und flaches Satz Log (C, A, A)

**Ziel:** Eigene Übungen verwalten und Sätze loggen, Basis für Timer und PR.

**Schritte:**

1. Room Entity `exercises` + `sets` + DAO, Migration 6 mit JSON Schema.
2. Domain `ExerciseRepository` Slugs Mapping beibehalten, Use Cases anlegen/umbenennen/löschen, validiere nur mit Gewicht (kein Bodyweight).
3. DataStore `exercise_rest_prefs` pro Übung default 90s.
4. UI Train Chip Sheet eigene Übungen + Neue anlegen Dialog, Gewicht Feld mit zuletzt Platzhalter + +/- 2.5 Chip, TalkBack Labels.
5. PR Volumen Use Case max `weightMg * reps` je Übung, Volumen Summe pro Tag für Verlauf.

**Verifikation:** Anlegen 5 Start Übungen, Sätze speichern, nach Neustart da, PR wechselt bei höherem Volumen.

---

### Phase 3 – Pausen Timer + Notification + Vordergrund Service (A, A, A)

**Ziel:** Timer läuft auch in Hosentasche, Notification steuert.

**Schritte:**

1. `TimerEngine` mit PREPARING 3-2-1 prepMs, TTS Ducking über Preamp, Haptik, State Flow.
2. Foreground Service `TimerService` mit MediaLibrarySession Notification, Actions Skip +15s Übung abschließen, Update alle 200ms nur wenn sichtbar.
3. Notification Kanäle, POST_NOTIFICATIONS Handling, para Xiaomi Fallback.
4. Train Pille bindet Timer State, zeigt Countdown und Chips, Schalter Drop Auto pro Pause als State in ViewModel.
5. Regel: Tap Satz fertig -> Timer start, Übung abschließen -> Timer cancel sofort.

**Verifikation:** Timer läuft bei Screen aus, Actions wirken, bei Go einmal Ton + Haptik, danach still.

---

### Phase 4 – Sensor Stack Portierung (A, A, A, A)

**Ziel:** BLE Zählung als Premium hinter Chip.

**Schritte:**

1. Neues `:domain:sensor` rein: Verträge SensorProvider, Modelle SensorSample, Engine Interface, PeakDetector, PhaseValidator, Kalibrierung.
2. `:data:sensor` mit `BleProtocolParser` (52/53 Byte, gyro Skalen), `JitterBuffer` (6*20ms), `BatchDedupTracker` (duplicateSkips/estimatedMissedBatches), `BleSensorProvider` Poll 30Hz, MTU Handling, `BleErrorMapper` deutsche Texte, `DeviceEvent` fee4.
3. Portiere FlowRep WorkoutEngine und PCA Kalibrierung nach Kotlin, persist pro Übung+Gerät, Calibration Wizard Screen 3 langsame Reps 20-30s.
4. Hilt Module bindet Sensor nur wenn Chip verbunden, sonst Fake Provider für manuelles +/-.
5. Train Waveform speist Live Samples aus Provider + Blitz bei Peak.

**Dateien neu:** `domain/sensor/*`, `data/sensor/*`, `feature/train/calibration/*`

**Verifikation:** Mit M5 live 12.5Hz Batches, Parsen grün, Kalibrierung speichert Häkchen, M5 BtnA mit Check.

---

### Phase 5 – Musik Import Waveform und Marker auto (A, A, B, A)

**Ziel:** Jeder neue Song sofort waveformbereit plus Drop Kandidaten, manuell verschiebbar.

**Schritte:**

1. SAF Ordner Scan bleibt, MediaStore Refresh.
2. TrackAnalyzer Worker `track_analysis_<songId>` streaming Min/Max + RMS, Cache `track_analysis` mit analyzer_version, bucket_count 0 = Fehler fallback Zeitachse.
3. OnsetDetection Worker `onset_detection_<songId>` Top 5 Mindestabstand 5s, schreibt `AUTO_DETECTED isEnabled=false`.
4. Library und Now Playing Waveform zeigt Lime gespielten Anteil, Marker Ticks, Tap Drag Long Press Logik, Review Screen in Einstellungen mit Bestätigen/Verwerfen.
5. Import Pipeline: Neuer Song -> analyse chain automatisch starten, UI zeigt pulsierenden Placeholder.

**Verifikation:** Import 10 Songs -> alle Waveforms sichtbar, Drops in Review, verschieben per Drag wirkt sofort, Landung nutzt neuen Punkt.

---

### Phase 6 – Musik Workout Kopplung mit Drop Landung (A, A, A, C, A)

**Ziel:** Rest Musik leise, Drop knallt bei Go exakt, du hast Vorrang. Latenz wird im Hintergrund pro Route kalibriert, kein Präzisionsversprechen in der UI.

**Konzepte (aus Super-KI Review übernommen):**

* **AudioClock-Abstraktion:** `Media3AudioClock` (MVP) hinter Interface, später `AudioTrackTimestampClock`. Timer basiert auf `SystemClock.elapsedRealtimeNanos()`, Drop-Start rechnet `WorkStart = Go - Marker - Latenz`.
* **RouteProfile:** `AudioRouteProfile(routeKey, sampleRate, channels, estimatedLatencyMs, p50ErrorMs, p95ErrorMs, calibratedAt, confidence)`. `routeKey` = interner Lautsprecher / USB / Kabel / BT-Gerät + Codec + Sample-Rate. Bei Route-Wechsel, Sample-Rate-Wechsel oder Fokusverlust Profil als unsicher markieren.
* **Latenz ohne Mikrofon:** Feste Latenz-Tabellen je Codec/BT-Gerät pflegen, wo verfügbar mit `AudioTimestamp` extrapolieren (`audibleFrame ≈ framePosition + (nowNanos - tsNano) * rate`). Kein Loopback-Messaufbau.
* **Modus intern:** `EXACT / CALIBRATED / BEST_EFFORT / UNAVAILABLE`. Bei `BEST_EFFORT` keine "millisekundengenau"-Aussage in der UI, nur dezenter Hinweis "Timing passt sich Route an".
* **Ducking nicht additiv:** `effectiveDuckDb = min(restDuckDb, ttsDuckDb)`, nie blind -8 + -12. Rampen: Attack 20-50ms, Release 150-300ms. Kein Doppel-Ducking, Limiter am Master.
* **Countdown-Piep-Töne statt TTS-Stimme:** 3-2-1-Go wird mit vorgerenderten Piep-Clips (Beep kurz, Beep kurz, Beep kurz, längerer Beep = Go) über den gleichen Gain-/Mixer-Pfad geplant, nicht mit System-TTS. Vor dem Countdown dekodieren, feste Audio-Frames, kein TTS-Callback als Trigger. Go ist damit ein echtes Audio-Event. (TTS als spätere Option möglich, nicht Standard.)
* **Cue Mode:** Go ist autoritativ. Erste Rep vor Go (Toleranz 250-500ms) wird als `EARLY_START` markiert, Timer und Drop bleiben bei Go, kein Adaptive Mode im Backlog.
* **Generation Token:** `PlaybackGeneration(id)` bei jedem Skip/Satzwechsel/Route-Wechsel erhöhen; alte geplante Audio-Events ignorieren.
* **Verpasster Drop (Underrun):** Wenn der Drop am Go exakt verpasst wurde, nicht mehrfach nachtriggern, sondern Zustand `MISSED_UNDERRUN` setzen, Work-Song weiterlaufen lassen und automatisch den nächsten passenden Drop im Song anbieten (weiterschalten). Leiser Hinweis an Nutzer.
* **ReplayGain:** Nicht in v1. Als Option "später möglich" unter Audio in Einstellungen vorgemerkt, nicht Standard, kein Lautheitsangleich bis dahin.

**Schritte:**

1. Reinen `DropLandingPlanner` in `:domain:timer` voll testen (Unit Tests equal power, monotony, FADE identisch, Formel `WorkStart = Go - Marker - Latenz`).
2. `RestMusicCoordinator` in `:feature:player` beobachtet TimerEngine + Settings, wählt Rest Playlisten label Rest, ruft Planner, setzt Queue bei Pausenbeginn, crossfadeTo mit Dauer aus DspConfig, Equal Power.
3. `AudioClock`-Interface + `Media3AudioClock`, RouteProfile-Store (DataStore), Latenz-Tabellen je Codec, Extrapolation via AudioTimestamp wo verfügbar, Wechsel auf BEST_EFFORT bei Underrun/Route-Wechsel.
4. Preamp Rest Duck Default -8dB einstellbar -12 bis 0, `min()`-Logik zu TTS, Crossfade endet vor Restende, Fall Rest < Marker -> DIRECT_TO_DROP Sprung.
5. Bei mehreren Markern wählt Planner nächsten passenden (37 B). Generation Token bei Skip/Neuplanung.
6. Manueller Skip/Pause -> Coordinator bricht Plan für diese Pause, Schalter im Countdown togge Drop Auto pro Pause, nächste Pause wieder an.
7. Einstellungen Abschnitt Musik in Pausen mit Label Badges, Duck Regler, Crossfade Dauer und Stil 6 Chips, Bit Perfect Hinweis, dezenter Timing-Hinweis je Route.

**Verifikation:** Rest 90s Marker 47s -> Start Work 43s nach Rest Start (minus Latenz), 3s Xfade fertig bei 90s Drop voll. Rest 60s Marker 80s -> Sprung direkt zum Drop ohne Intro, kein Knacksen. Route-Wechsel während Countdown -> Profil unsicher, BEST_EFFORT, keine kaputte Planung. Skip invalidiert alte Events via Generation. Underrun beim Drop -> MISSED_UNDERRUN, Work läuft weiter, nächster Drop wird weitergeschaltet, kein Mehrfach-Trigger.

---

### Phase 7 – Train Hero Politur (A, hybrid, A, A)

**Ziel:** Der Screen den man 95 Prozent sieht ist Apple like fertig.

**Schritte:**

1. Hero Layout: Rep Zahl 72-96sp Raleway 800, Waveform darunter 80dp hoch Lime, Gewicht Reihe, +/- Pill 56h.
2. Timer Pille sticky unter Chip, animiert Spring, Snackbar Undo 5s nach Satz.
3. Mini Player Bar mit Badges, Swipe Pager Train/Music/Verlauf, HorizontalPager wie Library.
4. Leer Zustände mit CTA statt nur Text, Skeleton statt CircularProgress, Fehlertexte in App Stimme.
5. Barrierefreiheit: 48dp Buttons, stateDescription für Slider.

**Verifikation:** Kompletter Flow Verbinden -> Kalibrieren -> Zählen -> Satz fertig -> Pause mit Musik -> Go mit Drop -> nächster Satz ohne Bruch, TalkBack lesbar, 200% Schrift ok.

---

### Phase 8 – Verlauf schlank (A, B, A)

**Ziel:** Motivation ohne Analyse Labyrinth.

**Schritte:**

1. Verlauf Screen Liste nach Tag, Tagesvolumen Summe, Linien Chart Volumen über Zeit mit fl_chart oder Canvas animiert, PR Abzeichen Lime.
2. Tap Satz Sheet ändern/löschen mit Undo, danach Domain rechnet PR neu.
3. Detail pro Übung als Filter Chip oben, nicht als extra Tab.
4. Leer Zustand mit CTA Neue Übung anlegen.

**Verifikation:** Charts laden bei >5 Sätzen korrekt, Undo stellt wieder her.

---

### Phase 9 – Berechtigungen und First Start (B, C)

**Ziel:** Beim ersten Start alles auf einmal, danach Xiaomi sicher.

**Schritte:**

1. First Start Dialog Kette BLUETOOTH_SCAN/CONNECT POST_NOTIFICATIONS SAF Ordner, Reihenfolge fix, Erklärung auf Deutsch kurz.
2. Prüfscreen Liste grün/grau mit Button In Einstellungen öffnen per Intent, erneute Prüfung onResume, HyperOS Hinweis.
3. Kein Onboarding Flow, App landet direkt in Train leer.

**Verifikation:** Frische Installation -> alle Dialoge, ablehnen -> Eintrag bleibt grau mit Button, nach Erteilen in System grün.

---

### Phase 10 – Klang Keller (A)

**Ziel:** Klang nur in Einstellungen, aber vollständig.

**Schritte:**

1. Audio und DSP Screen mit EQ grafisch/parametrisch Presets CRUD Seeder, Klangregler Stereo Reverb Resampler Dither DVC, Profile je Ausgang Auto Switch Save Through, BitPerfectGateway.
2. Mix Übergänge Abschnitt an/aus Stil 6 Chips Dauer 1-12s, Global statt pro Playlist.
3. Tests DspPerformanceTest 32 Bänder 48kHz >2x Echtzeit keine NaN/Inf.
4. ReplayGain ist NICHT in v1. Als Option unter Audio in Einstellungen vorgemerkt (später möglich), Standard bleibt aus, kein automatischer Lautheitsangleich.

**Verifikation:** Preset Wechsel wirkt sofort, Bit Perfect bypassed DSP Float und Crossfade, Hinweis sichtbar.

---

## 10. Latenz-Kalibrierung ohne Mikrofon

**Ziel:** Drop-Timing pro Route bestmöglich, ohne externen Messaufbau, keine Versprechen in UI.

* **Tabelle je Codec/BT-Gerät:** Startwerte aus Messungen pflegen, z.B. SBC ~120ms, AAC ~200ms, LDAC ~150ms, AptX ~80ms, kabelgebunden ~30ms, intern ~50ms. Werte initial best effort, verfeinern über Nutzungsdaten.
* **AudioTimestamp wo verfügbar:** `audibleFrame ≈ framePosition + (nowNanos - tsNano) * rate` extrapolieren; gibt bessere Schätzung als fester Tabellenwert.
* **Modus intern:** `EXACT / CALIBRATED / BEST_EFFORT / UNAVAILABLE`. UI zeigt nur dezent "Timing passt sich Route an" im BEST_EFFORT, nie "ms-genau".
* **Wichtig:** Bluetooth hat keine universelle ±50ms-Garantie. Das Produkt verspricht kalibrierte Planung pro Route, nicht absolute Präzision.

---

## 11. Tests und Gates

* Unit: Planner Equal Power, FADE identisch, Monotonie, paarweise verschieden, Crossfade Mikro Rampe, Codec Roundtrip, Slugs Progress, Repo 18 inkl Swap Repeat RestPref Snapshot, Migration 1->6 gegen JSON. Plus: Generation Token (Skip invalidiert alte Events), Ducking min() (kein Doppel-Duck), RouteProfile-Wechsel (BEST_EFFORT), Cue Mode (frühe Rep verschiebt Drop nicht), Direct-Drop mit seekPrerollFrame.
* Instrumentiert: JitterBuffer, Dedup, Scan, TimerService Foreground, Waveform Scrubbing, Marker Long Press, RestMusicCoordinator Vorrang, AudioTimestamp-Extrapolation, Route-Wechsel während Countdown, Underrun-Monitoring, AudioFocus (LOSS_TRANSIENT duckt + Timer weiter, permanenter LOSS stoppt).
* Golden Audio Fixtures für CI: Synthetische Testsignale (Sinus, Klickfolge, Bass-Impuls, Stille->Impuls, zwei unterschiedliche Sample-Rates, künstlicher Crossfade, absichtlicher Underrun). Metriken: Gain-Kontinuität (delta sample[n]-sample[n-1]), Click-Metrik (Hochpass-Energie, Peak-to-RMS in ersten 10-30ms), True Peak/Clipping (maxSample, samplesAbove0dBFS), Equal-Power-Check (gRest²+gWork²≈1), Drop-Alignment (mean/P50/P95 error über viele Läufe). Ersetzt nicht den Hörtest, fängt aber Regressionen.
* Performance: DSP Durchsatz >2x, 200ms Ticker nur wenn sichtbar, Batterie Hinweis bei HiRes.
* Release Gates: Gerät Abnahme BT Codec, USB DAC Bit Perfect, MusicFX mit/ohne Equalizer, TalkBack 200% Schrift, P95 Drop-Fehler auf unterstützten Routen dokumentiert.

---

## 11a. Analyse-Pipeline (Waveform, Onset, BPM)

* **Ein Decoder-Durchgang:** MediaExtractor/MediaCodec -> PCM-Block -> Mono-Downmix -> niedrigere Analyse-Sample-Rate -> gemeinsames Feature-Fenster (Waveform Min/Max/RMS, Spectral Flux, Onsets, BPM). Key nur optional und später (teuer, empfindlich).
* **Beim Import:** Schnell nur Dauer, grundlegende Waveform, RMS, grobe Onset-Kandidaten. Blockiert Import nicht mit teurer Analyse.
* **Vor erstem Play:** Falls fehlt, BPM verfeinern, Beat-Grid, automatische Drop-Kandidaten.
* **Cache-Invalidierung:** Cache-Key = `sha256(uri + size + lastModified + analyzerVersion + "mono22050-hop512-buckets10000")`. Dateiveränderung -> vollständige Neuanalyse möglich.
* **WorkManager:** Eine idempotente Aufgabe pro Song (PENDING/RUNNING/DONE/FAILED_RETRYABLE/FAILED_PERMANENT/STALE/CANCELLED), `requiresBatteryNotLow`, optional `requiresCharging`, Fortschritt persistieren, bei Abbruch beim nächsten Song fortsetzen, lange Läufe als Foreground Worker mit Notification. Priorität: angefordert > zuletzt gespielt > aktuelle Playlist > restliche Bibliothek > Key.
* **Nicht 1.000 Songs in einem unteilbaren Worker.**

---

## 12. Phasen-Reihenfolge (angepasst nach Super-KI Review)

Grundprinzip: Erst Audio-Grundlage mit manuellem Marker beweisen, dann Crossfade, dann TTS/Gain, dann Waveform, Auto-Erkennung und Skalierung ans Ende. Kein Feature bauen, dessen Fundament nicht steht.

| Phase | Inhalt | Gate |
|---|---|---|
| 0 | Repo Foundation, Build grün | App startet |
| 1 | Designsystem Schwarz/Weiß/Lime | Screens hell/dunkel |
| 2 | Übungen + flaches Satz-Log | Sätze gespeichert, PR |
| 3 | Pausen Timer + Notification + Service | Timer im Hintergrund |
| 4 | Sensor Stack Portierung | BLE zählt live |
| 5 | Audio-POC + manuelle Marker (statt Auto-Erkennung) | P95 Drop-Fehler pro Route dokumentiert |
| 6 | Crossfade + Audio-FSM + Route-Kalibrierung | Crossfade endet vor Drop |
| 7 | TTS + Gain-Struktur (Ducking min, Limiter) | Kein Doppel-Duck, kein Clipping |
| 8 | Waveform Rendering + Scrubbing + manuelle Marker UI | 60fps Scrub, Marker setzbar |
| 9 | Train Hero + Verlauf Politur | Kompletter Flow |
| 10 | Berechtigungen + First Start | Xiaomi sicher |
| 11 | Klang Keller (EQ, Presets, Profile) | DSP performant |
| 12 | Auto-Drop-Erkennung + große Analyse-Queue | Kandidaten + Review |

---

## 13. Risiken und Antworten

* HyperOS MTU 517 Bug -> Require 185 anfordern aber 517 akzeptieren, Protokoll v2 53 Byte passt.
* Xiaomi killt Service -> Foreground Priority + Notification sticky, Reconnect mit Dedup.
* Waveform Analyse langsam -> OneTimeWork dedup, Cache mit Version, pulsierender Placeholder.
* Drop Erkennung daneben -> nur Kandidaten disabled, Review Pflicht, Primary Logik nächster passender.
* Keine Sessions verwirrt Filter -> Verlauf gruppiert nur datumsmäßig, kein extra Modell.
* Flutter zu Kotlin Port Fehler -> Parser Tests gegen FlowRep Fixtures 1:1 übernehmen.
* Latenz variiert je Route -> RouteProfile + BEST_EFFORT, kein ms-Versprechen in UI.
* Race bei Skip/Route-Wechsel -> Generation Token invalidiert alte Events.
* Doppel-Ducking TTS+Rest -> effectiveDuck = min(), Limiter am Master.

---

## 14. Was bewusst nicht drin ist

Kamera Pose, Routinen, Sessions, Export, Herz, Velocity UI, RPE, Bodyweight, lbs, starke Gamification, Social, Streaming, Adaptive Mode. Alles später per ADR.

---

## 15. Nächste Schritte

1. Dieses Dokument reviewen.
2. Danach `docs/plans/YYYY-MM-DD-fusion-foundation-plan.md` per GSD Plan Phase schreiben.
3. Phase 0 starten, dann 1 bis 12 in Reihenfolge, jede Phase endet mit Device Check.

---

## 11. Risiken und Antworten

* HyperOS MTU 517 Bug -> Require 185 anfordern aber 517 akzeptieren, Protokoll v2 53 Byte passt.
* Xiaomi killt Service -> Foreground Priority + Notification sticky, Reconnect mit Dedup.
* Waveform Analyse langsam -> OneTimeWork dedup, Cache mit Version, pulsierender Placeholder.
* Drop Erkennung daneben -> nur Kandidaten disabled, Review Pflicht, Primary Logik nächster passender.
* Keine Sessions verwirrt Filter -> Verlauf gruppiert nur datumsmäßig, kein extra Modell.
* Flutter zu Kotlin Port Fehler -> Parser Tests gegen FlowRep Fixtures 1:1 übernehmen.

---

## 12. Was bewusst nicht drin ist

Kamera Pose, Routinen, Sessions, Export, Herz, Velocity UI, RPE, Bodyweight, lbs, starke Gamification, Social, Streaming. Alles später per ADR.

---

## 13. Nächste Schritte

1. Dieses Dokument reviewen.
2. Danach `docs/plans/YYYY-MM-DD-fusion-foundation-plan.md` per GSD Plan Phase schreiben.
3. Phase 0 starten, dann 1 bis 10 in Reihenfolge, jede Phase endet mit Device Check.

---

## Anhang: Ton und Copy

Schwarz erzeugt Fokus, Lime erzeugt Energie, Weiß erzeugt Ruhe. Copy kurz, deutsch, ohne Tech Kauderwelsch, Fehlertexte wie BleErrorMapper. Buttons immer klar, eine Primär Aktion pro Screen.


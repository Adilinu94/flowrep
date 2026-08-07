# Wissen aus Poweramp und Offtrack

## Reverse-Analyse, Audio-Architektur und Übertragung auf FlowRep x DropSync

**Datum:** 2026-08-07  
**Status:** Technische Wissensbasis / statische Analyse  
**Zweck:** Die aus den untersuchten Apps gewonnenen Architektur-, Audio-, Analyse- und UX-Erkenntnisse dauerhaft für die Kotlin-/Jetpack-Compose-Gym-App FlowRep x DropSync dokumentieren.  
**Neue Dokumentbezeichnung:** `WISSEN_POWERAMP_OFFTRACK_REVERSE_ANALYSE_2026-08-07.md`

---

## 0. Zusammenfassung für die Umsetzung

Die wichtigste gemeinsame Erkenntnis aus Poweramp und Offtrack lautet:

> Ein robuster Musikübergang ist kein UI-Fade und kein einzelner `setVolume()`-Aufruf. Er ist ein eigener, vorbereiteter Audio-Plan zwischen zwei Tracks, der Analyse-, Zeit-, Decoder-, DSP- und Ausgabegrenzen miteinander verbindet.

Beide Untersuchungen zeigen unterschiedliche Ausprägungen desselben Architekturprinzips:

```text
Track-/Bibliotheksdaten
        ↓
Analyse und Metadaten
        ↓
Orchestrierung / Queue / Service
        ↓
Transition- oder Processing-Plan
        ↓
Audio-Engine / DSP-Grenze
        ↓
Ausgabelayer / AudioTrack / AudioSink
        ↓
MediaSession, AudioFocus, Foreground Service, UI
```

### Die Poweramp-Analyse zeigt vor allem

Die folgenden Punkte sind statische APK-/Smali-Befunde, keine Behauptung über nicht sichtbare Native-Interna.

- eine klare Grenze zwischen Android-Service/Orchestrierung und nativer Audio-Pipeline;
- eine separate native EQ-/DSP-Grenze;
- eigene Audio-Plugin- und Processing-Komponenten;
- getrennte AudioFocus-/Foreground-Service-Integration;
- konfigurierbare Crossfade-/Gapless-Pfade;
- einen datenbankgestützten, nebenläufigen Bibliotheks- und Scan-Unterbau;
- dass wichtige Audioqualität nicht aus UI-Logik oder einfachen Player-Aufrufen entsteht.

### Die Offtrack-Analyse zeigt vor allem

Die folgenden Punkte sind APK-/DEX-/Smali-Befunde oder vorsichtige Aufrufketten; die stripped Native-Interna bleiben ausdrücklich offen.

- ein konkretes Track-Paar-Modell für Automix;
- vorbereitete Analyse-Daten mit BPM, Energie, Dauer und Boundary-Status;
- eine asynchrone Transition-Job-Queue;
- eine native Funktion `createMix(...)` als Transition-Berechnungs-/Ergebnis-Schnittstelle;
- drei von der Native-Schicht gelieferte Ergebniswerte, die in benannte Übergangsfelder übernommen werden;
- eine direkte `AudioTrack`-Ausgabe mit `ByteBuffer`-Writes und Playback-Head-Telemetrie;
- Fallbacks, wenn Analyse nicht rechtzeitig verfügbar ist;
- BPM-basierte Transition-Seek-Logik;
- die Trennung von Smart-Queue, Analyse, Transition-Anforderung/-Ergebnis und Audioausgabe; die vollständige Native-Renderstrecke bleibt teilweise offen.

### Konsequenz für DropSync

Für DropSync sollte die Zielarchitektur nicht lauten:

```text
Countdown endet
→ ExoPlayer.play()
→ volume in Coroutine ändern
→ hoffen, dass der Drop hörbar trifft
```

Sondern:

```text
Satz fertig
→ monotone Go-Deadline bestimmen
→ Work-Track und Drop-Marker auswählen
→ Route-/Audio-Latenz schätzen
→ Crossfade-/Drop-Plan erzeugen
→ Work-Player/Audio-Engine vorbereiten
→ Audio-Zeit und hörbare Zeit überwachen
→ Plan ausführen oder bei Unsicherheit in Best-Effort wechseln
```

---

## 1. Quellen, Untersuchungsumfang und Evidenzregeln

### 1.1 Untersuchte Quellen

#### Poweramp

- APK `Poweramp v1013 (Premium).apk`, lokal disassembliert.
- Baksmali-Smali-Ausgabe unter:

```text
D:\rev-tools\poweramp_offline_triage\smali-3.0.9\
```

- Relevante statische Dateien und Befunde:

```text
com/maxmpz/audioplayer/player/PlayerService.smali
com/maxmpz/audioplayer/processing/Pipeline2.smali
com/maxmpz/audioplayer/plugin/OutputInternalHelper.smali
com/maxmpz/audioplayer/plugin/NativePluginManager.smali
com/maxmpz/audioplayer/equalizer/Coefs.smali
com/maxmpz/equalizer/eq/PeqNativeUtils.smali
com/maxmpz/audioplayer/scanner/folder/H.smali
com/maxmpz/audioplayer/scanner/folder/X.smali
com/maxmpz/audioplayer/scanner/folder/DirScanner.smali
com/maxmpz/audioplayer/scanner/ScanDispatcherService.smali
com/maxmpz/audioplayer/scanner/TagReader.smali
com/maxmpz/audioplayer/scanner/FFMpegTagReader.smali
com/maxmpz/audioplayer/prefs/В.smali
```

#### Offtrack

- APK `com.offtrack.app v1.6.9_antisplit.apk`, lokal statisch untersucht.
- SHA-256:

```text
92251b2232ca077006fb5c2e6fa3c270b22723c9fe63eb2914c7ff61866bdf1b
```

- Extrahierte/analysierte Ausgabe:

```text
D:\rev-tools\offtrack-automix-triage\smali\
D:\rev-tools\offtrack-automix-triage\raw\lib\arm64-v8a\
```

- Relevante statische Dateien:

```text
com/offtrack/core/dj/PlaybackService.smali
com/mixonset/libtransition/LibTransitionExt.smali
Y8/d.smali
Y8/c.smali
X8/I.smali
X8/L.smali
X8/w.smali
X8/B.smali
c9.1/i.smali
c9.1/h.smali
d9.1/e.smali
e9/t.smali
f9.1/b.smali
B9/b0.smali
com/offtrack/core/model/data/Track.smali
```

#### Native Offtrack-Bibliotheken

```text
libtransition-aar.so
libts.so
libffmpegkit.so
libffmpegkit_abidetect.so
libavcodec.so
libavdevice.so
libavfilter.so
libavformat.so
libavutil.so
libswresample.so
libswscale.so
libc++_shared.so
```

### 1.2 Kanonische Smali-Pfade und Deskriptoren

Die APK-Ausgabe enthält wegen Obfuskation und Baksmali-Ausgabe teilweise Verzeichnisnamen wie `c9.1` oder `e9.1`, während die darin deklarierten Dalvik-Deskriptoren kürzer sind. Für dieses Dokument gilt folgende Zuordnung:

| Funktion | Kanonischer extrahierter Pfad | Dalvik-Deskriptor |
|---|---|---|
| Transition Engine | `Y8/d.smali` | `LY8/d;` |
| Audio-Deck/Output | `Y8/c.smali` | `LY8/c;` |
| Transition-Orchestrator | `X8/I.smali` | `LX8/I;` |
| Playback-State/Player Coordinator | `X8/L.smali` | `LX8/L;` |
| Transition Job | `c9.1/i.smali` | `Lc9/i;` |
| Job Runner | `c9.1/h.smali` | `Lc9/h;` |
| Dispatch Queue | `d9.1/e.smali` | `Ld9/e;` |
| Transition Result | `e9/t.smali` | `Le9/t;` |
| Native Bridge | `com/mixonset/libtransition/LibTransitionExt.smali` | `Lcom/mixonset/libtransition/LibTransitionExt;` |

Wenn ein Unterpfad in einem anderen Tool anders dargestellt wird, ist der Dalvik-Deskriptor die stabile Referenz.

### 1.3 Evidenzklassen

Jede Aussage in diesem Dokument gehört möglichst zu einer der folgenden Klassen:

| Klasse | Bedeutung |
|---|---|
| **E1 – direkt statisch belegt** | Konkrete Klasse, Methode, Feld, native Deklaration, Invoke-Stelle oder Konstante im Smali. |
| **E2 – stark aus Aufrufkette abgeleitet** | Mehrere direkte E1-Befunde ergeben einen eindeutigen Datenfluss, die Native-Interna bleiben aber teilweise verborgen. |
| **E3 – plausible technische Interpretation** | Passt zu Namen, Typen und Callflow, ist aber nicht vollständig aus dem Artefakt beweisbar. |
| **E4 – Produkt-/Praxiswissen** | Allgemeine Android-, Audio- oder DSP-Empfehlung; kein Befund über die konkrete App. |

### 1.4 Grenzen der Analyse

- Es wurde keine vollständige dynamische Laufzeitmessung der Apps durchgeführt.
- Die relevanten Offtrack-Native-Bibliotheken sind stripped ARM64 ELF-Dateien.
- Die genaue Mathematik in `libtransition-aar.so` ist daher nicht aus Java/Smali allein rekonstruierbar.
- Ein String oder Klassenname beweist keine aktive Verwendung. Deshalb werden reine Namensfunde nicht als Algorithmus ausgegeben.
- Die statische Analyse beweist nicht automatisch eine sample-genaue oder millisekundengenaue Laufzeitgarantie.
- Die beschriebenen Architekturen sollen als Muster und Schnittstellenvokabular dienen, nicht als Übernahme proprietärer Implementierung.

---

# Teil A – Poweramp

## 2. Poweramp: zentrale Architektur-Erkenntnisse

### 2.1 Verteilung der Verantwortlichkeiten

Die statischen Befunde zeigen eine klare Trennung:

```text
Android PlayerService
    ├── Lebenszyklus
    ├── Service-/Notification-Integration
    ├── Player-Orchestrierung
    ├── AudioFocus und UI-nahe Zustände
    └── Kommunikation mit Processing/Output

Processing Pipeline
    ├── Pipeline-Erzeugung
    ├── Decoder-/Track-Öffnung
    ├── Pause/Resume/Stop
    ├── Seek
    ├── Position-/Statusabfragen
    └── Plugin-/DSP-Nachrichten

Native EQ/DSP
    ├── Koeffizientenberechnung
    ├── Parametric-EQ-Steuerung
    ├── Commit/Deferred-Updates
    └── Output-/Plugin-Grenzen

Scanner/Library
    ├── native directory scan
    ├── Tag-/FFmpeg-Analyse
    ├── SQLite-Persistenz
    └── Hintergrund-Dispatcher
```

Das ist für DropSync relevanter als Poweramps interne Klassennamen. Die robuste Idee ist die **Tiefe der Module**: Jede Schicht hat eine begrenzte Aufgabe und kommuniziert über Zustände, Nachrichten oder Datenobjekte.

### 2.2 `Pipeline2` als native Processing-Grenze

`com/maxmpz/audioplayer/processing/Pipeline2.smali` enthält native Methoden und Lifecycle-Methoden für die Audio-Pipeline. Die statische Analyse identifizierte Funktionen für:

- Erzeugen und Aufbauen der Pipeline;
- Öffnen eines Tracks;
- Pause, Resume und Stop;
- Seek;
- Positions- und Statusabfrage;
- Routing von Plugin-/Processing-Nachrichten;
- Decoder-/Track-Lifecycle;
- End-Event- und Positionsinformationen.

Das ist kein Beweis für jede konkrete Mixing-Kurve, aber ein klarer Beleg für eine native Grenze zwischen Orchestrierung und zeitkritischer Audioverarbeitung.

### 2.3 EQ und DSP hinter nativen Methoden

Relevante Befunde:

```text
com/maxmpz/audioplayer/equalizer/Coefs.smali
com/maxmpz/equalizer/eq/PeqNativeUtils.smali
```

`Coefs` besitzt native Koeffizientenberechnung. `PeqNativeUtils` besitzt native Steuerung für Parametric-EQ-Zustände, unter anderem:

- `setEnabled`;
- Parameteränderungen;
- Commit-/Deferred-Pfade;
- Übergabe aktualisierter EQ-Parameter an die Audioverarbeitung.

#### Übertragbares Muster

Nicht jeder EQ-Slider sollte direkt im UI in einen Audio-Thread schreiben. Besser:

```text
Compose UI
   ↓
AudioSettings / EQ-Domain-State
   ↓
validated parameter snapshot
   ↓
AudioEngine command
   ↓
DSP boundary
   ↓
atomic/deferred commit
```

Für DropSync bedeutet das: EQ, Preamp, Replay Gain, Rest-Duck und TTS-Duck sollten nicht als fünf unabhängige Lautstärke-Callbacks implementiert werden.

### 2.4 Output- und Plugin-Grenze

`OutputInternalHelper.smali` und `NativePluginManager.smali` bestätigen, dass Output und Processing als eigene Erweiterungspunkte behandelt werden. Das spricht für:

- getrennte Decoder-/Output-Verantwortung;
- Plugin-fähige DSP-Grenzen;
- native Audio-Hotpaths;
- Java/Kotlin als Steuerung statt als sampleweiser Mixer.

### 2.5 AudioFocus und Foreground-Service getrennt vom DSP

In der Player- und Service-Schicht sind Android-Systemfunktionen getrennt von der eigentlichen Pipeline:

- AudioFocus-Handling über `AudioManager`/AudioFocus-Anforderungen;
- Foreground-Service-/Notification-Lifecycle;
- PlayerService als dauerhafte Wiedergabe-Komponente.

#### Übertragbares Muster

```text
MediaSessionService / PlaybackService
    ├── AudioFocus
    ├── Notification / Foreground Service
    ├── MediaSession Commands
    └── AudioEngine reference

AudioEngine
    ├── Decoder
    ├── Mixer/DSP
    └── AudioSink
```

Timer-Logik und AudioFocus dürfen nicht untrennbar in einer Compose-ViewModel-Schicht hängen.

### 2.6 Crossfade-Konfiguration

In `com/maxmpz/audioplayer/prefs/В.smali` wurde die Preference gefunden:

```text
crossfade_length_ms
```

Der statische Default ist:

```text
0x1388 = 5000 ms
```

Außerdem existieren in `PlayerService.smali` die Flags:

```text
FLAG_OPEN_NO_CROSSFADE
FLAG_OPEN_FORCE_GAPLESS
```

und in der Processing-/Preference-Schicht ein Crossfade-Auto-Advance-Pfad.

#### Was das belegt

- Crossfade ist eine eigene, konfigurierbare Playback-Entscheidung.
- Gapless und Crossfade werden als unterschiedliche Modi behandelt.
- Der Track-Open-Pfad kann abhängig von Flags den Übergang ändern.
- Crossfade-Länge ist nicht zwangsläufig fest im UI verdrahtet.

#### Was es nicht belegt

Die Befunde beweisen nicht:

- dass die Kurve Equal Power ist;
- dass die Kurve bei jedem Gerät gleich ist;
- dass ein konkreter 5-s-Wert eine Laufzeitgarantie darstellt;
- dass `FLAG_OPEN_FORCE_GAPLESS` intern sample-genau funktioniert.

### 2.7 Scanner- und Bibliotheksarchitektur

Poweramp verwendet eine eigene Scanner-Schicht:

```text
DirScanner / FolderScanner
    ↓
TagReader / FFMpegTagReader / ModTagReader
    ↓
SQLite-Datenbank
    ↓
ScanDispatcherService
```

Direkte Befunde:

- `DirScanner` besitzt native Methoden `native_init`, `native_scan`, `native_release`.
- `FFMpegTagReader` besitzt native Datei-/Dateityp-Analyse.
- Der Scanner setzt Thread-Prioritäten.
- Es werden SQLite-Transaktionen verwendet.
- `PRAGMA synchronous` wird abhängig von der Scanner-Phase angepasst.
- Der Datenbankpfad enthält eine große `eq_presets`-Struktur; in der früheren Analyse wurden 17.703 `eq_presets`-Zeilen konsistent festgestellt.

#### Übertragbares Muster

Die Waveform-/BPM-/Key-Analyse von DropSync sollte nicht im UI und nicht im Playback-Thread laufen:

```text
Import / Scan Dispatcher
    ↓
Streaming Analyzer
    ↓
versioned Room cache
    ↓
UI observes immutable analysis record
```

### 2.8 Threading und Persistenz

Der Scanner zeigt ein praxisnahes Muster für große Bibliotheken:

- schwere Arbeit in Hintergrundthreads;
- Prioritätssteuerung für Scannerarbeit;
- Transaktionen für konsistente DB-Zustände;
- unterschiedliche Synchronisationsstufen je Arbeitsphase;
- getrennte UI-/Service-/Analyse-Lebenszyklen.

Für DropSync sollte ein 1000-Song-Import niemals als eine große Coroutine auf dem Main Dispatcher ausgeführt werden.

---

## 3. Poweramp: Architekturübertragung auf DropSync

### 3.1 Empfohlene Modulgrenzen

```text
app-ui-compose
    └── zeigt Zustände und sendet User Commands

workout-domain
    ├── Set
    ├── RestTimer
    ├── DropLandingPlan
    └── WorkoutEvents

playback-service
    ├── MediaSession
    ├── AudioFocus
    ├── Foreground Service
    └── Service Commands

rest-music-coordinator
    ├── RestPlayer
    ├── WorkPlayer / Work Deck
    └── Transition Scheduler

analysis-module
    ├── Decoder/MediaCodec
    ├── Waveform
    ├── BPM/Onset/Key
    ├── Drop Candidates
    └── Versioned Cache

audio-engine
    ├── Gain Graph
    ├── Crossfade
    ├── Ducking
    ├── EQ/DSP boundary
    └── AudioSink / optional native mixer

sensor-module
    ├── BLE transport
    ├── packet parser
    ├── jitter buffer
    ├── calibration
    └── rep detector
```

### 3.2 Was nicht kopiert werden sollte

- keine Poweramp-Klassennamen;
- keine obfuskierten Flags;
- keine proprietären Native-Interfaces;
- keine Annahme, dass ein Android-`Media3`-Playlist-Mixer automatisch mit einem nativen Player gleichwertig ist;
- keine Annahme, dass ein statischer Crossfade-Wert eine akustische Präzisionsgarantie ist.

---

# Teil B – Offtrack

## 4. Offtrack: konkrete Automix-Architektur

### 4.1 App-eigene Playback-Komponenten

Die App besitzt unter anderem:

```text
com/offtrack/app/OffApplication
com/offtrack/app/MainActivity
com/offtrack/core/dj/PlaybackService
```

`PlaybackService` ist ein Android-Service und koordiniert die Wiedergabe. Media3-/MediaSession-Service-Referenzen sind im APK ebenfalls vorhanden.

### 4.2 Native Transition-Library

Die Klasse lautet:

```text
com/mixonset/libtransition/LibTransitionExt.smali
```

Sie lädt:

```smali
const-string v0, "transition-aar"
invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V
```

Damit wird die native Bibliothek geladen:

```text
libtransition-aar.so
```

Die Library ist stripped. Es gibt keine brauchbaren exportierten Symbolnamen, aus denen die Fade-/Beat-Formel direkt abgelesen werden kann.

### 4.3 Native API-Oberfläche

Die zentralen Methoden sind:

```smali
.method public native createMix(
    Ljava/lang/String;
    Ljava/lang/String;
    Ljava/lang/String;
    Ljava/lang/String;
    Ljava/lang/String;
    J
    Z
    Z
    Z
    J
    J
    J
    Z
    Z
    J
    Ljava/lang/String;
)[J
```

Weitere Methoden:

```smali
loadSongAnalysis(String, String, long): long[]
loadSongXMLStr(String, String): String
writeSongXMLStrENCData(String, String, String): int
```

#### Direkte Aufrufstellen

```text
Y8/d.smali:744
    createMix(...)[J

B9/b0.smali:5965
    loadSongAnalysis(...)[J

f9.1/b.smali:930
    loadSongXMLStr(...):String

f9.1/b.smali:1259
    writeSongXMLStrENCData(...):int
```

Das belegt eine native Analyse-/Transition-Schnittstelle mit persistierten Songdaten. Es beweist nicht, dass jede Analyse oder jede Transition ausschließlich in Native ausgeführt wird.

---

## 5. Offtrack: Track-Modell und Analyse-Daten

Das Track-Modell enthält mindestens:

```text
id
name
sourceUri
durationMs
bpm
energy
hasAnalysis
analyzedWithoutBoundaries
artists
album
genres
service
```

Die Felder `bpm`, `energy`, `durationMs`, `hasAnalysis` und `analyzedWithoutBoundaries` sind im Smali direkt sichtbar.

### 5.1 Bedeutung der Analyse-Flags

Die Analysefelder und Namen legen mindestens folgende Zustände nahe; die genaue fachliche Bedeutung ist statisch nicht vollständig bewiesen:

```text
keine Analyse vorhanden
Analyse vorhanden
Analyse vorhanden, aber ohne Boundaries
Analyse mit ausreichenden Daten für einen möglichen Transition-Pfad
```

Die genaue Definition jeder Boundary ist in der statischen Java-/Smali-Schicht nicht vollständig sichtbar. Für DropSync sollte dieses Muster jedoch explizit modelliert werden:

```kotlin
enum class AnalysisQuality {
    MISSING,
    BASIC,
    WITHOUT_BOUNDARIES,
    COMPLETE,
    INVALID
}
```

### 5.2 BPM-Anreicherung und Fallback

`X8/B.smali` und `X8/I.smali` protokollieren unter anderem:

```text
setQueueSmart: BEFORE enrichment - bpm=
setQueueSmart: AFTER enrichment - bpm=
appendRelatedTracksInternal: BEFORE enrichment - bpm=
appendRelatedTracksInternal: AFTER enrichment - bpm=
Spotify track, using existing metadata
waiting for SoundCloud analysis
analysis completed
analysis timed out, proceeding with original track
```

Das zeigt:

- Track-Metadaten können vor Queue-/Mix-Entscheidungen angereichert werden.
- Die Queue wartet in bestimmten Fällen auf Analyse.
- Es existiert ein begrenzter Timeout.
- Bei fehlender rechtzeitiger Analyse wird die Wiedergabe nicht endlos blockiert.

Ein beobachteter Timeout-Wert ist ungefähr:

```text
40.000 ms = 0x9c40
```

Für eine Offline-App kann DropSync einen kürzeren, benutzerfreundlicheren Timeout verwenden, da die lokale Analyse grundsätzlich planbarer ist.

---

## 6. Offtrack: Transition-Job-Queue

### 6.1 `c9/i` als Transition-Job

`c9/i` hält nachweisbar:

```text
Track A
Track B
mehrere long-Werte
optionale Long-Werte
String-/Storage-Parameter
Callback-/Dispatcher-Referenzen
LY8/d Transition Engine
```

Die Konstruktion erfolgt in `X8/I.smali` ungefähr bei der Job-Erzeugung:

```smali
new-instance v2, Lc9/i;
invoke-direct/range {...}, Lc9/i;-><init>(Track, Track, JJ, Long, Long, Long, ...)
```

Danach wird der Job in einen Dispatcher eingereiht:

```smali
invoke-virtual {v0, v2, v1}, Ld9/e;->b(Lc9/j;I)V
```

`c9/i` läuft später coroutine-/dispatcher-basiert und ruft auf:

```smali
LY8/d;->b(Track, Track, JJ, ZZ, Long, Long, Long)
```

### 6.2 Warum die Queue wichtig ist

Der nächste Übergang wird nicht erst dann berechnet, wenn Track A schon am Ende ist. Das Modell ist:

```text
Track A wird gespielt
Track B wird ausgewählt
Analyse wird geprüft
Transition Job wird erzeugt
Native Mix wird vorbereitet
Ergebnis wird gespeichert
Playback wartet nur noch auf den geplanten Zeitpunkt
```

Das verhindert, dass CPU-intensive Analyse oder Native-Rendering exakt in den Trackwechsel fällt.

### 6.3 DropSync-Übertragung

Für DropSync sollte es eine eigene, fachlich ähnliche Struktur geben:

```kotlin
data class TransitionJob(
    val sourceTrackId: String,
    val targetTrackId: String,
    val sourceMarkerUs: Long?,
    val targetMarkerUs: Long,
    val requestedGoTimeNs: Long,
    val routeProfileId: String,
    val priority: Int,
)
```

Der Job darf sich nicht in einer Compose-Recomposition oder in einem simplen Handler-Callback verstecken.

---

## 7. Offtrack: `createMix(...)` und Ergebniswerte

### 7.1 Aufruf

Die Transition-Methode liegt in:

```text
Y8/d.smali:b(...)
```

Der Native-Aufruf erfolgt bei:

```text
Y8/d.smali:744
```

Vor dem Aufruf werden unter anderem vorbereitet:

- mehrere Strings für IDs/Pfade/Storage;
- Zeit- und Positionswerte;
- mehrere Boolean-Flags;
- optionale Long-Parameter;
- der Outputname `mix.wav`.

Der letzte sichtbare String ist:

```smali
const-string v42, "mix.wav"
```

### 7.2 Fehler- und Erfolgslogik

Das Ergebnis ist ein `long[]`. Die folgenden Aussagen beziehen sich auf die sichtbare Java-/Smali-Verarbeitung nach dem Native-Aufruf; die interne Native-Berechnung selbst bleibt wegen `libtransition-aar.so` (stripped) offen.

Die App prüft:

```text
Ergebnis null? → Mix unavailable / Fehlerzustand
Array-Länge genau 3? → Ergebnis weiterverarbeiten
andere Länge? → Mix unavailable
Exception? → Mix failed und Fehlerzustand
```

Sichtbare Log-Semantik:

```text
[Mixer] createMix (native) START
[Mixer] createMix (native) DONE
[Mixer] Mix ready
[Mixer] Mix unavailable result
[Mixer] Mix failed
```

### 7.3 Ergebnisobjekt `Le9/t`

Die Klasse liegt in der disassemblierten Struktur unter:

```text
e9/t.smali
```

Sie enthält:

```text
a: long
b: long
c: long
d: Track
e: Track
f: String
```

Die `toString()`-Bezeichnungen sind:

```text
transitionStartFrames
transitionEndFrames
transitionSkipFrames
track1
track2
uri
```

### 7.4 Mapping des Native-Ergebnisses

Die sichtbare Smali-Schicht übernimmt die Array-Elemente so:

```text
native result[1] → Le9/t.a → Feldname transitionStartFrames
native result[0] → Le9/t.b → Feldname transitionEndFrames
native result[2] → Le9/t.c → Feldname transitionSkipFrames
```

Damit lautet das **statische Mapping** der sichtbaren Schicht:

```text
[end-or-native-index-0, start-or-native-index-1, skip-or-native-index-2]
```

Die Bezeichnungen `transitionStartFrames`, `transitionEndFrames` und `transitionSkipFrames` stammen aus der Objekt-/`toString()`-Semantik und werden von Verbrauchern verwendet. Trotzdem müssen zwei Punkte dynamisch oder über Native-Disassembly verifiziert werden:

1. ob die Werte tatsächlich PCM-/Audio-Frames und nicht eine andere Native-Zeiteinheit sind;
2. ob `result[0]`/`result[1]` semantisch wirklich Ende/Start bezeichnen oder ob die Native-Seite eine andere interne Konvention besitzt.

Für DropSync ist deshalb eine explizite Mapping-Funktion mit Tests besser als unbenannte Array-Indizes.

### 7.5 Verbraucher des Ergebnisses

Die Felder werden später unter anderem von folgenden Komponenten gelesen:

```text
X8/v.smali
X8/I.smali
X8/w.smali
X8/b.1.smali
```

Direkte Beobachtungen:

- `a` wird als Übergangsstartposition verwendet.
- `b` wird als Übergangsendeposition verwendet.
- `c` wird als Skip-/Frame-/Dauerparameter verwendet.
- `d` und `e` sind die beiden Track-Modelle.
- `f` ist die Output-URI bzw. der Output-String.

`X8/w.smali` verwendet `transitionEnd` und `skipBuffer` für die Seek-/Transition-Planung.

---

## 8. Offtrack: direkte Audioausgabe

### 8.1 `Y8/c` als Audio-Deck/Output

Die App verwendet direkt `android.media.AudioTrack`.

#### Aktive Audio-Operationen

```text
Y8/c.smali:618
AudioTrack.write(ByteBuffer, ...)

Y8/c.smali:3307
AudioTrack.play()

Y8/c.smali:4023
AudioTrack.play()

Y8/c.smali:1908
AudioTrack.getPlaybackHeadPosition()

Y8/c.smali:4283
AudioTrack.getPlaybackHeadPosition()
```

#### AudioTrack-Aufbau

In `Y8/c` wird ein `AudioTrack` über den Builder vorbereitet. Sichtbare Schritte umfassen:

- `AudioAttributes` setzen;
- `AudioFormat` setzen;
- Transfer Mode setzen;
- Buffergröße setzen;
- `AudioTrack` bauen;
- Referenz im Deck speichern.

#### Reset-/Stop-Pfade

Bei Seek, Stop, Reset oder Teardown gibt es:

```text
AudioTrack.pause()
AudioTrack.flush()
AudioTrack.release()
```

Die Service-Zerstörung in `PlaybackService.smali` räumt außerdem Transition-Objekte, Coroutine Jobs und AudioTrack-Ressourcen auf.

### 8.2 Bedeutung für Automix

Diese Architektur ermöglicht theoretisch:

```text
PCM aus Track A
PCM aus Track B
vorbereitetes Mix-/Transition-Segment
gezielte Bufferfolge
AudioTrack.write(...)
```

Sie ist damit wesentlich näher an einem echten Mixer als zwei unabhängige ExoPlayer mit gelegentlichen Lautstärkeänderungen.

Die statische Analyse beweist jedoch nicht, ob `mix.wav` vollständig in den AudioTrack geschrieben wird oder ob es nur ein Übergangssegment ist. Sicher ist nur:

- `mix.wav` wird im Transition-Pfad als Outputname verwendet;
- `AudioTrack` erhält direkte ByteBuffer-Daten;
- die Übergangsgrenzen werden separat als `long`-Werte transportiert.

---

## 9. Offtrack: Seek- und BPM-Logik

`X8/w.smali` enthält Log-Semantik wie:

```text
seekToTransition
bpm
skipBuffer
transitionEnd
```

Der Code berechnet einen Skip-/Offset-Wert und begrenzt ihn auf mindestens null:

```text
calculatedSkip = max(transitionEnd - offset, 0)
```

Das zeigt, dass der Transition-Seek nicht nur ein absoluter Trackstart ist. Er ist relativ zu einem analysierten Übergangsfenster und zu BPM-/Zeitparametern.

### 9.1 Was daraus sicher folgt

- BPM wird in der Transition-/Seek-Umgebung verwendet oder zumindest dafür vorbereitet.
- Es gibt ein Ende des Übergangsfensters.
- Es gibt einen Skip-/Offset-Wert.
- Negative Seek-Werte werden verhindert.

### 9.2 Was nicht sicher folgt

Nicht direkt belegt sind:

- eine konkrete Beatmatching-Formel;
- Pitch-Shifting oder Time-Stretching;
- Key-Lock;
- eine feste 4-/8-/16-Beat-Phrase;
- die konkrete Crossfade-Kurve;
- die genaue BPM-Toleranz.

---

## 10. Rekonstruierter Offtrack-Automix-Callflow

Der belegte und vorsichtig ergänzte Callflow lautet:

```text
1. Smart Queue besitzt Track A.
2. Smart Queue wählt Track B.
3. Track-Metadaten werden geprüft oder angereichert.
4. BPM, Energie, Dauer und Analyse-Flags sind verfügbar oder fehlen.
5. Bei extern benötigter Analyse wird gewartet.
6. Nach Timeout wird mit einem Fallback-Track/Metadatenzustand fortgefahren.
7. X8/I erzeugt einen c9/i-Transition-Job.
8. d9/e reiht den Job in eine Dispatch-/Prioritätsqueue ein.
9. c9/i ruft Y8/d.b(...) auf.
10. Y8/d baut Native-Parameter und Storage-/Outputwerte.
11. LibTransitionExt.createMix(...) fordert die native Transition-Berechnung an; der genaue Output-Typ bleibt wegen der stripped Library offen.
12. Native gibt long[] zurück.
13. Nur ein Ergebnis mit drei Werten wird akzeptiert.
14. Die drei Werte werden in Start, Ende und Skip überführt.
15. Ein Le9/t-Transition-Plan wird veröffentlicht.
16. X8/v/X8/w verwenden die Grenzen für Seek-/Transition-Logik.
17. Y8/c schreibt Audio-Buffer an AudioTrack.
18. Playback-Head und Zustandsobjekte verfolgen die Ausgabe.
```

### 10.1 Architekturdiagramm

```text
Track A ───────────────┐
                       │
Track B ───────────────┼──→ c9/i TransitionJob
                       │              │
BPM/Energie/Analyse ───┘              ↓
                               d9/e Queue
                                      ↓
                                  Y8/d.b
                                      ↓
                       LibTransitionExt.createMix
                                      ↓
                              libtransition-aar.so
                                      ↓
                       native long[] result
                                      ↓
                                Le9/t MixInfo
                                      ↓
                   X8/v / X8/w / X8/I Seek-Planung
                                      ↓
                             Y8/c AudioTrack
```

---

# Teil C – Vergleich Poweramp und Offtrack

## 11. Gemeinsame Muster

| Muster | Poweramp | Offtrack | Bedeutung für DropSync |
|---|---|---|---|
| eigene Audio-Hotpath-Grenze | `Pipeline2`, native Plugins | `LibTransitionExt`, `AudioTrack` | DSP/Timing nicht in Compose verstecken |
| Analyse getrennt von UI | Scanner/TagReader/DB | SongAnalysis/XML/Native Analyse | Analyse im Hintergrund und versioniert speichern |
| getrennte Service-Schicht | `PlayerService` | `PlaybackService` | MediaSession, AudioFocus und FGS zentralisieren |
| konfigurierbare Übergänge | `crossfade_length_ms`, Gapless Flags | Native Transition-Schnittstelle und Ergebnis-/Positionsplan | Übergang als Plan, nicht als spontaner Callback |
| Positions-/Statusmodell | Pipeline position/status | Playback Head/Transition Frames | Audio-Zeit und UI-Zeit trennen |
| Native Verarbeitung | EQ, Decoder, Processing | Transition-/Analyse-Library | Native erst dort einsetzen, wo Messung es rechtfertigt |
| Fallbacks | Open-/Gapless-/Plugin-Pfade | Analyse-Timeout und Mix unavailable | Unsicherheit muss sichtbare Best-Effort-Zustände haben |

## 11.1 Der wichtigste Unterschied

Poweramp zeigt stärker eine allgemeine, langlebige Audio-Plattform:

```text
Decoder → Processing/Pipeline → Output → Service
```

Offtrack zeigt stärker eine Automix-Funktion:

```text
Track-Paar → Analyse → native Transition-Schnittstelle → benannte Ergebniswerte → AudioTrack
```

Für DropSync werden beide Muster benötigt:

- Poweramp für langlebige Engine-/Service-/DSP-Grenzen;
- Offtrack für Track-Paar-, Marker-, Analyse- und Transition-Planung.

---

# Teil D – FlowRep x DropSync Zielarchitektur

## 12. Empfohlene Gesamtarchitektur

```text
Compose UI
    ↓ commands / state collection
Workout Domain
    ├── SetRepository
    ├── RestTimer
    ├── DropLandingPlanner
    └── RepState

Sensor Domain
    ├── BLE connection manager
    ├── 53-byte parser
    ├── 120-ms jitter buffer
    ├── dedup/reconnect
    ├── PCA calibration
    └── peak/repetition detector

Playback Service
    ├── MediaSession
    ├── AudioFocus
    ├── notification / foreground service
    ├── RestMusicCoordinator
    └── AudioEngine commands

Audio Engine
    ├── Rest deck
    ├── Work deck
    ├── PCM/AudioSink boundary
    ├── GainGraph
    ├── crossfade
    ├── ReplayGain
    ├── rest duck
    ├── TTS duck
    ├── EQ/DSP
    └── route clock / latency profile

Analysis Worker
    ├── MediaCodec streaming decode
    ├── waveform buckets
    ├── RMS/min/max
    ├── onset/beat/BPM
    ├── key estimate
    ├── drop candidates
    └── versioned Room records
```

## 13. DropLandingPlanner

Die zentrale Fachlogik sollte einen expliziten Plan erzeugen:

```kotlin
data class DropLandingPlan(
    val workTrackId: String,
    val markerUs: Long,
    val goDeadlineElapsedRealtimeNs: Long,
    val plannedStartUs: Long,
    val crossfadeUs: Long,
    val estimatedRouteLatencyUs: Long,
    val transitionStartUs: Long,
    val transitionEndUs: Long,
    val confidence: TimingConfidence,
    val mode: LandingMode,
)

enum class LandingMode {
    CALIBRATED,
    BEST_EFFORT,
    DIRECT_MARKER_SEEK,
    FALLBACK_NO_PRECISE_LANDING,
}
```

Grundformel:

```text
AudioStart = GoDeadline - MarkerPosition - EstimatedAudibleLatency
```

Wenn ein Crossfade vorher fertig sein muss:

```text
CrossfadeStart = GoDeadline - MarkerPosition - CrossfadeDuration - Latency
```

Bei zu kurzer Restzeit:

```text
RestRemaining < crossfadeDuration + preparationMargin
→ kein normaler Crossfade
→ Work-Deck vorbereiten
→ Marker-Direktseek mit Micro-Fade
→ confidence = BEST_EFFORT
```

## 14. Audio-Zeit, Timer-Zeit und hörbare Zeit

Drei Uhren müssen getrennt bleiben:

```text
Workout-/Timer-Zeit
    SystemClock.elapsedRealtimeNanos()

Medien-/Frame-Zeit
    Media3 position / AudioTrack playback head / Audio timestamp

Hörbare Zeit
    Frame-Zeit plus geschätzte Route-/Pipeline-Latenz
```

`player.currentPosition` allein ist keine hörbare Uhr.

Für DropSync:

```text
GoDeadline = elapsedRealtimeNanos()
TargetMarkerFrame = markerUs * sampleRate / 1_000_000
AudibleTarget = GoDeadline
```

Wenn die Route unbekannt oder gerade gewechselt wurde:

```text
confidence = BEST_EFFORT
UI-Hinweis = "Audioausgabe wird neu kalibriert"
```

Es darf keine absolute ±50-ms-Garantie für jede Android-/Bluetooth-Route versprochen werden.

## 15. Zwei Player versus eigener PCM-Mixer

### MVP: zwei Media3-/ExoPlayer-Decks

```text
RestPlayer
WorkPlayer
```

Vorteile:

- schneller implementierbar;
- MediaSession-Integration bleibt einfach;
- Work-Track kann vorbereitet und stumm gestartet werden;
- geeigneter Proof of Concept für Marker-/Timer-Logik.

Nachteile:

- zwei Player sind nicht automatisch ein samplegenauer Mixer;
- Resampler-/AudioSink-Rekonfiguration kann Timing verändern;
- Volume-Rampen im JVM-/Coroutine-Takt sind nicht samplegenau;
- parallele AudioFocus-Anforderungen müssen vermieden werden.

### Später: gemeinsamer Audio-Hotpath

```text
Decoder A ─┐
           ├── PCM Mixer / DSP → ein AudioSink / AudioTrack
Decoder B ─┘
```

Das folgt eher dem Offtrack-/Poweramp-Muster. Es sollte erst nach Messung als Native-/Custom-Audio-Engine umgesetzt werden.

### Nicht als Mixer missverstehen

- `MergingMediaSource` mischt nicht automatisch zwei unabhängig laufende Songs.
- `ConcatenatingMediaSource` bildet eine Queue, keinen frei steuerbaren Dual-Deck-Mixer.
- Ein `MediaSource.Factory`-Wrapper ist gut für Cache/URI/Metadaten, aber kein PCM-Mixer.

## 16. Crossfade

### Equal-Power-Modell

Für zwei unkorrelierte Quellen:

```text
gainA(t) = cos(pi/2 * t)
gainB(t) = sin(pi/2 * t)
```

oder äquivalent:

```text
gainA(t) = sqrt(1 - t²)
gainB(t) = sqrt(t²)
```

mit `t` von 0 bis 1.

### Ducking während Crossfade

Rest-Musik ist bereits ungefähr -8 dB geduckt. Deshalb darf nicht blind eine zweite Equal-Power-Kurve auf dieselbe Summe gelegt werden.

Besserer Gain-Graph:

```text
Source Gain
    ↓
Replay Gain
    ↓
Track-/Profile-Preamp
    ↓
Rest-Duck oder Work-Duck
    ↓
Crossfade Envelope
    ↓
TTS Sidechain Envelope
    ↓
EQ / DSP
    ↓
Limiter / Safety Ceiling
    ↓
AudioSink / DVC
```

In der Praxis sollten alle Faktoren in einem zentralen Mixer als lineare Gains berechnet werden:

```text
finalLinearGain =
    replayGainLinear
    * profileGainLinear
    * duckGainLinear
    * crossfadeGainLinear
    * ttsGainLinear
```

Ducking darf nicht durch mehrere unabhängige `setVolume()`-Aufrufe doppelt angewendet werden.

## 17. Direct-Drop-Seek

Wenn Restzeit zu kurz ist, muss der Work-Track mitten im Song starten. Dabei drohen Klicks durch einen nicht-nullwertigen Sample-Sprung.

Minimaler Ablauf:

```text
1. Work-Deck decodiert/positioniert vorbereiten.
2. Ausgang vor dem Seek mit 5–10 ms ausblenden.
3. Seek auf einen sicheren Decoder-/Framepunkt.
4. Decoder prerollen lassen.
5. Audio-Buffer verwerfen, die vor dem Ziel liegen.
6. auf Markerposition zielen.
7. 5–10 ms einblenden.
8. normaler Gain-/Drop-Plan übernimmt.
```

Ein kompletter Mixer-Stop ist dafür nicht zwingend notwendig, wenn die Deck-/Buffer-Grenze sauber implementiert ist. Die MVP-Variante darf bei unzuverlässigem Seek jedoch einen kurzen sicheren Micro-Fade bevorzugen.

## 18. Replay Gain, Rest-Duck und TTS

Empfohlene Reihenfolge:

```text
decoded PCM
    ↓
Replay Gain / Track Loudness
    ↓
Output Profile / Preamp
    ↓
EQ/DSP
    ↓
Ducking/Sidechain oder vorherige Gain-Planung
    ↓
Crossfade Envelope
    ↓
Limiter / ceiling
    ↓
Audio output / DVC
```

Die exakte Reihenfolge hängt davon ab, ob der Limiter Teil des DSP oder des finalen Output-Moduls ist. Entscheidend ist:

- Headroom vor EQ und Summation einplanen;
- Replay Gain nicht als weiteren unkoordinierten Volume-Callback behandeln;
- Rest-Duck und TTS-Duck zu einem Ducking-Faktor zusammenführen;
- TTS nicht zusätzlich über System-Ducking und internen Preamp doppelt absenken;
- bei Übersteuerung nicht einfach den Limiter als Reparatur für fehlendes Headroom missbrauchen.

Eine gute Produktentscheidung ist:

```text
Replay Gain = optional, transparent in Audio Settings
Rest Duck = eigener Sidechain-Zustand
TTS Duck = eigener Sidechain-Zustand
Final Gain = zentral berechnet
```

## 19. TTS-Countdown und Go

System-TTS hat eigene Initialisierungs-, Synthese- und Ausgabelatenz. Deshalb sollte TTS nicht die primäre Go-Uhr sein.

Robuster:

```text
GoDeadline wird unabhängig geplant.
3, 2, 1 werden frühzeitig gesprochen oder als Offline-Clips vorbereitet.
Go-Sound wird als kurzer lokaler Audio-Clip vorgepuffert.
Haptik und Go-Audio beziehen sich auf dieselbe monotone Deadline.
```

Für maximale Reproduzierbarkeit:

- kurze Countdown-Clips offline vor-rendern;
- TTS nur für längere variable Ansagen verwenden;
- `UtteranceProgressListener` nur als Beobachtung, nicht als harte Sample-Uhr verwenden;
- bei TTS-Fehler darf der Timer nicht stehen bleiben.

## 20. Haptik

Haptik hat eigene Hardware- und Vibrator-Latenz. Sie sollte parallel zur geplanten Go-Deadline ausgelöst werden, aber als Nutzerfeedback und nicht als Audio-Referenz behandelt werden.

```text
GoDeadline
    ├── Go-Audio Clip
    ├── Vibrator/VibrationEffect
    └── UI State / countdown=0
```

Für Gym-Kontext:

- kurzer starker Impuls für Go;
- optional zwei kurze Impulse bei Warnzustand;
- keine langen Notification-Muster während eines Satzes;
- Haptik bei Tasche/Bank stärker testen;
- `VibrationEffect` je Gerät testen und bei fehlender Amplitude auf robusten Fallback gehen.

## 21. AudioFocus und Interrupts

Poweramp zeigt, dass AudioFocus und Player-Service eigene Verantwortungsbereiche sind. Für DropSync:

```text
AudioFocus verloren transient:
    Musik ducken oder pausieren je Ereignis
    Timer läuft auf monotonic clock weiter
    DropPlan wird invalidiert oder neu bewertet

AudioFocus dauerhaft verloren:
    Playback stoppen/pause
    Timer-Zustand bleibt konsistent
    bei Resume neu planen
```

Wichtig:

- Notification- oder Assistenten-Interrupts dürfen den Workout-Timer nicht automatisch zurücksetzen;
- bei echtem Telefonat kann die App auf `BEST_EFFORT` wechseln;
- nach AudioFocus-Verlust, Route-Wechsel oder Resampler-Neukonfiguration muss der Plan neu bewertet werden;
- die App darf nicht so tun, als sei ein alter Audio-Plan weiterhin kalibriert.

## 22. Bluetooth-/Route-Wechsel

Bluetooth-Codecwechsel können die Ausgabelatenz und AudioSink-Konfiguration ändern. Route-Wechsel über `AudioDeviceCallback`, AudioManager-Zustände und Player-/AudioSink-Events beobachten.

Vor Go:

```text
Route stabil:
    bestehenden Plan ausführen

Route seit Planung geändert:
    Plan neu berechnen

Routewechsel in den letzten Sekunden:
    keine falsche Präzisionsgarantie
    direct marker / best effort
    Work-Track frühzeitig starten, falls sicherer
```

Ein Route-Profil sollte mindestens speichern:

```text
route key
output device type
sample rate
channel count
estimated latency
p50/p95 observed error
calibration timestamp
confidence
```

## 23. Buffer Underrun und Rebuffer

Media3-Listener und AudioTrack-Telemetrie sollten zusammen betrachtet werden:

```text
player state / isLoading
onPlaybackStateChanged
onIsLoadingChanged
onPlayerError
AudioTrack underrun callbacks, wenn verfügbar
playback head / timestamp observations
```

Bei Underrun:

```text
1. Event timestampen.
2. DropPlan auf BEST_EFFORT setzen.
3. Work-Track nicht als präzise kalibriert markieren.
4. Audio wieder stabilisieren.
5. bei ausreichender Restzeit neu planen.
6. bei Drop genau im Underrun: hörbaren Fallback auslösen und nicht blockieren.
```

Keine Architektur darf voraussetzen, dass ein Buffer-Underrun exakt vorhersagbar ist.

---

# Teil E – Offline-Analyse und Rendering

## 24. Analyse-Pipeline für 1000 Songs

Poweramp zeigt mit Scanner, nativen Tag-Readern, Thread-Priorität und SQLite, dass große Bibliotheken eine eigene Pipeline brauchen. Für DropSync:

```text
Import URI
    ↓
WorkManager/Coroutine Queue
    ↓
MediaCodec streaming decode
    ↓
Ein Durchgang:
    ├── Min/Max waveform buckets
    ├── RMS buckets
    ├── onset candidates
    ├── beat/BPM estimate
    ├── key estimate
    ├── energy curve
    └── drop candidates
    ↓
Room transaction
    ↓
analyzer_version + source fingerprint
```

### 24.1 Akku- und CPU-Strategie

Priorität:

1. aktuell gespielter Track;
2. nächster Work-Track;
3. nächste Rest-Tracks;
4. zuletzt häufig gespielte Tracks;
5. vollständiger Bibliotheks-Backfill.

Analyse nicht parallel zu unnötigem BLE-Scan und aufwendigem UI-Rendering maximieren.

### 24.2 Cache-Invalidierung

Der Cache-Key sollte nicht nur die URI sein:

```text
analysisKey = hash(
    canonicalUri,
    fileSize,
    lastModifiedOrContentFingerprint,
    analyzerVersion,
    analysisSettingsVersion
)
```

Room-Daten:

```kotlin
data class TrackAnalysisEntity(
    val trackId: String,
    val analyzerVersion: Int,
    val fileFingerprint: String,
    val durationMs: Long,
    val sampleRate: Int,
    val bpm: Float?,
    val key: String?,
    val energy: Float?,
    val hasBoundaries: Boolean,
    val waveformBlobRef: String?,
    val status: AnalysisStatus,
)
```

`analyzer_version` muss bei Algorithmusänderungen den alten Cache zuverlässig invalidieren.

## 25. Waveform in Compose

Für 5-Minuten-Songs und ungefähr 10.000 Buckets:

- Analysewerte persistent speichern;
- mehrere Auflösungen vorberechnen;
- keine Re-Decodierung während Recomposition;
- `Immutable`-/stabile ViewModels verwenden;
- Canvas nur aus vorbereiteten Arrays zeichnen;
- bei Scrubbing nicht pro Pixel neue Objekte allokieren;
- Marker separat vom Waveform-Path behandeln;
- Fortschritt als transformierte Clip-/Highlight-Schicht rendern.

Empfohlene Auflösungen:

```text
overview: 512–1024 buckets
normal:   2048–4096 buckets
detail:   8192–16384 buckets
```

Im Canvas:

```text
Waveform geometry = remembered/precomputed
Marker positions = immutable list
Progress = primitive fraction
Scrub overlay = separate lightweight draw pass
```

Ein Shader ist für v1 nicht nötig. Batching/Arrays und stabile Geometrie sind einfacher zu testen.

---

# Teil F – FlowRep-Sensor und Audio zusammenführen

## 26. BLE-Sensor-Architektur

Die Sensorseite aus FlowRep sollte dieselbe Schichtung bekommen wie die Audioseite:

```text
BLE transport
    ↓
53-byte packet parser
    ↓
sequence / timestamp validation
    ↓
dedup tracker
    ↓
120-ms jitter buffer
    ↓
feature extraction
    ↓
PCA calibration per exercise/device
    ↓
peak detector
    ↓
Rep events
    ↓
Workout domain
```

### 26.1 Nicht koppeln

Der BLE-Rep-Event darf nicht direkt `AudioTrack.play()` oder einen UI-Handler auslösen.

Besser:

```text
RepDetected(timestamp, confidence)
    ↓
Workout State
    ↓
optional audio/haptic cue
```

### 26.2 Sensor- und Audio-Uhr

BLE-Zeit, Workout-Zeit und Audio-Zeit sind unterschiedliche Uhren. Ein Rep-Event darf nicht ohne Timestamp-Normalisierung mit dem Drop-Plan verglichen werden.

```text
sensor packet time
    ↓ offset/drift estimate
elapsedRealtime domain
    ↓
workout event
```

### 26.3 Hybrid-Zählen

Für Auto- und manuelle Reps:

```text
AutoRepEvent(confidence, timestamp)
ManualIncrement(timestamp)
ManualDecrement(timestamp)
CorrectionEvent(targetCount)
```

Die UI zeigt einen gemeinsamen Rep-Wert, aber der Domain-State kennt Herkunft und Korrekturen. So bleibt die Korrektur innerhalb einer Sekunde möglich, ohne Auto-Zähler und manuelle Buttons gegeneinander laufen zu lassen.

---

# Teil G – Datenmodell ohne Sessions

## 27. Flache Satzliste und Historie

Auch ohne Session-Tabelle kann Volumen korrekt berechnet werden, wenn jeder Satz eine stabile Identität und Zeit besitzt:

```text
setId
createdAt
updatedAt
exerciseId
weightKg
reps
completed
isDeleted / tombstone
revision
```

Volumen:

```text
volume = weightKg * reps
```

Zeitaggregation:

```text
sum(volume) grouped by day/week/exercise
```

### 27.1 Edit und Undo

Nicht eine neue Kopie desselben Satzes als zweiten echten Satz speichern. Besser:

```text
Set row
    revision
    updatedAt
    previous snapshot or undo operation
```

Oder ein separates lokales Änderungsjournal:

```text
SetChange(setId, operationId, oldValue, newValue, timestamp)
```

Die fachliche Aggregation zählt nur den aktuellen aktiven Satz. Das vermeidet doppeltes Volumen.

### 27.2 PR-Volumen

PR sollte eine eindeutige Definition haben:

```text
max single-set volume
max total exercise volume per day
max weight at any reps
estimated 1RM, optional
```

Nicht alle Metriken als „PR“ zusammenwerfen.

---

# Teil H – UX und Einstellungsmodell

## 28. Poweramp-Prinzip: viele Möglichkeiten, wenige Einstiegspunkte

Poweramp zeigt, dass eine sehr tiefe Audio-Engine nicht bedeutet, dass die Hauptnavigation kompliziert sein muss.

Für FlowRep x DropSync:

```text
Train
Music
Verlauf
Einstellungen
```

In Einstellungen:

```text
Audio und DSP
    ├── Lautheit / Replay Gain
    ├── Rest-Ducking
    ├── TTS-Ducking
    ├── Crossfade
    ├── EQ
    ├── Output Profile
    └── Entwicklerdetails / Timing
```

### 28.1 Anfängeransicht

Standardmäßig sichtbar:

- Musiklautstärke;
- Rest-Musik leiser;
- Countdown-/TTS-Lautstärke;
- Crossfade an/aus;
- Drop-Modus automatisch/manuell.

### 28.2 Pro-Ansicht

Nach zwei Taps:

- Preamp;
- Replay Gain Mode;
- 32-Band-EQ und Q-Parameter;
- DVC-/Output-Optionen;
- Route-Profil;
- gemessene Latenz;
- Crossfade-Kurve;
- Analyse- und Cache-Version;
- Timing-Konfidenz.

### 28.3 Schwarz/Weiß/Lime nicht brechen

Technische Detailwerte sollten nicht durch zusätzliche Farben die visuelle Sprache zerstören:

```text
primary: lime
neutral: black/white/gray
warning: lime-outline/neutral emphasis
error: sparsam rot nur für echte Fehler
```

---

# Teil I – Was nicht behauptet werden darf

## 29. Harte Nicht-Garantien

### 29.1 Audio-Timing

Nicht versprechen:

```text
Drop trifft auf jedem Android-Gerät samplegenau.
Bluetooth-Latenz ist immer konstant.
Media3 currentPosition ist die hörbare Position.
```

Ehrliche Formulierung:

> DropSync plant die Landung auf Basis der monotonen Deadline, der Audio-Frame-Position und eines gemessenen/geschätzten Output-Profils. Bei instabiler Route, Underrun oder Bluetooth-Wechsel fällt die App transparent auf Best-Effort zurück.

### 29.2 Poweramp

Nicht behaupten:

- die genaue Poweramp-Fade-Kurve sei aus den Flags bewiesen;
- `FLAG_OPEN_FORCE_GAPLESS` sei identisch mit samplegenauem Gapless;
- jede native Methode bedeute automatisch Bit-Perfect-Ausgabe;
- das interne Poweramp-Design sei vollständig aus Smali rekonstruiert.

### 29.3 Offtrack

Nicht behaupten:

- die drei `long`-Werte seien ohne dynamische Prüfung definitiv Samples;
- `energy` werde nachweislich von `createMix` als Algorithmusinput verwendet;
- ein konkreter Equal-Power-Fade sei bewiesen;
- Keymatching oder Phrase-Matching sei aus den sichtbaren Java-Callsites sicher bestätigt;
- `mix.wav` sei sicher der komplette fertige Songmix.

---

# Teil J – Test- und Validierungsplan

## 30. Deterministische Tests

### 30.1 Transition Planner

Fake-Clock:

```kotlin
interface MonotonicClock {
    fun nowNs(): Long
}
```

Tests:

- Rest 90 s, Marker 42 s, Latenz 180 ms;
- Restzeit genau Crossfade-Dauer;
- Restzeit kürzer als Crossfade;
- Marker 0;
- Marker größer als Trackdauer;
- Routewechsel vor Go;
- Plan cancellation durch manuellen Skip;
- AudioFocusverlust während der Planung;
- Underrun kurz vor Marker.

### 30.2 Mixer/GainGraph

Prüfen:

- Replay Gain wird einmal angewendet;
- Rest-Duck und TTS-Duck werden nicht doppelt addiert;
- EQ-Headroom verhindert Clipping;
- Crossfade-Gain bleibt im zulässigen Bereich;
- limiter/ceiling reagiert reproduzierbar;
- kein NaN oder Infinity in Float-/Double-Pfaden.

### 30.3 Transition-Result

Golden Tests für:

```text
native result[1] → field start
native result[0] → field end
native result[2] → field skip
null
wrong length
negative values
out-of-range values
```

Die Offtrack-Beobachtung muss als explizite Mapping-Regel getestet werden, falls ein ähnliches eigenes Native-Interface entsteht. Nur das sichtbare Feldmapping ist statisch belegt; die Einheit und die Native-Semantik der Werte bleiben getrennte offene Punkte. Die Einheit und die native Semantik der drei Werte müssen dabei separat validiert werden.

### 30.4 BLE und Workout

Reproduzierbare Fixtures:

- gültige 53-Byte-Pakete;
- doppelte Sequenznummer;
- Paketverlust;
- Burst nach Verbindungsunterbrechung;
- Jitter außerhalb 120 ms;
- Schweiß-/Rauschprofil;
- falsche Auto-Rep plus manuelle Korrektur.

### 30.5 Audio-Drop-Erkennung im CI

Objektive Signale:

- RMS-Pegelkurve;
- Loudness LUFS, wenn verfügbar;
- Peak und True Peak;
- DC-Offset;
- Klick-/Pop-Erkennung über kurze Hochfrequenzspitzen;
- Übergangslänge;
- erwartete Markerposition;
- absolute Abweichung zwischen Ziel- und erzeugtem Ereignis im Offline-Signal.

Das ersetzt nicht Hörtests, macht Regressionen aber sichtbar.

## 31. Hörtests

Matrix:

```text
interner Lautsprecher
Kabel/USB
Bluetooth SBC/AAC/LDAC, soweit verfügbar
niedrige und hohe Lautstärke
verschiedene Sample Rates
Rest-Duck an/aus
TTS während Crossfade
manueller Skip
AudioFocus-Unterbrechung
```

Bewerten:

- Klicks/Pops;
- Lautheitssprung;
- Pumpen durch Ducking;
- verpasster Drop;
- hörbare Lücke;
- TTS-Verständlichkeit;
- Haptik-/Audio-Gefühl.

---

# Teil K – Empfohlene Phasenreihenfolge

## 32. Phase 0 – Machbarkeit

1. Zwei-Deck-POC mit lokalem Audio.
2. Monotone Timer-Deadline.
3. Manuelle Marker.
4. Work-Start-Berechnung.
5. Direct-Drop-Seek mit Micro-Fade.
6. AudioTrack-/Player-Position beobachten.
7. einfacher Route-Latenz-Test.
8. Underrun-/Route-Logging.

**Gate:** 30 kontrollierte Übergänge ohne reproduzierbare Klicks und mit dokumentierter Timing-Verteilung.

## 33. Phase 1 – Transition-Plan und Ducking

1. `DropLandingPlanner`.
2. `TransitionPlan` persistent/logbar machen.
3. zentraler GainGraph.
4. Rest-Duck und TTS-Duck zusammenführen.
5. vorgerenderte Countdown-/Go-Clips.
6. AudioFocus-/Resume-Verhalten.

**Gate:** Keine doppelten Ducking-Faktoren; AudioFocus darf Timer nicht beschädigen.

## 34. Phase 2 – Analyse

1. Streaming-Waveform.
2. BPM.
3. Onset.
4. Key optional.
5. Drop-Kandidaten.
6. Room-Cache mit `analyzer_version`.
7. WorkManager-Queue.

**Gate:** UI bleibt während Import flüssig; Cache invalidiert bei Datei-/Analyzeränderung.

## 35. Phase 3 – BLE-Integration

1. Parser-Fixtures.
2. JitterBuffer.
3. Dedup und Reconnect.
4. PCA pro Exercise/Device.
5. PeakDetector.
6. Auto-/Manual-Hybrid-UX.
7. Workout-Event-Timestamps.

**Gate:** echte Gym-Daten mit schlechtem BLE und Bewegungsrauschen bestehen gegen ein gelabeltes Referenzset.

## 36. Phase 4 – Native Audio-Hotpath nur bei Bedarf

Erst wenn Messungen zeigen, dass zwei Media3-Decks die Anforderungen nicht erfüllen:

```text
Media3/Decoder
    ↓
Custom AudioSink oder Oboe/AAudio/Native Mixer
    ↓
frame-aware crossfade
    ↓
AudioTrack/AAudio output
```

Poweramp und Offtrack rechtfertigen eine solche Grenze architektonisch. Sie rechtfertigen nicht, ohne Messung die gesamte App sofort in C++ zu schreiben.

---

# Teil L – Konkrete Designentscheidungen für DropSync

## 37. Entscheidungen

### Entscheidung 1: Übergang als Domain-Objekt

```text
TransitionPlan ist eine First-Class-Struktur.
```

### Entscheidung 2: Analyse vor Playback

```text
Nie große Analyse im kritischen Drop-Zeitfenster erzwingen.
```

### Entscheidung 3: Ein GainGraph

```text
Replay Gain, EQ, Rest-Duck, TTS-Duck und Crossfade werden zentral summiert.
```

### Entscheidung 4: Separate Audio-Uhr

```text
SystemClock für Deadlines,
AudioFrame/PlaybackHead für Audiofortschritt,
LatencyProfile für hörbare Korrektur.
```

### Entscheidung 5: Best-Effort als echter Zustand

```text
Routewechsel, Underrun, AudioFocus-Verlust oder fehlende Analyse setzen confidence herab.
```

### Entscheidung 6: Native nur hinter Interface

```kotlin
interface AudioEngine {
    suspend fun prepare(plan: TransitionPlan): PrepareResult
    fun schedule(plan: TransitionPlan): ScheduleResult
    fun cancel(reason: CancelReason)
    fun observeClock(): Flow<AudioClockSample>
}
```

Damit bleibt die spätere Native-Implementierung austauschbar.

---

# Teil M – Kompakte Checkliste

## 38. Vor jedem Drop-Feature-Release

### Architektur

- [ ] Timer läuft auf monotonic clock.
- [ ] AudioEngine ist von Compose getrennt.
- [ ] TransitionPlan ist logbar und testbar.
- [ ] AudioFocus ist vom Workout-State getrennt.
- [ ] Routewechsel invalidiert alte Präzisionsannahmen.

### Audio

- [ ] Zweiter Track wird vor dem kritischen Moment vorbereitet.
- [ ] Direct-Seek hat Micro-Fade oder PCM-sichere Grenze.
- [ ] GainGraph verhindert Doppel-Ducking.
- [ ] Replay Gain besitzt Headroom.
- [ ] Crossfade-Kurve ist messbar und konfigurierbar.
- [ ] Underrun wird erfasst.

### Analyse

- [ ] Waveform wird gestreamt berechnet.
- [ ] BPM/Onset/Key/Drop sind versioniert.
- [ ] Cache-Key enthält Datei-Fingerprint.
- [ ] Analyse blockiert den UI-Thread nicht.
- [ ] fehlende Analyse hat Fallback.

### BLE

- [ ] 53-Byte-Pakete werden validiert.
- [ ] Duplicate-/Loss-/Reconnect-Fälle sind getestet.
- [ ] PCA-Kalibrierung ist pro Exercise/Device getrennt.
- [ ] Auto-Rep und manuelle Korrektur besitzen eine gemeinsame Domain-Quelle.

### Ehrlichkeit

- [ ] Keine absolute Bluetooth-/Android-Timing-Garantie.
- [ ] Keine unbelegte Behauptung über Poweramp-/Offtrack-Native-Interna.
- [ ] Konfidenz und Messwerte werden gespeichert.

---

# 39. Schlussfolgerung

Poweramp liefert das Muster für eine langlebige Audio-Plattform:

```text
Service/Session
    → Orchestrierung
    → native Processing-/DSP-Grenze
    → Output
```

Offtrack liefert das Muster für Automix:

```text
Track A + Track B
    → Analyse
    → Transition Job
    → native createMix-Schnittstelle
    → benannte Start-/End-/Skip-Felder
    → direkte Audioausgabe
```

FlowRep x DropSync sollte beides kombinieren:

```text
Workout Event
    → Rest Timer
    → DropLandingPlanner
    → TransitionPlan
    → vorbereitete Audio-Engine
    → hörbare Landung bei Go
    → BLE-/Haptik-/TTS-Events als getrennte, synchronisierte Ausgaben
```

Die zentrale Produktidee bleibt dadurch klar:

> Der Nutzer setzt einen Satz fertig. Die App bereitet nicht nur irgendeinen Song vor, sondern plant ein analysiertes Audioereignis so, dass ein definierter musikalischer Marker möglichst zuverlässig auf den Trainingsmoment fällt. Die App zeigt dabei ehrlich, ob die Landung kalibriert oder nur Best-Effort ist.

---

# Teil N – Vertiefte Offtrack-Automix-Evidenz

## 41. Exakte Transition-Job-Parameter

Die zweite Auswertungsrunde der Smali-Aufrufkette ergänzt den groben Callflow um konkrete, sichtbare Parameterformen.

### 41.1 `Y8/d.b(...)`

```text
Y8/d.smali:217
b(Track, Track, long, long, boolean, boolean, Long, Long, Long)
```

Direkt aus der Signatur ableitbar:

| Parameter | Statischer Typ | Was sicher gesagt werden kann |
|---|---:|---|
| `p1` | `Track` | Quelle/erster Track des Transition-Jobs |
| `p2` | `Track` | Ziel/zweiter Track des Transition-Jobs |
| `p3/p4` | `long` | primitive Zeit-/Positionswerte, genaue Einheit offen |
| `p5/p6` | `long` | primitive Zeit-/Positionswerte, genaue Einheit offen |
| `p7/p8` | `boolean` | Native-/Transition-Flags, Semantik nicht benannt |
| `p9` | `Long?` | optionaler Native-Parameter; genaue Rolle offen |
| `p10` | `Long?` | optionaler Native-Parameter; genaue Rolle offen |
| `p11` | `Long?` | optionaler Native-Parameter; genaue Rolle offen |

### 41.2 Optionale Werte

Die drei optionalen Werte werden jeweils null-geprüft und bei Nicht-Null über `Long.longValue()` entpackt:

```text
Y8/d.smali:523–585
```

Das ist ein wichtiges Designsignal: Nicht jeder Aufruf liefert alle drei optionalen Werte. Ob diese Werte Boundaries, Seek-Daten, Konfiguration oder andere Native-Parameter repräsentieren, ist aus Nullprüfung und Unboxing allein nicht beweisbar. Ein negativer Sentinel wird sichtbar vorbereitet; seine fachliche Bedeutung bleibt offen.

Die sichtbare Fallback-Konvention verwendet dabei einen negativen Sentinelwert, der im Smali als `const-wide/16 ... -0x1` vorbereitet wird. Die genaue Bedeutung jedes einzelnen Sentinels muss getrennt von der bloßen Nullbehandlung validiert werden.

### 41.3 Zeit-/Delta-Berechnung

Vor dem Native-Aufruf wird berechnet:

```smali
Y8/d.smali:590
sub-long v40, p5, p3
```

Sicher ist damit:

```text
delta = p5 - p3
```

Nicht sicher ist, ob dieses Delta Millisekunden, Audioframes, Samples, Decoderpositionen oder eine andere interne Einheit darstellt. Für DropSync sollte eine ähnliche Rechnung niemals mit unbenannten `Long`-Werten implementiert werden; die Domain-Typen sollten die Einheit ausdrücken.

Beispiel:

```kotlin
@JvmInline
value class AudioFrame(val value: Long)

@JvmInline
value class MediaTimeUs(val value: Long)
```

## 42. Native-Aufruf und Statusmodell

### 42.1 Übergabe an `createMix(...)`

Die sichtbare Vorbereitung liegt ungefähr in:

```text
Y8/d.smali:672–744
```

Dort werden unter anderem:

- mehrere String-/Pfad-/ID-Werte;
- die zwei Boolean-Flags;
- primitive Long-Werte;
- optionale Werte beziehungsweise Sentinelwerte;
- der sichtbare Outputname `mix.wav`

in die Native-Aufrufregister gelegt.

Die direkte Native-Signatur ist:

```text
createMix(
    String, String, String, String, String,
    long,
    boolean, boolean, boolean,
    long, long, long,
    boolean, boolean,
    long,
    String
): long[]
```

Die konkrete Semantik der einzelnen Strings und Flags ist statisch nicht wiederhergestellt. `createMix` sollte deshalb in der Dokumentation als **Native-Transition-Schnittstelle** bezeichnet werden, nicht als vollständig verstandener Renderer.

### 42.2 Ergebniszustände

Nach dem Call werden mindestens diese Zustände unterschieden:

```text
Native result == null
→ unavailable/error path

Native result length != 3
→ Mix unavailable

Native result length == 3
→ Ergebnisobjekt Le9/t erzeugen

Exception
→ Mix failed / Fehlerstatus
```

Die Zustände werden über Wrapper-/State-Objekte wie `Lb9/i`, `Lb9/j` und `Lb9/f` weitergereicht. Damit ist der Transition-Status für die übrige Playback-Orchestrierung beobachtbar und nicht nur ein lokaler Return-Wert.

## 43. Exakte Queue- und Coroutine-Ausführung

### 43.1 Erzeugung und Priorität

`X8/I.smali` erzeugt den Job ungefähr im Bereich:

```text
X8/I.smali:5404–5516
```

Die sichtbare Dispatch-Sequenz enthält:

```smali
const/4 v1, 0x5
invoke-virtual {v0, v2, v1}, Ld9/e;->b(Lc9/j;I)V
```

Damit wird der Transition-Job mit einem sichtbaren numerischen Parameter `5` an `d9/e` übergeben. Dieser Wert kann ein Prioritäts-, Modus- oder Typwert sein; seine genaue Bedeutung ist aus dem Aufruf allein nicht beweisbar und müsste im Vertrag von `d9/e` verifiziert werden.

### 43.2 Coroutine-Ausführung

`c9.1/h.smali:83–118` dient als Continuation-/Coroutine-Wrapper und ruft:

```smali
Lc9/i;->d(Lya/c;)Ljava/lang/Object;
```

Die eigentliche Jobausführung ruft in `c9.1/i.smali` ungefähr bei:

```text
c9.1/i.smali:2140
```

auf:

```smali
LY8/d;->b(Track, Track, JJ, ZZ, Long, Long, Long)
```

Das bestätigt einen asynchronen Pfad:

```text
X8/I
  → c9/i erzeugen
  → d9/e einreihen
  → c9/h Coroutine/Continuation
  → c9/i.d()
  → Y8/d.b()
  → createMix()
```

### 43.3 Cancellation

Die Queue-/Orchestrierungsschicht behandelt Cancellation explizit. Sichtbare Muster umfassen:

```text
CancellationException
Job.cancel(...)
Iterator.remove()
ArrayList.remove()
Queue clear/abort
```

Logs nennen unter anderem:

```text
setQueueSmart: queueJob cancelled
appendRelatedTracksInternal: cancelled after analysis wait, aborting
navigateToTrack cancelled
setQueueManual: orderingJob cancelled
```

#### Übertragung auf DropSync

Ein manueller Skip oder ein neuer Satz darf einen alten Drop-Plan nicht nur logisch überschreiben. Er muss:

```text
1. Plan als cancelled markieren.
2. ausstehende Analyse-/Render-Jobs abbrechen.
3. alte Callbacks ignorieren.
4. Audio-Deck-/Buffer-Aktion invalidieren.
5. neuen Plan mit neuer Generation/Operation-ID erzeugen.
```

## 44. Direkter AudioTrack-Pfad

### 44.1 Bufferquelle

`Y8/c` besitzt unter anderem:

```text
AudioTrack e
MappedByteBuffer f
int g
long h
long p
long q
AtomicBoolean m
```

Im aktiven Write-Pfad wird der gemappte Buffer dupliziert bzw. begrenzt:

```text
MappedByteBuffer.duplicate()
ByteBuffer.position(...)
ByteBuffer.limit(...)
AudioTrack.write(ByteBuffer, ...)
```

Direkter Befund:

```text
Y8/c.smali:618
AudioTrack.write(ByteBuffer, ...)
```

Das zeigt einen blockweisen ByteBuffer-Ausgabepfad an `AudioTrack`. Weil `AudioTrack` Audiodaten ausgibt, liegt ein Audio-Buffer-Pfad nahe; ob die konkrete `MappedByteBuffer`-Quelle bereits PCM, ein anderes dekodiertes Format oder ein vorher verarbeitetes Artefakt enthält, muss über Format- und Decoderpfad separat verifiziert werden.

### 44.2 AudioTrack-Aufbau

Der Builder-Pfad setzt sichtbar:

```text
AudioAttributes
AudioFormat
TransferMode
BufferSizeInBytes
build()
```

Das ist relevant für DropSync, weil die Output-Konfiguration nicht losgelöst vom Timing betrachtet werden darf:

```text
sample rate
channel count
encoding
buffer size
transfer mode
route
```

ändern gemeinsam die Eigenschaften der hörbaren Ausgabe.

### 44.3 Start und Playback-Head

Aktive Startpfade:

```text
Y8/c.smali:3307
Y8/c.smali:4023
AudioTrack.play()
```

Positionsbeobachtung:

```text
Y8/c.smali:1908
Y8/c.smali:4283
AudioTrack.getPlaybackHeadPosition()
```

Für DropSync ist das das passende Architekturprinzip:

```text
AudioClockSample(
    monotonicSampleTime,
    playbackHeadFrames,
    sampleRate,
    routeId,
    confidence
)
```

`getPlaybackHeadPosition()` allein ist noch keine vollständige akustische Uhr; es muss mit monotonic time, Sample Rate und Route-/Output-Latenz verbunden werden.

### 44.4 Reset-/Seek-Grenze

Die Reset-/Cleanup-Pfade prüfen den Playback-Zustand und enthalten sichtbar Operationen für:

```text
AudioTrack.pause()
AudioTrack.flush()
Playback-/Position-Status zurücksetzen
StateFlow/MutableState aktualisieren
```

Ein `setPlaybackHeadPosition(0)`-Aufruf wurde in der Detailauswertung als Reset-Muster berichtet; für eine endgültige Zeilenreferenz sollte die konkrete lokale `Y8/c.smali`-Version nochmals direkt geprüft werden. Die allgemeine Seek-/Reset-Grenze ist durch Pause/Flush und Positionsstatus jedoch belegt.

Das ist ein wichtiger Klick-/Seek-Befund. Für einen Direct-Drop braucht DropSync eine definierte Buffergrenze. Ein Seek in einem gefüllten Buffer darf nicht einfach mit einem neuen Zielwert überschrieben werden.

MVP-Muster:

```text
fade down
pause/flush oder deck-isolierter reset
seek/preroll
start
fade up
```

Später:

```text
PCM mixer keeps output alive
only target deck buffer is replaced
micro-fade around discontinuity
```

## 45. Verbraucher der Transition-Ergebniswerte

Die Ergebnisfelder werden nicht nur gespeichert, sondern in mehreren Playback-Pfaden gelesen. Ihre Objektlabels suggerieren Start/Ende/Skip; die exakte Einheit und Native-Semantik bleiben offen:

| Komponente | Gelesene Werte | Sichtbare Rolle |
|---|---|---|
| `X8/v.smali` | `a`, `b`, `c` | Übergangs-Zeit-/Positionsparameter extrahieren |
| `X8/w.smali` | `e`, `b` | Ziel-Track und Übergangsende für Seek-Logik |
| `X8/I.smali` | `a`, `b` | Transition-/Seek-Handler und Vergleiche |
| `X8/b.1.smali` | `d`, `e`, `b` | ausgehenden/eingehenden Track und Übergangsposition |

Zusätzliche direkte Beobachtungen:

- `a` und `b` werden verglichen oder an weitere Positions-/Seek-Funktionen übergeben.
- `b` wird in `X8/w` als `transitionEnd`-naher Wert weiterverwendet.
- `c` wird in `X8/v` separat gelesen und ist damit nicht bloß redundante Kopie von `a`/`b`.
- `d/e` bilden das Track-Paar des Ergebnisses.
- `f` ist der URI-/Output-String des Ergebnisobjekts.

Die Feldnamen und Verbraucher rechtfertigen ein `TransitionResult`-Domainmodell. Sie rechtfertigen nicht, die drei Werte ohne Einheiten-Wrapper als Millisekunden zu behandeln.

## 46. Neue Umsetzungsempfehlungen für DropSync

### 46.1 Keine unbenannten Long-Parameter

Nicht:

```kotlin
createMix(trackA, trackB, p3, p5, flag1, flag2, p9, p10, p11)
```

Sondern:

```kotlin
data class TransitionInputs(
    val source: TrackId,
    val target: TrackId,
    val sourceBoundary: AudioFrame?,
    val targetBoundary: AudioFrame?,
    val requestedStart: MediaTimeUs?,
    val requestedEnd: MediaTimeUs?,
    val skip: AudioFrame?,
    val allowFallback: Boolean,
    val forceGapless: Boolean,
)
```

### 46.2 Operation IDs gegen späte Callbacks

```kotlin
@JvmInline
value class TransitionOperationId(val value: Long)
```

Jede Async-Aktion erhält eine ID. Ein Ergebnis darf nur angewendet werden, wenn es noch zur aktuellen Operation gehört.

### 46.3 Result-Mapping zentral kapseln

```kotlin
fun mapNativeTransitionResult(values: LongArray): NativeTransitionResult {
    require(values.size == 3)
    return NativeTransitionResult(
        fieldA = values[1],
        fieldB = values[0],
        fieldC = values[2],
    )
}
```

In einer echten App sollten `fieldA/B/C` sofort in benannte, einheitenbehaftete Werte überführt werden. Bis die Einheit verifiziert ist, ist ein expliziter `UnknownAudioUnit`-Zwischentyp besser als eine falsche Millisekundenbezeichnung.

### 46.4 Audio-Deck vom Transition-Plan trennen

```text
TransitionPlanner
    → TransitionResult

AudioDeckController
    → prepare / seek / preroll / play / flush

AudioClock
    → playback head / monotonic mapping

PlaybackService
    → orchestration / focus / lifecycle
```

Das entspricht gleichzeitig dem Poweramp-Muster (`Pipeline2`-Grenze) und dem Offtrack-Muster (`Y8/d` versus `Y8/c`).

---

## 47. Offene Punkte für eine weitere Analyse-Runde

Die Nummerierung 41–47 bildet bewusst den nachträglich ergänzten Vertiefungs-Appendix; das Quellenkapitel folgt als Abschnitt 48.

Die statische Analyse beantwortet jetzt den Java-/Smali-Datenfluss weitgehend. Offen bleiben bewusst:

1. die exakte Einheit von `p3`, `p5`, `p9`, `p10`, `p11` und `Le9/t.a/b/c`;
2. die genaue Bedeutung der drei Boolean-Flags;
3. ob `mix.wav` ein vollständiger Mix, ein Übergangssegment oder nur ein Native-Artefaktname ist;
4. die konkrete Fade-/Gain-Kurve;
5. ob BPM nur zur Seek-/Queue-Logik oder auch direkt im Native-Algorithmus verwendet wird;
6. ob Energie, Key und Boundaries tatsächlich als Native-Inputs an `createMix` eingehen;
7. ob der Decoderpfad Resampling vor oder nach dem Transition-Renderer durchführt;
8. ob und wie die App `AudioTrack`-Underruns misst;
9. ob die Route-/Codec-Konfiguration während einer Transition neu aufgebaut wird;
10. welche exakten Audioframes zu den drei Ergebniswerten gehören.

Für diese Punkte wäre eine nächste Runde mit kontrollierten lokalen Testtracks, dynamischem Logging auf einem eigenen Gerät und/oder ARM64-Disassembly der stripped Library erforderlich.

---

## 48. Quellen und Artefaktverweise

### 48.2 Öffentliche Produktclaims – nicht mit APK-/Smali-Evidenz gleichsetzen

Die ursprüngliche Notiz enthielt unter anderem Aussagen zu Poweramp Hi-Res/DSD/DVC/64-Bit-Pipeline und zu Offtrack Smart Mix, Highlight Mode, Spotify/Apple Music sowie Energie-/Key-/BPM-Kuration. Diese Informationen stammen aus der damaligen öffentlichen Produktbeschreibung bzw. den dort verlinkten Quellen und wurden in dieser Analyse **nicht** als konkrete APK-Implementierung verifiziert. Sie sind als E4-Praxis-/Produktclaims zu behandeln.

### 48.3 Öffentliche Produkt-/Dokumentationsquellen aus der ursprünglichen Notiz

- https://powerampapp.com/
- https://play.google.com/store/apps/details?id=com.maxmpz.audioplayer
- https://forum.powerampapp.com/topic/26908-gapless-albums-playback/
- https://www.offtrack.com/workoutmix/

### 48.4 Lokale statische Analyseartefakte

### 48.1 Zentrale Evidence-Referenzen

Die wichtigsten linearen Referenzen aus den disassemblierten Dateien sind:

| Befund | Datei und Stelle | Status |
|---|---|---|
| Poweramp native Pipeline-/Lifecycle-Grenze | `Pipeline2.smali:499–577` – native Methoden; `:213`, `:249`, `:5572`, `:5739`, `:6606`, `:7012` – konkrete Lifecycle-Aufrufe | E1 |
| Poweramp Crossfade-Preference | `com/maxmpz/audioplayer/prefs/В.smali:422–440` – `crossfade_auto_advance`, `crossfade_length_ms`, Default `0x1388` | E1 |
| Poweramp Open-Flags | `com/maxmpz/audioplayer/player/PlayerService.smali:14935–14961` – `FLAG_OPEN_NO_CROSSFADE`, `FLAG_OPEN_FORCE_GAPLESS` | E1 |
| Poweramp Scanner-Priorität/SQLite | `com/maxmpz/audioplayer/scanner/folder/H.smali:680–689` und Scanner-Transaktionsbereiche | E1 |
| Offtrack Native Bridge | `com/mixonset/libtransition/LibTransitionExt.smali:7–55` – `loadLibrary`, native API-Deklarationen | E1 |
| Offtrack `createMix`-Aufruf | `Y8/d.smali:744` | E1 |
| Offtrack Ergebnisprüfung | `Y8/d.smali:820–841` – `long[]`-Länge/Unavailable-Pfad | E1 |
| Offtrack `Le9/t`-Konstruktion | `Y8/d.smali:982–1050` | E1 |
| Offtrack Ergebnisfelder | `e9/t.smali` – Felder `a/b/c/d/e/f` und `toString()`-Labels; Pfad/Zeilen bei erneuter Disassemblierung gegen die lokale Ausgabe prüfen | E1, Pfad stabil über Deskriptor `Le9/t;` |
| Offtrack Audio-Write | `Y8/c.smali:618` – `AudioTrack.write(ByteBuffer,...)` | E1 |
| Offtrack Audio-Start | `Y8/c.smali:3307` und `4023` – `AudioTrack.play()` | E1 |
| Offtrack Playback-Head | `Y8/c.smali:1908` und `4283` – `getPlaybackHeadPosition()` | E1 |
| Offtrack Service-Teardown | `PlaybackService.smali:2477–2538` – Transition-/AudioTrack-Cleanup | E1 |
| Offtrack Analyse-Laden | `B9/b0.smali:5965` – `loadSongAnalysis(...)` | E1 |
| Offtrack Analyse-Persistenz | `f9.1/b.smali:930` und `1259` – XML lesen/schreiben | E1 |
| Offtrack BPM-/Transition-Seek | `X8/w.smali` – `seekToTransition`, `bpm`, `skipBuffer`, `transitionEnd` | E1/E2 |
| Offtrack Analyse-Timeout | `X8/B.smali` – `setQueueSmart` mit beobachtetem `0x9c40`-Timeout | E1 |

Die Zeilennummern beziehen sich auf die lokale Baksmali-Ausgabe der untersuchten Versionen und können sich bei einer erneuten Disassemblierung mit einem anderen Tool oder einer anderen APK-Version verändern.

#### Poweramp

```text
D:\rev-tools\poweramp_offline_triage\smali-3.0.9\
```

Besonders relevant:

```text
com/maxmpz/audioplayer/processing/Pipeline2.smali
com/maxmpz/audioplayer/player/PlayerService.smali
com/maxmpz/audioplayer/equalizer/Coefs.smali
com/maxmpz/equalizer/eq/PeqNativeUtils.smali
com/maxmpz/audioplayer/scanner/folder/DirScanner.smali
com/maxmpz/audioplayer/scanner/FFMpegTagReader.smali
com/maxmpz/audioplayer/prefs/В.smali
```

#### Offtrack

```text
D:\rev-tools\offtrack-automix-triage\smali\
D:\rev-tools\offtrack-automix-triage\raw\lib\arm64-v8a\
```

Besonders relevant:

```text
com/mixonset/libtransition/LibTransitionExt.smali
Y8/d.smali
Y8/c.smali
X8/I.smali
X8/L.smali
X8/w.smali
X8/B.smali
c9.1/i.smali
e9/t.smali
com/offtrack/core/dj/PlaybackService.smali
```

**Hinweis:** Diese Datei dokumentiert statische Analyse und technische Übertragung. Sie ist keine Behauptung, dass die vollständige proprietäre Native-Implementierung oder jede Laufzeitentscheidung der untersuchten Apps rekonstruiert wurde.

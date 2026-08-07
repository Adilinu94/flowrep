# Wissen Poweramp + Offtrack: Konzepte für FlowRep x DropSync Fusion

**Datum:** 2026-08-07  
**Quellenbasis:** Nur öffentliche Doku (powerampapp.com, Poweramp Forum, offtrack.com). Kein proprietärer Code dekompiliert.
**Zweck:** Konzepte für Audio Engine, Workout Mixing und UX in unsere Kotlin Gym App übernehmen.

---

## 1. Was wir von Poweramp lernen (Audio Engine)

### 1.1 Engine Priorität: Qualität, Leistung, Kontrolle
- Hi-Res Output via AAudio / OpenSL ES, USB DAC, 24/32 Bit 96/192/384 kHz, DSD. Native Engine optimiert für niedrigen Akkuverbrauch und Stabilität auch bei großen Bibliotheken.
- Wichtig für uns: DSP in 64 Bit Pipeline mit Float Output, DVC optional, Output Profile je Gerät. Das haben wir in DropSync bereits; Poweramp bestätigt den Weg.

### 1.2 64 Band parametrischer EQ statt fester Bänder
- Parametrisch (Frequenz + Q + Gain) plus grafisch, Preamp, Presets je Ausgang und Kopfhörer, Import/Export Presets.
- Unser Takeaway: EQ nicht nur als 32 Slider, sondern Frequenz + Q möglich, Presets pro Device. Wir können 32 Band lassen, aber Q-Faktor intern mitführen.

### 1.3 Direct Volume Control (DVC)
- DVC macht EQ/Bass/Treble wirksam ohne Android System Mixer, verbessert Qualität bei BT und DVC. Wichtig: Nicht mit System Volume kollidieren; wir machen DVC optional und doku.

### 1.4 Replay Gain, Gapless, Crossfade
- Replay Gain normalisiert Lautstärke über Alben, Gapless verlangt korrekt kodierte Dateien plus Preload Periode, Crossfade Länge einstellbar 5s Standard, Auto-Advance Fading kein/Short.
- Unser Takeaway: Preload zweite Datei rechtzeitig vor Ende der ersten, Crossfade Länge konfigurierbar, Gapless nur wenn Dateien korrekt.

### 1.5 Kontrolle überall
- Android Auto, Widgets, Headset Buttons, Bluetooth Control, Lock Screen.
- Unser Takeaway: MediaLibrarySession + Media3 gibt uns das kostenlos, wir nutzen es für M5 Taste + Headset.

### 1.6 Community-getriebene Features
- Top Community Vorschläge: USB Exclusive Driver, Bit Perfect Modes, 64 Bit Pipeline, DSD Remastering, Dynamic Reconfiguration, Output Presets.
- Unser Takeaway: Bit Perfect Modus der DSP Float Kette bypassed, aber UI dezent.

---

## 2. Was wir von Offtrack lernen (Workout Mixing)

### 2.1 Smart Mix: Playlist in DJ Mix verwandeln
- Logg dich mit Spotify/Apple Music ein, wähle Playlist, Smart Mix erzeugt nahtlosen Mix. Für uns offline: Gleiche Idee mit Rest/Work Playlisten, aber ohne Konto.

### 2.2 Highlight Mode: Song auf beste Momente kürzen
- Songs zu lang, Chorus wiederholt; Offtrack wechselt Songs alle paar Minuten, um Intensität zu halten. Genau unser Drop Konzept: Song beim Drop knallen lassen, nicht 4 Minuten durchziehen.

### 2.3 Seamless Transitions statt Lücken
- Keine Stille zwischen Songs, DJ-artige Crossfades. Unser Equal Power Crossfade 3s passt perfekt.

### 2.4 Song Queue nach DJ Metriken
- Shuffle zerstört Vibe; Offtrack analysiert Musik und kuratiert Queue nach Key, BPM, Energie.
- Unser Takeaway: Work Playlist nach Energie/BPM sortieren, Rest Playlist nach Ruhe. Offline können wir BPM + Key aus TrackAnalyzer nutzen und Queue entsprechend sortieren.

### 2.5 Energie Filter
- Workout Mix nur "intense/wild", Recovery Mix nur "mellow/chill". Unser Label Rest/Work ist exakt das.

### 2.6 BPM Filter
- Mix nach gewünschtem Tempo vorbereiten. Für Laufen/Radfahren wichtig, für Kraftsport weniger, aber wir können BPM Anzeige im Player anbieten.

---

## 3. Übertragbare Verbesserungen für DropSync/FlowRep

### 3.1 Audio Engine
- Parametrische EQ Frequenz + Q in Domain Modell aufnehmen (Poweramp Muster).
- Replay Gain statt fixer Pause Duck: Einheitliche Lautstärke über Songs, Preamp Node je Song, Option in Einstellungen.
- Gapless Preload: Bei Crossfade zu Work Song schon 3s vorher laden, Media3 Preload über MediaItem.
- Output Presets je BT Gerät behalten und erweitern, Auto Switch über DeviceProfileStore (haben wir schon, Poweramp bestätigt).

### 3.2 Workout Mixing
- Rest/Work Playlisten bleiben das Herz; zusätzlich Sortierung nach Energie/BPM in Queue Vorauswahl (Offtrack Muster).
- Highlight Konzept ist unser Drop: Wir können zusätzlich "Song max 2:00" Regel beim Work Queue bauen, damit nie ein Song ewig läuft und der nächste Drop verschenkt wird.
- BPM + Key aus TrackAnalyzer speichern und als Chip im Player anzeigen, Queue Editor sortiert nach BPM absteigend für Work, aufsteigend für Rest.

### 3.3 UX
- One-Tap Deep Link: Von Train direkt in Queue Editor.
- Keine Angst vor Optionen: Poweramp hat tausende Settings ohne dass es verwirrt, weil Einstellungen logisch gruppiert. Wir gruppieren Audio unter "Audio und DSP", alles andere bleibt.

---

## 4. Konkrete Änderungsvorschläge an unserem Design (bewusst klein halten)

1. **Replay Gain optional** hinter Audio Einstellungen, Default an bei Album, Preamp Node additiv zu Rest Duck.
2. **BPM/Key in TrackAnalyzer** mit speichern in `track_analysis`, dann Queue Vorauswahl nach Energie.
3. **Work Song max 2 Minuten Regel** in DropLandingPlanner: Wenn Work Song nach Drop länger als ~2:00 und nächster Song hat Drop, wechsle dort nahtlos weiter (Offtrack Highlight Mode).
4. **Gapless Preload** im CrossfadeController: Zweite Datei 3s vor Ende starten, Media3 `setMediaItems` mit Preload.

---

## 5. Grenze: Was wir nicht tun

- Kein proprietärer Poweramp Code dekompilieren oder übernehmen.
- Kein Streaming (Offtrack nutzt Spotify etc; wir bleiben offline).
- Kein DSD, kein USB Exclusive für v1 (später als Option).
- Kein AutoEQ auf Tausende Kopfhörer für v1.

---

## 6. Quellen

- https://powerampapp.com/ (Features, FAQ, Hi-Res, EQ, Engine)
- https://play.google.com/store/apps/details?id=com.maxmpz.audioplayer (Engine Details)
- https://forum.powerampapp.com/topic/26908-gapless-albums-playback/ (Gapless: Preload, Fading, Silence)
- https://www.offtrack.com/workoutmix/ (Smart Mix, Highlight Mode, Energy/BPM Filter)

---

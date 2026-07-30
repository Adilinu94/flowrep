# Umbauplan: Übungsverwaltung + Start-Countdown-Flow

**Datum:** 2026-07-28
**Status:** Planung, noch nicht umgesetzt.
**Entscheidungsgrundlage:** Produktentscheidung von Adi im selben Chat-Thread
(2026-07-28). Löst die im Audit offene Frage „Curl-only oder Übung #2?"
(`docs/design/AUDIT_FULL_REPO_IMPROVEMENTS.md`, Abschnitt „Offene Fragen")
bewusst auf: **mehrere, vom Nutzer selbst angelegte Übungen.**

**Ersetzt/überholt:** `KONZEPT_GUIDED_CALIBRATION_2_0.md`s Leitplanke „UI/Flows
V1 strikt single-exercise, keine generelle Übungslogik vor Übung #2" gilt ab
jetzt nicht mehr — Übung #2 (und #3, #4, …) sind jetzt explizit gewollt. Diese
Datei sollte bei Umsetzung mit einem Verweis auf diesen Umbauplan versehen
werden, statt sie stillschweigend zu ignorieren.

---

## 1. Entscheidungen (von Adi bestätigt)

1. Kein automatisches Zählen mehr nach der Kalibrierung. Zählen beginnt
   **ausschließlich** nach explizitem Tap auf „Start".
2. Der Countdown (+Vibration) läuft **vor jedem einzelnen Satz**, nicht nur
   beim ersten Mal nach der Kalibrierung.
3. Bizeps Curl darf beim Umbau als bereits angelegte Übung vorhanden sein
   (nichts geht verloren, keine Neuanlage durch den Nutzer nötig).

## 2. Die zentrale Architektur-Änderung

**Heute:** `main.dart` erzeugt **eine einzige** `WorkoutEngine(exerciseId:
'bicep_curl', ...)` beim App-Start. Fest verdrahtet, nicht pro Übung.

**Neu:** Die Engine wird erst erzeugt, wenn eine Übung ausgewählt wird, und
zwar **pro `exerciseId` eine eigene Instanz** (Riverpod-„Family"-Provider,
das dafür vorgesehene Werkzeug — kein Fremdkörper). `main.dart` erzeugt beim
Start nur noch die geräteweiten Dinge (BLE-Provider, Datenbank), keine
Engine mehr direkt.

Alles, was schon pro `exerciseId` funktioniert (`ExerciseProfile`,
`CalibrationController`, `WorkoutEngine`-Konstruktor selbst,
`CsvSessionRecorder`, Export), bleibt unverändert — das war nie auf Bizeps
Curl beschränkt, nur die App-Oberfläche hat bisher nur eine Übung angeboten.

## 3. Neue Datenstruktur: `Exercises`-Tabelle

Neue Drift-Tabelle (`app/lib/data/repositories/drift_database.dart`, gleicher
Stil wie `WorkoutSessions`/`ExerciseSets`):

```dart
class Exercises extends Table {
  TextColumn get id => text()();          // generierte ID, siehe unten
  TextColumn get displayName => text()(); // "Latzug", vom Nutzer editierbar
  DateTimeColumn get createdAt => dateTime()();
}
```

**Wichtig — `id` wird NICHT aus dem Namen abgeleitet** (kein "latzug"-Slug).
Grund: Nutzer tippen sich, benennen um, und zwei ähnliche Namen könnten
kollidieren. Stattdessen eine generierte, stabile ID (z.B. UUID), die sich
nie ändert, auch wenn `displayName` später umbenannt wird. `exerciseId` in
`ExerciseProfile`/`ExerciseSets`/CSV-Export bleibt exakt dieselbe ID — keine
Änderung an bestehenden Tabellen nötig, nur eine neue Tabelle dazu.

> **Nachtrag 2026-07-28** (siehe
> [`EXERCISE_BIOMECHANICAL_PRIORS_2026-07-28.md`](./EXERCISE_BIOMECHANICAL_PRIORS_2026-07-28.md)):
> Diese Aussage zur generierten `id` bleibt richtig. Die Tabelle braucht aber
> zusätzlich ein Pflichtfeld `templateId`, das eine von 5 vordefinierten
> Übungen referenziert (kein Freitext-Typ) — Anlegen wird dadurch von einem
> reinen Textfeld zu einer Auswahl aus 5 Optionen, `displayName` bleibt frei
> editierbar wie hier beschrieben.

## 4. Migration/Seeding

Beim ersten Start nach dem Umbau (einmaliger Migrationsschritt, analog zum
bestehenden Muster in `AppDatabase.migrateToEncryptedIfNeeded`): falls die
`Exercises`-Tabelle leer ist UND es bereits Kalibrierungs-/Sessiondaten für
`exerciseId = 'bicep_curl'` gibt, wird automatisch ein Eintrag „Bizeps Curl"
mit `id = 'bicep_curl'` angelegt (dieselbe ID wie bisher — bestehende Historie
bleibt ohne Bruch verknüpft). Falls noch gar keine Daten existieren
(Neuinstallation), bleibt die Liste leer, „Bizeps Curl" wird nicht künstlich
vorgeschlagen.

## 5. Bildschirme, im Detail

### 5.1 Übungsübersicht (neu, wird der neue Startbildschirm)

`FlowRepApp.home` ändert sich von `HomeScreen()` zu `ExerciseOverviewScreen()`.

- Liste aller `Exercises`-Einträge, je Zeile: Name + Status-Badge
  („Kalibriert" / „Noch nicht kalibriert" — Status kommt daher, ob ein
  `ExerciseProfile` für diese `id` existiert).
- „+ Neue Übung" — öffnet einen einfachen Dialog (Textfeld, „Erstellen").
- Tap auf eine Zeile → siehe 5.2/5.3.

### 5.2 Übung anlegen (neu, Dialog, kein eigener Screen)

Textfeld (Pflichtfeld, nicht leer) → erzeugt `Exercises`-Eintrag mit neuer
ID → zurück zur Übersicht, neuer Eintrag erscheint als „Noch nicht
kalibriert".

### 5.3 Weiterleitung beim Antippen einer Übung

- **Nicht kalibriert:** → `CalibrationWizardScreen`, jetzt parametrisiert mit
  `exerciseId`/`exerciseDisplayName` (aktuell vermutlich fest auf Bizeps Curl
  angenommen — muss beim Umbau geprüft und ggf. angepasst werden).
- **Bereits kalibriert:** → „Bereit"-Zustand (siehe 5.4), Engine für genau
  diese `exerciseId` wird jetzt (und nur jetzt) erzeugt/geladen.

### 5.4 „Bereit"-Zustand + Start-Countdown (ersetzt Auto-Arm)

- Nach Kalibrierung (oder beim erneuten Öffnen einer kalibrierten Übung):
  Home-Screen zeigt einen klaren „Bereit — Start drücken"-Zustand,
  **zählt nicht**.
- Tap auf „Start" → Countdown-Overlay (3-2-1, konfigurierbare Dauer) +
  Vibration (neue Methode in `feedback_service.dart`, gleiches Package wie
  die bestehenden `Vibration.vibrate(...)`-Aufrufe) → am Ende des Countdowns
  wird `startCounting()` aufgerufen (bestehende Methode, bisher nur vom
  Auto-Arm-Pfad genutzt).
- **Nach „Satz beenden":** kein Rücksprung zur Übungsübersicht nötig —
  direkt auf demselben Screen wieder ein „Start"-Button für den nächsten
  Satz, wieder mit Countdown (Punkt 2 der Entscheidungen).
- **Abbruch während des Countdowns:** Tap irgendwo/„Abbrechen" beendet den
  Countdown, zurück in den „Bereit"-Zustand, kein Zählen.
- **BLE-Verbindung bricht während des Countdowns ab:** Countdown wird
  automatisch abgebrochen, zurück in „Bereit" (verhindert Vibrieren +
  „Start" auf einem Gerät, das gar nicht mehr verbunden ist).

## 6. Was entfernt wird

- `EngineNotifier._autoArmAfterCalib` + der zugehörige Settings-Toggle
  (`autoArmAfterCalib`) entfallen komplett — der neue Start-Button ersetzt
  das Konzept, ein zusätzlicher „Auto-Start"-Schalter daneben wäre nur
  verwirrend (zwei Wege, wie ein Satz beginnt, wo genau einer reicht).
  `reloadCalibration()`/`_reloadCalibrationAndMaybeArm()` wird entsprechend
  vereinfacht (lädt nur noch die Kalibrierung, startet nichts mehr
  automatisch).

## 7. Bewusst NICHT Teil dieses Umbaus

- **Übung umbenennen oder löschen.** Nur Anlegen ist gefordert; Umbenennen/
  Löschen wäre ein natürlicher, kleiner Folgeschritt, aber jetzt nicht
  gebraucht — nicht mitbauen, nur nicht durch das Datenmodell verbauen
  (ist es nicht: `displayName` ist ein normales Textfeld, später änderbar).
- **Übungs-Icons/-Kategorien/-Typen.** Reine Namensliste reicht fürs Erste.
- **Unterschiedliche Kalibrierungs-Varianten je Übungstyp.** Der bestehende
  Guided-Calibration-2.0-Assistent lernt die Bewegungsachse generisch aus
  den Kalibrierungs-Wiederholungen — er ist nicht hart auf Bizeps-Curl-
  Geometrie zugeschnitten. Trotzdem: **bisher nur an einer einzigen Übung
  in der Praxis geprüft.** Ob er bei einer strukturell anderen Bewegung
  (z.B. Latzug: Zugbewegung statt Curl, andere Handgelenksrotation während
  der Wiederholung) genauso zuverlässig eine brauchbare Achse findet, ist
  offen — sollte bei der ersten echten Nicht-Curl-Kalibrierung bewusst
  beobachtet werden, nicht als selbstverständlich vorausgesetzt.

  > **Nachtrag 2026-07-28**: Diese Prämisse gilt ab jetzt nicht mehr —
  > siehe [`EXERCISE_BIOMECHANICAL_PRIORS_2026-07-28.md`](./EXERCISE_BIOMECHANICAL_PRIORS_2026-07-28.md).
  > Der Assistent selbst bleibt generisch (siehe Absatz oben, weiterhin
  > richtig), aber 5 Übungen bekommen zusätzlich ein recherchiertes
  > biomechanisches Profil zur Plausibilisierung des Kalibrierungsergebnisses
  > und für übungsspezifische Anweisungstexte. Der Satz „nicht als
  > selbstverständlich vorausgesetzt" bleibt trotzdem richtig — die
  > Profile ersetzen die empirische Kalibrierung nicht, sie prüfen sie nur.

## 8. Wiederverwendete Bausteine (nichts davon wird neu gebaut)

`ExerciseProfile`, `CalibrationController`, `CalibrationStore`,
`CalibrationWizardScreen` (nur neu parametrisiert), `WorkoutEngine`-
Konstruktor, `CsvSessionRecorder`, `ExportService`, `FeedbackService`
(`Vibration.vibrate(...)`), `startCounting()`.

## 9. Testplan

- Neue Drift-Tabelle: Migrationstest (leere DB → kein Auto-Seed; DB mit
  bestehenden Bizeps-Curl-Daten → genau ein Eintrag „Bizeps Curl" wird
  angelegt, mit `id = 'bicep_curl'`).
- `ExerciseOverviewScreen`: Widget-Test für Liste + Anlegen-Dialog.
- Countdown-Logik: eigenständig testbar (reiner Timer-Zustand, kein
  Hardware-Zugriff nötig) — Zustandsübergänge bereit → Countdown →
  zählend, plus Abbruch- und BLE-Trennungs-Fall.
- `EngineNotifier`: Test, dass `reloadCalibration()` nach Entfernen von
  Auto-Arm **nicht** mehr `startCounting()` aufruft.
- Bestehende Tests, die `autoArmAfterCalib`/Auto-Arm-Verhalten prüfen,
  müssen angepasst oder entfernt werden (sonst rot nach diesem Umbau —
  bewusst vorher einplanen, nicht als Überraschung nach dem `flutter test`-
  Lauf entdecken).

## 10. Reihenfolge der Umsetzung (Phasen, damit jede Phase für sich testbar ist)

1. **Datenmodell:** `Exercises`-Tabelle + Migration/Seeding. Für sich allein
   testbar, keine UI-Änderung nötig.
2. **Engine pro Übung:** Family-Provider, `main.dart` entschlackt. Noch mit
   der alten `HomeScreen` als einzigem Ziel, nur jetzt dynamisch erzeugt.
3. **Übungsübersicht + Anlegen-Dialog.** Neue Startseite, Navigation zur
   (noch unveränderten) Kalibrierung/HomeScreen.
4. **Start-Countdown-Flow + Entfernen von Auto-Arm.** Der eigentliche
   Verhaltenswechsel — bewusst als letzter Schritt, wenn 1-3 schon stabil
   sind.

## 11. Meine eigenen Verbesserungsvorschläge

Du hast danach gefragt — hier ist, was ich zusätzlich einbauen würde:

1. **Sofortiger Doppel-Tap-Schutz auf „Start"**: verhindert, dass ein
   hektischer Doppel-Tap zwei Countdowns gleichzeitig auslöst. Trivial, aber
   leicht zu übersehen.
2. **Countdown überspringbar** (z.B. Tap auf den Countdown selbst beendet
   ihn sofort): kleine, optionale Komfort-Ergänzung für Leute, die schon in
   Position sind. Nicht notwendig, aber günstig mitzunehmen, solange der
   Countdown ohnehin neu gebaut wird.
3. **„Bereit"-Zustand pro Übung merken, nicht nur pro Engine-Instanz:**
   wenn man aus der App raus- und wieder reingeht, sollte man nicht erneut
   durch die Übungsübersicht müssen, wenn man mitten in einer Übung war —
   die zuletzt aktive Übung sollte sich die App merken (kleine
   SharedPreferences/Settings-Notiz, kein großer Aufwand).
4. Der Cross-Reference-Hinweis oben (Punkt „Ersetzt/überholt") — die alte
   „Curl-only"-Leitplanke in `KONZEPT_GUIDED_CALIBRATION_2_0.md` sollte bei
   Umsetzung tatsächlich mit einem Verweis auf diesen Umbauplan versehen
   werden, sonst liest eine künftige Session (KI oder du in drei Monaten)
   dort weiterhin „bleib bei einer Übung" und ist verwirrt.

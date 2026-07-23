# Architecture Decision Records (ADR)

**Zweck:** Für jede Grundsatzentscheidung Kontext, Entscheidung und Konsequenz festhalten — damit die ausführende KI eine Entscheidung nicht für einen Fehler hält und eigenmächtig "korrigiert". Neue Entscheidungen werden als neuer Eintrag angehängt, bestehende werden nicht gelöscht, nur als "Ersetzt durch ADR-XXX" markiert.

---

### ADR-001: BLE-Byte-Protokoll — 52 Byte statt 30 Byte
- **Kontext:** `bauplan_projektgym.md` spezifizierte ein 30-Byte-Format (5 Samples, nur Beschleunigung), `kompletter_bauplan.md` ein 52-Byte-Format (4 Samples, Beschleunigung + Gyroskop + Timestamp).
- **Entscheidung:** 52-Byte-Format ist verbindlich (siehe `protocol.yaml`).
- **Konsequenz:** Gyroskop-Daten stehen für Segmentierung/Erkennung zur Verfügung, auch wenn sie für den reinen Zählalgorithmus laut RecoFit-Forschung nicht zwingend nötig sind. BLE-MTU muss auf ≥ 55 Byte verhandelt werden.

### ADR-002: BLE-Package — flutter_blue_plus statt flutter_reactive_ble
- **Kontext:** Beide Ursprungsdokumente nannten unterschiedliche Pakete.
- **Entscheidung:** `flutter_blue_plus`, begründet durch stärkere Community-Adoption und aktivere Wartung laut aktuellem Vergleich (2026).
- **Konsequenz:** `flutter_reactive_ble` wird nicht parallel eingebunden. Sollte `flutter_blue_plus` in der konkret eingesetzten Flutter-Version Probleme zeigen (siehe `00_ENTSCHEIDUNGEN_ERFORDERLICH.md`, Abschnitt C), ist das ein Eskalationsfall, kein Anlass für die KI, eigenständig zurück auf `flutter_reactive_ble` zu wechseln.

### ADR-003: Kalibrierung entfällt als separater Schritt
- **Kontext:** Spannung zwischen "Magic Moment" (sofortige erste Zahl) und der technischen Notwendigkeit, Schwellenwerte zu kalibrieren.
- **Entscheidung:** Der erste echte Satz dient gleichzeitig als Kalibrierung (siehe `WorkoutState.calibrating`).
- **Konsequenz:** Kein UI-Schritt "Mach 3 Kalibrierungs-Reps" existiert. Die ersten 2–3 Wiederholungen werden bereits angezeigt.

### ADR-004: Zählalgorithmus — adaptiver, relativer Schwellenwert statt fixer absoluter Wert
- **Kontext:** Vergleichbare Referenzprojekte (u. a. drei unabhängige Implementierungen desselben Tutorial-Datensatzes) nutzen einen fixen, pro Übung von Hand justierten Cutoff. Das RecoFit-Paper zeigt, dass ein relativer, an der Perzentil-Verteilung der eigenen Satz-Peaks orientierter Schwellenwert robuster ist als ein absoluter.
- **Entscheidung:** Envelope-Following mit relativer Perzentil-Filterung (siehe Architekturdokument Abschnitt 5.1.2).
- **Konsequenz:** Höherer Implementierungsaufwand als ein simpler Fixwert, aber begründet durch Vergleichsdaten aus externen Quellen.

### ADR-005: Fehler-State-Messaging — kein "Die KI lernt dazu" in V1
- **Kontext:** V1 enthält keine ML-Komponente, die live nachlernt.
- **Entscheidung:** Nutzer-Text bei Korrektur lautet "Danke, das hilft uns die Erkennung zu verbessern" — nicht personenbezogen als sofortiges KI-Lernversprechen formuliert.
- **Konsequenz:** Die stärkere Formulierung wird erst nach echtem Modell-Update (Phase 5) freigeschaltet.

### ADR-006: Datenbank — Drift statt Isar (finale Entscheidung)
- **Kontext:** Isar-Kernentwicklung gilt 2026 als weitgehend eingestellt (Community-Fork hält das Projekt am Leben). Diese ADR war ursprünglich als "Isar mit Abstraktionsschicht, Drift als Alternative" formuliert, mit ausdrücklich offener finaler Entscheidung.
- **Entscheidung (jetzt final):** **Drift**, nicht Isar. Die Wahl wurde an Claude delegiert (siehe `00_ENTSCHEIDUNGEN_ERFORDERLICH.md`, Abschnitt C). Begründung: Da noch keine einzige Zeile Repository-Code existiert (Entscheidung fällt vor Phase 1), ist jetzt der günstigste mögliche Zeitpunkt für den Wechsel — der Umstieg kostet keine Migration, weil es nichts zu migrieren gibt. Drift ist aktiv gepflegt, baut auf dem quelloffenen, weit verbreiteten sqlite3-Unterbau auf und ist damit für ein Projekt ohne festen Zeit-/Team-Rahmen die risikoärmere Wahl als eine Technologie mit ungewissem Wartungshorizont.
- **Konsequenz:** `IWorkoutRepository`-Interface bleibt wie geplant; konkrete Implementierungsklasse heißt `DriftWorkoutRepository` statt `IsarWorkoutRepository`. Alle anderen Dokumente, die noch "Isar" als aktive Wahl nennen, sind entsprechend aktualisiert (siehe `06_SETUP_ANLEITUNG.md`, `08_DATENMODELL_REFERENZ.md`, Hauptarchitekturdokument).
- **Ergänzender Hinweis:** Eine unabhängig befragte KI kam laut Adi zur selben Empfehlung (Isar→Drift wegen eingestellter Entwicklung) — ein gutes Konvergenz-Signal, dass diese Entscheidung nicht auf einer einzelnen, möglicherweise verzerrten Quelle beruht.

### ADR-007: Android-BLE-Berechtigungen — neverForLocation, kein Standortzugriff nötig
- **Kontext:** Recherche (Android-Entwickler-Dokumentation, Stand Juni 2026) bestätigt: Apps, die per BLE nach einem bekannten, spezifischen Gerät (Servicename/UUID) suchen und daraus keine Standortinformation ableiten, können das Flag `neverForLocation` auf der `BLUETOOTH_SCAN`-Berechtigung setzen und benötigen dann **keine** `ACCESS_FINE_LOCATION`-Berechtigung auf Android 12+.
- **Entscheidung:** `neverForLocation` wird gesetzt. Keine Standortberechtigung in der App anfragen.
- **Konsequenz:** Weniger invasive Berechtigungsanfrage beim ersten Start, potenziell höhere Opt-in-Rate. Auf Geräten mit Android 11 oder niedriger wird weiterhin `ACCESS_FINE_LOCATION` benötigt (Legacy-Pfad über `maxSdkVersion="30"` im Manifest).

### ADR-008: Android 15+ — Foreground Service Type "connectedDevice" für Hintergrund-BLE
- **Kontext:** Recherche (Stand März/Juni 2026) zeigt: Ab Android 15 wird Hintergrund-BLE-Scanning/-Verbindung ohne deklarierten `foregroundServiceType="connectedDevice"` von der Systemebene zunehmend eingeschränkt bzw. stillschweigend beendet — ohne Absturz, ohne Fehlermeldung.
- **Entscheidung:** Foreground-Service mit Typ `connectedDevice` wird ab Phase 0 eingeplant, nicht erst bei einem Bugreport nachgerüstet.
- **Konsequenz:** Zusätzliche Manifest-Deklaration und Service-Implementierung, aber verhindert ein "funktioniert bei mir, aber nicht beim Nutzer mit gesperrtem Bildschirm"-Szenario. Explizit in `02_DEFINITION_OF_DONE.md`, Kriterium 4.4 verankert.

### ADR-009: Supabase-Region — eu-central-1 (Frankfurt), mit Sovereignitäts-Vorbehalt
- **Kontext:** Recherche bestätigt eu-central-1 (Frankfurt) als verfügbare Supabase-Region. Gleichzeitig bleibt Supabase ein US-Unternehmen (Delaware), wodurch die Frage der Datenresidenz (wo liegen die Daten physisch) von der Frage der Datensouveränität (welchem Recht unterliegt der Anbieter, z. B. US CLOUD Act) zu unterscheiden ist.
- **Entscheidung:** Falls Cloud-Sync umgesetzt wird (Phase 5, selbst optional — siehe `00_ENTSCHEIDUNGEN_ERFORDERLICH.md`), Region eu-central-1 verwenden. Die Sovereignitätsfrage wird nicht durch diese ADR gelöst, sondern als bekannte Einschränkung dokumentiert.
- **Konsequenz:** Für ein kommerzielles Vorhaben mit hohen Compliance-Anforderungen wäre eine gesonderte Prüfung nötig (siehe `00_ENTSCHEIDUNGEN_ERFORDERLICH.md`, Abschnitt A: kommerziell vs. persönlich).

### ADR-010: Einwilligung für Rohdaten — vorsorglich wie Gesundheitsdaten behandeln
- **Kontext:** Der EuGH hat 2022 (Rs. C-184/20) eine weite Auslegung von Art. 9 DSGVO bestätigt: auch Daten, aus denen sich Gesundheitsinformationen nur indirekt ableiten lassen, können darunterfallen. Bewegungs-/IMU-Rohdaten aus einem Trainings-Tracker lassen über die Zeit Rückschlüsse auf Fitnesslevel und ggf. gesundheitliche Zustände zu.
- **Entscheidung:** Bis zur rechtlichen Prüfung (siehe `00_ENTSCHEIDUNGEN_ERFORDERLICH.md`) wird vorsorglich die strengere Einwilligungslogik nach Art. 9 Abs. 2 lit. a DSGVO angenommen (ausdrückliche, gesonderte Einwilligung), nicht die allgemeine Rechtsgrundlage nach Art. 6.
- **Konsequenz:** Die Einwilligungs-UI muss eine separate, explizite Bestätigung vorsehen, nicht in die allgemeinen AGB eingebettet sein. Diese ADR ersetzt keine anwaltliche Prüfung.

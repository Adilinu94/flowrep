/// ExerciseRegistry: Zentrale Verwaltung von Übungsprofilen.
///
/// Verwaltet [ExerciseProfile]-Objekte nach exerciseId und bietet
/// Standard-Profile für bekannte Übungen (V1: bicep_curl).
///
/// Verwendung:
/// ```dart
/// final registry = ExerciseRegistry();
///
/// // Standard-Profil abrufen
/// final profile = registry.getProfile('bicep_curl');
///
/// // Kalibriertes Profil speichern
/// registry.setProfile(calibratedProfile);
///
/// // Alle verfügbaren Übungen
/// final exercises = registry.availableExercises;
/// ```
///
/// Die Registry ist bewusst einfach gehalten (In-Memory, kein Persistence) —
/// die eigentliche Persistenz erfolgt über [CalibrationStore] (Secure Storage).
library;

import '../models/exercise_profile.dart';

/// Metadaten einer Übung (für UI-Anzeige).
///
/// Biomechanische Felder (ab EXERCISE_BIOMECHANICAL_PRIORS_2026-07-28.md):
/// recherchierte Startwerte für Plausibilisierung, KEINE validierten Messwerte.
/// null, wo die Recherche keine belastbare Gradzahl/Zeitangabe ergeben hat —
/// bewusst nicht mit einer erfundenen Zahl aufgefüllt.
class ExerciseMetadata {
  /// Eindeutige ID (z.B. 'bicep_curl').
  final String id;

  /// Anzeigename (z.B. 'Bizeps-Curl').
  final String displayName;

  /// Muskelgruppe (z.B. 'Arme').
  final String muscleGroup;

  /// Beschreibung der Bewegung.
  final String description;

  /// true, wenn die Übung kalibriert werden muss.
  final bool requiresCalibration;

  /// Beteiligte(s) Gelenk(e), z.B. "Ellbogen (Flexion)".
  final String jointDescription;

  /// true bei mehrgelenkigen Übungen (Schulter+Ellbogen o.ä.) — steuert
  /// aktuell knownSetCount in CalibrationWizardScreen (mehr Kalibrierungs-
  /// Reps, siehe Abschnitt 4.3 Punkt 3 der Priors-Doku).
  final bool isMultiJoint;

  /// (min, max) Gelenk-ROM in Grad, falls recherchiert.
  final (double, double)? expectedRomDegrees;

  /// (min, max) Tempo pro Wiederholung in Sekunden, falls recherchiert.
  final (double, double)? expectedTempoSecPerRep;

  /// Übungsspezifischer Hinweis für die Briefing-Phase der Kalibrierung.
  final String instructionText;

  const ExerciseMetadata({
    required this.id,
    required this.displayName,
    required this.muscleGroup,
    required this.description,
    this.requiresCalibration = true,
    this.jointDescription = '',
    this.isMultiJoint = false,
    this.expectedRomDegrees,
    this.expectedTempoSecPerRep,
    this.instructionText = '',
  });
}

/// Standard-Übungen (V1: bicep_curl; 2026-07-28: 5 weitere dazu, siehe
/// docs/design/EXERCISE_BIOMECHANICAL_PRIORS_2026-07-28.md).
const Map<String, ExerciseMetadata> kExerciseCatalog = {
  'bicep_curl': ExerciseMetadata(
    id: 'bicep_curl',
    displayName: 'Bizeps-Curl',
    muscleGroup: 'Arme',
    description: 'Klassische Bizeps-Übung mit Kurzhantel oder Kabelzug.',
    jointDescription: 'Ellbogen (Flexion)',
    isMultiJoint: false,
    // GVSU-Biomechanik-Thesis: 156-157° Standard-Curl; Exosuit-Studie:
    // 107-115° gemessen.
    expectedRomDegrees: (110.0, 160.0),
    expectedTempoSecPerRep: (1.2, 1.6),
    instructionText: 'Sensor am Handgelenk. Ellbogen am Körper, Unterarm '
        'rauf und runter — der Ellbogen bleibt der feste Punkt.',
  ),
  'hs_lat_pulldown': ExerciseMetadata(
    id: 'hs_lat_pulldown',
    displayName: 'Hammer Strength Front Lat Pulldown',
    muscleGroup: 'Rücken',
    description: 'Iso-laterale Latzug-Maschine, Untergriff, konvergierende/'
        'divergierende Zugbahn.',
    jointDescription: 'Schulter + Ellbogen',
    isMultiJoint: true,
    // Keine belastbare ROM-Gradzahl recherchiert (Herstellerseite
    // beschreibt Bewegung qualitativ, keine Winkelangabe) - bewusst null.
    expectedRomDegrees: null,
    // Aus generischer Latzug-Recherche uebernommen (NASM/S&C Journal,
    // kontrolliertes Tempo), nicht Hammer-Strength-spezifisch gemessen.
    expectedTempoSecPerRep: (2.0, 4.0),
    instructionText: 'Sensor am Handgelenk. Griff im Untergriff kontrolliert '
        'zur Brust ziehen, dann kontrolliert zurück — die Maschine führt '
        'die Bahn, du musst sie nicht erzwingen.',
  ),
  'hs_incline_press': ExerciseMetadata(
    id: 'hs_incline_press',
    displayName: 'Hammer Strength Incline Press',
    muscleGroup: 'Brust',
    description: 'Iso-laterale Schrägbank-Druckmaschine, steiler als '
        'klassischer Incline Press, konvergierende/divergierende Bahn.',
    jointDescription: 'Schulter + Ellbogen',
    isMultiJoint: true,
    expectedRomDegrees: null, // keine Gradzahl recherchiert
    expectedTempoSecPerRep: null, // kein Hammer-Strength-Tempo recherchiert
    instructionText: 'Sensor am Handgelenk. Griffe nach schräg oben drücken, '
        'bis die Arme fast gestreckt sind, dann kontrolliert zurück.',
  ),
  'hs_row': ExerciseMetadata(
    id: 'hs_row',
    displayName: 'Hammer Strength Row',
    muscleGroup: 'Rücken',
    description: 'Iso-laterale, brustgestützte Rudermaschine, horizontale '
        'Zugbahn.',
    jointDescription: 'Schulter + Ellbogen',
    isMultiJoint: true,
    expectedRomDegrees: null,
    expectedTempoSecPerRep: null,
    instructionText: 'Sensor am Handgelenk. Brust am Polster, Griffe '
        'waagerecht zum Körper ziehen, Schulterblätter zusammenziehen.',
  ),
  'scott_curl': ExerciseMetadata(
    id: 'scott_curl',
    displayName: 'Scott Curls / Preacher Curls',
    muscleGroup: 'Arme',
    description: 'Bizeps-Curl mit auf geneigtem Polster fixiertem Oberarm, '
        'deutlich reduzierter Körperschwung.',
    jointDescription: 'Ellbogen (Flexion)',
    isMultiJoint: false,
    // Gleiches Gelenk wie bicep_curl, ROM auf den Ellbogenwinkel bezogen -
    // Groessenordnung uebernommen, Ruhelage im Raum unterscheidet sich
    // (Arm liegt auf geneigtem Polster statt haengend).
    expectedRomDegrees: (110.0, 160.0),
    expectedTempoSecPerRep: (1.2, 1.6),
    instructionText: 'Sensor am Handgelenk. Oberarm bleibt fest auf dem '
        'Polster liegen, nur der Unterarm bewegt sich — kein Schwung aus '
        'dem Körper.',
  ),
  'hs_bench_press': ExerciseMetadata(
    id: 'hs_bench_press',
    displayName: 'Hammer Strength Horizontal Bench Press',
    muscleGroup: 'Brust',
    description: 'Iso-laterale Flachbank-Druckmaschine, 5°-geneigter Sitz, '
        'konvergierende/divergierende Bahn.',
    jointDescription: 'Schulter + Ellbogen',
    isMultiJoint: true,
    expectedRomDegrees: null,
    expectedTempoSecPerRep: null,
    instructionText: 'Sensor am Handgelenk. Griffe gerade nach vorne '
        'drücken, bis die Arme fast gestreckt sind, dann kontrolliert '
        'zurück.',
  ),
};

/// Zentrale Verwaltung von Übungsprofilen.
///
/// Die Registry verwaltet:
/// 1. Den Übungskatalog (statische Metadaten)
/// 2. Kalibrierte Profile (dynamisch, pro Benutzer)
///
/// Thread-Sicherheit: NICHT thread-safe (Dart ist single-threaded für
/// User-Code; bei Isolate-Nutzung muss synchronisiert werden).
class ExerciseRegistry {
  /// Kalibrierte Profile nach exerciseId.
  final Map<String, ExerciseProfile> _profiles = {};

  /// Erstellt eine Registry mit optionalen Start-Profilen.
  ///
  /// [initialProfiles]: Liste von Profilen, die beim Start geladen werden
  /// (z.B. aus CalibrationStore).
  ExerciseRegistry({List<ExerciseProfile>? initialProfiles}) {
    if (initialProfiles != null) {
      for (final profile in initialProfiles) {
        _profiles[profile.exerciseId] = profile;
      }
    }
  }

  /// Gibt das Profil für eine Übung zurück.
  ///
  /// [exerciseId]: ID der Übung (z.B. 'bicep_curl').
  /// Rückgabe: Das kalibrierte Profil, oder ein Legacy-Fallback-Profil,
  /// falls kein kalibriertes Profil existiert.
  ExerciseProfile getProfile(String exerciseId) {
    final existing = _profiles[exerciseId];
    if (existing != null) return existing;

    // Fallback: Legacy-Profil mit Standardwerten
    return ExerciseProfile.legacy(
      exerciseId: exerciseId,
      peakThreshold: 1.2,
      minThresholdAboveBaseline: 0.10,
    );
  }

  /// Gibt das Profil zurück, oder null falls nicht vorhanden.
  ExerciseProfile? getProfileOrNull(String exerciseId) => _profiles[exerciseId];

  /// Speichert ein kalibriertes Profil.
  ///
  /// [profile]: Das zu speichernde Profil.
  /// Überschreibt ein bestehendes Profil für dieselbe exerciseId.
  void setProfile(ExerciseProfile profile) {
    _profiles[profile.exerciseId] = profile;
  }

  /// Entfernt ein Profil.
  ///
  /// [exerciseId]: ID der Übung.
  /// Rückgabe: true, wenn ein Profil entfernt wurde.
  bool removeProfile(String exerciseId) {
    return _profiles.remove(exerciseId) != null;
  }

  /// true, wenn ein kalibriertes Profil für die Übung existiert.
  bool hasProfile(String exerciseId) => _profiles.containsKey(exerciseId);

  /// true, wenn die Übung im Katalog verfügbar ist.
  bool isExerciseAvailable(String exerciseId) =>
      kExerciseCatalog.containsKey(exerciseId);

  /// Alle verfügbaren Übungen (aus dem Katalog).
  List<ExerciseMetadata> get availableExercises =>
      kExerciseCatalog.values.toList();

  /// Alle kalibrierten Profile.
  List<ExerciseProfile> get calibratedProfiles => _profiles.values.toList();

  /// IDs aller kalibrierten Übungen.
  Set<String> get calibratedExerciseIds => _profiles.keys.toSet();

  /// Metadaten einer Übung abrufen.
  ///
  /// [exerciseId]: ID der Übung.
  /// Rückgabe: Metadaten oder null, falls Übung unbekannt.
  ExerciseMetadata? getMetadata(String exerciseId) =>
      kExerciseCatalog[exerciseId];

  /// Bayesianisches Blending: mischt ein neues Profil mit dem bestehenden.
  ///
  /// [newProfile]: Das neue (frisch kalibrierte) Profil.
  /// [weight]: Gewicht des neuen Profils (0.0-1.0).
  ///
  /// Wenn kein bestehendes Profil existiert, wird das neue direkt gespeichert.
  void blendProfile(ExerciseProfile newProfile, double weight) {
    final existing = _profiles[newProfile.exerciseId];
    if (existing == null) {
      _profiles[newProfile.exerciseId] = newProfile;
      return;
    }
    _profiles[newProfile.exerciseId] = existing.blendWith(newProfile, weight);
  }

  /// Setzt die Registry zurück (entfernt alle Profile).
  void clear() => _profiles.clear();

  /// Anzahl der kalibrierten Profile.
  int get profileCount => _profiles.length;
}

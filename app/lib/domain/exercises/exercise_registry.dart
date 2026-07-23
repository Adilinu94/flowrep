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

  const ExerciseMetadata({
    required this.id,
    required this.displayName,
    required this.muscleGroup,
    required this.description,
    this.requiresCalibration = true,
  });
}

/// Standard-Übungen (V1).
const Map<String, ExerciseMetadata> kExerciseCatalog = {
  'bicep_curl': ExerciseMetadata(
    id: 'bicep_curl',
    displayName: 'Bizeps-Curl',
    muscleGroup: 'Arme',
    description: 'Klassische Bizeps-Übung mit Kurzhantel oder Kabelzug.',
  ),
  // V2: weitere Übungen hier hinzufügen
  // 'shoulder_press': ExerciseMetadata(...),
  // 'lateral_raise': ExerciseMetadata(...),
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

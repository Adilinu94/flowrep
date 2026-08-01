import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/exercises/exercise_registry.dart';
import 'package:flowrep/domain/models/exercise_profile.dart';

void main() {
  group('ExerciseRegistry', () {
    late ExerciseRegistry registry;

    setUp(() {
      registry = ExerciseRegistry();
    });

    test('getProfile gibt Legacy-Fallback für unbekannte Übung', () {
      final profile = registry.getProfile('unknown_exercise');
      expect(profile.exerciseId, 'unknown_exercise');
      expect(profile.migratedFrom, 1); // Legacy
      expect(profile.theta, 1.2);
    });

    test('getProfileOrNull gibt null für nicht vorhandenes Profil', () {
      expect(registry.getProfileOrNull('bicep_curl'), isNull);
    });

    test('setProfile und getProfile round-trip', () {
      final profile = ExerciseProfile(
        exerciseId: 'bicep_curl',
        rotationAxis: const [0.1, 0.9, 0.2],
        chosenSignal: ChosenSignal.gP,
        theta: 85.0,
        minRepIntervalSeconds: 0.8,
        medianTSeconds: 1.6,
        madTSeconds: 0.2,
        gyroBias: const [0.5, -0.3, 0.1],
        qualityScore: 0.85,
        calibratedAt: DateTime(2026, 7, 22),
      );

      registry.setProfile(profile);

      final retrieved = registry.getProfile('bicep_curl');
      expect(retrieved.exerciseId, 'bicep_curl');
      expect(retrieved.theta, 85.0);
      expect(retrieved.chosenSignal, ChosenSignal.gP);
      expect(retrieved.qualityScore, 0.85);
    });

    test('hasProfile gibt true für vorhandenes Profil', () {
      expect(registry.hasProfile('bicep_curl'), isFalse);

      registry.setProfile(ExerciseProfile.legacy(
        exerciseId: 'bicep_curl',
        peakThreshold: 1.2,
        minThresholdAboveBaseline: 0.1,
      ));

      expect(registry.hasProfile('bicep_curl'), isTrue);
    });

    test('removeProfile entfernt Profil', () {
      registry.setProfile(ExerciseProfile.legacy(
        exerciseId: 'bicep_curl',
        peakThreshold: 1.2,
        minThresholdAboveBaseline: 0.1,
      ));

      expect(registry.removeProfile('bicep_curl'), isTrue);
      expect(registry.hasProfile('bicep_curl'), isFalse);
      expect(registry.removeProfile('bicep_curl'), isFalse);
    });

    test('availableExercises enthält bicep_curl', () {
      final exercises = registry.availableExercises;
      expect(exercises.length, greaterThanOrEqualTo(1));
      expect(exercises.any((e) => e.id == 'bicep_curl'), isTrue);
    });

    test('isExerciseAvailable prüft Katalog', () {
      expect(registry.isExerciseAvailable('bicep_curl'), isTrue);
      expect(registry.isExerciseAvailable('unknown'), isFalse);
    });

    test('getMetadata gibt Metadaten zurück', () {
      final metadata = registry.getMetadata('bicep_curl');
      expect(metadata, isNotNull);
      expect(metadata!.displayName, 'Bizeps-Curl');
      expect(metadata.muscleGroup, 'Arme');
    });

    test('blendProfile mischt Profile', () {
      final old = ExerciseProfile(
        exerciseId: 'bicep_curl',
        rotationAxis: const [1.0, 0.0, 0.0],
        chosenSignal: ChosenSignal.combined,
        theta: 50.0,
        minRepIntervalSeconds: 0.8,
        medianTSeconds: 1.6,
        madTSeconds: 0.0,
        gyroBias: const [0.0, 0.0, 0.0],
        qualityScore: 0.5,
        calibratedAt: DateTime(2026, 7, 1),
      );

      final neu = ExerciseProfile(
        exerciseId: 'bicep_curl',
        rotationAxis: const [0.0, 1.0, 0.0],
        chosenSignal: ChosenSignal.gP,
        theta: 100.0,
        minRepIntervalSeconds: 1.0,
        medianTSeconds: 2.0,
        madTSeconds: 0.2,
        gyroBias: const [1.0, 1.0, 1.0],
        qualityScore: 0.9,
        calibratedAt: DateTime(2026, 7, 22),
      );

      registry.setProfile(old);
      registry.blendProfile(neu, 0.5); // 50/50 Mix

      final blended = registry.getProfile('bicep_curl');
      expect(blended.theta, 75.0); // (50+100)/2
      expect(blended.chosenSignal, ChosenSignal.gP); // w>=0.5 → neu
    });

    test('blendProfile speichert direkt wenn kein bestehendes Profil', () {
      final neu = ExerciseProfile(
        exerciseId: 'bicep_curl',
        rotationAxis: const [0.0, 1.0, 0.0],
        chosenSignal: ChosenSignal.gP,
        theta: 100.0,
        minRepIntervalSeconds: 1.0,
        medianTSeconds: 2.0,
        madTSeconds: 0.2,
        gyroBias: const [1.0, 1.0, 1.0],
        qualityScore: 0.9,
        calibratedAt: DateTime(2026, 7, 22),
      );

      registry.blendProfile(neu, 0.5);

      expect(registry.hasProfile('bicep_curl'), isTrue);
      expect(registry.getProfile('bicep_curl').theta, 100.0);
    });

    test('clear entfernt alle Profile', () {
      registry.setProfile(ExerciseProfile.legacy(
        exerciseId: 'bicep_curl',
        peakThreshold: 1.2,
        minThresholdAboveBaseline: 0.1,
      ));
      registry.setProfile(ExerciseProfile.legacy(
        exerciseId: 'shoulder_press',
        peakThreshold: 1.5,
        minThresholdAboveBaseline: 0.15,
      ));

      expect(registry.profileCount, 2);
      registry.clear();
      expect(registry.profileCount, 0);
    });

    test('initialProfiles werden geladen', () {
      final profiles = [
        ExerciseProfile.legacy(
          exerciseId: 'bicep_curl',
          peakThreshold: 1.2,
          minThresholdAboveBaseline: 0.1,
        ),
        ExerciseProfile.legacy(
          exerciseId: 'shoulder_press',
          peakThreshold: 1.5,
          minThresholdAboveBaseline: 0.15,
        ),
      ];

      final registryWithProfiles = ExerciseRegistry(initialProfiles: profiles);
      expect(registryWithProfiles.profileCount, 2);
      expect(registryWithProfiles.hasProfile('bicep_curl'), isTrue);
      expect(registryWithProfiles.hasProfile('shoulder_press'), isTrue);
    });

    test('calibratedExerciseIds gibt IDs zurück', () {
      registry.setProfile(ExerciseProfile.legacy(
        exerciseId: 'bicep_curl',
        peakThreshold: 1.2,
        minThresholdAboveBaseline: 0.1,
      ));

      expect(registry.calibratedExerciseIds, contains('bicep_curl'));
    });
  });

  group('ExerciseMetadata', () {
    test('bicep_curl Metadaten sind korrekt', () {
      final metadata = kExerciseCatalog['bicep_curl'];
      expect(metadata, isNotNull);
      expect(metadata!.id, 'bicep_curl');
      expect(metadata.displayName, 'Bizeps-Curl');
      expect(metadata.muscleGroup, 'Arme');
      expect(metadata.requiresCalibration, isTrue);
    });

    test('bicep_curl hat biomechanische Felder befüllt (eingelenkig)', () {
      final metadata = kExerciseCatalog['bicep_curl']!;
      expect(metadata.jointDescription, 'Ellbogen (Flexion)');
      expect(metadata.isMultiJoint, isFalse);
      expect(metadata.expectedRomDegrees, isNotNull);
      expect(metadata.expectedRomDegrees!.$1, lessThan(metadata.expectedRomDegrees!.$2));
      expect(metadata.instructionText, isNotEmpty);
    });

    test('scott_curl hat dieselbe ROM-Größenordnung wie bicep_curl '
        '(gleiches Gelenk), aber eigenen Instruktionstext', () {
      final curl = kExerciseCatalog['bicep_curl']!;
      final scott = kExerciseCatalog['scott_curl']!;
      expect(scott.isMultiJoint, isFalse);
      expect(scott.expectedRomDegrees, curl.expectedRomDegrees);
      expect(scott.instructionText, isNot(equals(curl.instructionText)));
      expect(scott.instructionText, contains('Oberarm'));
    });

    test('alle 4 Hammer-Strength-Übungen sind mehrgelenkig und im Katalog',
        () {
      for (final id in [
        'hs_lat_pulldown',
        'hs_incline_press',
        'hs_row',
        'hs_bench_press',
      ]) {
        final metadata = kExerciseCatalog[id];
        expect(metadata, isNotNull, reason: '$id fehlt im Katalog');
        expect(metadata!.isMultiJoint, isTrue,
            reason: '$id sollte mehrgelenkig sein');
        expect(metadata.jointDescription, isNotEmpty);
        expect(metadata.instructionText, isNotEmpty);
      }
    });

    test('Hammer-Strength-Übungen ohne recherchierte ROM-Gradzahl haben '
        'bewusst null statt einer erfundenen Zahl', () {
      // Nur hs_lat_pulldown hat ein recherchiertes Tempo (aus generischer
      // Latzug-Recherche übernommen); die ROM-Gradzahl fehlt bei allen 4.
      for (final id in [
        'hs_lat_pulldown',
        'hs_incline_press',
        'hs_row',
        'hs_bench_press',
      ]) {
        expect(kExerciseCatalog[id]!.expectedRomDegrees, isNull,
            reason: '$id: keine ROM-Gradzahl recherchiert, sollte null sein');
      }
    });

    test('kExerciseCatalog enthält genau 6 Übungen (1 bestehend + 5 neu)',
        () {
      expect(kExerciseCatalog.length, 6);
      expect(
        kExerciseCatalog.keys,
        containsAll([
          'bicep_curl',
          'hs_lat_pulldown',
          'hs_incline_press',
          'hs_row',
          'scott_curl',
          'hs_bench_press',
        ]),
      );
    });

    test('jede Übung im Katalog hat eine eindeutige, nicht-leere '
        'instructionText', () {
      final texts = kExerciseCatalog.values.map((m) => m.instructionText);
      expect(texts.every((t) => t.isNotEmpty), isTrue);
      expect(texts.toSet().length, kExerciseCatalog.length,
          reason: 'Instruktionstexte sollten sich unterscheiden');
    });
  });
}

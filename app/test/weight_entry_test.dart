import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';
import 'package:flowrep/data/services/export_service.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:flowrep/presentation/providers/engine_provider.dart';

void main() {
  group('ExerciseSet.copyWith Gewicht', () {
    test('weightKg wird gesetzt, andere Felder bleiben', () {
      final set = ExerciseSet(
        id: 's1',
        exerciseId: 'hs_row',
        countedReps: 10,
        endedAt: DateTime.now(),
        reps: [],
      );
      final withWeight = set.copyWith(weightKg: 20);
      expect(withWeight.weightKg, 20);
      expect(withWeight.countedReps, 10);
      expect(withWeight.exerciseId, 'hs_row');
    });

    test('weightKg ist null ohne Angabe (z. B. Bodyweight)', () {
      final set = ExerciseSet(
        id: 's2',
        exerciseId: 'bicep_curl',
        countedReps: 8,
        endedAt: DateTime.now(),
        reps: [],
      );
      expect(set.weightKg, isNull);
    });
  });

  group('EngineNotifier.setWeightForCurrentSet', () {
    late EngineNotifier notifier;

    setUp(() {
      notifier = EngineNotifier.create(
        sensorProvider: MockSensorProvider(),
        engine: WorkoutEngine(
          exerciseId: 'bicep_curl',
          useSignedProjectionCounting: true,
        ),
      );
    });

    tearDown(() {
      notifier.dispose();
    });

    test('setzt pendingWeightKg im State', () {
      notifier.setWeightForCurrentSet(20);
      expect(notifier.state.pendingWeightKg, 20);
    });

    test('null löscht pendingWeightKg wieder (leeres Feld)', () {
      notifier.setWeightForCurrentSet(20);
      notifier.setWeightForCurrentSet(null);
      expect(notifier.state.pendingWeightKg, isNull);
    });

    test('bleibt nach dem Setzen unverändert stehen (kein Auto-Reset)', () {
      notifier.setWeightForCurrentSet(15);
      notifier.setWeightForCurrentSet(15);
      expect(notifier.state.pendingWeightKg, 15);
    });

    // Hinweis: dass _onSetCompleted() pendingWeightKg tatsächlich auf den
    // fertigen Satz überträgt, ist NICHT durch einen automatisierten Test
    // abgedeckt (nur durch Code-Lektüre verifiziert) - der reguläre
    // Satzabschluss läuft über ein Event aus der echten WorkoutEngine, das
    // sich ohne Sensor-Simulation nicht isoliert triggern lässt. Der
    // bestehende debugAddCompletedSet()-Testhelfer (siehe correction_test.dart)
    // umgeht _onSetCompleted komplett und würde diese Stelle nicht abdecken.
  });

  group('ExportService Gewicht in CSV/JSON', () {
    test('CSV-Header und Zeile enthalten weightKg', () {
      final session = WorkoutSession(
        id: 'sess-1',
        startedAt: DateTime(2026, 8, 2, 10),
        endedAt: DateTime(2026, 8, 2, 10, 5),
        sets: [
          ExerciseSet(
            id: 'set-1',
            exerciseId: 'hs_row',
            countedReps: 10,
            endedAt: DateTime(2026, 8, 2, 10, 3),
            reps: const [],
            weightKg: 22.5,
          ),
        ],
      );
      final csv = ExportService.sessionsToCsv([session]);
      final lines = csv.trim().split('\n');
      expect(lines.first.split(',').contains('weightKg'), isTrue);
      expect(lines[1], contains('22.5'));
    });

    test('CSV-Zeile ohne Gewicht lässt das Feld leer', () {
      final session = WorkoutSession(
        id: 'sess-2',
        startedAt: DateTime(2026, 8, 2, 10),
        endedAt: DateTime(2026, 8, 2, 10, 5),
        sets: [
          ExerciseSet(
            id: 'set-2',
            exerciseId: 'bicep_curl',
            countedReps: 5,
            endedAt: DateTime(2026, 8, 2, 10, 3),
            reps: const [],
          ),
        ],
      );
      final csv = ExportService.sessionsToCsv([session]);
      final header = csv.trim().split('\n').first.split(',');
      final weightIdx = header.indexOf('weightKg');
      final row = csv.trim().split('\n')[1].split(',');
      expect(row[weightIdx], '');
    });
  });
}

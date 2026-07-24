import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/metrics/placement_energy_monitor.dart';
import 'package:flowrep/domain/metrics/sensor_health_monitor.dart';
import 'package:flowrep/domain/metrics/set_quality_score.dart';
import 'package:flowrep/domain/models/workout_models.dart';

void main() {
  group('SensorHealthMonitor', () {
    test('flags stuck high gyro at rest after N windows', () {
      final m = SensorHealthMonitor(
        windowSize: 10,
        windowsToFlag: 2,
        unhealthyRestGyroMean: 40,
      );
      // Two rest windows with bad gyro (~86 like COUNT_ZERO).
      for (var w = 0; w < 2; w++) {
        for (var i = 0; i < 10; i++) {
          m.push(gyroMagnitude: 86.0, accelMagnitude: 1.0);
        }
      }
      expect(m.isUnhealthy, isTrue);
      expect(m.message, isNotNull);
      expect(m.message!, contains('Sensor unruhig'));
    });

    test('healthy rest does not flag', () {
      final m = SensorHealthMonitor(windowSize: 10, windowsToFlag: 2);
      for (var w = 0; w < 3; w++) {
        for (var i = 0; i < 10; i++) {
          m.push(gyroMagnitude: 0.5, accelMagnitude: 1.0);
        }
      }
      expect(m.isUnhealthy, isFalse);
    });

    test('motion does not trigger bad flag alone', () {
      final m = SensorHealthMonitor(windowSize: 10, windowsToFlag: 1);
      for (var i = 0; i < 10; i++) {
        m.push(gyroMagnitude: 120.0, accelMagnitude: 1.4); // moving
      }
      expect(m.isUnhealthy, isFalse);
    });
  });

  group('PlacementEnergyMonitor', () {
    test('warns when moving with weak gP vs theta', () {
      final m = PlacementEnergyMonitor(
        windowSize: 10,
        windowsToWarn: 2,
        motionAccelDeltaMin: 0.12,
        weakGpFractionOfTheta: 0.25,
      );
      for (var w = 0; w < 2; w++) {
        for (var i = 0; i < 10; i++) {
          m.push(
            accelMagnitude: 1.3, // delta 0.3
            gpAbs: 5.0, // weak vs theta 80
            theta: 80.0,
          );
        }
      }
      expect(m.shouldWarn, isTrue);
    });

    test('no warn when gP strong', () {
      final m = PlacementEnergyMonitor(windowSize: 10, windowsToWarn: 2);
      for (var w = 0; w < 2; w++) {
        for (var i = 0; i < 10; i++) {
          m.push(accelMagnitude: 1.3, gpAbs: 90.0, theta: 80.0);
        }
      }
      expect(m.shouldWarn, isFalse);
    });
  });

  group('SetQualityScore', () {
    test('empty reps → Schwach/Mittel band', () {
      final q = SetQualityScore.forSet(reps: const []);
      expect(q.score01, lessThan(0.6));
      expect(q.label, isNotEmpty);
    });

    test('consistent peaks score higher; packet loss lowers', () {
      final t0 = DateTime(2026, 7, 24);
      final reps = List.generate(
        8,
        (i) => Rep(
          timestamp: t0.add(Duration(milliseconds: i * 1200)),
          peakMagnitude: 100.0 + (i.isEven ? 2 : -2),
        ),
      );
      final good = SetQualityScore.forSet(reps: reps);
      final badLink = SetQualityScore.forSet(
        reps: reps,
        packetLossWarned: true,
        sensorUnhealthy: true,
      );
      expect(good.score01, greaterThan(badLink.score01));
      expect(badLink.notes, contains('Paketverlust'));
      expect(badLink.notes, contains('Sensor-Gesundheit'));
    });
  });
}

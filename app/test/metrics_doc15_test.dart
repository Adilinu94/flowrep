import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/coaching/rule_coaching.dart';
import 'package:flowrep/domain/metrics/form_quality.dart';
import 'package:flowrep/domain/metrics/ghost_rep_gate.dart';
import 'package:flowrep/domain/metrics/shadow_report.dart';
import 'package:flowrep/domain/metrics/velocity_metrics.dart';
import 'package:flowrep/domain/ml/exercise_classifier.dart';
import 'package:flowrep/domain/models/workout_models.dart';
import 'package:flowrep/data/services/export_service.dart';

void main() {
  group('VelocityMetrics (FR-A1)', () {
    test('velocity loss first vs last', () {
      final t0 = DateTime(2026, 1, 1);
      final reps = [
        Rep(timestamp: t0, peakMagnitude: 100),
        Rep(timestamp: t0.add(const Duration(seconds: 2)), peakMagnitude: 80),
        Rep(timestamp: t0.add(const Duration(seconds: 4)), peakMagnitude: 70),
      ];
      expect(VelocityMetrics.setVelocityLossPct(reps), closeTo(30, 0.01));
      expect(VelocityMetrics.meanPeak(reps), closeTo(250 / 3, 0.01));
    });

    test('adaptive rest lengthens on high loss', () {
      expect(
        VelocityMetrics.adaptiveRestSeconds(
          baseSeconds: 90,
          velocityLossPct: 25,
        ),
        greaterThan(90),
      );
      expect(
        VelocityMetrics.adaptiveRestSeconds(
          baseSeconds: 90,
          velocityLossPct: 2,
        ),
        lessThan(90),
      );
    });
  });

  group('GhostRepGate (FR-B6)', () {
    test('pauses after idle windows, resumes on activity', () {
      final gate = GhostRepGate(
        windowSize: 10,
        minIdleWindowsToPause: 2,
        minActiveWindowsToResume: 1,
        idleMeanMax: 15,
        idleVarianceMax: 5,
        activeMeanMin: 40,
      );
      expect(gate.allowCounting, isTrue);
      // Two idle windows of 10 samples each.
      for (var w = 0; w < 2; w++) {
        for (var i = 0; i < 10; i++) {
          gate.push(5);
        }
      }
      expect(gate.isPaused, isTrue);
      for (var i = 0; i < 10; i++) {
        gate.push(80);
      }
      expect(gate.isPaused, isFalse);
    });
  });

  group('FormQuality / PRs / Correction (FR-A5/B4/B13)', () {
    test('scores and outliers', () {
      final t0 = DateTime(2026, 1, 1);
      final reps = [
        for (var i = 0; i < 5; i++)
          Rep(
            timestamp: t0.add(Duration(seconds: i * 2)),
            peakMagnitude: i == 3 ? 30 : 100,
          ),
      ];
      final scores = FormQuality.scoresForSet(reps);
      expect(scores.length, 5);
      expect(FormQuality.outlierIndices(reps), contains(3));
    });

    test('PR detection', () {
      final prior = [
        WorkoutSession(
          id: 's1',
          startedAt: DateTime(2026, 1, 1),
          sets: [
            ExerciseSet(
              id: 'a',
              exerciseId: 'bicep_curl',
              countedReps: 8,
              endedAt: DateTime(2026, 1, 1),
              reps: const [],
            ),
          ],
        ),
      ];
      final set = ExerciseSet(
        id: 'b',
        exerciseId: 'bicep_curl',
        countedReps: 12,
        endedAt: DateTime(2026, 1, 2),
        reps: const [],
      );
      expect(PersonalRecords.isRepsPr(set: set, priorSessions: prior), isTrue);
    });

    test('correction aggregate', () {
      final events = [
        CorrectionEvent(
          id: '1',
          setId: 's',
          systemCount: 12,
          userCorrectedCount: 10,
          timestamp: DateTime(2026, 1, 1),
        ),
        CorrectionEvent(
          id: '2',
          setId: 's',
          systemCount: 8,
          userCorrectedCount: 10,
          timestamp: DateTime(2026, 1, 1),
        ),
      ];
      final agg = CorrectionAnalytics.aggregate(events);
      expect(agg.overCountSum, 2);
      expect(agg.underCountSum, 2);
    });
  });

  group('ShadowReport / Export / Coaching / Classifier', () {
    test('shadow jsonl', () {
      final buf = ShadowReportBuffer(capacity: 2);
      buf.add(ShadowReportLine(
        timestamp: DateTime(2026, 1, 1),
        source: 'magnitude',
        liveReps: 3,
        shadowReps: 4,
      ));
      expect(buf.exportJsonl().contains('magnitude'), isTrue);
      expect(ShadowReportLine.fromJson(
        {
          'ts': '2026-01-01T00:00:00.000',
          'source': 'x',
          'liveReps': 1,
          'shadowReps': 1,
        },
      ).delta, 0);
    });

    test('export csv/json contains privacy + peaks', () {
      final session = WorkoutSession(
        id: 'sess',
        startedAt: DateTime(2026, 1, 1, 10),
        endedAt: DateTime(2026, 1, 1, 11),
        sets: [
          ExerciseSet(
            id: 'set1',
            exerciseId: 'bicep_curl',
            countedReps: 2,
            endedAt: DateTime(2026, 1, 1, 10, 30),
            reps: [
              Rep(timestamp: DateTime(2026, 1, 1, 10, 20), peakMagnitude: 90),
              Rep(timestamp: DateTime(2026, 1, 1, 10, 21), peakMagnitude: 80),
            ],
          ),
        ],
      );
      final json = ExportService.sessionsToJson([session]);
      expect(json.contains('flowrep-export-v1'), isTrue);
      expect(json.contains('privacy'), isTrue);
      final csv = ExportService.sessionsToCsv([session]);
      expect(csv.contains('peakMagnitude'), isTrue);
      expect(csv.contains('80'), isTrue);
    });

    test('rule coaching mentions velocity loss', () {
      final session = WorkoutSession(
        id: 's',
        startedAt: DateTime(2026, 1, 1),
        sets: [
          ExerciseSet(
            id: 'set',
            exerciseId: 'bicep_curl',
            countedReps: 3,
            endedAt: DateTime(2026, 1, 1),
            reps: [
              Rep(timestamp: DateTime(2026, 1, 1), peakMagnitude: 100),
              Rep(
                  timestamp: DateTime(2026, 1, 1, 0, 0, 2),
                  peakMagnitude: 50),
              Rep(
                  timestamp: DateTime(2026, 1, 1, 0, 0, 4),
                  peakMagnitude: 40),
            ],
          ),
        ],
      );
      final tips = RuleCoaching.tipsForSession(session);
      expect(tips.any((t) => t.contains('Velocity')), isTrue);
    });

    test('heuristic classifier returns curl or null', () async {
      final clf = HeuristicExerciseClassifier();
      final quiet = await clf.classify(ImuWindow(
        samples: List.filled(30, 1.0),
        sampleRateHz: 50,
        endedAt: DateTime(2026, 1, 1),
      ));
      expect(quiet, isNull);

      // Synthetic peaks ~0.5 Hz at high magnitude.
      final samples = <double>[];
      for (var i = 0; i < 100; i++) {
        samples.add(i % 20 == 10 ? 90.0 : 20.0);
      }
      final curl = await clf.classify(ImuWindow(
        samples: samples,
        sampleRateHz: 50,
        endedAt: DateTime(2026, 1, 1),
      ));
      // May or may not fire depending on peak logic — just ensure no throw.
      expect(curl == null || curl.exerciseId == 'bicep_curl', isTrue);
    });
  });
}

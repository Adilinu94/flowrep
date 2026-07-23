import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/exercise_engine.dart';
import 'package:flowrep/domain/detection/peak_detector.dart';
import 'package:flowrep/domain/models/processed_frame.dart';

void main() {
  test('Debug: PeakDetector direkt mit Envelope-Werten', () {
    // Teste PeakDetector ISOLIERT mit typischen Envelope-Werten
    final pd = PeakDetector(sampleRateHz: 50.0);

    // Simuliere Envelope einer 1Hz-Sinus-Rep (Amplitude ~200)
    // Envelope = exponentiell geglätteter |sin|
    final envelopeValues = <double>[];
    for (int i = 0; i < 50; i++) {
      // Approximation der Envelope: |sin| geglättet
      envelopeValues.add(200.0 * math.sin(2.0 * math.pi * i / 50).abs());
    }

    // ignore: avoid_print
    print('Envelope min: ${envelopeValues.reduce(math.min)}');
    // ignore: avoid_print
    print('Envelope max: ${envelopeValues.reduce(math.max)}');
    // ignore: avoid_print
    print('Threshold: ${pd.currentThreshold}');

    // Feed 3 reps through isolated PeakDetector
    int peaks = 0;
    for (int rep = 0; rep < 3; rep++) {
      for (int i = 0; i < 50; i++) {
        final frame = ProcessedFrame(
          timestampMs: (rep * 75 + i) * 20,
          rawGp: envelopeValues[i],
          filteredGp: envelopeValues[i],
          smoothedGp: envelopeValues[i],
          envelope: envelopeValues[i],
          isSettled: true,
        );
        final peak = pd.process(frame);
        if (peak != null) {
          peaks++;
          // ignore: avoid_print
          print('Peak detected at rep ${rep + 1}, sample $i: '
              'prom=${peak.prominence.toStringAsFixed(1)}, '
              'dur=${peak.durationSamples}');
        }
      }
      // Pause (envelope = 0)
      for (int i = 0; i < 25; i++) {
        final frame = ProcessedFrame(
          timestampMs: (rep * 75 + 50 + i) * 20,
          rawGp: 0,
          filteredGp: 0,
          smoothedGp: 0,
          envelope: 0,
          isSettled: true,
        );
        pd.process(frame);
      }
    }
    // ignore: avoid_print
    print('Isolated PeakDetector: $peaks peaks from 3 reps');
    // ignore: avoid_print
    print('SPK: ${pd.spk}, NPK: ${pd.npk}');
  });

  test('Debug: Slow reps (100 samples)', () {
    final engine = ExerciseEngine(
      config: ExerciseEngineConfig(
        rotationAxis: [0.0, 1.0, 0.0],
        gyroBias: [0.0, 0.0, 0.0],
        hasValidCalibration: true,
        expectedProminence: 100.0,
        expectedDurationSamples: 100.0,
        minQualityScore: 0.3,
      ),
    );

    // Einschwingen
    for (int i = 0; i < 300; i++) {
      engine.processSample(timestampMs: i * 20, gx: 0, gy: 0, gz: 0);
    }

    // 3 langsame Reps (100 Samples = 2s)
    int repsCounted = 0;
    double maxSmoothed = 0;
    for (int rep = 0; rep < 3; rep++) {
      for (int i = 0; i < 100; i++) {
        final gy = 200.0 * math.sin(2.0 * math.pi * i / 100);
        final result = engine.processSample(
          timestampMs: (300 + rep * 150 + i) * 20,
          gx: 0, gy: gy, gz: 0,
        );
        final sg = result.frame?.smoothedGp ?? 0;
        if (sg > maxSmoothed) maxSmoothed = sg;
        // Print signal at key points
        if (i == 25 || i == 50 || i == 75) {
          // ignore: avoid_print
          print('Rep${rep + 1} i=$i: smoothedGp=${sg.toStringAsFixed(1)}');
        }
        if (result.repResult.repCounted) {
          repsCounted++;
          // ignore: avoid_print
          print('Rep${rep + 1} i=$i: COUNTED #${result.repResult.repNumber} '
              'q=${result.repResult.qualityScore?.toStringAsFixed(3)}');
        } else if (result.repResult.rejectionReason != null) {
          // ignore: avoid_print
          print('Rep${rep + 1} i=$i: REJECTED: ${result.repResult.rejectionReason}');
        }
      }
      for (int i = 0; i < 50; i++) {
        engine.processSample(
          timestampMs: (300 + rep * 150 + 100 + i) * 20,
          gx: 0, gy: 0, gz: 0,
        );
      }
    }
    // ignore: avoid_print
    print('repsCounted=$repsCounted, maxSmoothed=${maxSmoothed.toStringAsFixed(1)}');
    final pd = engine.repCounter.peakDetector;
    // ignore: avoid_print
    print('SPK=${pd.spk.toStringAsFixed(1)} NPK=${pd.npk.toStringAsFixed(1)} '
        'thresh=${pd.currentThreshold.toStringAsFixed(1)}');
  });

  test('Debug: Full pipeline trace', () {
    final engine = ExerciseEngine(
      config: ExerciseEngineConfig(
        rotationAxis: [0.0, 1.0, 0.0],
        gyroBias: [0.0, 0.0, 0.0],
        hasValidCalibration: true,
        expectedProminence: 100.0,
        expectedDurationSamples: 50.0,
        minQualityScore: 0.3,
      ),
    );

    // Einschwingen
    for (int i = 0; i < 300; i++) {
      engine.processSample(timestampMs: i * 20, gx: 0, gy: 0, gz: 0);
    }

    // 5 Reps mit voller Diagnose
    int peaksDetected = 0;
    int repsCounted = 0;
    for (int rep = 0; rep < 5; rep++) {
      for (int i = 0; i < 50; i++) {
        final gy = 250.0 * math.sin(2.0 * math.pi * i / 50);
        final result = engine.processSample(
          timestampMs: (300 + rep * 75 + i) * 20,
          gx: 0, gy: gy, gz: 0,
        );
        if (result.repResult.repCounted) {
          repsCounted++;
          // ignore: avoid_print
          print('Rep${rep + 1} i=$i: COUNTED #${result.repResult.repNumber} '
              'q=${result.repResult.qualityScore?.toStringAsFixed(3)}');
        } else if (result.repResult.rejectionReason != null) {
          // ignore: avoid_print
          print('Rep${rep + 1} i=$i: REJECTED: ${result.repResult.rejectionReason}');
        }
      }
      for (int i = 0; i < 25; i++) {
        engine.processSample(
          timestampMs: (300 + rep * 75 + 50 + i) * 20,
          gx: 0, gy: 0, gz: 0,
        );
      }
    }
    // ignore: avoid_print
    print('repsCounted=$repsCounted, engine.repCount=${engine.repCount}');
    final pd = engine.repCounter.peakDetector;
    // ignore: avoid_print
    print('SPK=${pd.spk.toStringAsFixed(1)} NPK=${pd.npk.toStringAsFixed(1)} '
        'thresh=${pd.currentThreshold.toStringAsFixed(1)}');
  });
}

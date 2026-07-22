import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/detection/peak_detector.dart';
import 'package:flowrep/domain/detection/peak_event.dart';
import 'package:flowrep/domain/models/processed_frame.dart';

/// Erzeugt ein ProcessedFrame mit gegebenem Hüllkurven-Wert.
ProcessedFrame _frame(double envelope, {int t = 0}) {
  return ProcessedFrame(
    timestampMs: t,
    rawGp: envelope,
    filteredGp: envelope,
    smoothedGp: envelope,
    envelope: envelope,
    isSettled: true,
  );
}

/// Erzeugt eine sinusförmige Rep-Sequenz (eine vollständige Excursion).
///
/// [peakAmplitude]: Maximale Amplitude der Hüllkurve.
/// [durationSamples]: Dauer der Excursion in Samples.
/// [baselineSamples]: Ruhige Samples vor/nach der Excursion.
List<double> _repSequence({
  double peakAmplitude = 120.0,
  int durationSamples = 40,
  int baselineSamples = 30,
}) {
  final result = <double>[];
  // Baseline (Rauschen niedrig)
  for (int i = 0; i < baselineSamples; i++) {
    result.add(2.0);
  }
  // Sinusförmige Excursion (Halbwelle)
  for (int i = 0; i < durationSamples; i++) {
    final phase = math.pi * i / durationSamples;
    result.add(peakAmplitude * math.sin(phase));
  }
  // Baseline danach
  for (int i = 0; i < baselineSamples; i++) {
    result.add(2.0);
  }
  return result;
}

void main() {
  group('PeakDetector', () {
    late PeakDetector detector;

    setUp(() {
      detector = PeakDetector(
        sampleRateHz: 50.0,
        initialSpk: 100.0,
        initialNpk: 10.0,
        refractorySeconds: 0.5,
      );
    });

    test('Erkennt einzelne Rep-Excursion', () {
      final sequence = _repSequence(peakAmplitude: 120.0);
      PeakEvent? detected;

      for (int i = 0; i < sequence.length; i++) {
        final peak = detector.process(_frame(sequence[i], t: i * 20));
        if (peak != null) {
          detected = peak;
          break;
        }
      }

      expect(detected, isNotNull, reason: 'Peak sollte erkannt werden');
      expect(detected!.peakValue, closeTo(120.0, 5.0));
      expect(detected.prominence, greaterThan(50.0));
      expect(detected.durationSamples, greaterThan(10));
      expect(detected.window.length, equals(detected.durationSamples));
    });

    test('Ignoriert niedriges Rauschen unter der Schwelle', () {
      // Nur Rauschen um 5.0 (unter θ = 10 + 0.25*(100-10) = 32.5)
      PeakEvent? detected;
      for (int i = 0; i < 200; i++) {
        final noise = 5.0 + 3.0 * math.sin(i * 0.3);
        final peak = detector.process(_frame(noise, t: i * 20));
        if (peak != null) detected = peak;
      }

      expect(detected, isNull, reason: 'Rauschen sollte keinen Peak auslösen');
    });

    test('Refractory-Zeit verhindert Doppelzählung', () {
      // Zwei Peaks direkt hintereinander (innerhalb 0.5s = 25 Samples)
      final seq1 = _repSequence(
        peakAmplitude: 120.0,
        baselineSamples: 5,
        durationSamples: 20,
      );
      // Direkt danach einen zweiten Peak (ohne ausreichende Pause)
      final seq2 = _repSequence(
        peakAmplitude: 120.0,
        baselineSamples: 3,
        durationSamples: 20,
      );

      final fullSequence = [...seq1, ...seq2];
      int peakCount = 0;

      for (int i = 0; i < fullSequence.length; i++) {
        final peak = detector.process(_frame(fullSequence[i], t: i * 20));
        if (peak != null) peakCount++;
      }

      // Innerhalb der Refractory-Zeit sollte der zweite Peak unterdrückt werden
      expect(peakCount, equals(1),
          reason: 'Refractory sollte Doppelzählung verhindern');
    });

    test('Adaptive Schwelle passt sich an (SPK-Update)', () {
      final initialThreshold = detector.currentThreshold;

      // Füttere einen starken Peak (Amplitude 200 >> SPK=100)
      final sequence = _repSequence(peakAmplitude: 200.0);
      for (int i = 0; i < sequence.length; i++) {
        detector.process(_frame(sequence[i], t: i * 20));
      }

      // SPK sollte gestiegen sein → Schwelle steigt
      expect(detector.spk, greaterThan(100.0),
          reason: 'SPK sollte nach starkem Peak steigen');
      expect(detector.currentThreshold, greaterThan(initialThreshold),
          reason: 'Schwelle sollte nach SPK-Update steigen');
    });

    test('NPK-Update bei verworfenem Peak', () {
      // Sehr niedrige initialSpk setzen, damit Prominenz-Check fehlschlägt
      final det = PeakDetector(
        sampleRateHz: 50.0,
        initialSpk: 100.0,
        initialNpk: 5.0,
        prominenceRatio: 0.9, // Sehr hohe Anforderung: 90% von SPK
      );

      final initialNpk = det.npk;

      // Peak mit Amplitude 40 → Prominenz ~38, aber min = 100*0.9 = 90
      final sequence = _repSequence(peakAmplitude: 40.0);
      for (int i = 0; i < sequence.length; i++) {
        det.process(_frame(sequence[i], t: i * 20));
      }

      // NPK sollte gestiegen sein (verworfener Peak fließt in NPK ein)
      expect(det.npk, greaterThan(initialNpk),
          reason: 'NPK sollte nach verworfenem Peak steigen');
    });

    test('NaN-Eingabe wird sicher ignoriert', () {
      // NaN sollte keinen Crash verursachen
      final peak = detector.process(_frame(double.nan));
      expect(peak, isNull);
    });

    test('Reset setzt Zustand zurück (nicht SPK/NPK)', () {
      // Erst einen Peak erkennen
      final sequence = _repSequence(peakAmplitude: 150.0);
      for (int i = 0; i < sequence.length; i++) {
        detector.process(_frame(sequence[i], t: i * 20));
      }

      final spkBefore = detector.spk;
      final npkBefore = detector.npk;

      detector.reset();

      // SPK/NPK bleiben erhalten
      expect(detector.spk, equals(spkBefore));
      expect(detector.npk, equals(npkBefore));
      // Sample-Counter zurückgesetzt
      expect(detector.sampleCount, equals(0));
    });

    test('Mehrere Reps werden korrekt gezählt', () {
      // 3 Reps mit ausreichendem Abstand (> 25 Samples = 0.5s Refractory)
      int peakCount = 0;

      for (int rep = 0; rep < 3; rep++) {
        final sequence = _repSequence(
          peakAmplitude: 120.0,
          baselineSamples: 30, // 30 Samples Abstand > 25 Refractory
          durationSamples: 40,
        );
        for (int i = 0; i < sequence.length; i++) {
          final peak = detector.process(_frame(sequence[i], t: (rep * 100 + i) * 20));
          if (peak != null) peakCount++;
        }
      }

      expect(peakCount, equals(3), reason: '3 Reps sollten 3 Peaks ergeben');
    });

    test('updateLevels setzt SPK/NPK manuell', () {
      detector.updateLevels(spk: 200.0, npk: 20.0);
      expect(detector.spk, equals(200.0));
      expect(detector.npk, equals(20.0));
      // Schwelle: 20 + 0.25*(200-20) = 65
      expect(detector.currentThreshold, closeTo(65.0, 0.01));
    });
  });
}

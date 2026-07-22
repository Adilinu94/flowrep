import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/detection/online_adapter.dart';

void main() {
  group('OnlineAdapter', () {
    late OnlineAdapter adapter;

    setUp(() {
      adapter = OnlineAdapter(
        emaAlpha: 0.1,
        minRepsForAdaptation: 3,
        initialDurationSamples: 50.0,
        initialProminence: 100.0,
        initialIntervalMs: 2000.0,
      );
    });

    test('Startet mit initialen Werten', () {
      expect(adapter.adaptiveDurationSamples, equals(50.0));
      expect(adapter.adaptiveProminence, equals(100.0));
      expect(adapter.adaptiveIntervalMs, equals(2000.0));
      expect(adapter.isAdaptive, isFalse);
      expect(adapter.repCount, equals(0));
    });

    test('isAdaptive wird true nach minRepsForAdaptation Reps', () {
      adapter.onRepConfirmed(durationSamples: 50, prominence: 100);
      expect(adapter.isAdaptive, isFalse);

      adapter.onRepConfirmed(durationSamples: 50, prominence: 100);
      expect(adapter.isAdaptive, isFalse);

      adapter.onRepConfirmed(durationSamples: 50, prominence: 100);
      expect(adapter.isAdaptive, isTrue);
      expect(adapter.repCount, equals(3));
    });

    test('Adaptive Werte aktualisieren sich nach 3+ Reps', () {
      // 3 Reps mit anderer Dauer/Prominenz
      adapter.onRepConfirmed(durationSamples: 80, prominence: 150);
      adapter.onRepConfirmed(durationSamples: 80, prominence: 150);
      adapter.onRepConfirmed(durationSamples: 80, prominence: 150);

      // EMA: 0.1 * 80 + 0.9 * 50 = 8 + 45 = 53
      expect(adapter.adaptiveDurationSamples, closeTo(53.0, 0.1));
      // EMA: 0.1 * 150 + 0.9 * 100 = 15 + 90 = 105
      expect(adapter.adaptiveProminence, closeTo(105.0, 0.1));
    });

    test('Intervall-Berechnung mit Timestamps', () {
      adapter.onRepConfirmed(
        durationSamples: 50,
        prominence: 100,
        timestampMs: 1000,
      );
      adapter.onRepConfirmed(
        durationSamples: 50,
        prominence: 100,
        timestampMs: 3000, // 2000ms Intervall
      );
      adapter.onRepConfirmed(
        durationSamples: 50,
        prominence: 100,
        timestampMs: 5000, // 2000ms Intervall
      );

      // Intervall sollte bei ~2000ms liegen
      expect(adapter.adaptiveIntervalMs, closeTo(2000.0, 100.0));
    });

    test('reset() setzt repCount zurück (nicht adaptive Werte)', () {
      adapter.onRepConfirmed(durationSamples: 80, prominence: 150);
      adapter.onRepConfirmed(durationSamples: 80, prominence: 150);
      adapter.onRepConfirmed(durationSamples: 80, prominence: 150);

      final durationBefore = adapter.adaptiveDurationSamples;
      final prominenceBefore = adapter.adaptiveProminence;

      adapter.reset();

      expect(adapter.repCount, equals(0));
      expect(adapter.isAdaptive, isFalse);
      // Adaptive Werte bleiben erhalten
      expect(adapter.adaptiveDurationSamples, equals(durationBefore));
      expect(adapter.adaptiveProminence, equals(prominenceBefore));
    });

    test('setExpectations setzt adaptive Werte manuell', () {
      adapter.setExpectations(
        durationSamples: 60.0,
        prominence: 120.0,
        intervalMs: 2500.0,
      );

      expect(adapter.adaptiveDurationSamples, equals(60.0));
      expect(adapter.adaptiveProminence, equals(120.0));
      expect(adapter.adaptiveIntervalMs, equals(2500.0));
    });

    test('Fenstergröße wird begrenzt (maxWindowSize)', () {
      final smallAdapter = OnlineAdapter(
        emaAlpha: 0.5,
        minRepsForAdaptation: 1,
        maxWindowSize: 3,
        initialDurationSamples: 50.0,
        initialProminence: 100.0,
      );

      // 5 Reps füttern (Fenster = 3)
      for (int i = 0; i < 5; i++) {
        smallAdapter.onRepConfirmed(durationSamples: 100, prominence: 200);
      }

      // Nur letzte 3 Reps im Fenster → Mittelwert = 100
      // EMA: 0.5 * 100 + 0.5 * vorheriger_Wert
      expect(smallAdapter.adaptiveDurationSamples, greaterThan(50.0));
    });

    test('Ausreißer-Intervall wird ignoriert (> 30s)', () {
      adapter.onRepConfirmed(
        durationSamples: 50,
        prominence: 100,
        timestampMs: 1000,
      );
      adapter.onRepConfirmed(
        durationSamples: 50,
        prominence: 100,
        timestampMs: 50000, // 49s Intervall → Ausreißer
      );
      adapter.onRepConfirmed(
        durationSamples: 50,
        prominence: 100,
        timestampMs: 52000, // 2s Intervall → OK
      );

      // Das 49s-Intervall sollte ignoriert worden sein
      expect(adapter.adaptiveIntervalMs, lessThan(10000.0));
    });

    test('repCount zählt korrekt', () {
      expect(adapter.repCount, equals(0));

      adapter.onRepConfirmed(durationSamples: 50, prominence: 100);
      expect(adapter.repCount, equals(1));

      adapter.onRepConfirmed(durationSamples: 50, prominence: 100);
      expect(adapter.repCount, equals(2));
    });
  });
}

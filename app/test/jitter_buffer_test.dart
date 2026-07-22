import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/filters/jitter_buffer.dart';

/// Test-Sample (einfacher Record).
class _TestSample {
  final int timestampMs;
  final double value;
  const _TestSample(this.timestampMs, this.value);
}

void main() {
  group('JitterBuffer', () {
    test('add() füllt den Puffer', () {
      final buffer = JitterBuffer<_TestSample>(onFrame: (_) {});
      buffer.add(const _TestSample(0, 1.0));
      buffer.add(const _TestSample(20, 2.0));
      expect(buffer.queueLength, equals(2));
      buffer.dispose();
    });

    test('Drop-Oldest bei vollem Puffer', () {
      final buffer = JitterBuffer<_TestSample>(
        onFrame: (_) {},
        bufferSize: 3,
      );
      buffer.add(const _TestSample(0, 1.0));
      buffer.add(const _TestSample(20, 2.0));
      buffer.add(const _TestSample(40, 3.0));
      expect(buffer.queueLength, equals(3));
      expect(buffer.droppedFrames, equals(0));

      // 4. Sample → ältestes wird verworfen
      buffer.add(const _TestSample(60, 4.0));
      expect(buffer.queueLength, equals(3));
      expect(buffer.droppedFrames, equals(1));
      buffer.dispose();
    });

    test('addBatch() fügt mehrere Elemente hinzu', () {
      final buffer = JitterBuffer<_TestSample>(onFrame: (_) {});
      buffer.addBatch([
        const _TestSample(0, 1.0),
        const _TestSample(20, 2.0),
        const _TestSample(40, 3.0),
      ]);
      expect(buffer.queueLength, equals(3));
      buffer.dispose();
    });

    test('start() ist idempotent', () {
      final buffer = JitterBuffer<_TestSample>(onFrame: (_) {});
      buffer.start();
      expect(buffer.isRunning, isTrue);
      buffer.start(); // nochmal → kein Fehler
      expect(buffer.isRunning, isTrue);
      buffer.dispose();
    });

    test('stop() leert Puffer und stoppt Timer', () {
      final buffer = JitterBuffer<_TestSample>(onFrame: (_) {});
      buffer.add(const _TestSample(0, 1.0));
      buffer.start();
      buffer.stop();
      expect(buffer.isRunning, isFalse);
      expect(buffer.queueLength, equals(0));
      buffer.dispose();
    });

    test('Timer gibt Samples in Reihenfolge aus', () async {
      final received = <int>[];
      final buffer = JitterBuffer<_TestSample>(
        onFrame: (s) => received.add(s.timestampMs),
        tickIntervalMs: 10,
      );

      buffer.add(const _TestSample(100, 1.0));
      buffer.add(const _TestSample(120, 2.0));
      buffer.add(const _TestSample(140, 3.0));
      buffer.start();

      // Warten bis alle 3 Samples ausgegeben wurden
      await Future<void>.delayed(const Duration(milliseconds: 80));
      buffer.stop();

      expect(received, equals([100, 120, 140]));
      expect(buffer.outputFrames, equals(3));
      buffer.dispose();
    });

    test('Leerer Puffer gibt nichts aus', () async {
      final received = <int>[];
      final buffer = JitterBuffer<_TestSample>(
        onFrame: (s) => received.add(s.timestampMs),
        tickIntervalMs: 10,
      );

      buffer.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      buffer.stop();

      expect(received, isEmpty);
      expect(buffer.outputFrames, equals(0));
      buffer.dispose();
    });

    test('reset() leert Puffer und setzt Zähler zurück', () {
      final buffer = JitterBuffer<_TestSample>(
        onFrame: (_) {},
        bufferSize: 2,
      );
      buffer.add(const _TestSample(0, 1.0));
      buffer.add(const _TestSample(20, 2.0));
      buffer.add(const _TestSample(40, 3.0)); // drop
      expect(buffer.droppedFrames, equals(1));

      buffer.reset();
      expect(buffer.queueLength, equals(0));
      expect(buffer.droppedFrames, equals(0));
      expect(buffer.outputFrames, equals(0));
      buffer.dispose();
    });

    test('dispose() stoppt den Timer', () {
      final buffer = JitterBuffer<_TestSample>(onFrame: (_) {});
      buffer.start();
      expect(buffer.isRunning, isTrue);
      buffer.dispose();
      expect(buffer.isRunning, isFalse);
    });
  });
}

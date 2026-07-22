import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/filters/jitter_buffer.dart';

void main() {
  group('JitterBuffer', () {
    test('add() füllt den Puffer', () {
      final buffer = JitterBuffer(onFrame: (_, __, ___, ____) {});
      buffer.add(0, 1.0, 2.0, 3.0);
      buffer.add(20, 4.0, 5.0, 6.0);
      expect(buffer.queueLength, equals(2));
      buffer.dispose();
    });

    test('Drop-Oldest bei vollem Puffer', () {
      final buffer = JitterBuffer(
        onFrame: (_, __, ___, ____) {},
        bufferSize: 3,
      );
      buffer.add(0, 1.0, 0.0, 0.0);
      buffer.add(20, 2.0, 0.0, 0.0);
      buffer.add(40, 3.0, 0.0, 0.0);
      expect(buffer.queueLength, equals(3));
      expect(buffer.droppedFrames, equals(0));

      // 4. Sample → ältestes wird verworfen
      buffer.add(60, 4.0, 0.0, 0.0);
      expect(buffer.queueLength, equals(3));
      expect(buffer.droppedFrames, equals(1));
      buffer.dispose();
    });

    test('start() ist idempotent', () {
      final buffer = JitterBuffer(onFrame: (_, __, ___, ____) {});
      buffer.start();
      expect(buffer.isRunning, isTrue);
      buffer.start(); // nochmal → kein Fehler
      expect(buffer.isRunning, isTrue);
      buffer.dispose();
    });

    test('stop() leert Puffer und stoppt Timer', () {
      final buffer = JitterBuffer(onFrame: (_, __, ___, ____) {});
      buffer.add(0, 1.0, 2.0, 3.0);
      buffer.start();
      buffer.stop();
      expect(buffer.isRunning, isFalse);
      expect(buffer.queueLength, equals(0));
      buffer.dispose();
    });

    test('Timer gibt Samples in Reihenfolge aus', () async {
      final received = <int>[];
      final buffer = JitterBuffer(
        onFrame: (ts, _, __, ___) => received.add(ts),
        tickIntervalMs: 10,
      );

      buffer.add(100, 1.0, 0.0, 0.0);
      buffer.add(120, 2.0, 0.0, 0.0);
      buffer.add(140, 3.0, 0.0, 0.0);
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
      final buffer = JitterBuffer(
        onFrame: (ts, _, __, ___) => received.add(ts),
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
      final buffer = JitterBuffer(
        onFrame: (_, __, ___, ____) {},
        bufferSize: 2,
      );
      buffer.add(0, 1.0, 0.0, 0.0);
      buffer.add(20, 2.0, 0.0, 0.0);
      buffer.add(40, 3.0, 0.0, 0.0); // drop
      expect(buffer.droppedFrames, equals(1));

      buffer.reset();
      expect(buffer.queueLength, equals(0));
      expect(buffer.droppedFrames, equals(0));
      expect(buffer.outputFrames, equals(0));
      buffer.dispose();
    });

    test('dispose() stoppt den Timer', () {
      final buffer = JitterBuffer(onFrame: (_, __, ___, ____) {});
      buffer.start();
      expect(buffer.isRunning, isTrue);
      buffer.dispose();
      expect(buffer.isRunning, isFalse);
    });
  });
}

import 'package:test/test.dart';
import 'package:flowrep/data/protocol/ble_protocol_parser.dart';
import 'package:flowrep/domain/workout_engine.dart';

void main() {
  group('BleProtocolParser', () {
    final parser = BleProtocolParser();

    test('encodeBatch produces exactly 52 bytes', () {
      final samples = List.generate(
        4,
        (i) => SensorSample(
          timestamp: DateTime.now(),
          ax: 0.1, ay: 1.0, az: 0.05,
          gx: 5.0, gy: -3.0, gz: 1.5,
        ),
      );
      final bytes = parser.encodeBatch(timestampMs: 123456, samples: samples);
      expect(bytes.length, 52);
    });

    test('parseBatch is the inverse of encodeBatch within scale rounding', () {
      final original = List.generate(
        4,
        (i) => SensorSample(
          timestamp: DateTime.now(),
          ax: 0.123, ay: -1.5, az: 0.987,
          gx: 45.5, gy: -90.25, gz: 12.0,
        ),
      );
      final bytes = parser.encodeBatch(timestampMs: 1000, samples: original);
      final decoded = parser.parseBatch(bytes);

      expect(decoded.length, 4);
      for (var i = 0; i < 4; i++) {
        expect(decoded[i].ax, closeTo(original[i].ax, 0.001));
        expect(decoded[i].ay, closeTo(original[i].ay, 0.001));
        expect(decoded[i].az, closeTo(original[i].az, 0.001));
        expect(decoded[i].gx, closeTo(original[i].gx, 0.01));
        expect(decoded[i].gy, closeTo(original[i].gy, 0.01));
        expect(decoded[i].gz, closeTo(original[i].gz, 0.01));
      }
    });

    test('parseBatch rejects payloads that are not 52 bytes', () {
      final tooShort = parser.encodeBatch(
        timestampMs: 0,
        samples: List.generate(
          4,
          (_) => SensorSample(
            timestamp: DateTime.now(),
            ax: 0, ay: 0, az: 0, gx: 0, gy: 0, gz: 0,
          ),
        ),
      ).sublist(0, 30);

      expect(() => parser.parseBatch(tooShort),
          throwsA(isA<BleProtocolException>()));
    });

    test('encodeBatch rejects a sample count other than 4', () {
      expect(
        () => parser.encodeBatch(
          timestampMs: 0,
          samples: List.generate(
            3,
            (_) => SensorSample(
              timestamp: DateTime.now(),
              ax: 0, ay: 0, az: 0, gx: 0, gy: 0, gz: 0,
            ),
          ),
        ),
        throwsA(isA<BleProtocolException>()),
      );
    });
  });
}

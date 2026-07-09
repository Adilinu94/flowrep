import 'dart:typed_data';

import '../../domain/workout_engine.dart';

/// Parses the canonical 52-byte BLE sensor-data payload defined in
/// docs/protocol.yaml. This file and protocol.yaml MUST stay in sync -
/// if you change one, change the other, and update ADR-001 if the wire
/// format itself changes.
///
/// Layout (little-endian):
///   bytes 0-3:   uint32 timestamp (ms)
///   bytes 4-51:  4 samples x 12 bytes
///     each sample: int16 ax, ay, az (scale 0.001 -> g)
///                  int16 gx, gy, gz (scale 0.01  -> deg/s)
class BleProtocolException implements Exception {
  final String message;
  BleProtocolException(this.message);
  @override
  String toString() => 'BleProtocolException: $message';
}

class BleProtocolParser {
  static const int expectedTotalBytes = 52;
  static const int samplesPerBatch = 4;
  static const int bytesPerSample = 12;
  static const double accelScale = 0.001;
  static const double gyroScale = 0.01;

  /// Throws [BleProtocolException] rather than silently returning partial
  /// data - a malformed packet should be visible, not swallowed, since
  /// mis-parsed sensor data would corrupt the Workout Engine's threshold
  /// calibration silently.
  List<SensorSample> parseBatch(Uint8List bytes) {
    if (bytes.length != expectedTotalBytes) {
      throw BleProtocolException(
        'Erwartete $expectedTotalBytes Byte, aber ${bytes.length} erhalten. '
        'Prüfe die BLE-MTU-Verhandlung (siehe protocol.yaml, constraints.ble_mtu) '
        'und ob Firmware und App dieselbe protocol.yaml-Version verwenden.',
      );
    }

    final data = ByteData.sublistView(bytes);
    final timestampMs = data.getUint32(0, Endian.little);
    final baseTime = DateTime.fromMillisecondsSinceEpoch(timestampMs);

    final samples = <SensorSample>[];
    for (var i = 0; i < samplesPerBatch; i++) {
      final offset = 4 + i * bytesPerSample;
      samples.add(SensorSample(
        // Samples within a batch are ~20ms apart at 50 Hz; approximate
        // per-sample timestamps rather than assigning all four the same
        // instant, since the Workout Engine's pause-detection logic
        // relies on meaningful time deltas between samples.
        timestamp: baseTime.add(Duration(milliseconds: (i * 20))),
        ax: data.getInt16(offset, Endian.little) * accelScale,
        ay: data.getInt16(offset + 2, Endian.little) * accelScale,
        az: data.getInt16(offset + 4, Endian.little) * accelScale,
        gx: data.getInt16(offset + 6, Endian.little) * gyroScale,
        gy: data.getInt16(offset + 8, Endian.little) * gyroScale,
        gz: data.getInt16(offset + 10, Endian.little) * gyroScale,
      ));
    }
    return samples;
  }

  /// Inverse of [parseBatch] - mainly useful for the MockSensorProvider and
  /// for unit tests, so tests can construct a valid wire-format packet
  /// instead of hand-writing byte offsets.
  Uint8List encodeBatch({
    required int timestampMs,
    required List<SensorSample> samples,
  }) {
    if (samples.length != samplesPerBatch) {
      throw BleProtocolException(
        'encodeBatch erwartet genau $samplesPerBatch Samples, '
        'bekam ${samples.length}.',
      );
    }
    final bytes = ByteData(expectedTotalBytes);
    bytes.setUint32(0, timestampMs, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      final offset = 4 + i * bytesPerSample;
      bytes.setInt16(offset, (s.ax / accelScale).round(), Endian.little);
      bytes.setInt16(offset + 2, (s.ay / accelScale).round(), Endian.little);
      bytes.setInt16(offset + 4, (s.az / accelScale).round(), Endian.little);
      bytes.setInt16(offset + 6, (s.gx / gyroScale).round(), Endian.little);
      bytes.setInt16(offset + 8, (s.gy / gyroScale).round(), Endian.little);
      bytes.setInt16(offset + 10, (s.gz / gyroScale).round(), Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}

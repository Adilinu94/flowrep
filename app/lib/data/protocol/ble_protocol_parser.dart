import 'dart:typed_data';

import '../../domain/workout_engine.dart';

/// Parses the BLE sensor-data payload defined in docs/01_protocol.yaml.
/// This file and protocol.yaml MUST stay in sync.
///
/// Wire-format detection (see protocol.yaml versions:):
///   52 bytes = v1 (no protocol_version field, gyro scale 0.01)
///   53 bytes = v2 (uint8 protocol_version at offset 4, gyro scale 0.02)
///
/// Layout v1 (little-endian):
///   bytes 0-3:   uint32 timestamp (ms)
///   bytes 4-51:  4 samples x 12 bytes
///
/// Layout v2 (little-endian):
///   bytes 0-3:   uint32 timestamp (ms)
///   byte  4:     uint8 protocol_version (= 2)
///   bytes 5-52:  4 samples x 12 bytes
///
/// Each sample: int16 ax, ay, az (scale 0.001 -> g)
///              int16 gx, gy, gz (v1: 0.01 / v2: 0.02 -> deg/s)
class BleProtocolException implements Exception {
  final String message;
  BleProtocolException(this.message);
  @override
  String toString() => 'BleProtocolException: $message';
}

class BleProtocolParser {
  static const int v1TotalBytes = 52;
  static const int v2TotalBytes = 53;
  static const int samplesPerBatch = 4;
  static const int bytesPerSample = 12;
  static const double accelScale = 0.001;
  static const double gyroScaleV1 = 0.01;
  static const double gyroScaleV2 = 0.02;

  /// Preferred total size for new encodes (protocol v2 / current firmware).
  static const int expectedTotalBytes = v2TotalBytes;
  static const double gyroScale = gyroScaleV2;

  /// Throws [BleProtocolException] rather than silently returning partial
  /// data - a malformed packet should be visible, not swallowed, since
  /// mis-parsed sensor data would corrupt the Workout Engine's threshold
  /// calibration silently.
  List<SensorSample> parseBatch(Uint8List bytes) {
    late final int samplesStart;
    late final double gyroScaleUsed;

    if (bytes.length == v2TotalBytes) {
      samplesStart = 5;
      gyroScaleUsed = gyroScaleV2;
    } else if (bytes.length == v1TotalBytes) {
      samplesStart = 4;
      gyroScaleUsed = gyroScaleV1;
    } else {
      throw BleProtocolException(
        'Erwartete $v1TotalBytes (v1) oder $v2TotalBytes (v2) Byte, '
        'aber ${bytes.length} erhalten. '
        'Prüfe die BLE-MTU-Verhandlung (siehe protocol.yaml, constraints.ble_mtu) '
        'und ob Firmware und App dieselbe protocol.yaml-Version verwenden.',
      );
    }

    final data = ByteData.sublistView(bytes);
    final timestampMs = data.getUint32(0, Endian.little);
    final baseTime = DateTime.fromMillisecondsSinceEpoch(timestampMs);

    final samples = <SensorSample>[];
    for (var i = 0; i < samplesPerBatch; i++) {
      final offset = samplesStart + i * bytesPerSample;
      samples.add(SensorSample(
        // Protocol v2 firmware guarantees 20 ms between consecutive samples
        // (including across batch boundaries). Same spacing is applied for v1
        // for engine compatibility; v1 wire timing was less honest.
        timestamp: baseTime.add(Duration(milliseconds: (i * 20))),
        ax: data.getInt16(offset, Endian.little) * accelScale,
        ay: data.getInt16(offset + 2, Endian.little) * accelScale,
        az: data.getInt16(offset + 4, Endian.little) * accelScale,
        gx: data.getInt16(offset + 6, Endian.little) * gyroScaleUsed,
        gy: data.getInt16(offset + 8, Endian.little) * gyroScaleUsed,
        gz: data.getInt16(offset + 10, Endian.little) * gyroScaleUsed,
      ));
    }
    return samples;
  }

  /// Inverse of [parseBatch] - mainly useful for the MockSensorProvider and
  /// for unit tests. Encodes **protocol v2** (53 bytes) by default.
  Uint8List encodeBatch({
    required int timestampMs,
    required List<SensorSample> samples,
    int protocolVersion = 2,
  }) {
    if (samples.length != samplesPerBatch) {
      throw BleProtocolException(
        'encodeBatch erwartet genau $samplesPerBatch Samples, '
        'bekam ${samples.length}.',
      );
    }

    if (protocolVersion == 2) {
      final bytes = ByteData(v2TotalBytes);
      bytes.setUint32(0, timestampMs, Endian.little);
      bytes.setUint8(4, 2);
      for (var i = 0; i < samples.length; i++) {
        final s = samples[i];
        final offset = 5 + i * bytesPerSample;
        bytes.setInt16(offset, (s.ax / accelScale).round(), Endian.little);
        bytes.setInt16(offset + 2, (s.ay / accelScale).round(), Endian.little);
        bytes.setInt16(offset + 4, (s.az / accelScale).round(), Endian.little);
        bytes.setInt16(offset + 6, (s.gx / gyroScaleV2).round(), Endian.little);
        bytes.setInt16(offset + 8, (s.gy / gyroScaleV2).round(), Endian.little);
        bytes.setInt16(offset + 10, (s.gz / gyroScaleV2).round(), Endian.little);
      }
      return bytes.buffer.asUint8List();
    }

    if (protocolVersion == 1) {
      final bytes = ByteData(v1TotalBytes);
      bytes.setUint32(0, timestampMs, Endian.little);
      for (var i = 0; i < samples.length; i++) {
        final s = samples[i];
        final offset = 4 + i * bytesPerSample;
        bytes.setInt16(offset, (s.ax / accelScale).round(), Endian.little);
        bytes.setInt16(offset + 2, (s.ay / accelScale).round(), Endian.little);
        bytes.setInt16(offset + 4, (s.az / accelScale).round(), Endian.little);
        bytes.setInt16(offset + 6, (s.gx / gyroScaleV1).round(), Endian.little);
        bytes.setInt16(offset + 8, (s.gy / gyroScaleV1).round(), Endian.little);
        bytes.setInt16(offset + 10, (s.gz / gyroScaleV1).round(), Endian.little);
      }
      return bytes.buffer.asUint8List();
    }

    throw BleProtocolException(
      'encodeBatch: unbekannte protocolVersion=$protocolVersion (1 oder 2).',
    );
  }
}

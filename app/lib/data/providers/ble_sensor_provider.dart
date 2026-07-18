import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../domain/workout_engine.dart';
import '../logger.dart';
import '../protocol/ble_protocol_parser.dart';
import 'sensor_provider.dart';

/// Real hardware implementation of ISensorProvider. Talks to the
/// "GymTracker" GATT service defined in docs/protocol.yaml.
///
/// NOT hardware-tested: written in Claude.ai before the M5StickC Plus2
/// arrived, per ADR (see docs/adr/ARCHITECTURE_DECISION_RECORDS.md and the
/// chat note accompanying this commit). Treat this file as a careful draft,
/// not verified working code, until it has been run against real hardware.
/// The first thing to check on real hardware: does deviceName match
/// exactly what the firmware advertises ("GymTracker"), and does MTU
/// negotiation actually reach >= 55 bytes (see protocol.yaml constraints).
class BleSensorProvider implements ISensorProvider {
  static const String deviceName = 'GymTracker';

  // UUIDs are placeholders - the firmware side (firmware/src/main.cpp) must
  // define and advertise the SAME UUIDs. Neither side is authoritative by
  // itself; docs/protocol.yaml is. Replace these once the firmware assigns
  // concrete UUIDs (a random v4 UUID per characteristic is fine, they just
  // have to match on both sides).
  static const String serviceUuid = '0000fee0-0000-1000-8000-00805f9b34fb';
  static const String sensorDataCharUuid =
      '0000fee1-0000-1000-8000-00805f9b34fb';
  static const String controlPointCharUuid =
      '0000fee2-0000-1000-8000-00805f9b34fb';
  static const String batteryLevelCharUuid =
      '0000fee3-0000-1000-8000-00805f9b34fb';

  // We request 185 to avoid the HyperOS MTU-517 off-by-one boundary bug,
  // but HyperOS ignores client MTU requests and always returns the
  // server's MTU (517 from NimBLEDevice::setMTU(517)). The actual
  // negotiated MTU is 517, which fits the 53-byte protocol-v2 payload
  // (and the legacy 52-byte v1 payload).
  static const int requiredMtu = 185;

  final _connectionController = StreamController<SensorConnectionState>.broadcast();
  final _sampleController = StreamController<SensorSample>.broadcast();
  final _parser = BleProtocolParser();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _sensorDataChar;
  BluetoothCharacteristic? _controlPointChar;
  BluetoothCharacteristic? _batteryChar;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<int>? _mtuSubscription;
  int _lastNegotiatedMtu = 0;

  int get lastNegotiatedMtu => _lastNegotiatedMtu;
  int get receivedBatches => _receivedBatches;
  int get parseErrors => _parseErrors;
  double get pollingRateHz => _pollingRateHz;
  /// The BLE device identifier (MAC address or equivalent).
  /// Only available after a successful [connect].
  String? get remoteId => _device?.remoteId.toString();

  @override
  Stream<SensorConnectionState> get connectionState => _connectionController.stream;

  @override
  Stream<SensorSample> get samples => _sampleController.stream;

  static bool _uuidMatches(Guid uuid, String expected) {
    final full = uuid.str128.toLowerCase();
    final short = uuid.str.toLowerCase();
    final target = expected.toLowerCase();
    return full == target || short == target || full.endsWith(target);
  }

  // Accepted wire sizes from docs/01_protocol.yaml: 52 = v1, 53 = v2.
  static const int _sampleBytesV1 = 52;
  static const int _sampleBytesV2 = 53;
  int _receivedBatches = 0;
  int _parseErrors = 0;
  double _pollingRateHz = 0;
  int _pollStartMicros = 0;
  int _pollBatchCount = 0;
  int _lastBatchTimestampMs = -1;  // deduplication: skip batches already read
  int _diagSampleCount = 0;         // diagnostics: how many samples fed to engine

  @override
  Future<void> connect() async {
    _connectionController.add(SensorConnectionState.connecting);

    final adapterState = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 5));
    if (adapterState != BluetoothAdapterState.on) {
      throw StateError(
        'Bluetooth ist nicht aktiv (state=$adapterState). '
        'Bitte Bluetooth am Handy einschalten.',
      );
    }

    // neverForLocation: this scan looks for a specific, known service/name
    // and does not use scan results to infer location, so no
    // ACCESS_FINE_LOCATION is requested on Android 12+ (see ADR-007 and
    // AndroidManifest.xml in this repo).
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      withNames: [deviceName],
    );

    late final ScanResult result;
    try {
      result = await FlutterBluePlus.scanResults
          .expand((results) => results)
          .firstWhere((r) => r.device.platformName == deviceName)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw StateError(
              'GymTracker nicht gefunden (15s Scan). '
              'Stick eingeschaltet? Display zeigt "Gym Tracker Bereit"?',
            ),
          );
    } finally {
      await FlutterBluePlus.stopScan();
    }

    _device = result.device;
    await _device!.connect(
      timeout: const Duration(seconds: 15),
      license: License.nonprofit,
    );

    // Subscribe to MTU change stream BEFORE negotiating, so we see
    // every MTU event the Android BLE stack emits. This diagnoses
    // why the UI shows MTU 517 even though we request 185.
    await _mtuSubscription?.cancel();
    _mtuSubscription = _device!.mtu.listen((mtu) {
      AppLogger.d('MTU stream event: $mtu (stored=$_lastNegotiatedMtu)');
      _lastNegotiatedMtu = mtu;
    });

    // Negotiate MTU BEFORE the CCCD sequence.
    AppLogger.i('calling requestMtu($requiredMtu)...');
    final negotiatedMtu = await _device!.requestMtu(requiredMtu);
    AppLogger.i('requestMtu($requiredMtu) returned: $negotiatedMtu');
    _lastNegotiatedMtu = negotiatedMtu;
    if (negotiatedMtu < requiredMtu) {
      throw StateError(
        'MTU negotiation returned $negotiatedMtu, need >= $requiredMtu.',
      );
    }

    final services = await _device!.discoverServices();
    final service = services.firstWhere(
      (s) => _uuidMatches(s.uuid, serviceUuid),
      orElse: () => throw StateError(
        'Service $serviceUuid nicht gefunden. '
        'Gefunden: ${services.map((s) => s.uuid.str128).join(", ")}',
      ),
    );

    _sensorDataChar = service.characteristics.firstWhere(
      (c) => _uuidMatches(c.uuid, sensorDataCharUuid),
      orElse: () => throw StateError('SensorData-Char fehlt'),
    );
    _controlPointChar = service.characteristics.firstWhere(
      (c) => _uuidMatches(c.uuid, controlPointCharUuid),
      orElse: () => throw StateError('ControlPoint-Char fehlt'),
    );
    _batteryChar = service.characteristics.firstWhere(
      (c) => _uuidMatches(c.uuid, batteryLevelCharUuid),
      orElse: () => throw StateError('Battery-Char fehlt'),
    );

    // NO CCCD / setNotifyValue: HyperOS caches the "last notified value"
    // and returns it for every read(), even though notification delivery is
    // blocked. Without a CCCD, Android does real Over-the-Air Read Requests.
    // The firmware always calls setValue() unconditionally so read() gets
    // fresh data.
    //
    // Keep a listener for diagnostic purposes only: if HyperOS ever starts
    // delivering notifications, we can switch to notification-driven streaming.
    await _notifySubscription?.cancel();
    _notifySubscription = _sensorDataChar!.lastValueStream.listen((_) {
      AppLogger.i('NOTIFY received! HyperOS notification block lifted?');
    });

    AppLogger.i('SKIPPING setNotifyValue - relying on pure read() polling');

    // High connection priority reduces read() round-trip latency significantly.
    // Without it, Android uses a power-saving connection interval that adds
    // 50-100ms to every GATT read.
    AppLogger.i('stream auto-started by firmware, requesting high connection priority...');
    await _device!.requestConnectionPriority(connectionPriorityRequest: ConnectionPriority.high);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Firmware auto-starts streaming in onConnect (ADR-017).
    // No START_STREAM command needed — sending 0x01 would just reset
    // streaming=false for 500ms, creating an unnecessary gap.
    _connectionController.add(SensorConnectionState.connected);

    // Delay polling start to match firmware's 500ms deferred stream start.
    // Starting read() too early would pull stale/zero data and corrupt the
    // Workout Engine's baseline estimate and EMA filter.
    Future<void>.delayed(const Duration(milliseconds: 600), _startPolling);
  }

  Future<void> _sendControlCommand(int command) async {
    AppLogger.i('sendControlCommand: 0x${command.toRadixString(16).padLeft(2, '0')}');
    try {
      await _controlPointChar?.write([command], withoutResponse: false);
      AppLogger.i('sendControlCommand: 0x${command.toRadixString(16).padLeft(2, '0')} done');
    } catch (e) {
      AppLogger.e('sendControlCommand: 0x${command.toRadixString(16).padLeft(2, '0')} FAILED: $e');
      rethrow;
    }
  }

  /// Poll the sensor data characteristic via read() instead of waiting
  /// for notifications. HyperOS on Xiaomi 11T silently drops GATT
  /// notifications even when the CCCD is correctly set. This workaround
  /// reads the characteristic value in a tight loop, proving the data
  /// path works and providing functional streaming at lower throughput.
  void _startPolling() {
    // Keep the notification listener active — diagnostic: if it ever fires,
    // we switch to notification-driven streaming at 50 Hz. Until then,
    // read() polling is the primary data path at ~20 Hz.

    _pollStartMicros = DateTime.now().microsecondsSinceEpoch;
    _pollBatchCount = 0;
    _lastBatchTimestampMs = -1;  // reset on reconnect to avoid stale dedup
    _diagSampleCount = 0;        // reset diagnostics for new session

    Future<void> poll() async {
      while (_device?.isConnected == true) {
        try {
          final t0 = DateTime.now().microsecondsSinceEpoch;
          final bytes = await _sensorDataChar?.read();
          if (bytes == null || bytes.isEmpty) continue;

          // Measure read() round-trip time for diagnostics.
          final dt = DateTime.now().microsecondsSinceEpoch - t0;

          if (bytes.length != _sampleBytesV1 &&
              bytes.length != _sampleBytesV2) {
            _parseErrors++;
            continue;
          }
          // Deduplication: the firmware updates the characteristic at
          // ~50 Hz, but we poll at ~30 Hz. Without dedup, the same batch
          // would be read and fed to the Workout Engine multiple times,
          // corrupting the EMA filter and rep counting.
          final list = Uint8List.fromList(bytes);
          final batchTimestampMs =
              ByteData.sublistView(list).getUint32(0, Endian.little);
          if (batchTimestampMs == _lastBatchTimestampMs) continue;
          _lastBatchTimestampMs = batchTimestampMs;

          final samples = _parser.parseBatch(list);
          _receivedBatches++;
          _pollBatchCount++;

          // Calculate polling rate every batch: batches / elapsed seconds.
          final elapsedSec = (DateTime.now().microsecondsSinceEpoch - _pollStartMicros) / 1000000.0;
          if (elapsedSec > 0.1) {
            _pollingRateHz = _pollBatchCount / elapsedSec;
          }

          for (final s in samples) {
            _sampleController.add(s);
          }

          // DIAGNOSTIC: log raw IMU values every ~50 batches so we can
          // see what the sensor is actually measuring during movement.
          _diagSampleCount += samples.length;
          if (_pollBatchCount % 50 == 0) {
            final s = samples[0];
            AppLogger.d('DIAG raw(ax=${s.ax.toStringAsFixed(3)} '
                'ay=${s.ay.toStringAsFixed(3)} az=${s.az.toStringAsFixed(3)}) '
                'mag=${s.accelMagnitude.toStringAsFixed(3)} '
                'gyro_mag=${s.gyroMagnitude.toStringAsFixed(1)} '
                'totalSamples=$_diagSampleCount');
          }

          // Log read() timing for rate diagnostics.
          AppLogger.d('read() took ${dt ~/ 1000}ms, '
              'rate=${_pollingRateHz.toStringAsFixed(1)} Hz, '
              'batches=$_pollBatchCount');
        } catch (e) {
          // Transient GATT errors (GATT_BUSY, timeout, etc.) are expected
          // when polling read() in a tight loop on Android. Breaking the
          // loop here would kill the entire streaming session. Instead:
          // log, back off briefly, and retry.
          AppLogger.w('polling transient: $e');
          await Future<void>.delayed(const Duration(milliseconds: 50));
          continue;
        }
        // NO deliberate delay — let read()'s natural GATT round-trip
        // time govern the polling rate. Goal: measure max throughput.
      }
    }

    // Fire and forget — runs in background until disconnect.
    poll();
  }

  @override
  Future<void> disconnect() async {
    await _sendControlCommand(0x02); // STOP_STREAM
    await _notifySubscription?.cancel();
    await _mtuSubscription?.cancel();
    await _device?.disconnect();
    _connectionController.add(SensorConnectionState.disconnected);
  }

  @override
  Future<int> readBatteryPercent() async {
    // Send REQUEST_BATTERY (0x03) to trigger a fresh voltage reading
    // on the firmware, then read the updated value.
    await _sendControlCommand(0x03);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final value = await _batteryChar?.read();
    return (value != null && value.isNotEmpty) ? value.first : 0;
  }

  @override
  void simulateRepetition() {
    // No-op for real BLE: the user performs the repetition physically.
  }

  /// Debug: toggle dummy stream on the firmware (control command 0x04).
  /// The firmware sends constant fake IMU data without touching the real
  /// IMU/I2C bus, which isolates whether the streaming hang is caused by
  /// the IMU or by the BLE notify() path. See HANDOFF_BLE_DEBUG_2026-07-11.md.
  Future<void> toggleDummyStream() async {
    AppLogger.i('toggleDummyStream() called - sending 0x04');
    await _sendControlCommand(0x04);
  }

  void dispose() {
    _notifySubscription?.cancel();
    _mtuSubscription?.cancel();
    _connectionController.close();
    _sampleController.close();
  }
}

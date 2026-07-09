import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../domain/workout_engine.dart';
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

  static const int requiredMtu = 55; // see protocol.yaml constraints.ble_mtu

  final _connectionController = StreamController<ConnectionState>.broadcast();
  final _sampleController = StreamController<SensorSample>.broadcast();
  final _parser = BleProtocolParser();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _sensorDataChar;
  BluetoothCharacteristic? _controlPointChar;
  BluetoothCharacteristic? _batteryChar;
  StreamSubscription<List<int>>? _notifySubscription;

  @override
  Stream<ConnectionState> get connectionState => _connectionController.stream;

  @override
  Stream<SensorSample> get samples => _sampleController.stream;

  @override
  Future<void> connect() async {
    _connectionController.add(ConnectionState.connecting);

    // neverForLocation: this scan looks for a specific, known service/name
    // and does not use scan results to infer location, so no
    // ACCESS_FINE_LOCATION is requested on Android 12+ (see ADR-007 and
    // AndroidManifest.xml in this repo).
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      withNames: [deviceName],
    );

    final result = await FlutterBluePlus.scanResults
        .expand((results) => results)
        .firstWhere((r) => r.device.platformName == deviceName);
    await FlutterBluePlus.stopScan();

    _device = result.device;
    await _device!.connect();

    final negotiatedMtu = await _device!.requestMtu(requiredMtu);
    if (negotiatedMtu < requiredMtu) {
      // This must surface, not be silently ignored - undersized MTU means
      // the 52-byte payload will not arrive intact. See
      // 07_ESKALATIONS_PLAYBOOK.md, "MTU-Verhandlung schlägt fehl".
      throw StateError(
        'MTU negotiation returned $negotiatedMtu, need >= $requiredMtu. '
        'See protocol.yaml constraints.ble_mtu and the escalation playbook.',
      );
    }

    final services = await _device!.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid.toString().toLowerCase() == serviceUuid,
    );

    _sensorDataChar = service.characteristics.firstWhere(
      (c) => c.uuid.toString().toLowerCase() == sensorDataCharUuid,
    );
    _controlPointChar = service.characteristics.firstWhere(
      (c) => c.uuid.toString().toLowerCase() == controlPointCharUuid,
    );
    _batteryChar = service.characteristics.firstWhere(
      (c) => c.uuid.toString().toLowerCase() == batteryLevelCharUuid,
    );

    await _sensorDataChar!.setNotifyValue(true);
    _notifySubscription = _sensorDataChar!.lastValueStream.listen((bytes) {
      try {
        final samples = _parser.parseBatch(Uint8List.fromList(bytes));
        for (final s in samples) {
          _sampleController.add(s);
        }
      } on BleProtocolException catch (e) {
        // Deliberately not swallowed - a parse error means firmware and
        // app disagree about the wire format, which is always an
        // escalation case (see ESKALATIONS_PLAYBOOK.md), never something
        // to silently work around by e.g. truncating/padding bytes.
        _connectionController.addError(e);
      }
    });

    await _sendControlCommand(0x01); // START_STREAM
    _connectionController.add(ConnectionState.connected);
  }

  Future<void> _sendControlCommand(int command) async {
    await _controlPointChar?.write([command], withoutResponse: false);
  }

  @override
  Future<void> disconnect() async {
    await _sendControlCommand(0x02); // STOP_STREAM
    await _notifySubscription?.cancel();
    await _device?.disconnect();
    _connectionController.add(ConnectionState.disconnected);
  }

  @override
  Future<int> readBatteryPercent() async {
    final value = await _batteryChar?.read();
    return (value != null && value.isNotEmpty) ? value.first : 0;
  }

  void dispose() {
    _notifySubscription?.cancel();
    _connectionController.close();
    _sampleController.close();
  }
}

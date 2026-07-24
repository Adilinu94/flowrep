/// BLE DeviceEvent from M5Stick (protocol.yaml DeviceEvent / fee4).
enum DeviceEventId {
  none(0x00),
  /// BtnA: app starts counting if idle, ends set if counting.
  countPrimary(0x01);

  const DeviceEventId(this.wireValue);
  final int wireValue;

  static DeviceEventId fromWire(int value) {
    for (final e in DeviceEventId.values) {
      if (e.wireValue == value) return e;
    }
    return DeviceEventId.none;
  }
}

/// One button/device event (seq distinguishes repeats).
class DeviceEvent {
  final int seq;
  final DeviceEventId id;
  final DateTime receivedAt;

  const DeviceEvent({
    required this.seq,
    required this.id,
    required this.receivedAt,
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/ble_sensor_provider.dart';

void main() {
  group('BleSensorProvider dual advertise names (F-03)', () {
    test('accepts FlowRep and GymTracker', () {
      expect(BleSensorProvider.isFlowRepDeviceName('FlowRep'), isTrue);
      expect(BleSensorProvider.isFlowRepDeviceName('GymTracker'), isTrue);
      expect(BleSensorProvider.isFlowRepDeviceName(' FlowRep '), isTrue);
    });

    test('rejects unrelated names', () {
      expect(BleSensorProvider.isFlowRepDeviceName(''), isFalse);
      expect(BleSensorProvider.isFlowRepDeviceName('iPhone'), isFalse);
      expect(BleSensorProvider.isFlowRepDeviceName('flowrep'), isFalse);
    });

    test('deviceNames lists preferred first', () {
      expect(BleSensorProvider.deviceNames.first, 'FlowRep');
      expect(BleSensorProvider.deviceNames, contains('GymTracker'));
      expect(BleSensorProvider.deviceName, 'FlowRep');
    });
  });
}

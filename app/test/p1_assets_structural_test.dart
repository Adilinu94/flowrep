import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P1 assets / iOS / CI structural', () {
    test('rep_click.wav exists and is non-empty', () {
      final f = File('assets/sounds/rep_click.wav');
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(100));
    });

    test('icon assets exist', () {
      expect(File('assets/icon/flowrep_icon.png').existsSync(), isTrue);
      expect(File('assets/icon/flowrep_foreground.png').existsSync(), isTrue);
      expect(File('assets/icon/flowrep_splash.png').existsSync(), isTrue);
    });

    test('pubspec declares sounds and icon assets', () {
      final pub = File('pubspec.yaml').readAsStringSync();
      expect(pub.contains('assets/sounds/'), isTrue);
      expect(pub.contains('assets/icon/'), isTrue);
      expect(pub.contains('flutter_launcher_icons:'), isTrue);
      expect(pub.contains('flutter_native_splash:'), isTrue);
    });

    test('iOS Info.plist has BLE usage strings', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist.contains('NSBluetoothAlwaysUsageDescription'), isTrue);
      expect(plist.contains('NSBluetoothPeripheralUsageDescription'), isTrue);
      expect(plist.contains('bluetooth-central'), isTrue);
      expect(plist.contains('GymTracker-Sensor'), isTrue);
    });

    test('CI workflow exists at repo root', () {
      final ci = File('../.github/workflows/ci.yml');
      expect(ci.existsSync(), isTrue);
      final text = ci.readAsStringSync();
      expect(text.contains('flutter test'), isTrue);
      expect(text.contains('working-directory: app'), isTrue);
    });
  });
}

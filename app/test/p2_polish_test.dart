import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/ble_error_mapper.dart';
import 'package:flowrep/domain/config/engine_constants.dart';
import 'package:flowrep/main.dart';
import 'package:flowrep/presentation/widgets/rep_counter_display.dart';

void main() {
  group('BleErrorMapper (P2-4)', () {
    test('mappt timeout auf nutzerfreundliche Meldung', () {
      final msg = BleErrorMapper.toUserMessage(Exception('scan timeout'));
      expect(msg.toLowerCase(), contains('flowrep'));
      expect(msg.contains('PlatformException'), isFalse);
    });

    test('mappt bluetooth off', () {
      final msg = BleErrorMapper.toUserMessage(Exception('adapterState poweredOff'));
      expect(msg.toLowerCase(), contains('bluetooth'));
    });

    test('fallback ohne technische Details', () {
      final msg = BleErrorMapper.toUserMessage(Exception('weird xyz'));
      expect(msg, 'Verbindungsfehler. Bitte erneut versuchen.');
    });
  });

  group('engine_constants (P2-6)', () {
    test('Standard-Werte dokumentiert', () {
      expect(kDefaultRestDurationSeconds, 90);
      expect(kMaxReconnectAttempts, 10);
      expect(kMaxReconnectBackoffSeconds, 16);
      expect(kPacketLossWarnThreshold, 0.05);
      expect(kMinThresholdAboveBaseline, 0.10);
    });
  });

  group('Dark Mode wiring (P2-1)', () {
    test('main.dart configures light/dark themes', () {
      final src = File('lib/main.dart').readAsStringSync();
      expect(src.contains('darkTheme:'), isTrue);
      expect(src.contains('themeMode: ThemeMode.system'), isTrue);
      expect(src.contains('Brightness.dark'), isTrue);
    });

    test('FlowRepApp is StatelessWidget', () {
      expect(const FlowRepApp(), isA<StatelessWidget>());
    });
  });

  group('RepCounterDisplay glanceability/a11y (P2-2/3)', () {
    testWidgets('Semantics label und große Schrift', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RepCounterDisplay(repCount: 12),
          ),
        ),
      );
      final node = tester.getSemantics(find.byType(RepCounterDisplay));
      expect(node.label, contains('Wiederholungen: 12'));
      expect(node.value, '12');
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Wiederholungen'), findsOneWidget);
      handle.dispose();
    });
  });

  group('P2 structural', () {
    test('BleErrorMapper and constants files exist', () {
      expect(File('lib/data/providers/ble_error_mapper.dart').existsSync(),
          isTrue);
      expect(File('lib/domain/config/engine_constants.dart').existsSync(),
          isTrue);
    });
  });
}

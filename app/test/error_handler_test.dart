import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/logger.dart';
import 'package:flowrep/main.dart';

void main() {
  group('AppLogger (P1-1)', () {
    test('e akzeptiert stack und error ohne Exception', () {
      expect(
        () => AppLogger.e(
          'test',
          error: Exception('x'),
          stack: StackTrace.current,
        ),
        returnsNormally,
      );
      expect(() => AppLogger.d('d'), returnsNormally);
      expect(() => AppLogger.i('i'), returnsNormally);
      expect(() => AppLogger.w('w'), returnsNormally);
      // Backward-compatible: positional message only
      expect(() => AppLogger.e('only message'), returnsNormally);
    });
  });

  group('FlowRepApp (P1-1)', () {
    test('FlowRepApp is a StatelessWidget', () {
      const app = FlowRepApp();
      expect(app, isA<StatelessWidget>());
    });
  });

  group('P1-1 structural wiring in main.dart', () {
    test('main.dart hat Error-Handler und runZonedGuarded', () {
      final src = File('lib/main.dart').readAsStringSync();
      expect(src.contains('FlutterError.onError'), isTrue);
      expect(src.contains('runZonedGuarded'), isTrue);
      expect(src.contains('ErrorWidget.builder'), isTrue);
      expect(src.contains('AppLogger.e'), isTrue);
      expect(src.contains('PlatformDispatcher.instance.onError'), isTrue);
      expect(
        src.contains('Ein unerwarteter Fehler ist aufgetreten.'),
        isTrue,
      );
    });
  });
}

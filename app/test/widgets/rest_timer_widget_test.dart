import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/presentation/widgets/rest_timer_widget.dart';

void main() {
  group('RestTimerWidget (P1-7)', () {
    testWidgets('zeigt verbleibende Zeit', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RestTimerWidget(
              secondsRemaining: 75,
              totalSeconds: 90,
              onSkip: () {},
            ),
          ),
        ),
      );

      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('1:15'), findsOneWidget);
      expect(find.text('Pause überspringen'), findsOneWidget);
    });

    testWidgets('Skip-Button ruft Callback', (tester) async {
      var skipped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RestTimerWidget(
              secondsRemaining: 45,
              totalSeconds: 90,
              onSkip: () => skipped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pause überspringen'));
      expect(skipped, isTrue);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/presentation/widgets/session_summary_dialog.dart';

void main() {
  group('SessionSummaryDialog (P1-7)', () {
    testWidgets('zeigt Sätze, Reps und Dauer', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionSummaryDialog(
              totalSets: 2,
              totalReps: 17,
              duration: const Duration(minutes: 5),
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );
      expect(find.text('Training beendet'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('17'), findsOneWidget);
      expect(find.text('5 min'), findsOneWidget);
      await tester.tap(find.text('Fertig'));
      expect(dismissed, isTrue);
    });
  });
}

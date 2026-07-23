import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/presentation/widgets/correction_dialog.dart';

void main() {
  group('CorrectionDialog (P1-7)', () {
    testWidgets('zeigt gezählte Reps und +/- Buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CorrectionDialog(
              countedReps: 10,
              userReps: 10,
              onIncrement: () {},
              onDecrement: () {},
              onConfirm: () {},
              onDismiss: () {},
            ),
          ),
        ),
      );

      expect(find.text('Satz beendet'), findsOneWidget);
      expect(find.textContaining('App hat 10 gezählt'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
    });

    testWidgets('Danke-Nachricht nur bei Korrektur', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CorrectionDialog(
              countedReps: 10,
              userReps: 9,
              onIncrement: () {},
              onDecrement: () {},
              onConfirm: () {},
              onDismiss: () {},
            ),
          ),
        ),
      );

      expect(
        find.text(CorrectionDialog.thankYouMessage),
        findsOneWidget,
      );
      expect(find.textContaining('Die KI lernt'), findsNothing);
    });

    testWidgets('onIncrement wird aufgerufen', (tester) async {
      var incremented = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CorrectionDialog(
              countedReps: 10,
              userReps: 10,
              onIncrement: () => incremented = true,
              onDecrement: () {},
              onConfirm: () {},
              onDismiss: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add));
      expect(incremented, isTrue);
    });
  });
}

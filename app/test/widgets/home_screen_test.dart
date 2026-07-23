import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/sensor_provider.dart';
import 'package:flowrep/domain/workout_engine.dart';
import 'package:flowrep/presentation/providers/engine_provider.dart';
import 'package:flowrep/presentation/screens/home_screen.dart';

Widget buildTestApp() {
  return ProviderScope(
    overrides: [
      engineProvider.overrideWith(
        (_) => EngineNotifier.create(
          sensorProvider: MockSensorProvider(),
          engine: WorkoutEngine(
            exerciseId: 'bicep_curl',
            useSignedProjectionCounting: true,
          ),
        ),
      ),
    ],
    child: const MaterialApp(home: HomeScreen()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeScreen Widget-Tests (P1-7)', () {
    testWidgets('zeigt Getrennt wenn nicht verbunden', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump();
      expect(find.text('Getrennt'), findsOneWidget);
    });

    testWidgets('zeigt Gerät verbinden Button', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump();
      expect(find.text('Gerät verbinden'), findsOneWidget);
    });

    testWidgets('zeigt FlowRep im AppBar', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump();
      expect(find.text('FlowRep'), findsOneWidget);
    });

    testWidgets('Settings- und History-Icons in AppBar', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump();
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
    });
  });
}

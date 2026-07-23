import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/presentation/widgets/fusion_status_badge.dart';

void main() {
  testWidgets('FusionStatusBadge shows camera and stats', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FusionStatusBadge(
            cameraEnabled: true,
            fusedReps: 2,
            imuOnlyReps: 1,
            poseReps: 3,
            lastElbowAngle: 120,
            diagnostic: 'IMU + Kamera einig',
          ),
        ),
      ),
    );
    expect(find.textContaining('Fusion'), findsOneWidget);
    expect(find.textContaining('both 2'), findsOneWidget);
    expect(find.textContaining('120'), findsOneWidget);
  });
}

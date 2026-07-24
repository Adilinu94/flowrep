import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/presentation/widgets/fusion_status_badge.dart';
import 'package:flowrep/presentation/widgets/vision_agreement_badge.dart';

void main() {
  testWidgets('FusionStatusBadge shows agreement and stats', (tester) async {
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
    expect(find.textContaining('Pose bestätigt 2/3'), findsOneWidget);
    expect(find.textContaining('both 2'), findsOneWidget);
    expect(find.textContaining('120'), findsOneWidget);
    expect(find.textContaining('IMU zählt'), findsOneWidget);
  });

  testWidgets('VisionAgreementBadge compact shows Pose bestätigt',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VisionAgreementBadge(
            cameraEnabled: true,
            fusedReps: 7,
            imuOnlyReps: 3,
            compact: true,
          ),
        ),
      ),
    );
    expect(find.text('Pose bestätigt 7/10'), findsOneWidget);
  });

  testWidgets('VisionAgreementBadge hidden when camera off', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VisionAgreementBadge(
            cameraEnabled: false,
            fusedReps: 5,
            imuOnlyReps: 0,
          ),
        ),
      ),
    );
    expect(find.textContaining('Pose'), findsNothing);
  });

  testWidgets('VisionAgreementBadge ready when no IMU decisions yet',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VisionAgreementBadge(
            cameraEnabled: true,
            fusedReps: 0,
            imuOnlyReps: 0,
          ),
        ),
      ),
    );
    expect(find.text('Pose bereit'), findsOneWidget);
  });
}

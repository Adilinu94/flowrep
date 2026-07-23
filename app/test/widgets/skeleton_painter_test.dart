import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/data/providers/camera_pose_provider.dart';
import 'package:flowrep/domain/vision/pose_skeleton.dart';
import 'package:flowrep/presentation/widgets/skeleton_painter.dart';
import 'package:flowrep/presentation/widgets/framed_guide_overlay.dart';

void main() {
  testWidgets('SkeletonPainter paints without crash on empty landmarks',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(200, 200),
            painter: const SkeletonPainter(landmarks: null),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('SkeletonPainter paints synthetic pose without crash',
      (tester) async {
    final lms = List.generate(
      33,
      (i) => FlowPoseLandmark(
        x: 0.3 + (i % 5) * 0.05,
        y: 0.2 + (i % 7) * 0.05,
        confidence: 0.9,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(300, 400),
            painter: SkeletonPainter(
              landmarks: lms,
              drawMode: SkeletonDrawMode.upper,
              highlightRightArm: true,
              primaryJointForm: AngleFormColor.good,
              pulseScale: 1.5,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('FramedGuideOverlay shows message when visible', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 300,
            child: FramedGuideOverlay(visible: true),
          ),
        ),
      ),
    );
    expect(find.textContaining('Oberkörper'), findsOneWidget);
  });

  testWidgets('FramedGuideOverlay hidden when not visible', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FramedGuideOverlay(visible: false),
        ),
      ),
    );
    expect(find.textContaining('Oberkörper'), findsNothing);
  });
}

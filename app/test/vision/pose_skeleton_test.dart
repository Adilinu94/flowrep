import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/vision/pose_skeleton.dart';
import 'package:flowrep/domain/vision/vision_focus.dart';
import 'package:flowrep/domain/vision/angle_calculator.dart';

void main() {
  group('PoseSkeleton topology', () {
    test('all bone indices valid for full/upper/armOnly', () {
      expect(
        PoseSkeleton.allBoneIndicesValid(PoseSkeleton.fullBones),
        isTrue,
      );
      expect(
        PoseSkeleton.allBoneIndicesValid(PoseSkeleton.upperBones),
        isTrue,
      );
      expect(
        PoseSkeleton.allBoneIndicesValid(
          PoseSkeleton.bonesFor(SkeletonDrawMode.armOnly, activeRight: true),
        ),
        isTrue,
      );
      expect(
        PoseSkeleton.allBoneIndicesValid(
          PoseSkeleton.bonesFor(SkeletonDrawMode.armOnly, activeRight: false),
        ),
        isTrue,
      );
    });

    test('upper has fewer bones than full', () {
      expect(
        PoseSkeleton.bonesFor(SkeletonDrawMode.upper).length,
        lessThan(PoseSkeleton.bonesFor(SkeletonDrawMode.full).length),
      );
    });

    test('armOnly has fewer bones than upper', () {
      final arm = PoseSkeleton.bonesFor(
        SkeletonDrawMode.armOnly,
        activeRight: true,
      );
      final upper = PoseSkeleton.bonesFor(SkeletonDrawMode.upper);
      expect(arm.length, lessThan(upper.length));
      expect(
        PoseSkeleton.jointIndices(arm),
        containsAll([
          PoseLandmarkIndex.rightShoulder,
          PoseLandmarkIndex.rightElbow,
          PoseLandmarkIndex.rightWrist,
        ]),
      );
    });

    test('toCanvasOffset maps corners and mirrorX', () {
      const size = Size(200, 100);
      final origin = PoseSkeleton.toCanvasOffset(
        x: 0,
        y: 0,
        canvas: size,
      );
      expect(origin, const Offset(0, 0));

      final br = PoseSkeleton.toCanvasOffset(
        x: 1,
        y: 1,
        canvas: size,
      );
      expect(br, const Offset(200, 100));

      final mirrored = PoseSkeleton.toCanvasOffset(
        x: 0.25,
        y: 0.5,
        canvas: size,
        mirrorX: true,
      );
      expect(mirrored.dx, closeTo(150, 0.001));
      expect(mirrored.dy, closeTo(50, 0.001));
    });

    test('visibleEnough respects threshold', () {
      expect(PoseSkeleton.visibleEnough(0.5, 0.5), isTrue);
      expect(PoseSkeleton.visibleEnough(0.49, 0.5), isFalse);
    });

    test('highlightJoints for curl right arm is SEW chain', () {
      final j = PoseSkeleton.highlightJoints(rightArm: true);
      expect(
        j,
        {
          PoseLandmarkIndex.rightShoulder,
          PoseLandmarkIndex.rightElbow,
          PoseLandmarkIndex.rightWrist,
        },
      );
    });
  });

  group('VisionFocus E10', () {
    test('bicep_curl focus is elbow with arm landmarks', () {
      final f = VisionFocus.forExercise('bicep_curl');
      expect(f.primaryAngle, PrimaryAngleKind.elbow);
      expect(f.primaryLandmarks, isNotEmpty);
      expect(f.armChain(rightArm: true).length, 3);
      expect(f.armChain(rightArm: false).first, PoseLandmarkIndex.leftShoulder);
    });

    test('unknown exercise falls back to curl', () {
      expect(
        VisionFocus.forExercise('future_squat').primaryAngle,
        PrimaryAngleKind.elbow,
      );
    });
  });

  group('AngleFormClassifier E2', () {
    test('good inside ROM band', () {
      expect(
        AngleFormClassifier.classify(
          angleDegrees: 120,
          confidence: 0.9,
          angleUpThreshold: 90,
          angleDownThreshold: 160,
        ),
        AngleFormColor.good,
      );
    });

    test('poor when null angle or low conf', () {
      expect(
        AngleFormClassifier.classify(
          angleDegrees: null,
          confidence: 0.9,
          angleUpThreshold: 90,
          angleDownThreshold: 160,
        ),
        AngleFormColor.poor,
      );
      expect(
        AngleFormClassifier.classify(
          angleDegrees: 120,
          confidence: 0.1,
          angleUpThreshold: 90,
          angleDownThreshold: 160,
        ),
        AngleFormColor.poor,
      );
    });

    test('warning near band edge outside', () {
      expect(
        AngleFormClassifier.classify(
          angleDegrees: 80,
          confidence: 0.9,
          angleUpThreshold: 90,
          angleDownThreshold: 160,
        ),
        AngleFormColor.warning,
      );
    });
  });
}

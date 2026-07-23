/// Per-exercise vision focus maps (CV-07 E10).
///
/// Defines which landmarks / angle matter for skeleton highlight and form color.
/// Bicep curl is fully wired; other exercise IDs can be added without painter rewrites.
library;

import 'angle_calculator.dart';

/// Which joint angle is primary for form feedback.
enum PrimaryAngleKind {
  elbow,
  shoulder,
  knee,
}

/// Which arm side is preferred for highlight (when not auto-detected).
enum ArmSide {
  left,
  right,
  auto,
}

/// Semantic focus for camera skeleton + angle color (pure domain).
class VisionFocus {
  final PrimaryAngleKind primaryAngle;
  final List<int> primaryLandmarks;
  final ArmSide preferredArm;

  const VisionFocus({
    required this.primaryAngle,
    required this.primaryLandmarks,
    this.preferredArm = ArmSide.auto,
  });

  /// Bicep curl: shoulder–elbow–wrist (right preferred when both visible).
  static const VisionFocus bicepCurl = VisionFocus(
    primaryAngle: PrimaryAngleKind.elbow,
    primaryLandmarks: [
      PoseLandmarkIndex.rightShoulder,
      PoseLandmarkIndex.rightElbow,
      PoseLandmarkIndex.rightWrist,
    ],
    preferredArm: ArmSide.auto,
  );

  /// Resolve focus for a known exercise id; unknown → curl default.
  static VisionFocus forExercise(String exerciseId) {
    switch (exerciseId) {
      case 'bicep_curl':
      case kDefaultVisionExerciseId:
        return bicepCurl;
      default:
        return bicepCurl;
    }
  }

  /// Primary chain for [rightArm] (mirror of curl map).
  List<int> armChain({required bool rightArm}) {
    if (primaryAngle != PrimaryAngleKind.elbow) {
      return List<int>.from(primaryLandmarks);
    }
    if (rightArm) {
      return const [
        PoseLandmarkIndex.rightShoulder,
        PoseLandmarkIndex.rightElbow,
        PoseLandmarkIndex.rightWrist,
      ];
    }
    return const [
      PoseLandmarkIndex.leftShoulder,
      PoseLandmarkIndex.leftElbow,
      PoseLandmarkIndex.leftWrist,
    ];
  }
}

/// Default exercise id for vision when none selected.
const String kDefaultVisionExerciseId = 'bicep_curl';

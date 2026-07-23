/// Riverpod wiring for the optional Computer-Vision pipeline (CV-02).
///
/// IMU remains authoritative. Camera is off unless explicitly enabled.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/camera_pose_provider.dart';
import '../../domain/vision/vision_config.dart';

/// Live [CameraPoseProvider]. Dispose is handled by Riverpod.
///
/// Default config keeps [VisionConfig.enabled] true only for the provider
/// instance when the camera UI is opened; global default remains IMU-first.
final visionProvider = ChangeNotifierProvider<CameraPoseProvider>((ref) {
  // Riverpod disposes ChangeNotifiers automatically — do not double-dispose.
  return CameraPoseProvider(
    config: const VisionConfig(
      enabled: true,
      showSkeletonOverlay: true,
      cameraLens: 'back',
    ),
  );
});

/// Editable vision config for settings / future camera UI.
final visionConfigProvider = StateProvider<VisionConfig>((ref) {
  return const VisionConfig(); // default: camera disabled
});

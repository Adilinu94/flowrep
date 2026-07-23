import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Live camera preview (optional CV path). Safe when controller is null.
class CameraPreviewOverlay extends StatelessWidget {
  final CameraController? controller;
  final bool isDetecting;
  final String? error;
  final VoidCallback? onStart;
  final VoidCallback? onStop;

  const CameraPreviewOverlay({
    super.key,
    required this.controller,
    this.isDetecting = false,
    this.error,
    this.onStart,
    this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = controller != null && controller!.value.isInitialized;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: ready ? controller!.value.aspectRatio : 4 / 3,
            child: ready
                ? CameraPreview(controller!)
                : ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Center(
                      child: Text(
                        error ?? 'Kamera nicht aktiv',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isDetecting ? 'Pose-Erkennung läuft' : 'Pose pausiert',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (!isDetecting && onStart != null)
                  FilledButton.tonal(
                    onPressed: onStart,
                    child: const Text('Start'),
                  ),
                if (isDetecting && onStop != null)
                  FilledButton.tonal(
                    onPressed: onStop,
                    child: const Text('Stop'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

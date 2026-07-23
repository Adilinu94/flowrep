/// Framed guide when pose tracking is lost (CV-07 E4).
library;

import 'package:flutter/material.dart';

/// Semi-transparent frame + copy: place upper body in view.
class FramedGuideOverlay extends StatelessWidget {
  final bool visible;
  final String message;

  const FramedGuideOverlay({
    super.key,
    required this.visible,
    this.message = 'Oberkörper mittig, Arme im Bild',
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _FramePainter(color: theme.colorScheme.primary)),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  final Color color;

  _FramePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final inset = size.shortestSide * 0.12;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - 2 * inset,
      size.height - 2 * inset,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRRect(rrect, paint);

    const tick = 18.0;
    final p = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    void corner(Offset o, double dx, double dy) {
      canvas.drawLine(o, o + Offset(dx * tick, 0), p);
      canvas.drawLine(o, o + Offset(0, dy * tick), p);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(covariant _FramePainter oldDelegate) =>
      oldDelegate.color != color;
}

import 'package:flutter/material.dart';

import '../../domain/models/workout_models.dart';

/// Sparkline of rep peaks for a set (Doc 15 FR-B3).
class RepTimeline extends StatelessWidget {
  const RepTimeline({
    super.key,
    required this.reps,
    this.height = 48,
  });

  final List<Rep> reps;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (reps.isEmpty) {
      return const SizedBox.shrink();
    }
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(
        painter: _RepTimelinePainter(reps: reps, color: color),
      ),
    );
  }
}

class _RepTimelinePainter extends CustomPainter {
  _RepTimelinePainter({required this.reps, required this.color});

  final List<Rep> reps;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (reps.isEmpty) return;
    final maxPeak =
        reps.map((r) => r.peakMagnitude).fold<double>(0, (a, b) => a > b ? a : b);
    final peakScale = maxPeak <= 0 ? 1.0 : maxPeak;

    final axis = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 2),
      Offset(size.width, size.height - 2),
      axis,
    );

    final barPaint = Paint()..color = color;
    final n = reps.length;
    final slot = size.width / n;
    final barW = (slot * 0.55).clamp(2.0, 16.0);
    for (var i = 0; i < n; i++) {
      final h = (reps[i].peakMagnitude / peakScale) * (size.height - 8);
      final x = slot * i + (slot - barW) / 2;
      final y = size.height - 2 - h;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, h),
          const Radius.circular(2),
        ),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RepTimelinePainter oldDelegate) =>
      oldDelegate.reps != reps || oldDelegate.color != color;
}

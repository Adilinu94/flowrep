import 'package:flutter/material.dart';

/// Farbiger Qualitäts-Ring (SPEC TEIL 6, §6.3).
///
/// Zeigt die Qualität der letzten Wiederholung als kreisförmige Anzeige.
class QualityIndicator extends StatelessWidget {
  const QualityIndicator({
    super.key,
    required this.score,
    this.size = 48,
  });

  /// Quality-Score 0.0–1.0
  final double score;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: score.clamp(0.0, 1.0),
              strokeWidth: 4,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(_color),
            ),
          ),
          Text(
            '${(score * 100).toInt()}%',
            style: TextStyle(
              fontSize: size * 0.22,
              fontWeight: FontWeight.bold,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }

  Color get _color {
    if (score >= 0.8) return Colors.green;
    if (score >= 0.5) return Colors.orange;
    return Colors.red;
  }
}

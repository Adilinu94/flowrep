import 'package:flutter/material.dart';

/// Große Rep-Zahl mit optionalem Quality-Ring (SPEC TEIL 6, §6.3).
class RepCounterDisplay extends StatelessWidget {
  const RepCounterDisplay({
    super.key,
    required this.repCount,
    this.qualityScore,
  });

  final int repCount;
  final double? qualityScore;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            if (qualityScore != null)
              SizedBox(
                width: 160,
                height: 160,
                child: CircularProgressIndicator(
                  value: qualityScore!.clamp(0.0, 1.0),
                  strokeWidth: 6,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _qualityColor(qualityScore!),
                  ),
                ),
              ),
            Text(
              '$repCount',
              style: const TextStyle(
                fontSize: 96,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Wiederholungen',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Color _qualityColor(double score) {
    if (score >= 0.8) return Colors.green;
    if (score >= 0.5) return Colors.orange;
    return Colors.red;
  }
}

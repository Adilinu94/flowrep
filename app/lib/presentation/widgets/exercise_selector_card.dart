import 'package:flutter/material.dart';

import '../../domain/exercises/exercise_registry.dart';

/// Übungsauswahl-Karte (V1: nur Bizeps-Curl, Architektur für V2 offen).
///
/// Zeigt alle verfügbaren Übungen aus dem Katalog als auswählbare Chips.
/// Kalibrierte Übungen erhalten einen grünen Haken.
class ExerciseSelectorCard extends StatelessWidget {
  final String selectedExerciseId;
  final bool hasCalibration;
  final ValueChanged<String> onExerciseSelected;

  const ExerciseSelectorCard({
    super.key,
    required this.selectedExerciseId,
    required this.hasCalibration,
    required this.onExerciseSelected,
  });

  @override
  Widget build(BuildContext context) {
    final exercises = kExerciseCatalog.values.toList();
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fitness_center, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Übung',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: exercises.map((ex) {
                final isSelected = ex.id == selectedExerciseId;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(ex.displayName),
                      if (isSelected && hasCalibration) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.check_circle, size: 14, color: Colors.green),
                      ],
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (_) => onExerciseSelected(ex.id),
                  selectedColor: theme.colorScheme.primaryContainer,
                  avatar: isSelected
                      ? null
                      : const Icon(Icons.fitness_center, size: 14),
                );
              }).toList(),
            ),
            // Beschreibung der ausgewählten Übung
            Builder(builder: (context) {
              final meta = kExerciseCatalog[selectedExerciseId];
              if (meta == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  meta.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

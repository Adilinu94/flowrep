import 'package:flutter/material.dart';

/// Zeigt den letzten abgeschlossenen Satz an (SPEC TEIL 6, §6.3).
class SetHistoryCard extends StatelessWidget {
  const SetHistoryCard({
    super.key,
    required this.lastSetCount,
  });

  final int? lastSetCount;

  @override
  Widget build(BuildContext context) {
    if (lastSetCount == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              'Letzter Satz: $lastSetCount Wiederholungen',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

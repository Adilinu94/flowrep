import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/workout_models.dart';
import '../providers/repository_provider.dart';

/// History Screen (SPEC Phase 5.3): zeigt vergangene Workout-Sessions.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(workoutRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Verlauf')),
      body: FutureBuilder<List<WorkoutSession>>(
        future: repository.getHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fehler: ${snapshot.error}'));
          }
          final sessions = snapshot.data ?? [];
          if (sessions.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Noch keine Workouts aufgezeichnet.'),
                ],
              ),
            );
          }
          // Neueste zuerst
          sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            itemBuilder: (context, index) => _SessionCard(session: sessions[index]),
          );
        },
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final totalReps =
        session.sets.fold<int>(0, (sum, s) => sum + s.effectiveReps);
    final dateStr = _formatDate(session.startedAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            '${session.sets.length}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(dateStr),
        subtitle: Text(
          '${session.sets.length} Sätze · $totalReps Wiederholungen',
        ),
        trailing: session.endedAt != null
            ? Text(
                _formatDuration(
                    session.endedAt!.difference(session.startedAt)),
                style: Theme.of(context).textTheme.bodySmall,
              )
            : null,
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Heute ${_time(dt)}';
    if (diff.inDays == 1) return 'Gestern ${_time(dt)}';
    return '${dt.day}.${dt.month}.${dt.year} ${_time(dt)}';
  }

  String _time(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _formatDuration(Duration d) {
    if (d.inMinutes < 1) return '<1 min';
    return '${d.inMinutes} min';
  }
}

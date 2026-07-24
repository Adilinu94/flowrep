import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/metrics/velocity_metrics.dart';
import '../../domain/models/workout_models.dart';
import '../providers/repository_provider.dart';

/// History Screen (SPEC Phase 5.3) + trends (Doc 15 FR-B5).
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
          final volumeSeries = _volumeByDay(sessions);
          final lossSeries = _meanLossBySession(sessions);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Volumen (Sätze×Reps) — letzte Sessions',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: CustomPaint(
                  painter: _TrendPainter(
                    values: volumeSeries,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              if (lossSeries.any((e) => e != null)) ...[
                const SizedBox(height: 16),
                Text('Mean Velocity-Loss % (relativ)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SizedBox(
                  height: 80,
                  child: CustomPaint(
                    painter: _TrendPainter(
                      values: lossSeries
                          .map((e) => e ?? 0.0)
                          .toList(growable: false),
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text('Sessions', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...sessions.map((s) => _SessionCard(session: s)),
            ],
          );
        },
      ),
    );
  }

  static List<double> _volumeByDay(List<WorkoutSession> sessions) {
    // Chronological oldest→newest for chart; take last 14.
    final chrono = List<WorkoutSession>.from(sessions)
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final vols = chrono
        .map((s) {
          final reps = s.sets.fold<int>(0, (a, e) => a + e.effectiveReps);
          return reps.toDouble();
        })
        .toList();
    if (vols.length > 14) return vols.sublist(vols.length - 14);
    return vols;
  }

  static List<double?> _meanLossBySession(List<WorkoutSession> sessions) {
    final chrono = List<WorkoutSession>.from(sessions)
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final losses = chrono.map((s) {
      final perSet = s.sets
          .map((set) => VelocityMetrics.setVelocityLossPct(set.reps))
          .whereType<double>()
          .toList();
      if (perSet.isEmpty) return null;
      return perSet.reduce((a, b) => a + b) / perSet.length;
    }).toList();
    if (losses.length > 14) return losses.sublist(losses.length - 14);
    return losses;
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
    final losses = session.sets
        .map((set) => VelocityMetrics.setVelocityLossPct(set.reps))
        .whereType<double>()
        .toList();
    final meanLoss = losses.isEmpty
        ? null
        : losses.reduce((a, b) => a + b) / losses.length;

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
          meanLoss != null
              ? '${session.sets.length} Sätze · $totalReps Wdh. · '
                  'Loss ${meanLoss.toStringAsFixed(0)} %'
              : '${session.sets.length} Sätze · $totalReps Wiederholungen',
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

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.fold<double>(0, (a, b) => a > b ? a : b);
    final scale = maxV <= 0 ? 1.0 : maxV;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final y = size.height - (values[i] / scale) * (size.height - 8) - 4;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
    final fill = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fillPath, fill);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

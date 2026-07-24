import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/metrics/velocity_metrics.dart';
import '../../domain/models/workout_models.dart';

/// Local-first session export (Doc 15 FR-B2 / FR-B15).
///
/// Privacy: no auto-upload; user explicitly shares via OS share sheet.
/// Contents: sessions, sets, reps (peak), corrections if present on sets.
class ExportService {
  /// Builds a privacy-notice string shown before export.
  static const privacyNotice =
      'Export enthält lokal gespeicherte Trainingsdaten: '
      'Zeitstempel, Übungs-IDs, gezählte/korrigierte Reps, '
      'Peak-Velocity (relativ). Kein automatischer Upload.';

  static String sessionsToJson(List<WorkoutSession> sessions) {
    final payload = {
      'format': 'flowrep-export-v1',
      'exportedAt': DateTime.now().toIso8601String(),
      'privacy': privacyNotice,
      'sessions': sessions.map(_sessionJson).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static String sessionsToCsv(List<WorkoutSession> sessions) {
    final buf = StringBuffer();
    buf.writeln(
      'sessionId,sessionStartedAt,sessionEndedAt,setId,exerciseId,'
      'countedReps,correctedReps,effectiveReps,repIndex,repTimestamp,'
      'peakMagnitude,setVelocityLossPct',
    );
    for (final session in sessions) {
      for (final set in session.sets) {
        final loss = VelocityMetrics.setVelocityLossPct(set.reps);
        if (set.reps.isEmpty) {
          buf.writeln(
            '${_csv(session.id)},${_csv(session.startedAt.toIso8601String())},'
            '${_csv(session.endedAt?.toIso8601String() ?? '')},'
            '${_csv(set.id)},${_csv(set.exerciseId)},'
            '${set.countedReps},${set.correctedReps ?? ''},'
            '${set.effectiveReps},,,,${loss?.toStringAsFixed(2) ?? ''}',
          );
          continue;
        }
        for (var i = 0; i < set.reps.length; i++) {
          final rep = set.reps[i];
          buf.writeln(
            '${_csv(session.id)},${_csv(session.startedAt.toIso8601String())},'
            '${_csv(session.endedAt?.toIso8601String() ?? '')},'
            '${_csv(set.id)},${_csv(set.exerciseId)},'
            '${set.countedReps},${set.correctedReps ?? ''},'
            '${set.effectiveReps},${i + 1},'
            '${_csv(rep.timestamp.toIso8601String())},'
            '${rep.peakMagnitude.toStringAsFixed(4)},'
            '${loss?.toStringAsFixed(2) ?? ''}',
          );
        }
      }
    }
    return buf.toString();
  }

  /// Writes JSON + CSV to app documents and opens the share sheet for both.
  static Future<ExportResult> exportAndShare(
    List<WorkoutSession> sessions, {
    bool asJson = true,
    bool asCsv = true,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final files = <XFile>[];
    String? jsonPath;
    String? csvPath;

    if (asJson) {
      final path = p.join(dir.path, 'flowrep_export_$stamp.json');
      await File(path).writeAsString(sessionsToJson(sessions));
      jsonPath = path;
      files.add(XFile(path, mimeType: 'application/json'));
    }
    if (asCsv) {
      final path = p.join(dir.path, 'flowrep_export_$stamp.csv');
      await File(path).writeAsString(sessionsToCsv(sessions));
      csvPath = path;
      files.add(XFile(path, mimeType: 'text/csv'));
    }

    if (files.isNotEmpty) {
      await SharePlus.instance.share(
        ShareParams(
          files: files,
          subject: 'FlowRep Trainings-Export',
          text: privacyNotice,
        ),
      );
    }

    return ExportResult(jsonPath: jsonPath, csvPath: csvPath);
  }

  static Map<String, dynamic> _sessionJson(WorkoutSession s) => {
        'id': s.id,
        'startedAt': s.startedAt.toIso8601String(),
        'endedAt': s.endedAt?.toIso8601String(),
        'sets': s.sets.map((set) {
          final loss = VelocityMetrics.setVelocityLossPct(set.reps);
          return {
            'id': set.id,
            'exerciseId': set.exerciseId,
            'countedReps': set.countedReps,
            'correctedReps': set.correctedReps,
            'effectiveReps': set.effectiveReps,
            'endedAt': set.endedAt.toIso8601String(),
            'velocityLossPct': loss,
            'meanPeakVelocity': VelocityMetrics.meanPeak(set.reps),
            'reps': set.reps
                .map(
                  (r) => {
                    'timestamp': r.timestamp.toIso8601String(),
                    'peakMagnitude': r.peakMagnitude,
                  },
                )
                .toList(),
          };
        }).toList(),
      };

  static String _csv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

class ExportResult {
  final String? jsonPath;
  final String? csvPath;

  const ExportResult({this.jsonPath, this.csvPath});
}

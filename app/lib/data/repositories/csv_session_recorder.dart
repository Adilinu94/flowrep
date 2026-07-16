import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/signal_processor.dart';
import '../../domain/workout_engine.dart';

/// Records raw [SensorSample]s (plus the same derived combined signal the
/// production pipeline computes) to a CSV file for offline DSP analysis
/// in Python. See docs/Umbauplan Flowrep/07_STRATEGISCHES_ARBEITSDOKUMENT_
/// DATENAKQUISITION.md (why) and 08_CSV_AUFNAHME_IMPLEMENTIERUNGSPLAN.md
/// (implementation decisions - storage location, column format).
///
/// Deliberately independent of [WorkoutEngine]/[SignalProcessor]: it is
/// meant to be wired as a *second*, independent listener on the same
/// broadcast `ISensorProvider.samples` stream the engine already listens
/// to, with its own private [SignalProcessor] instance (same defaults as
/// production - see [SignalProcessor]'s constructor). It never calls into
/// or mutates the engine, so it cannot affect rep-counting behaviour.
///
/// Column format (deviates from Dokument 07 in two ways, both documented
/// in 08_...: no `filtered_accel_x/y/z`, since the currently deployed
/// pipeline never computes per-axis filtered acceleration; an added
/// `workout_state` column for easier offline filtering):
/// `timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,dyn_magnitude,workout_state`
/// `timestamp_ms` is milliseconds *since recording start* (not epoch), to
/// match the time convention already used by tools/workout_engine_simulation.py
/// and tools/dsp_lab_phase2_extended.py (t starts at 0).
class CsvSessionRecorder {
  /// [getBaseDirectory] defaults to [getExternalStorageDirectory] (real
  /// Android app-specific external storage). Overridable so tests can
  /// inject a temp directory instead of going through path_provider's
  /// platform channel, which isn't available in plain `dart test` runs.
  CsvSessionRecorder({Future<Directory?> Function()? getBaseDirectory})
      : _getBaseDirectory = getBaseDirectory ?? getExternalStorageDirectory;

  final Future<Directory?> Function() _getBaseDirectory;

  static const csvHeader =
      'timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,dyn_magnitude,workout_state';

  final SignalProcessor _signalProcessor = SignalProcessor();
  final List<String> _rows = [];
  DateTime? _sessionStart;
  WorkoutState _currentState = WorkoutState.idle;

  bool get isRecording => _sessionStart != null;
  int get sampleCount => _rows.length;

  /// Feed the latest known engine state, so newly recorded rows carry it.
  /// Best-effort: engine events and sensor samples are two independent
  /// streams, so this is "most recently known state", not a guaranteed
  /// per-sample match - good enough for offline filtering by phase.
  void onEngineStateChanged(WorkoutState state) {
    _currentState = state;
  }

  void start() {
    _rows.clear();
    _signalProcessor.reset();
    _currentState = WorkoutState.idle;
    _sessionStart = DateTime.now();
  }

  /// Wire this as a listener on `ISensorProvider.samples`. No-op while not
  /// recording, so it is safe to keep the subscription alive permanently.
  void onSample(SensorSample s) {
    final start = _sessionStart;
    if (start == null) return;
    final combined = _signalProcessor.process(s);
    final elapsedMs = s.timestamp.difference(start).inMilliseconds;
    _rows.add(
      '$elapsedMs,'
      '${s.ax.toStringAsFixed(4)},${s.ay.toStringAsFixed(4)},${s.az.toStringAsFixed(4)},'
      '${s.gx.toStringAsFixed(4)},${s.gy.toStringAsFixed(4)},${s.gz.toStringAsFixed(4)},'
      '${combined.toStringAsFixed(4)},${_currentState.name}',
    );
  }

  /// Stops recording and writes the buffered rows to a CSV file under
  /// app-specific external storage (`/Android/data/<package>/files/recordings/`
  /// - no runtime permission required on current Android, still reachable
  /// via USB/Dateimanager; see 08_..., Abschnitt 3). Returns the written
  /// file, or null if recording was already stopped or nothing was
  /// captured (e.g. stopped immediately after starting).
  Future<File?> stop(String exerciseId) async {
    final start = _sessionStart;
    if (start == null) return null;
    final rowsSnapshot = List<String>.from(_rows);
    _sessionStart = null;
    if (rowsSnapshot.isEmpty) return null;

    final baseDir = await _getBaseDirectory();
    if (baseDir == null) return null;
    final recordingsDir = Directory('${baseDir.path}/recordings');
    await recordingsDir.create(recursive: true);

    final safeTimestamp = start.toIso8601String().replaceAll(RegExp('[:.]'), '-');
    final file = File('${recordingsDir.path}/${safeTimestamp}_$exerciseId.csv');

    final buffer = StringBuffer()..writeln(csvHeader);
    for (final row in rowsSnapshot) {
      buffer.writeln(row);
    }
    await file.writeAsString(buffer.toString());
    return file;
  }

  void dispose() {
    _rows.clear();
    _sessionStart = null;
  }
}

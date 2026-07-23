/// Opt-in local landmark debug recorder (CV-07 E9).
///
/// Default off. No network. File sink under app documents (or injected dir).
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../providers/camera_pose_provider.dart';

/// Sink for recorded lines (file or memory).
abstract class LandmarkRecordSink {
  void writeLine(String line);
  void close();

  /// Optional path for UI / tests (null for memory).
  String? get path => null;
}

/// In-memory sink for unit tests.
class MemoryLandmarkSink implements LandmarkRecordSink {
  final List<String> lines = [];

  @override
  void writeLine(String line) => lines.add(line);

  @override
  void close() {}

  @override
  String? get path => null;
}

/// Appends CSV lines to a local file (grows while recording).
///
/// Uses synchronous append+flush so the file length grows immediately
/// (reliable for mid-session reads and unit tests).
class FileLandmarkSink implements LandmarkRecordSink {
  final File file;

  FileLandmarkSink(this.file);

  @override
  String? get path => file.path;

  @override
  void writeLine(String line) {
    file.writeAsStringSync(
      '$line\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  @override
  void close() {
    // Nothing to close for sync path; method kept for sink interface.
  }
}

/// Resolves a timestamped CSV path under app documents (or [getBaseDirectory]).
class LandmarkFilePaths {
  /// [getBaseDirectory] injectable for tests (no path_provider channel).
  static Future<File> createSessionFile({
    Future<Directory> Function()? getBaseDirectory,
    DateTime? now,
  }) async {
    final baseFn = getBaseDirectory ?? getApplicationDocumentsDirectory;
    final base = await baseFn();
    final dir = Directory('${base.path}${Platform.pathSeparator}landmark_logs');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final ts = (now ?? DateTime.now()).toIso8601String().replaceAll(':', '-');
    final path =
        '${dir.path}${Platform.pathSeparator}landmarks_$ts.csv';
    return File(path);
  }
}

/// Records throttled pose landmarks as CSV lines.
class LandmarkSessionRecorder {
  final LandmarkRecordSink sink;
  final int minIntervalMs;
  final bool enabled;

  int? _lastWriteMs;
  bool _headerWritten = false;
  int _framesWritten = 0;

  LandmarkSessionRecorder({
    required this.sink,
    this.enabled = false,
    this.minIntervalMs = 100,
  });

  int get framesWritten => _framesWritten;

  String? get outputPath => sink.path;

  /// CSV header (stable schema for offline tools).
  static String get csvHeader {
    final cols = <String>['timestampMs', 'confidence'];
    for (var i = 0; i < 33; i++) {
      cols.add('x$i');
      cols.add('y$i');
      cols.add('c$i');
    }
    return cols.join(',');
  }

  /// Format one frame (shipped path used by tests).
  static String formatFrame({
    required int timestampMs,
    required double meanConfidence,
    required List<FlowPoseLandmark> landmarks,
  }) {
    final parts = <String>[
      '$timestampMs',
      meanConfidence.toStringAsFixed(4),
    ];
    for (var i = 0; i < 33; i++) {
      if (i < landmarks.length) {
        final lm = landmarks[i];
        parts.add(lm.x.toStringAsFixed(5));
        parts.add(lm.y.toStringAsFixed(5));
        parts.add(lm.confidence.toStringAsFixed(4));
      } else {
        parts.addAll(['0', '0', '0']);
      }
    }
    return parts.join(',');
  }

  /// Record if enabled and throttle allows.
  bool maybeRecord({
    required int timestampMs,
    required double meanConfidence,
    required List<FlowPoseLandmark> landmarks,
  }) {
    if (!enabled) return false;
    if (_lastWriteMs != null &&
        timestampMs - _lastWriteMs! < minIntervalMs) {
      return false;
    }
    if (!_headerWritten) {
      sink.writeLine(csvHeader);
      _headerWritten = true;
    }
    sink.writeLine(
      formatFrame(
        timestampMs: timestampMs,
        meanConfidence: meanConfidence,
        landmarks: landmarks,
      ),
    );
    _lastWriteMs = timestampMs;
    _framesWritten++;
    return true;
  }

  void close() => sink.close();
}

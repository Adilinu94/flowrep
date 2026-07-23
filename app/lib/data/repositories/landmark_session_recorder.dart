/// Opt-in local landmark debug recorder (CV-07 E9).
///
/// Default off. No network. Pure formatting + in-memory sink for tests.
library;

import '../providers/camera_pose_provider.dart';

/// Sink for recorded lines (file or memory).
abstract class LandmarkRecordSink {
  void writeLine(String line);
  void close();
}

/// In-memory sink for unit tests.
class MemoryLandmarkSink implements LandmarkRecordSink {
  final List<String> lines = [];

  @override
  void writeLine(String line) => lines.add(line);

  @override
  void close() {}
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

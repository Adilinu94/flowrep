import 'dart:convert';

/// Unified shadow-vs-live report line (Doc 15 FR-B12).
///
/// Intended for local JSONL logs / Dev overlay — never uploaded.
class ShadowReportLine {
  final DateTime timestamp;
  final String source; // e.g. magnitude, new_pipeline, ml_suggest
  final int liveReps;
  final int shadowReps;
  final double? liveSignal;
  final double? shadowSignal;
  final String? note;

  const ShadowReportLine({
    required this.timestamp,
    required this.source,
    required this.liveReps,
    required this.shadowReps,
    this.liveSignal,
    this.shadowSignal,
    this.note,
  });

  int get delta => shadowReps - liveReps;

  Map<String, dynamic> toJson() => {
        'ts': timestamp.toIso8601String(),
        'source': source,
        'liveReps': liveReps,
        'shadowReps': shadowReps,
        'delta': delta,
        if (liveSignal != null) 'liveSignal': liveSignal,
        if (shadowSignal != null) 'shadowSignal': shadowSignal,
        if (note != null) 'note': note,
      };

  String toJsonLine() => jsonEncode(toJson());

  factory ShadowReportLine.fromJson(Map<String, dynamic> json) {
    return ShadowReportLine(
      timestamp: DateTime.parse(json['ts'] as String),
      source: json['source'] as String,
      liveReps: json['liveReps'] as int,
      shadowReps: json['shadowReps'] as int,
      liveSignal: (json['liveSignal'] as num?)?.toDouble(),
      shadowSignal: (json['shadowSignal'] as num?)?.toDouble(),
      note: json['note'] as String?,
    );
  }
}

/// In-memory ring of recent shadow lines for the diagnose overlay.
class ShadowReportBuffer {
  ShadowReportBuffer({this.capacity = 200});

  final int capacity;
  final List<ShadowReportLine> _lines = <ShadowReportLine>[];

  List<ShadowReportLine> get lines => List.unmodifiable(_lines);

  void add(ShadowReportLine line) {
    _lines.add(line);
    if (_lines.length > capacity) {
      _lines.removeRange(0, _lines.length - capacity);
    }
  }

  void clear() => _lines.clear();

  String exportJsonl() => _lines.map((e) => e.toJsonLine()).join('\n');
}

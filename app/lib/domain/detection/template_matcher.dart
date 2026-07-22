/// Template-Matching via Normalisierte Kreuzkorrelation (NCC).
///
/// Vergleicht das Signal-Fenster eines erkannten Peaks mit einem
/// gelernten Rep-Template. NCC ∈ [-1, 1], wobei 1 = perfekte Übereinstimmung.
///
/// Algorithmus:
///   1. Resample: Window auf TEMPLATE_LENGTH (64) Samples interpolieren
///   2. Normalize: Mittelwert entfernen, durch StdDev teilen
///   3. CrossCorrelate: NCC = Σ(a[i]*b[i]) / (N * stdA * stdB)
///
/// Komplexität: O(N) pro Match — geeignet für Echtzeit bei 50 Hz.
library;

import 'dart:math' as math;

/// Ergebnis eines Template-Matches.
class MatchResult {
  /// NCC-Wert ∈ [-1, 1]. 1 = perfekte Übereinstimmung.
  final double correlation;

  /// true, wenn correlation >= threshold (Standard: 0.7).
  final bool accepted;

  /// true, wenn kein Template vorhanden war (Match nicht möglich).
  final bool noTemplate;

  const MatchResult({
    required this.correlation,
    required this.accepted,
    this.noTemplate = false,
  });

  @override
  String toString() =>
      'MatchResult(ncc=${correlation.toStringAsFixed(3)}, accepted=$accepted)';
}

/// Template-Matcher für Rep-Erkennung.
///
/// Verwendung:
/// ```dart
/// final matcher = TemplateMatcher();
/// matcher.setTemplate(learnedTemplate); // 64 Samples
/// final result = matcher.match(peakWindow);
/// if (result.accepted) { /* Rep bestätigt */ }
/// ```
class TemplateMatcher {
  /// Länge des Templates (fest, 64 Samples = 1.28s bei 50 Hz).
  static const int templateLength = 64;

  /// Akzeptanz-Schwelle für NCC (0.7 = 70% Übereinstimmung).
  final double threshold;

  List<double>? _template; // Normalisiertes Template (Mittelwert=0, StdDev=1)

  /// Erstellt den TemplateMatcher.
  ///
  /// [threshold]: NCC-Schwelle für Akzeptanz (Standard: 0.7).
  TemplateMatcher({this.threshold = 0.7});

  /// Setzt das gelernte Rep-Template.
  ///
  /// [rawTemplate]: Roh-Signalverlauf eines typischen Reps (beliebige Länge).
  ///   Wird intern auf [templateLength] Samples resampelt und normalisiert.
  void setTemplate(List<double> rawTemplate) {
    if (rawTemplate.length < 4) {
      // Zu kurz für sinnvolles Resampling
      _template = null;
      return;
    }
    final resampled = _resample(rawTemplate, templateLength);
    _template = _normalize(resampled);
  }

  /// Vergleicht ein Peak-Window mit dem Template.
  ///
  /// [window]: Signalverlauf der Excursion (aus PeakEvent.window).
  /// Rückgabe: [MatchResult] mit NCC-Wert und Akzeptanz-Entscheidung.
  MatchResult match(List<double> window) {
    // Fehlerfall 1: Kein Template vorhanden
    if (_template == null) {
      return const MatchResult(correlation: 0.0, accepted: true, noTemplate: true);
    }

    // Fehlerfall 2: Window zu kurz
    if (window.length < 4) {
      return const MatchResult(correlation: 0.0, accepted: false);
    }

    // Resample auf Template-Länge
    final resampled = _resample(window, templateLength);

    // Normalisieren
    final normalized = _normalize(resampled);

    // Fehlerfall 3: NaN im Ergebnis
    if (normalized == null) {
      return const MatchResult(correlation: 0.0, accepted: false);
    }

    // NCC berechnen
    final ncc = _crossCorrelate(_template!, normalized);

    return MatchResult(
      correlation: ncc,
      accepted: ncc >= threshold,
    );
  }

  /// true, wenn ein Template gesetzt ist.
  bool get hasTemplate => _template != null;

  /// Entfernt das Template (z.B. bei Übungswechsel).
  void clearTemplate() {
    _template = null;
  }

  /// Lineares Resampling auf [targetLength] Samples.
  ///
  /// Interpoliert zwischen den vorhandenen Samples.
  static List<double> _resample(List<double> input, int targetLength) {
    if (input.length == targetLength) return List<double>.from(input);

    final result = List<double>.filled(targetLength, 0.0);
    final ratio = (input.length - 1) / (targetLength - 1);

    for (int i = 0; i < targetLength; i++) {
      final srcPos = i * ratio;
      final srcIdx = srcPos.floor();
      final frac = srcPos - srcIdx;

      if (srcIdx >= input.length - 1) {
        result[i] = input[input.length - 1];
      } else {
        result[i] = input[srcIdx] * (1.0 - frac) + input[srcIdx + 1] * frac;
      }
    }
    return result;
  }

  /// Normalisiert ein Signal: Mittelwert entfernen, durch StdDev teilen.
  ///
  /// Gibt null zurück wenn StdDev ≈ 0 (konstantes Signal).
  static List<double>? _normalize(List<double> input) {
    final n = input.length;
    if (n == 0) return null;

    // Mittelwert
    var sum = 0.0;
    for (final v in input) {
      sum += v;
    }
    final mean = sum / n;

    // StdDev
    var variance = 0.0;
    for (final v in input) {
      final d = v - mean;
      variance += d * d;
    }
    variance /= n;
    final std = math.sqrt(variance);

    // Fehlerfall: konstantes Signal (StdDev ≈ 0)
    if (std < 1e-10) return null;

    // Normalisieren
    final result = List<double>.filled(n, 0.0);
    for (int i = 0; i < n; i++) {
      result[i] = (input[i] - mean) / std;
    }
    return result;
  }

  /// Berechnet die normalisierte Kreuzkorrelation zwischen zwei
  /// normalisierten Signalen gleicher Länge.
  ///
  /// NCC = Σ(a[i] * b[i]) / N
  /// (beide Signale haben bereits Mean=0, StdDev=1)
  static double _crossCorrelate(List<double> a, List<double> b) {
    final n = math.min(a.length, b.length);
    if (n == 0) return 0.0;

    var sum = 0.0;
    for (int i = 0; i < n; i++) {
      sum += a[i] * b[i];
    }
    final ncc = sum / n;

    // Clamp auf [-1, 1] (numerische Sicherheit)
    return ncc.clamp(-1.0, 1.0);
  }
}

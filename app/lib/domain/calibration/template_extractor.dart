/// TemplateExtractor: Extrahiert ein Rep-Template aus Kalibrierungs-Reps.
///
/// Algorithmus (SPEC 4.2):
///   1. Alle validierten Reps aus der Kalibrierung sammeln (PeakEvent.window)
///   2. Jede Rep auf 64 Samples resamplen (lineare Interpolation)
///   3. Jede Rep normalisieren: (x - mean) / std
///   4. Median über alle Reps bilden (robust gegen Ausreißer)
///   5. Ergebnis: repTemplate[0..63]
///
/// Das Template wird im ExerciseProfile gespeichert und vom TemplateMatcher
/// für die NCC-basierte Rep-Validierung verwendet.
library;

import 'dart:math' as math;

/// Extrahiert ein Rep-Template aus mehreren Kalibrierungs-Reps.
///
/// Verwendung:
/// ```dart
/// final windows = [rep1Window, rep2Window, rep3Window];
/// final template = TemplateExtractor.extract(windows);
/// if (template != null) {
///   engine.setTemplate(template);
/// }
/// ```
class TemplateExtractor {
  /// Länge des Templates (fest, 64 Samples = 1.28s bei 50 Hz).
  static const int templateLength = 64;

  /// Minimale Anzahl Reps für ein gültiges Template.
  static const int minReps = 2;

  /// Extrahiert ein Template aus mehreren Rep-Windows.
  ///
  /// [windows]: Liste von PeakEvent.window (beliebige Länge pro Rep).
  /// Rückgabe: Normalisiertes Template (64 Samples) oder null wenn zu wenige Reps.
  static List<double>? extract(List<List<double>> windows) {
    if (windows.length < minReps) return null;

    // Schritt 1+2: Resamplen auf templateLength
    final resampled = windows
        .map((w) => resample(w, templateLength))
        .toList();

    // Schritt 3: Jede Rep normalisieren
    final normalized = resampled.map((r) => normalize(r)).toList();

    // Schritt 4: Median über alle Reps (robust gegen Ausreißer)
    final template = List<double>.generate(templateLength, (i) {
      final values = normalized.map((n) => n[i]).toList()..sort();
      return _median(values);
    });

    // Schritt 5: Finale Normalisierung (Mittelwert 0, Std 1)
    return normalize(template);
  }

  /// Resampelt ein Signal auf [targetLength] Samples (lineare Interpolation).
  ///
  /// [input]: Eingabesignal (beliebige Länge >= 2).
  /// [targetLength]: Ziellänge.
  /// Rückgabe: Resampeltes Signal der Länge [targetLength].
  static List<double> resample(List<double> input, int targetLength) {
    if (input.length == targetLength) return List.from(input);
    if (input.length < 2) {
      // Zu kurz: mit letztem Wert auffüllen
      return List.filled(targetLength, input.isEmpty ? 0.0 : input[0]);
    }

    final result = List<double>.filled(targetLength, 0.0);
    final ratio = (input.length - 1) / (targetLength - 1);

    for (int i = 0; i < targetLength; i++) {
      final srcIndex = i * ratio;
      final lower = srcIndex.floor();
      final upper = srcIndex.ceil();
      final frac = srcIndex - lower;

      if (lower == upper || upper >= input.length) {
        result[i] = input[lower.clamp(0, input.length - 1)];
      } else {
        result[i] = input[lower] * (1.0 - frac) + input[upper] * frac;
      }
    }

    return result;
  }

  /// Normalisiert ein Signal: (x - mean) / std.
  ///
  /// Bei std == 0 (konstantes Signal): gibt Null-Vektor zurück.
  static List<double> normalize(List<double> input) {
    if (input.isEmpty) return [];

    final mean = input.reduce((a, b) => a + b) / input.length;
    final variance =
        input.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
            input.length;
    final std = math.sqrt(variance);

    if (std < 1e-10) {
      return List.filled(input.length, 0.0);
    }

    return input.map((x) => (x - mean) / std).toList();
  }

  /// Berechnet den Median einer sortierten Liste.
  static double _median(List<double> sorted) {
    if (sorted.isEmpty) return 0.0;
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[mid];
    }
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }
}

/// Signalverarbeitungskette: Roh-Gyro → verarbeitetes Frame.
///
/// Verarbeitungsreihenfolge (LD-7):
///   1. GpProjection: 3D-Gyro → signiertes 1D-Signal (g_p)
///   2. Butterworth: Bandpass 0.1–5 Hz (entfernt Drift + Rauschen)
///   3. OneEuro: Adaptive Glättung (reduziert Jitter bei langsamer Bewegung)
///   4. Envelope: Hüllkurve aus filteredGp (für Diagnose/Qualität)
///
/// Peak-Eingangssignal: Der PeakDetector nutzt smoothedGp (signiert),
/// NICHT die Envelope. Die Envelope dient als Zusatzinformation für
/// QualityScorer und Diagnose. Begründung: Signiertes g_p erhält die
/// Phaseninformation (pos/neg), die für PhaseValidator nötig ist.
///
/// Die SignalChain ist ZUSTANDSBEHAFTET — reset() bei Session-Wechsel aufrufen.
library;

import 'butterworth.dart';
import 'envelope_detector.dart';
import 'gp_projection.dart';
import 'one_euro_filter.dart';
import '../models/processed_frame.dart';

/// Vollständige Signalverarbeitungskette für ein IMU-Sample.
///
/// Verwendung:
/// ```dart
/// final chain = SignalChain(
///   rotationAxis: [0.1, 0.9, 0.2],
///   gyroBias: [0.5, -0.3, 0.1],
/// );
///
/// // Pro BLE-Paket:
/// final frame = chain.process(timestampMs, gx, gy, gz);
/// ```
class SignalChain {
  final GpProjection _gpProjection;
  final ButterworthBandpass _butterworth;
  final OneEuroFilter _oneEuro;
  final EnvelopeDetector _envelope;

  /// Erstellt die Signalverarbeitungskette.
  ///
  /// [rotationAxis]: Einheitsvektor der Rotationsachse (aus Kalibrierung).
  /// [gyroBias]: Gyro-Bias [bx, by, bz] in °/s (aus Ruhephase).
  /// [sampleRateHz]: Abtastrate (Standard: 50.0 Hz).
  /// [oneEuroMinCutoff]: Min. Cutoff für One-Euro (Standard: 1.0 Hz).
  /// [oneEuroBeta]: Beta für One-Euro (Standard: 0.007).
  /// [envelopeCutoffHz]: Cutoff für Hüllkurve (Standard: 3.0 Hz).
  SignalChain({
    required List<double> rotationAxis,
    required List<double> gyroBias,
    double sampleRateHz = 50.0,
    double oneEuroMinCutoff = 1.0,
    double oneEuroBeta = 0.007,
    double envelopeCutoffHz = 3.0,
  })  : _gpProjection = GpProjection(
          rotationAxis: rotationAxis,
          gyroBias: gyroBias,
        ),
        _butterworth = ButterworthBandpass(),
        _oneEuro = OneEuroFilter(
          sampleRateHz: sampleRateHz,
          minCutoff: oneEuroMinCutoff,
          beta: oneEuroBeta,
        ),
        _envelope = EnvelopeDetector(
          cutoffHz: envelopeCutoffHz,
          sampleRateHz: sampleRateHz,
        );

  /// Verarbeitet ein rohes Gyro-Sample durch die gesamte Kette.
  ///
  /// [timestampMs]: Zeitstempel des BLE-Pakets in Millisekunden.
  /// [gx], [gy], [gz]: Roh-Gyrowerte in °/s.
  ///
  /// Rückgabe: [ProcessedFrame] mit allen Zwischenwerten.
  ProcessedFrame process(int timestampMs, double gx, double gy, double gz) {
    // Schritt 1: Projektion auf Rotationsachse
    final rawGp = _gpProjection.project(gx, gy, gz);

    // Schritt 2: Butterworth-Bandpass (0.1–5 Hz)
    final filteredGp = _butterworth.process(rawGp);

    // Schritt 3: One-Euro adaptive Glättung
    final smoothedGp = _oneEuro.process(filteredGp);

    // Schritt 4: Hüllkurve aus filteredGp (für Diagnose/QualityScorer, NICHT Peak-Eingang)
    final envelope = _envelope.process(filteredGp);

    // Einschwing-Status: alle Filter müssen eingeschwungen sein
    final isSettled = _butterworth.isSettled && _envelope.isSettled;

    return ProcessedFrame(
      timestampMs: timestampMs,
      rawGp: rawGp,
      filteredGp: filteredGp,
      smoothedGp: smoothedGp,
      envelope: envelope,
      isSettled: isSettled,
    );
  }

  /// Setzt ALLE Filterzustände zurück.
  ///
  /// Aufrufen bei: neue Session, Reconnect, Übungswechsel, nach Kalibrierung.
  void reset() {
    _butterworth.reset();
    _oneEuro.reset();
    _envelope.reset();
  }

  /// Aktualisiert Achse und Bias (nach Rekalibrierung).
  ///
  /// Setzt zusätzlich alle Filter zurück, da sich die Signalcharakteristik ändert.
  void updateCalibration({
    required List<double> rotationAxis,
    required List<double> gyroBias,
  }) {
    _gpProjection.updateAxisAndBias(
      rotationAxis: rotationAxis,
      gyroBias: gyroBias,
    );
    reset();
  }

  /// Aktualisiert One-Euro-Parameter (z.B. nach Übungserkennung).
  void updateOneEuroParameters({double? minCutoff, double? beta}) {
    _oneEuro.updateParameters(minCutoff: minCutoff, beta: beta);
  }

  /// Zugriff auf die GpProjection (für TemplateExtractor etc.).
  GpProjection get gpProjection => _gpProjection;

  /// true, wenn die Kette eingeschwungen ist.
  bool get isSettled => _butterworth.isSettled && _envelope.isSettled;

  /// Anzahl verarbeiteter Samples (Butterworth-Zähler).
  int get sampleCount => _butterworth.sampleCount;
}

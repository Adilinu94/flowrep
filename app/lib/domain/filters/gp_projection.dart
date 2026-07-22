/// Signierte Gyro-Projektion auf die gelernte Rotationsachse.
///
/// Projiziert den 3D-Gyro-Vektor (bias-korrigiert) auf einen Einheitsvektor.
/// Das Ergebnis ist ein VORZEICHENBEHAFTETES 1D-Signal:
///   g_p > 0 → Rotation in "positive" Richtung (z.B. konzentrisch)
///   g_p < 0 → Rotation in "negative" Richtung (z.B. exzentrisch)
///   g_p ≈ 0 → keine Rotation um die Übungsachse
///
/// Dies ist das Primärsignal für die Rep-Erkennung (LD-6).
library;

import 'dart:math' as math;

/// Projiziert Gyro-Samples auf eine gelernte Rotationsachse.
class GpProjection {
  List<double> _axis; // Einheitsvektor [x, y, z]
  List<double> _bias; // Gyro-Bias [bx, by, bz] in °/s

  /// Erstellt die Projektion.
  ///
  /// [rotationAxis]: Einheitsvektor der Rotationsachse (aus PCA/Kalibrierung).
  ///   Muss die Länge 3 haben. Wird intern normalisiert falls nötig.
  /// [gyroBias]: Gyro-Bias aus der Ruhephase [bx, by, bz] in °/s.
  GpProjection({
    required List<double> rotationAxis,
    required List<double> gyroBias,
  })  : _axis = _normalizeAxis(rotationAxis),
        _bias = List<double>.from(gyroBias) {
    if (gyroBias.length != 3) {
      throw ArgumentError('gyroBias muss genau 3 Elemente haben');
    }
  }

  /// Projiziert ein Gyro-Sample auf die Rotationsachse.
  ///
  /// [gx], [gy], [gz]: Roh-Gyrowerte in °/s.
  /// Rückgabe: signierte Projektion in °/s.
  ///
  /// Formel: g_p = (gx-bx)*ax + (gy-by)*ay + (gz-bz)*az
  double project(double gx, double gy, double gz) {
    if (gx.isNaN || gy.isNaN || gz.isNaN) return 0.0;

    final cx = gx - _bias[0];
    final cy = gy - _bias[1];
    final cz = gz - _bias[2];

    return cx * _axis[0] + cy * _axis[1] + cz * _axis[2];
  }

  /// Aktualisiert Achse und Bias (nach Rekalibrierung).
  ///
  /// [rotationAxis]: Neuer Einheitsvektor (Länge 3).
  /// [gyroBias]: Neuer Bias [bx, by, bz] in °/s.
  void updateAxisAndBias({
    required List<double> rotationAxis,
    required List<double> gyroBias,
  }) {
    if (rotationAxis.length != 3) {
      throw ArgumentError('rotationAxis muss genau 3 Elemente haben');
    }
    if (gyroBias.length != 3) {
      throw ArgumentError('gyroBias muss genau 3 Elemente haben');
    }
    _axis = _normalizeAxis(rotationAxis);
    _bias = List<double>.from(gyroBias);
  }

  /// Aktuelle Rotationsachse (Kopie).
  List<double> get axis => List<double>.from(_axis);

  /// Aktueller Gyro-Bias (Kopie).
  List<double> get bias => List<double>.from(_bias);

  /// Setzt den Bias auf Null zurück (Achse bleibt erhalten).
  void resetBias() {
    _bias = [0.0, 0.0, 0.0];
  }

  /// Normalisiert einen Vektor auf Einheitslänge.
  /// Bei Null-Vektor: gibt [1, 0, 0] zurück (Fallback).
  static List<double> _normalizeAxis(List<double> v) {
    if (v.length != 3) {
      throw ArgumentError('rotationAxis muss genau 3 Elemente haben');
    }
    final len = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (len < 1e-10) return [1.0, 0.0, 0.0];
    return [v[0] / len, v[1] / len, v[2] / len];
  }
}

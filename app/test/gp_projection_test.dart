import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/filters/gp_projection.dart';

void main() {
  group('GpProjection', () {
    test('Projektion auf Z-Achse mit Null-Bias', () {
      final gp = GpProjection(
        rotationAxis: [0.0, 0.0, 1.0],
        gyroBias: [0.0, 0.0, 0.0],
      );
      // Nur Z-Komponente sollte durchkommen
      expect(gp.project(10.0, 20.0, 30.0), closeTo(30.0, 1e-10));
    });

    test('Projektion auf X-Achse mit Null-Bias', () {
      final gp = GpProjection(
        rotationAxis: [1.0, 0.0, 0.0],
        gyroBias: [0.0, 0.0, 0.0],
      );
      expect(gp.project(10.0, 20.0, 30.0), closeTo(10.0, 1e-10));
    });

    test('Bias-Korrektur wird angewendet', () {
      final gp = GpProjection(
        rotationAxis: [0.0, 0.0, 1.0],
        gyroBias: [0.0, 0.0, 5.0], // Bias auf Z
      );
      // 30 - 5 = 25
      expect(gp.project(0.0, 0.0, 30.0), closeTo(25.0, 1e-10));
    });

    test('Diagonale Achse wird normalisiert', () {
      final gp = GpProjection(
        rotationAxis: [1.0, 1.0, 0.0], // nicht normalisiert
        gyroBias: [0.0, 0.0, 0.0],
      );
      // Achse wird zu [1/√2, 1/√2, 0]
      // Projektion von [10, 10, 0] = 10/√2 + 10/√2 = 20/√2 ≈ 14.142
      final result = gp.project(10.0, 10.0, 0.0);
      expect(result, closeTo(14.1421356, 0.001));
    });

    test('Null-Vektor als Achse gibt Fallback [1,0,0]', () {
      final gp = GpProjection(
        rotationAxis: [0.0, 0.0, 0.0],
        gyroBias: [0.0, 0.0, 0.0],
      );
      // Fallback: X-Achse
      expect(gp.project(42.0, 99.0, 77.0), closeTo(42.0, 1e-10));
    });

    test('NaN-Eingabe gibt 0.0 zurück', () {
      final gp = GpProjection(
        rotationAxis: [1.0, 0.0, 0.0],
        gyroBias: [0.0, 0.0, 0.0],
      );
      expect(gp.project(double.nan, 0.0, 0.0), equals(0.0));
      expect(gp.project(0.0, double.nan, 0.0), equals(0.0));
      expect(gp.project(0.0, 0.0, double.nan), equals(0.0));
    });

    test('updateAxisAndBias ändert Projektion', () {
      final gp = GpProjection(
        rotationAxis: [1.0, 0.0, 0.0],
        gyroBias: [0.0, 0.0, 0.0],
      );
      expect(gp.project(10.0, 20.0, 30.0), closeTo(10.0, 1e-10));

      gp.updateAxisAndBias(
        rotationAxis: [0.0, 1.0, 0.0],
        gyroBias: [0.0, 5.0, 0.0],
      );
      // Jetzt Y-Achse mit Bias 5: 20 - 5 = 15
      expect(gp.project(10.0, 20.0, 30.0), closeTo(15.0, 1e-10));
    });

    test('resetBias setzt Bias auf Null', () {
      final gp = GpProjection(
        rotationAxis: [0.0, 0.0, 1.0],
        gyroBias: [0.0, 0.0, 10.0],
      );
      expect(gp.project(0.0, 0.0, 30.0), closeTo(20.0, 1e-10));

      gp.resetBias();
      expect(gp.project(0.0, 0.0, 30.0), closeTo(30.0, 1e-10));
    });

    test('axis und bias Getter geben Kopien zurück', () {
      final gp = GpProjection(
        rotationAxis: [1.0, 0.0, 0.0],
        gyroBias: [1.0, 2.0, 3.0],
      );
      final axis = gp.axis;
      final bias = gp.bias;

      // Mutation der Kopie darf intern nichts ändern
      axis[0] = 999.0;
      bias[0] = 999.0;

      expect(gp.axis[0], closeTo(1.0, 1e-10));
      expect(gp.bias[0], equals(1.0));
    });

    test('Falsche Vektorlänge wirft ArgumentError', () {
      expect(
        () => GpProjection(rotationAxis: [1.0, 0.0], gyroBias: [0.0, 0.0, 0.0]),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => GpProjection(rotationAxis: [1.0, 0.0, 0.0], gyroBias: [0.0, 0.0]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

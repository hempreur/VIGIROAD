import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/navigation/domain/geo_fix.dart';
import 'package:vigiroad/features/navigation/domain/geo_math.dart';

void main() {
  group('distanceMeters', () {
    test('Paris – Lyon ≈ 392 km', () {
      const paris = GeoPoint(48.8566, 2.3522);
      const lyon = GeoPoint(45.7640, 4.8357);
      expect(distanceMeters(paris, lyon) / 1000, closeTo(391.5, 2));
    });

    test('distance nulle pour un même point', () {
      const p = GeoPoint(43.6, 1.44);
      expect(distanceMeters(p, p), 0);
    });
  });

  group('formatDistance', () {
    test('mètres arrondis à la dizaine', () => expect(formatDistance(847), '850 m'));
    test('kilomètres avec virgule', () => expect(formatDistance(12400), '12,4 km'));
    test('au-delà de 100 km sans décimale', () => expect(formatDistance(128400), '128 km'));
  });

  group('GeoFix', () {
    GeoFix fix(double? mps, {double? heading}) => GeoFix(
      point: const GeoPoint(0, 0),
      timestamp: DateTime(2026),
      speedMps: mps,
      headingDeg: heading,
    );

    test('convertit m/s en km/h', () => expect(fix(22.78).speedKmh, 82));
    test('0 km/h à l\'arrêt (bruit GPS)', () => expect(fix(0.2).speedKmh, 0));
    test('vitesse inconnue', () => expect(fix(null).speedKmh, isNull));
    test('cap fiable seulement en mouvement', () {
      expect(fix(0.5, heading: 90).headingReliable, isFalse);
      expect(fix(10, heading: 90).headingReliable, isTrue);
      expect(fix(10).headingReliable, isFalse);
    });
  });
}

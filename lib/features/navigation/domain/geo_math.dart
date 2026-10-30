import 'dart:math' as math;

import 'geo_fix.dart';

const double _earthRadiusM = 6371008.8;

double _rad(double deg) => deg * math.pi / 180;

/// Distance orthodromique (formule de haversine), en mètres.
double distanceMeters(GeoPoint a, GeoPoint b) {
  final dLat = _rad(b.latitude - a.latitude);
  final dLon = _rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
}

/// Formate une distance à la française : « 850 m », « 12,4 km », « 128 km ».
String formatDistance(double meters) {
  if (meters < 1000) {
    // Arrondi par pas de 10 m, comme les GPS du marché.
    final rounded = (meters / 10).round() * 10;
    return '$rounded m';
  }
  final km = meters / 1000;
  if (km < 100) {
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }
  return '${km.round()} km';
}

import 'dart:math' as math;

import 'traffic_event.dart';

const double _r = 6371008.8;

double _rad(double d) => d * math.pi / 180;

/// Distance orthodromique en mètres.
double haversine(LatLng a, LatLng b) {
  final dLat = _rad(b.lat - a.lat), dLng = _rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _r * math.asin(math.min(1.0, math.sqrt(h.toDouble())));
}

/// Rectangle géographique.
class BBox {
  const BBox(this.minLng, this.minLat, this.maxLng, this.maxLat);

  final double minLng, minLat, maxLng, maxLat;

  /// Lecture de `minLng,minLat,maxLng,maxLat`.
  static BBox? tryParse(String? s) {
    final p = s?.split(',').map(double.tryParse).toList();
    if (p == null || p.length != 4 || p.any((v) => v == null)) return null;
    final b = BBox(p[0]!, p[1]!, p[2]!, p[3]!);
    final valid = b.minLng >= -180 && b.maxLng <= 180 && b.minLat >= -90 && b.maxLat <= 90 &&
        b.minLng <= b.maxLng && b.minLat <= b.maxLat;
    return valid ? b : null;
  }

  bool intersects(BBox o) => minLng <= o.maxLng && o.minLng <= maxLng && minLat <= o.maxLat && o.minLat <= maxLat;

  /// Rectangle englobant une suite de points, agrandi de [padDeg] degrés.
  static BBox around(Iterable<LatLng> points, {double padDeg = 0}) {
    var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    return BBox(minLng - padDeg, minLat - padDeg, maxLng + padDeg, maxLat + padDeg);
  }

  List<double> toJson() => [minLng, minLat, maxLng, maxLat];

  @override
  String toString() => '$minLng,$minLat,$maxLng,$maxLat';

  bool contains(LatLng p) => p.lat >= minLat && p.lat <= maxLat && p.lng >= minLng && p.lng <= maxLng;

  /// Surface approximative en km² (limite des requêtes trop larges).
  double get areaKm2 {
    final h = haversine(LatLng(minLat, minLng), LatLng(maxLat, minLng)) / 1000;
    final midLat = (minLat + maxLat) / 2;
    final w = haversine(LatLng(midLat, minLng), LatLng(midLat, maxLng)) / 1000;
    return h * w;
  }
}

/// Distance (m) d'un point à une polyligne, et distance le long de celle-ci
/// jusqu'au point le plus proche.
({double distance, double along}) distanceToPolyline(LatLng p, List<LatLng> line) {
  if (line.length == 1) return (distance: haversine(p, line.first), along: 0);
  final lat0 = _rad(p.lat);
  (double, double) xy(LatLng q) => (_rad(q.lng) * _r * math.cos(lat0), _rad(q.lat) * _r);
  final pt = xy(p);
  var best = double.infinity, bestAlong = 0.0, cum = 0.0;
  for (var i = 0; i + 1 < line.length; i++) {
    final a = xy(line[i]), b = xy(line[i + 1]);
    final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
    final len2 = dx * dx + dy * dy;
    final len = math.sqrt(len2);
    final t = len2 == 0 ? 0.0 : (((pt.$1 - a.$1) * dx + (pt.$2 - a.$2) * dy) / len2).clamp(0.0, 1.0);
    final qx = a.$1 + t * dx - pt.$1, qy = a.$2 + t * dy - pt.$2;
    final d = math.sqrt(qx * qx + qy * qy);
    if (d < best) {
      best = d;
      bestAlong = cum + t * len;
    }
    cum += len;
  }
  return (distance: best, along: bestAlong);
}

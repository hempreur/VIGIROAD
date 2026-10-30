import 'dart:math' as math;

import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import 'osm_way.dart';

/// Associe à chaque segment d'un itinéraire la limitation de la voie OSM
/// qu'il emprunte, dans le bon sens de circulation.
///
/// Un segment n'est rattaché à une voie que si elle passe à moins de
/// [maxOffsetM] de son milieu **et** dans la même direction (± [maxAngleDeg]) :
/// une rue qui croise l'itinéraire n'est jamais prise pour celle qu'on suit.
/// Sans correspondance sûre, la limitation reste inconnue (`null`).
class SpeedLimitMatcher {
  const SpeedLimitMatcher({this.maxOffsetM = 12, this.maxAngleDeg = 30});

  final double maxOffsetM;
  final double maxAngleDeg;

  static const _cell = 0.002; // ≈ 200 m

  List<int?> match(List<LatLng> route, List<OsmWay> ways) {
    if (route.length < 2) return const [];
    // Index spatial des segments de voies.
    final grid = <(int, int), List<(OsmWay, int)>>{};
    (int, int) key(double lat, double lng) => ((lat / _cell).floor(), (lng / _cell).floor());
    for (final w in ways) {
      for (var i = 0; i + 1 < w.geometry.length; i++) {
        final a = w.geometry[i], b = w.geometry[i + 1];
        final k0 = key(math.min(a.lat, b.lat), math.min(a.lng, b.lng));
        final k1 = key(math.max(a.lat, b.lat), math.max(a.lng, b.lng));
        for (var y = k0.$1; y <= k1.$1; y++) {
          for (var x = k0.$2; x <= k1.$2; x++) {
            (grid[(y, x)] ??= []).add((w, i));
          }
        }
      }
    }

    final out = List<int?>.filled(route.length - 1, null);
    for (var i = 0; i + 1 < route.length; i++) {
      final a = route[i], b = route[i + 1];
      if (haversine(a, b) < 0.5) continue;
      final mid = LatLng((a.lat + b.lat) / 2, (a.lng + b.lng) / 2);
      final heading = _bearing(a, b);
      final k = key(mid.lat, mid.lng);
      var best = double.infinity;
      int? limit;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          for (final (w, s) in grid[(k.$1 + dy, k.$2 + dx)] ?? const <(OsmWay, int)>[]) {
            final p = w.geometry[s], q = w.geometry[s + 1];
            final d = distanceToPolyline(mid, [p, q]).distance;
            if (d > maxOffsetM || d >= best) continue;
            final diff = _angle(heading, _bearing(p, q));
            final int? v;
            if (diff <= maxAngleDeg) {
              v = w.forward;
            } else if (diff >= 180 - maxAngleDeg) {
              v = w.backward;
            } else {
              continue; // voie qui croise l'itinéraire
            }
            best = d;
            limit = v; // la voie la plus proche décide, même si sa valeur est inconnue
          }
        }
      }
      out[i] = limit;
    }
    return out;
  }

  static double _bearing(LatLng a, LatLng b) {
    final la1 = a.lat * math.pi / 180, la2 = b.lat * math.pi / 180;
    final dl = (b.lng - a.lng) * math.pi / 180;
    final y = math.sin(dl) * math.cos(la2);
    final x = math.cos(la1) * math.sin(la2) - math.sin(la1) * math.cos(la2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  static double _angle(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }
}

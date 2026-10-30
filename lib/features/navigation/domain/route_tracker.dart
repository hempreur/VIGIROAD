import 'dart:math' as math;

import 'geo_fix.dart';
import 'geo_math.dart';
import 'route.dart';

/// Avancement sur l'itinéraire à un instant donné.
class RouteProgress {
  const RouteProgress({
    required this.snapped,
    required this.offRouteM,
    required this.alongM,
    required this.remainingM,
    required this.remainingS,
    required this.nextStepIndex,
    required this.toNextManeuverM,
    required this.speedLimitKmh,
  });

  /// Position ramenée sur le tracé.
  final GeoPoint snapped;

  /// Écart entre la position GPS et le tracé, en mètres.
  final double offRouteM;

  /// Distance déjà parcourue le long du tracé.
  final double alongM;
  final double remainingM;
  final double remainingS;

  /// Indice (dans `route.steps`) de la prochaine manœuvre.
  final int nextStepIndex;
  final double toNextManeuverM;

  /// Limitation de vitesse du segment courant, si connue.
  final int? speedLimitKmh;

  bool get arrived => remainingM < 25;
}

/// Suit la progression d'une position GPS le long d'un [NavRoute].
class RouteTracker {
  RouteTracker(this.route) : assert(route.geometry.length >= 2) {
    final g = route.geometry;
    _lat0 = g.first.latitude;
    _xy = [for (final p in g) _project(p)];
    _cum = List<double>.filled(g.length, 0);
    for (var i = 1; i < g.length; i++) {
      _cum[i] = _cum[i - 1] + _dist(_xy[i - 1], _xy[i]);
    }
    // Position de chaque manœuvre le long du tracé (recherche monotone).
    var from = 0;
    _stepAlong = [];
    for (final s in route.steps) {
      final hit = _nearest(_project(s.location), from, g.length - 2);
      _stepAlong.add(hit.along);
      from = hit.segment;
    }
  }

  final NavRoute route;
  late final double _lat0;
  late final List<(double, double)> _xy;
  late final List<double> _cum;
  late final List<double> _stepAlong;
  int _lastSegment = 0;

  static const _r = 6371008.8;

  /// Longueur du tracé calculée localement (≈ `route.distanceM`).
  double get length => _cum.last;

  /// Distance le long du tracé de la manœuvre d'indice [i].
  double stepAlong(int i) => _stepAlong[i];

  (double, double) _project(GeoPoint p) {
    final k = math.cos(_lat0 * math.pi / 180);
    return (p.longitude * math.pi / 180 * _r * k, p.latitude * math.pi / 180 * _r);
  }

  GeoPoint _unproject((double, double) xy) {
    final k = math.cos(_lat0 * math.pi / 180);
    return GeoPoint(xy.$2 / _r * 180 / math.pi, xy.$1 / (_r * k) * 180 / math.pi);
  }

  static double _dist((double, double) a, (double, double) b) {
    final dx = a.$1 - b.$1, dy = a.$2 - b.$2;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Point le plus proche de [p] sur les segments [from]..[to] inclus.
  ({int segment, double along, double distance, (double, double) point}) _nearest(
    (double, double) p,
    int from,
    int to,
  ) {
    from = math.max(0, from);
    var best = (segment: from, along: _cum[from], distance: double.infinity, point: _xy[from]);
    for (var i = math.max(0, from); i <= math.min(to, _xy.length - 2); i++) {
      final a = _xy[i], b = _xy[i + 1];
      final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : (((p.$1 - a.$1) * dx + (p.$2 - a.$2) * dy) / len2).clamp(0.0, 1.0);
      final q = (a.$1 + t * dx, a.$2 + t * dy);
      final d = _dist(p, q);
      if (d < best.distance) {
        best = (segment: i, along: _cum[i] + t * math.sqrt(len2), distance: d, point: q);
      }
    }
    return best;
  }

  RouteProgress update(GeoPoint position) {
    final p = _project(position);
    // Recherche d'abord autour du dernier segment (évite de sauter sur une
    // portion de l'itinéraire qui repasse à proximité), puis globale.
    var hit = _nearest(p, _lastSegment - 3, _lastSegment + 250);
    if (hit.distance > 60) {
      final global = _nearest(p, 0, _xy.length - 2);
      if (global.distance < hit.distance - 20) hit = global;
    }
    _lastSegment = hit.segment;

    final along = hit.along;
    final remaining = math.max(0.0, length - along);
    var next = route.steps.length - 1;
    for (var i = 1; i < route.steps.length; i++) {
      if (_stepAlong[i] > along + 5) {
        next = i;
        break;
      }
    }
    final limits = route.segmentSpeedLimits;
    return RouteProgress(
      snapped: _unproject(hit.point),
      offRouteM: hit.distance,
      alongM: along,
      remainingM: remaining,
      remainingS: length == 0 ? 0 : route.durationS * remaining / length,
      nextStepIndex: next,
      toNextManeuverM: math.max(0, _stepAlong[next] - along),
      speedLimitKmh: limits.isEmpty ? null : limits[hit.segment],
    );
  }
}

/// Décide quand recalculer l'itinéraire : écart supérieur au seuil sur
/// plusieurs positions consécutives, pour ignorer les sauts GPS isolés.
class OffRouteDetector {
  OffRouteDetector({this.thresholdM = 45, this.requiredFixes = 3});

  final double thresholdM;
  final int requiredFixes;
  int _count = 0;

  /// Retourne `true` quand le recalcul doit être lancé.
  bool feed(RouteProgress p, {double? accuracyM}) {
    final limit = math.max(thresholdM, (accuracyM ?? 0) * 1.5);
    _count = p.offRouteM > limit ? _count + 1 : 0;
    return _count >= requiredFixes;
  }

  void reset() => _count = 0;
}

/// Distance restante formatée, réexportée pour l'interface.
String formatRemaining(double meters) => formatDistance(meters);

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/geo_fix.dart';
import '../domain/route.dart';

class RoutingException implements Exception {
  const RoutingException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class RouteService {
  /// Calcule un itinéraire en voiture. [bearing] (cap actuel) aide le
  /// serveur à partir dans le sens de circulation lors d'un recalcul.
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? bearing});
}

/// Calcul d'itinéraire via une API compatible OSRM (profil voiture).
class OsrmRouter implements RouteService {
  OsrmRouter({required this.baseUrl, required this.userAgent, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final String userAgent;
  final http.Client _client;

  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? bearing}) async {
    String c(GeoPoint p) => '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}';
    final uri = Uri.parse('$baseUrl/route/v1/driving/${c(from)};${c(to)}').replace(
      queryParameters: {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'true',
        'annotations': 'maxspeed',
        'alternatives': 'false',
        if (bearing != null) 'bearings': '${bearing.round() % 360},45;',
      },
    );
    final http.Response res;
    try {
      res = await _client
          .get(uri, headers: {'User-Agent': userAgent, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
    } on Exception {
      throw const RoutingException('Calcul d\'itinéraire impossible : vérifiez la connexion réseau.');
    }
    if (res.statusCode == 429) {
      throw const RoutingException('Service d\'itinéraire saturé, nouvel essai dans quelques secondes.');
    }
    if (res.statusCode != 200 && res.statusCode != 400) {
      throw RoutingException('Le service d\'itinéraire a répondu ${res.statusCode}.');
    }
    return parseOsrmResponse(utf8.decode(res.bodyBytes));
  }
}

GeoPoint _pt(Object? lonLat) {
  final l = lonLat! as List<dynamic>;
  return GeoPoint((l[1] as num).toDouble(), (l[0] as num).toDouble());
}

ManeuverKind _kind(String type) => switch (type) {
  'depart' => ManeuverKind.depart,
  'arrive' => ManeuverKind.arrive,
  'turn' => ManeuverKind.turn,
  'continue' => ManeuverKind.continueStraight,
  'merge' => ManeuverKind.merge,
  'on ramp' => ManeuverKind.onRamp,
  'off ramp' => ManeuverKind.offRamp,
  'fork' => ManeuverKind.fork,
  'end of road' => ManeuverKind.endOfRoad,
  'roundabout' || 'rotary' || 'roundabout turn' => ManeuverKind.roundabout,
  'exit roundabout' || 'exit rotary' => ManeuverKind.exitRoundabout,
  'new name' => ManeuverKind.newName,
  _ => ManeuverKind.notification,
};

ManeuverDirection _dir(String? m) => switch (m) {
  'uturn' => ManeuverDirection.uturn,
  'sharp right' => ManeuverDirection.sharpRight,
  'right' => ManeuverDirection.right,
  'slight right' => ManeuverDirection.slightRight,
  'straight' => ManeuverDirection.straight,
  'slight left' => ManeuverDirection.slightLeft,
  'left' => ManeuverDirection.left,
  'sharp left' => ManeuverDirection.sharpLeft,
  _ => ManeuverDirection.none,
};

int? _maxspeed(Object? v) {
  if (v is! Map<String, dynamic>) return null;
  final speed = v['speed'];
  if (speed is! num) return null;
  return v['unit'] == 'mph' ? (speed * 1.609344).round() : speed.round();
}

/// Convertit une réponse OSRM en [NavRoute].
NavRoute parseOsrmResponse(String body) {
  final json = jsonDecode(body);
  if (json is! Map<String, dynamic>) throw const RoutingException('Réponse d\'itinéraire illisible.');
  final code = json['code'];
  if (code == 'NoRoute') throw const RoutingException('Aucun itinéraire routier trouvé vers cette destination.');
  if (code == 'NoSegment') throw const RoutingException('Point de départ ou d\'arrivée trop loin d\'une route.');
  if (code != 'Ok') throw RoutingException('Itinéraire indisponible (${code ?? 'erreur inconnue'}).');

  final routes = json['routes'] as List<dynamic>;
  if (routes.isEmpty) throw const RoutingException('Aucun itinéraire trouvé.');
  final r = routes.first as Map<String, dynamic>;

  final geometry = [
    for (final c in (r['geometry'] as Map<String, dynamic>)['coordinates'] as List<dynamic>) _pt(c),
  ];

  final steps = <RouteStep>[];
  final limits = <int?>[];
  for (final leg in (r['legs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    final annotation = leg['annotation'];
    if (annotation is Map<String, dynamic> && annotation['maxspeed'] is List) {
      limits.addAll((annotation['maxspeed'] as List<dynamic>).map(_maxspeed));
    }
    for (final s in (leg['steps'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final m = s['maneuver'] as Map<String, dynamic>;
      String str(String k) => (s[k] is String) ? (s[k] as String).trim() : '';
      final exits = str('exits');
      steps.add(
        RouteStep(
          kind: _kind(m['type'] as String? ?? ''),
          direction: _dir(m['modifier'] as String?),
          location: _pt(m['location']),
          distanceM: (s['distance'] as num).toDouble(),
          durationS: (s['duration'] as num).toDouble(),
          roadName: str('name'),
          roadRef: str('ref').split(';').first.trim(),
          destinations: str('destinations').split(':').last.split(',').first.trim(),
          exitNumber: exits.isEmpty ? null : exits.split(';').first,
          roundaboutExit: (m['exit'] as num?)?.toInt(),
        ),
      );
    }
  }

  return NavRoute(
    geometry: geometry,
    distanceM: (r['distance'] as num).toDouble(),
    durationS: (r['duration'] as num).toDouble(),
    steps: steps,
    segmentSpeedLimits: limits.length == geometry.length - 1 ? limits : const [],
  );
}

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import 'aggregator.dart';

/// Limiteur de débit par clé (seau à jetons).
class RateLimiter {
  RateLimiter({this.capacity = 120, this.refillPerMinute = 120, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final int capacity;
  final int refillPerMinute;
  final DateTime Function() _clock;
  final _buckets = <String, (double, DateTime)>{};

  bool allow(String key) {
    final now = _clock();
    final (tokens, at) = _buckets[key] ?? (capacity.toDouble(), now);
    final refilled = (tokens + now.difference(at).inMilliseconds / 60000 * refillPerMinute).clamp(0, capacity).toDouble();
    if (refilled < 1) {
      _buckets[key] = (refilled, now);
      return false;
    }
    _buckets[key] = (refilled - 1, now);
    return true;
  }
}

/// Comparaison en temps constant (évite les attaques temporelles sur la clé).
bool _secureEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// API HTTP exposée à l'application VIGIROAD.
///
/// - `GET  /health` : état du service (sans clé)
/// - `GET  /v1/sources` : sources, licences, mentions et santé
/// - `GET  /v1/events?bbox=minLng,minLat,maxLng,maxLat` : événements d'une zone
/// - `POST /v1/events/route` `{"route": [[lng,lat],…], "bufferMeters": 150}` :
///   perturbations sur un itinéraire, dans l'ordre de rencontre
///
/// Authentification par en-tête `X-Api-Key`, limite de débit par clé, zone
/// interrogée plafonnée. Le transport HTTPS est assuré par l'hébergeur.
class TrafficApi {
  TrafficApi(this.aggregator, {required this.apiKeys, RateLimiter? limiter, this.maxBoxKm2 = 250000})
    : limiter = limiter ?? RateLimiter();

  final TrafficAggregator aggregator;
  final Set<String> apiKeys;
  final RateLimiter limiter;
  final double maxBoxKm2;

  static const _json = {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'};

  Response _ok(Object body) => Response.ok(jsonEncode(body), headers: _json);
  Response _error(int code, String message) => Response(code, body: jsonEncode({'error': message}), headers: _json);

  Handler get handler => (Request req) async {
    final path = '/${req.url.path}';
    if (path == '/health') {
      return _ok({'status': 'ok', 'sources': aggregator.statuses.length, 'coverage': aggregator.coverage().toList()..sort()});
    }

    final key = req.headers['x-api-key'] ?? '';
    if (!apiKeys.any((k) => _secureEquals(k, key))) return _error(401, 'Clé API absente ou invalide');
    if (!limiter.allow(key)) return _error(429, 'Trop de requêtes');

    try {
      switch ((req.method, path)) {
        case ('GET', '/v1/sources'):
          final now = DateTime.now().toUtc();
          return _ok({'sources': [for (final s in aggregator.statuses) s.toJson(now)]});
        case ('GET', '/v1/events'):
          final box = BBox.tryParse(req.url.queryParameters['bbox']);
          if (box == null) return _error(400, 'Paramètre bbox=minLng,minLat,maxLng,maxLat attendu');
          if (box.areaKm2 > maxBoxKm2) return _error(400, 'Zone trop grande');
          return _ok(_payload(aggregator.inBox(box), box));
        case ('POST', '/v1/events/route'):
          final body = jsonDecode(await req.readAsString());
          final raw = body is Map<String, dynamic> ? body['route'] : null;
          if (raw is! List || raw.length < 2 || raw.length > 20000) {
            return _error(400, 'route : liste de 2 à 20 000 points [lng, lat] attendue');
          }
          final route = [for (final p in raw) LatLng.fromJson(p as List<dynamic>)];
          final buffer = ((body as Map<String, dynamic>)['bufferMeters'] as num?)?.toDouble().clamp(20, 1000) ?? 150.0;
          final hits = aggregator.alongRoute(route, bufferM: buffer.toDouble());
          return _ok({
            ..._payload([for (final h in hits) h.event], BBox.around(route)),
            'along': [for (final h in hits) {'id': h.event.id, 'alongMeters': h.along.round(), 'offsetMeters': h.offset.round()}],
          });
        default:
          return _error(404, 'Ressource inconnue');
      }
    } on FormatException {
      return _error(400, 'Requête mal formée');
    } on TypeError {
      return _error(400, 'Requête mal formée');
    }
  };

  /// Réponse avec événements, état de la zone demandée et mentions
  /// obligatoires des sources utilisées.
  ///
  /// `area.known` est faux quand aucune source à jour ne couvre la zone :
  /// l'application affiche alors l'état **inconnu** (jamais « fluide »).
  /// `area.updatedAt` est la collecte la plus ancienne parmi les sources
  /// couvrantes (date de mise à jour à afficher, exigée par Bison Futé).
  Map<String, Object?> _payload(List<TrafficEvent> events, BBox box) {
    final covering = aggregator.coveringFresh(box);
    final used = {for (final e in events) ...e.sources, for (final s in covering) s.connector.info.id};
    final oldest = covering.isEmpty
        ? null
        : covering.map((s) => s.lastSuccess!).reduce((a, b) => a.isBefore(b) ? a : b);
    return {
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'coverage': aggregator.coverage().toList()..sort(),
      'area': {
        'known': covering.isNotEmpty,
        'updatedAt': oldest?.toIso8601String(),
        'sources': [
          for (final s in covering)
            {'source': s.connector.info.id, 'coverage': s.connector.info.coverageNote},
        ],
      },
      'attributions': [
        for (final s in aggregator.statuses)
          if (used.contains(s.connector.info.id))
            {
              'source': s.connector.info.id,
              'text': s.connector.info.attribution,
              'url': s.connector.info.homepage,
              'updatedAt': s.lastSuccess?.toIso8601String(),
            },
      ],
      'events': [for (final e in events) e.toJson()],
    };
  }
}

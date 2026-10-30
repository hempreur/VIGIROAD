import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../domain/traffic_snapshot.dart';

class TrafficException implements Exception {
  const TrafficException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Accès au serveur VigiRoadTrafficAggregator.
abstract interface class TrafficClient {
  /// Perturbations d'une zone.
  Future<TrafficSnapshot> inBox(BBox box);

  /// Perturbations à moins de [bufferM] d'un itinéraire.
  Future<TrafficSnapshot> alongRoute(List<LatLng> route, {double bufferM = 150});
}

class HttpTrafficClient implements TrafficClient {
  HttpTrafficClient({
    required this.baseUrl,
    required this.apiKey,
    required this.userAgent,
    http.Client? client,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final String baseUrl;
  final String apiKey;
  final String userAgent;
  final http.Client _client;
  final DateTime Function() _clock;

  /// Points envoyés au plus pour un itinéraire (limite le volume transféré).
  static const maxRoutePoints = 1500;

  Map<String, String> get _headers => {
    'X-Api-Key': apiKey,
    'User-Agent': userAgent,
    'Accept': 'application/json',
  };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  @override
  Future<TrafficSnapshot> inBox(BBox box) => _send(() => _client.get(
    _uri('/v1/events', {'bbox': [for (final v in box.toJson()) v.toStringAsFixed(5)].join(',')}),
    headers: _headers,
  ));

  @override
  Future<TrafficSnapshot> alongRoute(List<LatLng> route, {double bufferM = 150}) => _send(() => _client.post(
    _uri('/v1/events/route'),
    headers: {..._headers, 'Content-Type': 'application/json'},
    body: jsonEncode({
      'route': [for (final p in thin(route, maxRoutePoints)) p.toJson()],
      'bufferMeters': bufferM,
    }),
  ));

  Future<TrafficSnapshot> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(const Duration(seconds: 10));
    } on Exception {
      throw const TrafficException('Serveur de trafic injoignable');
    }
    switch (res.statusCode) {
      case 200:
        break;
      case 401:
        throw const TrafficException('Clé du serveur de trafic refusée');
      case 429:
        throw const TrafficException('Serveur de trafic saturé');
      default:
        throw TrafficException('Serveur de trafic : erreur ${res.statusCode}');
    }
    try {
      return TrafficSnapshot.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>, receivedAt: _clock());
    } on Object {
      throw const TrafficException('Réponse du serveur de trafic illisible');
    }
  }
}

/// Garde au plus [max] points, premier et dernier compris, à intervalles
/// réguliers (le serveur ne sert qu'à repérer les événements proches).
List<LatLng> thin(List<LatLng> points, int max) {
  if (points.length <= max) return points;
  final step = (points.length - 1) / (max - 1);
  return [for (var i = 0; i < max; i++) points[(i * step).round()]];
}

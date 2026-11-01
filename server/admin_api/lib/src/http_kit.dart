import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

/// Erreur renvoyée telle quelle au client (message en français).
class ApiError implements Exception {
  const ApiError(this.status, this.message, {this.code});

  final int status;
  final String message;

  /// Code stable exploitable par les applications (`revoked`, `mfa_required`…).
  final String? code;

  static ApiError badRequest(String m) => ApiError(400, m, code: 'bad_request');
  static const unauthorized = ApiError(401, 'Authentification requise', code: 'unauthorized');
  static const forbidden = ApiError(403, 'Action non autorisée pour votre rôle', code: 'forbidden');
  static const notFound = ApiError(404, 'Ressource introuvable', code: 'not_found');
  static const tooMany = ApiError(429, 'Trop de tentatives, réessayez plus tard', code: 'rate_limited');

  @override
  String toString() => 'ApiError($status, $message)';
}

const jsonHeaders = {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'};

Response jsonOk(Object? body, {int status = 200}) => Response(status, body: jsonEncode(body), headers: jsonHeaders);

Response jsonError(ApiError e) =>
    Response(e.status, body: jsonEncode({'error': e.message, 'code': e.code}), headers: jsonHeaders);

/// Corps JSON d'une requête (objet attendu).
Future<Map<String, dynamic>> readJson(Request req) async {
  final text = await req.readAsString();
  if (text.length > 256 * 1024) throw ApiError.badRequest('Requête trop volumineuse');
  if (text.trim().isEmpty) return {};
  final v = jsonDecode(text);
  if (v is! Map<String, dynamic>) throw ApiError.badRequest('Objet JSON attendu');
  return v;
}

extension JsonFields on Map<String, dynamic> {
  String? str(String k, {int max = 256}) {
    final v = this[k];
    if (v == null) return null;
    if (v is! String) throw ApiError.badRequest('Champ « $k » : texte attendu');
    final t = v.trim();
    if (t.length > max) throw ApiError.badRequest('Champ « $k » trop long');
    return t.isEmpty ? null : t;
  }

  String need(String k, {int max = 256}) => str(k, max: max) ?? (throw ApiError.badRequest('Champ « $k » requis'));

  bool? flag(String k) {
    final v = this[k];
    if (v == null) return null;
    if (v is! bool) throw ApiError.badRequest('Champ « $k » : booléen attendu');
    return v;
  }

  num? number(String k) {
    final v = this[k];
    if (v == null) return null;
    if (v is! num) throw ApiError.badRequest('Champ « $k » : nombre attendu');
    return v;
  }
}

typedef RouteHandler = FutureOr<Response> Function(Request req, Map<String, String> params);

/// Routeur minimal : `/admin/users/:id/revoke`.
class Router {
  final _routes = <(String, List<String>, RouteHandler)>[];

  void add(String method, String pattern, RouteHandler h) =>
      _routes.add((method, pattern.split('/').where((s) => s.isNotEmpty).toList(), h));

  void get(String p, RouteHandler h) => add('GET', p, h);
  void post(String p, RouteHandler h) => add('POST', p, h);
  void patch(String p, RouteHandler h) => add('PATCH', p, h);
  void put(String p, RouteHandler h) => add('PUT', p, h);
  void delete(String p, RouteHandler h) => add('DELETE', p, h);

  /// Route correspondante et son modèle (pour les statistiques), ou null.
  (RouteHandler, Map<String, String>, String)? match(String method, String path) {
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    var pathMatched = false;
    for (final (m, pattern, h) in _routes) {
      if (pattern.length != segs.length) continue;
      final params = <String, String>{};
      var ok = true;
      for (var i = 0; i < segs.length; i++) {
        if (pattern[i].startsWith(':')) {
          params[pattern[i].substring(1)] = Uri.decodeComponent(segs[i]);
        } else if (pattern[i] != segs[i]) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      pathMatched = true;
      if (m == method) return (h, params, '/${pattern.join('/')}');
    }
    if (pathMatched) throw const ApiError(405, 'Méthode non autorisée', code: 'method_not_allowed');
    return null;
  }
}

/// Adresse du client : en-tête posé par Caddy (seul point d'entrée public),
/// sinon adresse de la connexion.
String? clientIp(Request req, {bool trustProxy = true}) {
  if (trustProxy) {
    final xff = req.headers['x-forwarded-for'];
    if (xff != null && xff.isNotEmpty) return xff.split(',').first.trim();
  }
  final info = req.context['shelf.io.connection_info'];
  return info is HttpConnectionInfo ? info.remoteAddress.address : null;
}

/// Limiteur à fenêtre glissante (tentatives de connexion, inscriptions).
class SlidingLimiter {
  SlidingLimiter({required this.max, required this.window, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final int max;
  final Duration window;
  final DateTime Function() _clock;
  final _hits = <String, List<DateTime>>{};

  bool allow(String key) {
    final now = _clock();
    final list = _hits.putIfAbsent(key, () => []);
    list.removeWhere((t) => now.difference(t) > window);
    if (list.length >= max) return false;
    list.add(now);
    if (_hits.length > 50000) _hits.removeWhere((_, v) => v.isEmpty || now.difference(v.last) > window);
    return true;
  }

  void reset(String key) => _hits.remove(key);
}

/// Compteurs de requêtes et de latence par minute et par route.
class RequestStats {
  RequestStats({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _buckets = <(DateTime, String), _Bucket>{};

  void record(String route, Duration latency, {required bool error}) {
    final now = _clock().toUtc();
    final minute = DateTime.utc(now.year, now.month, now.day, now.hour, now.minute);
    final b = _buckets.putIfAbsent((minute, route), _Bucket.new);
    b.count++;
    if (error) b.errors++;
    if (b.samples.length < 2000) b.samples.add(latency.inMicroseconds / 1000);
    _buckets.removeWhere((k, _) => now.difference(k.$1) > const Duration(hours: 2));
  }

  /// Minutes terminées (et la minute en cours si [includeCurrent]).
  List<Map<String, Object?>> snapshot({bool includeCurrent = true}) {
    final now = _clock().toUtc();
    final current = DateTime.utc(now.year, now.month, now.day, now.hour, now.minute);
    return [
      for (final e in _buckets.entries)
        if (includeCurrent || e.key.$1.isBefore(current))
          {
            'minute': e.key.$1.toIso8601String(),
            'route': e.key.$2,
            'count': e.value.count,
            'errors': e.value.errors,
            'p50Ms': e.value.percentile(0.5),
            'p95Ms': e.value.percentile(0.95),
          },
    ];
  }

  /// Middleware shelf (modèle de route via [routeOf]).
  Middleware middleware(String Function(Request) routeOf) => (inner) => (req) async {
    final sw = Stopwatch()..start();
    try {
      final res = await inner(req);
      record(routeOf(req), sw.elapsed, error: res.statusCode >= 500);
      return res;
    } catch (_) {
      record(routeOf(req), sw.elapsed, error: true);
      rethrow;
    }
  };
}

class _Bucket {
  int count = 0;
  int errors = 0;
  final samples = <double>[];

  double? percentile(double p) {
    if (samples.isEmpty) return null;
    final s = [...samples]..sort();
    return s[((s.length - 1) * p).round()];
  }
}

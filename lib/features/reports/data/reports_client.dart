import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

class ReportsException implements Exception {
  const ReportsException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Signalements « Chicken » partagés (serveur VIGIROAD).
abstract interface class ReportsClient {
  /// Signalements actifs d'une zone.
  Future<List<ChickenReport>> inBox(BBox box);

  /// Envoie un signalement. [heading] : cap du conducteur (null à l'arrêt).
  Future<ChickenReport> submit({required LatLng position, double? heading, required ReportSide side});
}

class HttpReportsClient implements ReportsClient {
  HttpReportsClient({
    required this.baseUrl,
    required this.apiKey,
    required this.userAgent,
    http.Client? client,
    this.extraHeaders = const {},
    this.onRejected,
  }) : _client = client ?? http.Client();

  /// Version de l'application (refus des versions obsolètes par le serveur).
  final Map<String, String> extraHeaders;

  /// Version refusée (426) : obsolète ou bloquée à distance.
  final void Function({required bool blocked, String? message})? onRejected;

  final String baseUrl;
  final String apiKey;
  final String userAgent;
  final http.Client _client;

  Uri _uri(String path, [Map<String, String>? q]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: q);
  }

  Map<String, String> get _headers => {
    'X-Api-Key': apiKey,
    'User-Agent': userAgent,
    'Accept': 'application/json',
    ...extraHeaders,
  };

  @override
  Future<List<ChickenReport>> inBox(BBox box) async {
    final j = await _json(() => _client.get(
      _uri('/v1/reports', {'bbox': [for (final v in box.toJson()) v.toStringAsFixed(5)].join(',')}),
      headers: _headers,
    ));
    final raw = j['reports'];
    if (raw is! List) throw const ReportsException('Réponse du serveur illisible');
    return [for (final r in raw) ChickenReport.fromJson(r as Map<String, dynamic>)];
  }

  @override
  Future<ChickenReport> submit({required LatLng position, double? heading, required ReportSide side}) async {
    final j = await _json(() => _client.post(
      _uri('/v1/reports'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'position': position.toJson(), 'heading': heading, 'side': side.name}),
    ));
    return ChickenReport.fromJson(j['report'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _json(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(const Duration(seconds: 10));
    } on Exception {
      throw const ReportsException('Serveur injoignable');
    }
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on Object {
      body = null;
    }
    if (res.statusCode == 200 || res.statusCode == 201) {
      if (body == null) throw const ReportsException('Réponse du serveur illisible');
      return body;
    }
    final msg = body?['error'];
    if (res.statusCode == 426) {
      onRejected?.call(blocked: body?['code'] == 'app_blocked', message: msg is String ? msg : null);
    }
    throw ReportsException(switch (res.statusCode) {
      401 => 'Clé du serveur refusée',
      426 => 'Version de VIGIROAD obsolète : mettez à jour l\'application',
      429 => msg is String ? msg : 'Trop de signalements, réessayez dans une minute',
      _ => msg is String ? msg : 'Erreur du serveur (${res.statusCode})',
    });
  }
}

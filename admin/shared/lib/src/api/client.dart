import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Erreur renvoyée par l'API (ou réseau : [status] = 0).
class ApiException implements Exception {
  const ApiException(this.status, this.message, {this.code, this.details});

  final int status;
  final String message;
  final String? code;

  /// Corps complet de la réponse (ex. mise à jour à installer pour un 426).
  final Map<String, dynamic>? details;

  bool get updateRequired => status == 426;

  bool get isNetwork => status == 0;
  bool get isAuth => status == 401;

  @override
  String toString() => message;
}

/// Client HTTPS de l'API d'administration. Le HTTP en clair n'est accepté
/// que pour l'ordinateur local (tunnel SSH, tests).
class AdminClient {
  AdminClient(this.baseUrl, {http.Client? client, this.timeout = const Duration(seconds: 30), this.appTag})
    : _http = client ?? http.Client() {
    if (!isAllowedUrl(baseUrl)) {
      throw const ApiException(0, 'Adresse refusée : HTTPS obligatoire (sauf ordinateur local)', code: 'insecure');
    }
  }

  final Uri baseUrl;
  final Duration timeout;
  final http.Client _http;
  String? token;

  /// Appelé quand la session n'est plus valide (expiration, révocation).
  void Function(ApiException e)? onUnauthorized;

  /// Application et version (« admin-manager/1.7.0 ») : le serveur refuse
  /// (426) une version antérieure à la dernière déposée.
  final String? appTag;

  /// Version refusée : mise à jour à installer (fichiers, empreintes, liens).
  void Function(Map<String, dynamic> update)? onUpdateRequired;

  /// Adresse absolue d'un chemin de l'API (téléchargements).
  Uri resolve(String pathAndQuery) => baseUrl.resolve(pathAndQuery);

  /// Client HTTP sous-jacent (téléchargements en flux).
  http.Client get httpClient => _http;

  static bool isAllowedUrl(Uri u) =>
      u.scheme == 'https' || (u.scheme == 'http' && (u.host == 'localhost' || u.host == '127.0.0.1' || u.host == '::1'));

  /// Normalise une adresse saisie (« vps.exemple.fr » → https://vps.exemple.fr).
  static Uri? parseServer(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'https://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty) return null;
    return u.replace(path: '', query: null, fragment: null);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final q = path.contains('?') ? Uri.splitQueryString(path.split('?')[1]) : <String, String>{};
    return baseUrl.replace(path: path.split('?').first, queryParameters: {...q, ...?query}.isEmpty ? null : {...q, ...?query});
  }

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    'accept': 'application/json',
    if (token != null) 'authorization': 'Bearer $token',
    'x-vigiroad-app': ?appTag,
  };

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String>? query, bool raw = false}) async {
    final req = http.Request(method, _uri(path, query))..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on TimeoutException {
      throw const ApiException(0, 'Le serveur ne répond pas (délai dépassé)', code: 'timeout');
    } on SocketException catch (e) {
      throw ApiException(0, 'Serveur injoignable : ${e.osError?.message ?? e.message}', code: 'network');
    } on HandshakeException {
      throw const ApiException(0, 'Certificat HTTPS invalide ou non reconnu', code: 'tls');
    } on http.ClientException catch (e) {
      throw ApiException(0, 'Connexion impossible : ${e.message}', code: 'network');
    }
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (res.statusCode >= 400) {
      var message = 'Erreur ${res.statusCode}';
      String? code;
      Map<String, dynamic>? details;
      try {
        final j = jsonDecode(text) as Map<String, dynamic>;
        message = j['error'] as String? ?? message;
        code = j['code'] as String?;
        details = j;
      } catch (_) {}
      final e = ApiException(res.statusCode, message, code: code, details: details);
      if (res.statusCode == 401 && token != null && !path.startsWith('/admin/auth/')) onUnauthorized?.call(e);
      if (res.statusCode == 426 && details?['update'] is Map<String, dynamic>) {
        onUpdateRequired?.call(details!['update'] as Map<String, dynamic>);
      }
      throw e;
    }
    if (raw) return text;
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) async =>
      (await _send('GET', path, query: query) as Map<String, dynamic>?) ?? {};

  Future<String> getText(String path) async => await _send('GET', path, raw: true) as String;

  Future<Map<String, dynamic>> post(String path, [Object? body]) async =>
      (await _send('POST', path, body: body ?? const {}) as Map<String, dynamic>?) ?? {};

  Future<Map<String, dynamic>> patch(String path, Object body) async =>
      (await _send('PATCH', path, body: body) as Map<String, dynamic>?) ?? {};

  Future<Map<String, dynamic>> put(String path, Object body) async =>
      (await _send('PUT', path, body: body) as Map<String, dynamic>?) ?? {};

  Future<Map<String, dynamic>> delete(String path, {Map<String, String>? query}) async =>
      (await _send('DELETE', path, query: query) as Map<String, dynamic>?) ?? {};

  /// Flux Server-Sent Events (`event:` / `data:`) de l'API.
  Stream<(String, Map<String, dynamic>)> events(String path) async* {
    final req = http.Request('GET', _uri(path))
      ..headers.addAll({..._headers, 'accept': 'text/event-stream'});
    final res = await _http.send(req).timeout(timeout);
    if (res.statusCode != 200) {
      await res.stream.drain<void>();
      final e = ApiException(res.statusCode, 'Flux temps réel indisponible (${res.statusCode})');
      if (res.statusCode == 401) onUnauthorized?.call(e);
      throw e;
    }
    var event = 'message';
    final data = StringBuffer();
    await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          try {
            yield (event, jsonDecode(data.toString()) as Map<String, dynamic>);
          } on FormatException {
            // Bloc incomplet ignoré.
          }
        }
        event = 'message';
        data.clear();
      } else if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data.write(line.substring(5).trimLeft());
      }
    }
  }

  void close() => _http.close();
}

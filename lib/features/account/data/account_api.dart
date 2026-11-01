import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Erreur renvoyée par le serveur de comptes (ou réseau : [status] = 0).
class AccountException implements Exception {
  const AccountException(this.status, this.message, {this.code});

  final int status;
  final String message;
  final String? code;

  /// La session n'est plus valable (révoquée, expirée, compte désactivé).
  bool get sessionEnded => status == 401;

  @override
  String toString() => message;
}

/// Client des comptes VIGIROAD (`/v1/account/*`), sur le même serveur HTTPS
/// que le trafic. Aucune image, plaque ni voix n'est envoyée.
class AccountApi {
  AccountApi({required this.baseUrl, required this.apiKey, required this.userAgent, http.Client? client})
    : _http = client ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String userAgent;
  final http.Client _http;

  Future<Map<String, dynamic>> _call(String method, String path, {Object? body, String? token}) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll({
        'content-type': 'application/json',
        'user-agent': userAgent,
        'x-api-key': apiKey,
        if (token != null) 'authorization': 'Bearer $token',
      });
    if (body != null) req.body = jsonEncode(body);
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 20)));
    } on TimeoutException {
      throw const AccountException(0, 'Le serveur ne répond pas. Vérifiez votre connexion.');
    } on SocketException {
      throw const AccountException(0, 'Pas de connexion au serveur VIGIROAD.');
    } on http.ClientException {
      throw const AccountException(0, 'Pas de connexion au serveur VIGIROAD.');
    }
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    Map<String, dynamic> json = const {};
    try {
      if (text.isNotEmpty) json = jsonDecode(text) as Map<String, dynamic>;
    } on FormatException {
      // Réponse non JSON (proxy, maintenance).
    }
    if (res.statusCode >= 400) {
      throw AccountException(
        res.statusCode,
        json['error'] as String? ?? 'Erreur du serveur (${res.statusCode})',
        code: json['code'] as String?,
      );
    }
    return json;
  }

  Future<Map<String, dynamic>> register({
    required String pseudonym,
    required String password,
    String? email,
    String? displayName,
    required bool regionConsent,
    required bool locationConsent,
    Map<String, Object?>? device,
    String? appVersion,
  }) => _call('POST', '/v1/account/register', body: {
    'pseudonym': pseudonym,
    'password': password,
    'email': ?email,
    'displayName': ?displayName,
    'consents': {'region': regionConsent, 'location': locationConsent},
    'device': ?device,
    'appVersion': ?appVersion,
  });

  Future<Map<String, dynamic>> login(String login, String password, {Map<String, Object?>? device, String? appVersion}) =>
      _call('POST', '/v1/account/login', body: {'login': login, 'password': password, 'device': ?device, 'appVersion': ?appVersion});

  Future<void> reset(String login, String code, String newPassword) =>
      _call('POST', '/v1/account/reset', body: {'login': login, 'code': code, 'newPassword': newPassword});

  Future<void> logout(String token) => _call('POST', '/v1/account/logout', token: token);

  Future<Map<String, dynamic>> me(String token) => _call('GET', '/v1/account/me', token: token);

  Future<Map<String, dynamic>> update(String token, Map<String, Object?> body) =>
      _call('PATCH', '/v1/account/me', token: token, body: body);

  Future<void> delete(String token, String password) =>
      _call('POST', '/v1/account/me/delete', token: token, body: {'password': password});

  Future<Map<String, dynamic>> export(String token) => _call('GET', '/v1/account/data', token: token);

  Future<String> registerDevice(String token, Map<String, Object?> device) async =>
      (await _call('POST', '/v1/account/device', token: token, body: device))['deviceId'] as String;

  Future<void> forgetDevice(String token) => _call('DELETE', '/v1/account/device', token: token);

  /// Battement de cœur (application au premier plan). [lat]/[lng] seulement
  /// avec le consentement « position approximative ».
  Future<Map<String, dynamic>> heartbeat(String token, {String? appVersion, double? lat, double? lng}) => _call(
    'POST',
    '/v1/account/heartbeat',
    token: token,
    body: {
      'appVersion': ?appVersion,
      if (lat != null && lng != null) 'location': {'lat': lat, 'lng': lng},
    },
  );

  Future<Map<String, dynamic>> sessions(String token) => _call('GET', '/v1/account/sessions', token: token);

  Future<void> revokeSession(String token, String id) => _call('POST', '/v1/account/sessions/$id/revoke', token: token);

  Future<void> clearLocation(String token) => _call('DELETE', '/v1/account/location', token: token);
}

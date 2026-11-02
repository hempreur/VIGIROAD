import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

/// Règle de version de l'application VIGIROAD, lue auprès de l'API
/// d'administration (réseau Docker interne) : les applications obsolètes ou
/// bloquées à distance n'obtiennent plus aucune donnée (trafic, limitations,
/// signalements) et chaque refus est journalisé dans ADMIN MANAGER.
///
/// L'application envoie `X-App-Build` (numéro de compilation),
/// `X-App-Version` et `X-App-Platform` ; les versions 1.6 et antérieures
/// n'envoient rien et sont donc refusées dès qu'une règle est en vigueur.
/// Sans réponse de l'API d'administration depuis [staleAfter], plus rien
/// n'est refusé (une panne ne doit pas couper toutes les applications).
class AppPolicyClient {
  AppPolicyClient({
    required this.adminUrl,
    required this.apiKey,
    http.Client? client,
    this.refreshEvery = const Duration(seconds: 60),
    this.staleAfter = const Duration(minutes: 15),
    DateTime Function()? clock,
  }) : _http = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final Uri adminUrl;
  final String apiKey;
  final http.Client _http;
  final Duration refreshEvery;
  final Duration staleAfter;
  final DateTime Function() _clock;
  Timer? _timer;

  int minBuild = 0;
  bool blocked = false;
  String? message;
  DateTime? loadedAt;
  final _reported = <String, DateTime>{};

  void start() {
    unawaited(refresh());
    _timer = Timer.periodic(refreshEvery, (_) => unawaited(refresh()));
  }

  void stop() => _timer?.cancel();

  bool get active => loadedAt != null && _clock().difference(loadedAt!) < staleAfter;

  Future<void> refresh() async {
    try {
      final r = await _http
          .get(adminUrl.resolve('/v1/app/policy'), headers: {'x-api-key': apiKey})
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      apply(minBuild: (j['minBuild'] as num?)?.toInt() ?? 0, blocked: j['blocked'] == true, message: j['message'] as String?);
    } on Object catch (e) {
      stderr.writeln('Règle de version indisponible : $e');
    }
  }

  void apply({required int minBuild, required bool blocked, String? message}) {
    this.minBuild = minBuild;
    this.blocked = blocked;
    this.message = message;
    loadedAt = _clock();
  }

  /// `null` si la requête est acceptée, sinon la réponse 426 à renvoyer.
  Response? check(Request req, String client) {
    if (!active) return null;
    final build = int.tryParse(req.headers['x-app-build'] ?? '');
    final String status;
    if (blocked) {
      status = 'blocked';
    } else if (build == null || build < minBuild) {
      status = 'outdated';
    } else {
      return null;
    }
    _report(req, client, status, build);
    return Response(
      426,
      body: jsonEncode({
        'error': status == 'blocked'
            ? (message ?? 'VIGIROAD est temporairement suspendu.')
            : 'Version de VIGIROAD obsolète : installez la dernière version.',
        'code': status == 'blocked' ? 'app_blocked' : 'update_required',
      }),
      headers: const {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'},
    );
  }

  /// Journalisé une fois par connexion et par 10 minutes.
  void _report(Request req, String client, String status, int? build) {
    final now = _clock();
    final last = _reported[client];
    if (last != null && now.difference(last) < const Duration(minutes: 10)) return;
    _reported[client] = now;
    if (_reported.length > 20000) _reported.removeWhere((_, t) => now.difference(t) > const Duration(minutes: 10));
    unawaited(
      _http
          .post(
            adminUrl.resolve('/v1/app/rejected'),
            headers: {'x-api-key': apiKey, 'content-type': 'application/json', 'x-forwarded-for': client},
            body: jsonEncode({
              'platform': req.headers['x-app-platform'] ?? 'inconnu',
              'version': req.headers['x-app-version'] ?? '1.6 ou antérieure',
              'build': build,
              'status': status,
            }),
          )
          .timeout(const Duration(seconds: 10))
          .then((_) {}, onError: (Object _) {}),
    );
  }
}

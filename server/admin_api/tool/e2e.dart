// Vérification de bout en bout de la pile déployée (Docker Compose + Caddy) :
//   dart run tool/e2e.dart https://localhost
// Variables : VR_APP_KEY, VR_SETUP_TOKEN. Certificat local de Caddy accepté
// pour « localhost » uniquement.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:vigiroad_admin_api/admin_api.dart' show Totp;

late Uri base;
late http.Client client;
var failures = 0;

void check(bool ok, String label, [Object? detail]) {
  stdout.writeln('${ok ? '✅' : '❌'} $label${detail == null ? '' : ' — $detail'}');
  if (!ok) failures++;
}

Future<(int, dynamic)> call(String method, String path, {Object? body, String? token, Map<String, String>? headers}) async {
  final req = http.Request(method, base.replace(path: path.split('?').first, query: path.contains('?') ? path.split('?')[1] : null))
    ..headers.addAll({'content-type': 'application/json', if (token != null) 'authorization': 'Bearer $token', ...?headers});
  if (body != null) req.body = jsonEncode(body);
  final res = await http.Response.fromStream(await client.send(req).timeout(const Duration(seconds: 120)));
  final isJson = (res.headers['content-type'] ?? '').contains('json');
  return (res.statusCode, isJson && res.body.isNotEmpty ? jsonDecode(res.body) : res.body);
}

Future<T> until<T>(String label, Future<T?> Function() probe, {Duration timeout = const Duration(minutes: 3)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final v = await probe();
    if (v != null) return v;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  throw TimeoutException(label);
}

Future<void> main(List<String> args) async {
  base = Uri.parse(args.isEmpty ? 'https://localhost' : args.first);
  client = IOClient(HttpClient()..badCertificateCallback = (c, host, p) => host == 'localhost');
  final appKey = Platform.environment['VR_APP_KEY']!;
  final setupToken = Platform.environment['VR_SETUP_TOKEN']!;

  var (s, b) = await call('GET', '/admin/health');
  check(s == 200, 'API d\'administration en HTTPS derrière Caddy', b);
  (s, b) = await call('GET', '/health');
  check(s == 200, 'serveur de trafic toujours servi', b);

  // Premier administrateur avec TOTP.
  (s, b) = await call('POST', '/admin/setup', body: {
    'setupToken': setupToken,
    'email': 'proprietaire@vigiroad.test',
    'displayName': 'CI',
    'password': 'CI-MotDePasse-2026',
  });
  check(s == 201, 'création du propriétaire', s);
  final secret = b['enrollment']['secret'] as String;
  (s, b) = await call('POST', '/admin/auth/mfa', body: {'ticket': b['ticket'], 'code': Totp.code(secret, Totp.step(DateTime.now()))});
  check(s == 200, 'double authentification TOTP', s);
  final token = b['token'] as String;
  final tokenFile = Platform.environment['VR_TOKEN_FILE'];
  if (tokenFile != null) File(tokenFile).writeAsStringSync(token);

  // Comptes mobiles.
  final tokens = <String>[];
  for (var i = 0; i < 3; i++) {
    (s, b) = await call('POST', '/v1/account/register', headers: {'x-api-key': appKey}, body: {
      'pseudonym': 'ci_user_$i',
      'password': 'Conduite2026',
      'appVersion': '1.4.0',
      'device': {'installationId': 'ci-installation-000$i', 'brand': 'Google', 'model': 'Pixel 9', 'os': 'android', 'osVersion': '16'},
    });
    check(s == 201, 'inscription ci_user_$i', s);
    tokens.add(b['token'] as String);
  }
  for (final t in tokens) {
    (s, b) = await call('POST', '/v1/account/heartbeat', token: t, body: {'appVersion': '1.4.0'});
  }
  check(s == 200, 'battements de cœur', b);
  (s, b) = await call('GET', '/admin/dashboard', token: token);
  check(s == 200 && b['usersTotal'] == 3 && b['usersOnline'] == 3, 'tableau de bord : 3 comptes connectés', b['usersOnline']);

  // Supervision réelle par l'agent.
  (s, b) = await call('GET', '/admin/server/overview', token: token);
  final metrics = b['metrics'] as Map<String, dynamic>?;
  check(s == 200 && b['agentError'] == null, 'agent de supervision joignable', b['agentError']);
  check((metrics?['memory']?['total'] as num? ?? 0) > 0, 'RAM de l\'hôte', metrics?['memory']);
  check(((metrics?['disks'] as List?) ?? const []).isNotEmpty, 'disque de l\'hôte', metrics?['disks']);
  check(b['system']?['os'] != null, 'système', b['system']?['os']);
  await Future<void>.delayed(const Duration(seconds: 3));
  (s, b) = await call('GET', '/admin/server/overview', token: token);
  check((b['metrics']?['cpuPercent']) != null, 'processeur en temps réel', b['metrics']?['cpuPercent']);

  (s, b) = await call('GET', '/admin/docker/containers', token: token);
  final containers = ((b['containers'] as List?) ?? const []).cast<Map<String, dynamic>>();
  final services = {for (final c in containers) if (c['vigiroad'] == true) c['service']: c};
  check(
    services.keys.toSet().containsAll({'traffic', 'admin-api', 'postgres', 'agent', 'backup', 'caddy'}),
    'conteneurs VIGIROAD détectés',
    services.keys.toList(),
  );
  check(services.values.every((c) => c['state'] == 'running'), 'tous en fonctionnement');
  check(services['traffic']?['stats']?['memUsage'] != null, 'CPU/RAM par conteneur', services['traffic']?['stats']);
  check((services['postgres']?['actions'] as List?)?.contains('stop') == false, 'PostgreSQL : arrêt interdit');

  final trafficId = services['traffic']!['id'] as String;
  (s, b) = await call('GET', '/admin/docker/containers/$trafficId/logs?tail=20', token: token);
  check(s == 200 && (b['lines'] as List).isNotEmpty, 'journaux du conteneur trafic', (b['lines'] as List?)?.length);
  (s, b) = await call('POST', '/admin/docker/containers/${services['postgres']!['id']}/stop', token: token);
  check(s == 403, 'arrêt de PostgreSQL refusé par l\'agent', s);
  (s, b) = await call('POST', '/admin/docker/containers/$trafficId/restart', token: token);
  check(s == 200, 'redémarrage contrôlé du serveur de trafic', b);
  await until('trafic de retour', () async => (await call('GET', '/health')).$1 == 200 ? true : null);
  check(true, 'serveur de trafic de nouveau disponible');

  for (final p in ['/admin/docker/volumes', '/admin/docker/networks', '/admin/docker/images', '/admin/server/processes']) {
    (s, b) = await call('GET', p, token: token);
    check(s == 200, p, s == 200 ? null : b);
  }
  (s, b) = await call('GET', '/admin/vigiroad/status', token: token);
  check(s == 200 && b['traffic']['ok'] == true && b['database']['schemaVersion'] == 1, 'état VIGIROAD', b['traffic']?['ok']);

  // Sauvegarde puis test de restauration par le service « backup ».
  (s, b) = await call('POST', '/admin/backups', token: token, body: {'kind': 'manual'});
  check(s == 202, 'sauvegarde demandée', b);
  Future<Map<String, dynamic>?> job(int id) async {
    final (_, l) = await call('GET', '/admin/backups', token: token);
    final j = (l['items'] as List).cast<Map<String, dynamic>>().firstWhere((x) => x['id'] == id);
    return j['status'] == 'success' || j['status'] == 'failed' ? j : null;
  }

  var done = await until('sauvegarde', () => job(b['id'] as int));
  check(done['status'] == 'success', 'sauvegarde réalisée', '${done['fileName']} ${done['sizeBytes']} octets');
  (s, b) = await call('POST', '/admin/backups', token: token, body: {'kind': 'restore_test'});
  done = await until('restauration', () => job(b['id'] as int));
  check(done['status'] == 'success', 'test de restauration', done['message']);

  (s, b) = await call('GET', '/admin/diagnostics', token: token);
  for (final c in (b['checks'] as List).cast<Map<String, dynamic>>()) {
    stdout.writeln('   diagnostic ${c['ok'] ? '✓' : '·'} ${c['label']} : ${c['detail']}');
  }
  final checks = {for (final c in b['checks'] as List) c['id']: c['ok']};
  check(checks['database'] == true && checks['agent'] == true && checks['containers'] == true, 'diagnostic');
  check(checks['backup'] == true && checks['restore'] == true, 'diagnostic : sauvegarde et restauration récentes');

  (s, b) = await call('POST', '/admin/updates/deploy', token: token);
  check(s == 202, 'mise à jour à distance : demande transmise à l\'hôte', b);

  // Flux temps réel au travers de Caddy.
  final sse = http.Request('GET', base.replace(path: '/admin/events'))..headers['authorization'] = 'Bearer $token';
  final res = await client.send(sse);
  final first = await res.stream.transform(utf8.decoder).firstWhere((c) => c.contains('event: snapshot')).timeout(
    const Duration(seconds: 20),
  );
  check(first.contains('usersOnline'), 'flux SSE temps réel via HTTPS');

  stdout.writeln(failures == 0 ? '\nBout en bout : tout est conforme.' : '\n$failures vérification(s) en échec.');
  exit(failures == 0 ? 0 : 1);
}

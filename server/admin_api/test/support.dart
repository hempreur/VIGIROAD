import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:vigiroad_admin_api/admin_api.dart';

const appKey = 'cle-application-test-1234567890';
const setupToken = 'jeton-installation-test-abcdef';
const ownerPassword = 'MotDePasseAdmin2026';
const releaseToken = 'jeton-depot-ci-0123456789abcdef';

/// Base de test (CI : service PostgreSQL ; en local : variables VR_TEST_DB_*).
Map<String, String> testDbEnv() {
  final e = Platform.environment;
  return {
    'VR_DB_HOST': e['VR_TEST_DB_HOST'] ?? 'localhost',
    'VR_DB_PORT': e['VR_TEST_DB_PORT'] ?? '5432',
    'VR_DB_NAME': e['VR_TEST_DB_NAME'] ?? 'vigiroad_test',
    'VR_DB_USER': e['VR_TEST_DB_USER'] ?? 'postgres',
    'VR_DB_PASSWORD': e['VR_TEST_DB_PASSWORD'] ?? 'postgres',
  };
}

/// Faux agent de supervision (réponses fixes, actions enregistrées).
class FakeAgent {
  final actions = <String>[];
  bool down = false;

  http.Client get client => MockClient((req) async {
    if (down) throw const SocketException('agent arrêté');
    if (req.headers['x-agent-token'] != 'jeton-agent-test-0123456789abcdef') {
      return http.Response(jsonEncode({'error': 'Jeton agent invalide'}), 401);
    }
    final path = req.url.path;
    Object body;
    if (path == '/metrics') {
      body = {
        'cpuPercent': 12.5,
        'load': [0.4, 0.3, 0.2],
        'memory': {'total': 4000000000, 'used': 1500000000, 'available': 2500000000},
        'disks': [
          {'mount': '/', 'total': 40000000000, 'used': 36000000000, 'available': 4000000000},
        ],
        'network': {'rxBps': 1200, 'txBps': 800},
        'temperatures': [],
        'uptimeSeconds': 3600,
      };
    } else if (path == '/system') {
      body = {'hostname': 'vps-test', 'os': 'Ubuntu 24.04 LTS', 'cpus': 2, 'gui': {'xfce': false}};
    } else if (path == '/containers') {
      body = {
        'containers': [
          {'id': 'abc123', 'name': 'deploy-traffic-1', 'service': 'traffic', 'state': 'running', 'vigiroad': true, 'actions': ['restart', 'start', 'stop']},
          {'id': 'def456', 'name': 'deploy-postgres-1', 'service': 'postgres', 'state': 'running', 'vigiroad': true, 'actions': ['restart']},
        ],
      };
    } else if (req.method == 'POST' && path.startsWith('/containers/')) {
      final action = path.split('/').last;
      if (path.contains('def456') && action == 'stop') {
        return http.Response(jsonEncode({'error': 'Action « stop » non autorisée sur ce conteneur'}), 403);
      }
      actions.add(path);
      body = {'ok': true, 'action': action, 'service': 'traffic'};
    } else if (path == '/deploy') {
      body = req.method == 'POST'
          ? {'ok': true, 'state': 'pending'}
          : {'deployed': {'commit': 'abc', 'date': '2026-11-01T10:00:00Z'}, 'state': 'idle', 'log': []};
    } else {
      body = {'items': []};
    }
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
  });
}

/// Faux serveur de trafic.
http.Client fakeTraffic() => MockClient((req) async {
  final now = DateTime.now().toUtc().toIso8601String();
  return switch (req.url.path) {
    '/health' => http.Response(jsonEncode({'status': 'ok', 'sources': 1, 'coverage': ['FR']}), 200),
    '/v1/sources' => http.Response(
      jsonEncode({
        'sources': [
          {'id': 'fr-bison-fute', 'name': 'Bison Futé', 'healthy': true, 'events': 42, 'lastSuccess': now},
        ],
      }),
      200,
    ),
    '/v1/metrics' => http.Response(
      jsonEncode({
        'minutes': [
          {'minute': '${now.substring(0, 16)}:00.000Z', 'route': '/v1/events', 'count': 12, 'errors': 0, 'p50Ms': 3.0, 'p95Ms': 9.0},
        ],
      }),
      200,
    ),
    _ => http.Response('{}', 404),
  };
});

class TestApp {
  TestApp._(this.api, this.ctx, this.agent);

  final AdminApi api;
  final AppContext ctx;
  final FakeAgent agent;
  Db get db => ctx.db;

  static Future<TestApp> start() async {
    final env = {
      ...testDbEnv(),
      'VR_API_KEYS': appKey,
      'VR_ADMIN_SECRET': '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
      'VR_ADMIN_SETUP_TOKEN': setupToken,
      'VR_AGENT_URL': 'http://agent:9100',
      'VR_AGENT_TOKEN': 'jeton-agent-test-0123456789abcdef',
      'VR_ARGON_MEMORY_KB': '1024',
      'VR_ARGON_ITERATIONS': '1',
      'VR_BACKGROUND_JOBS': 'off',
      'VR_DESKTOP_DIR': Directory.systemTemp.createTempSync('vr_desktop').path,
      'VR_RELEASE_TOKEN': releaseToken,
    };
    final config = AdminConfig(env);
    final admin = await Connection.open(
      Endpoint(host: config.dbHost, port: config.dbPort, database: 'postgres', username: config.dbUser, password: config.dbPassword),
      settings: ConnectionSettings(sslMode: SslMode.disable),
    );
    await admin.execute('DROP DATABASE IF EXISTS ${config.dbName} WITH (FORCE)');
    await admin.execute('CREATE DATABASE ${config.dbName}');
    await admin.close();
    final db = await Db.connect(
      host: config.dbHost,
      port: config.dbPort,
      database: config.dbName,
      user: config.dbUser,
      password: config.dbPassword,
    );
    final dir = Directory('../database/migrations').existsSync() ? '../database/migrations' : 'server/database/migrations';
    await db.migrate(dir);
    final ctx = AppContext(
      config: config,
      db: db,
      geo: GeoIp.parse(['203.0.113.0,203.0.113.255,FR', '198.51.100.0,198.51.100.255,BE']),
    );
    final agent = FakeAgent();
    final api = AdminApi(
      ctx,
      agent: AgentClient(config.agentUrl, config.agentToken, client: agent.client),
      traffic: TrafficProbe(Uri.parse('http://traffic:8080'), appKey, client: fakeTraffic()),
    );
    return TestApp._(api, ctx, agent);
  }

  Future<void> close() => db.close();

  Future<(int, dynamic)> call(
    String method,
    String path, {
    Object? body,
    String? token,
    bool appKeyHeader = false,
    String ip = '203.0.113.7',
    Map<String, String> headers = const {},
    List<int>? bytes,
  }) async {
    final res = await api.handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        body: bytes ?? (body == null ? null : jsonEncode(body)),
        headers: {
          'content-type': bytes != null ? 'application/octet-stream' : 'application/json',
          'x-forwarded-for': ip,
          if (token != null) 'authorization': 'Bearer $token',
          if (appKeyHeader) 'x-api-key': appKey,
          ...headers,
        },
      ),
    );
    final text = await res.readAsString();
    if (res.statusCode == 500 && ctx.recentErrors.isNotEmpty) stderr.writeln('ERREUR 500 : ${ctx.recentErrors.first}');
    final type = res.headers['content-type'] ?? '';
    return (res.statusCode, type.contains('json') && text.isNotEmpty ? jsonDecode(text) : text);
  }

  /// Ouvre une session administrateur (le pas TOTP est réinitialisé pour
  /// permettre plusieurs connexions dans la même fenêtre de 30 s).
  Future<String> adminLogin(String email, String password, {String? secret}) async {
    await db.exec('UPDATE admin_accounts SET totp_last_step = 0 WHERE lower(email) = @e', {'e': email.toLowerCase()});
    final (s, b) = await call('POST', '/admin/auth/login', body: {'email': email, 'password': password, 'client': 'test'});
    expect(s, 200, reason: '$b');
    final m = b as Map<String, dynamic>;
    final sec = secret ?? (m['enrollment'] as Map<String, dynamic>?)?['secret'] as String;
    final (s2, b2) = await call(
      'POST',
      '/admin/auth/mfa',
      body: {'ticket': m['ticket'], 'code': Totp.code(sec, Totp.step(DateTime.now()))},
    );
    expect(s2, 200, reason: '$b2');
    return (b2 as Map<String, dynamic>)['token'] as String;
  }
}

/// Faux serveur d'administration pour les tests des applications de bureau
/// (données réalistes, actions enregistrées, flux temps réel).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeAdminBackend {
  FakeAdminBackend({this.needsSetup = false, this.role = 'owner'});

  bool needsSetup;
  String role;
  final requests = <String>[];
  final _sse = StreamController<List<int>>.broadcast();
  final now = DateTime.now().toUtc();

  String _ago(Duration d) => now.subtract(d).toIso8601String();

  void close() => unawaited(_sse.close());

  /// Envoie un instantané temps réel aux applications connectées.
  void pushSnapshot({List<Map<String, Object?>> alerts = const []}) {
    _sse.add(utf8.encode('event: snapshot\ndata: ${jsonEncode(snapshot(alerts: alerts))}\n\n'));
  }

  Map<String, Object?> metrics() => {
    'at': now.toIso8601String(),
    'cpuPercent': 23.4,
    'perCore': [31.0, 15.8],
    'load': [0.46, 0.39, 0.31],
    'memory': {'total': 4113000000, 'used': 1690000000, 'available': 2423000000},
    'disks': [
      {'mount': '/', 'total': 41000000000, 'used': 14600000000, 'available': 26400000000},
    ],
    'network': {'rxBps': 48200, 'txBps': 23100, 'rxTotal': 9100000000, 'txTotal': 4400000000},
    'temperatures': [],
    'uptimeSeconds': 1209600,
  };

  Map<String, Object?> snapshot({List<Map<String, Object?>> alerts = const []}) => {
    'at': now.toIso8601String(),
    'metrics': metrics(),
    'counts': {'usersOnline': 37, 'sessionsOnline': 41},
    'alerts': alerts,
    'traffic': {'ok': true, 'latencyMs': 4},
  };

  List<Map<String, Object?>> users() => [
    for (var i = 0; i < 12; i++)
      {
        'id': '00000000-0000-4000-8000-${(i + 1).toString().padLeft(12, '0')}',
        'pseudonym': ['RouteurPro', 'Camille_75', 'nuit.blanche', 'TaxiLyon', 'Mehdi.R', 'Sandrine', 'VTC_Marseille', 'jules',
            'Livreur13', 'A7_Express', 'Inès', 'Baptiste'][i],
        'displayName': i.isEven ? null : ['Camille D.', 'Mehdi R.', 'Sandrine L.', 'Jules P.', 'Inès B.', 'Baptiste M.'][i ~/ 2],
        'email': i % 3 == 0 ? null : 'utilisateur$i@exemple.fr',
        'status': i == 4 ? 'disabled' : 'active',
        'createdAt': _ago(Duration(days: 40 - i * 3)),
        'lastLoginAt': _ago(Duration(hours: i * 5)),
        'lastSeenAt': _ago(Duration(minutes: i * 17)),
        'totalActiveSeconds': 3600 * (30 - i * 2) + 125 * i,
        'country': ['FR', 'FR', 'BE', 'FR', 'CH', 'FR', 'FR', null, 'FR', 'FR', 'LU', 'CA'][i],
        'appVersion': i < 9 ? '1.4.0' : '1.3.0',
        'regionConsent': i != 7,
        'locationConsent': i < 3,
        'devices': 1 + i % 2,
        'openSessions': 1,
        'online': i < 5,
      },
  ];

  List<Map<String, Object?>> devices() => [
    for (var i = 0; i < 8; i++)
      {
        'id': '10000000-0000-4000-8000-${(i + 1).toString().padLeft(12, '0')}',
        'userId': users()[i]['id'],
        'pseudonym': users()[i]['pseudonym'],
        'installationId': 'inst-${(0x5f3a9c + i * 7919).toRadixString(16)}a1b2c3d4',
        'brand': ['Samsung', 'Google', 'Apple', 'Xiaomi', 'OnePlus', 'Samsung', 'Apple', 'Fairphone'][i],
        'model': ['Galaxy S24', 'Pixel 9', 'iPhone 15', 'Redmi Note 13', 'OnePlus 12', 'Galaxy A55', 'iPhone 14', 'Fairphone 5'][i],
        'os': i == 2 || i == 6 ? 'ios' : 'android',
        'osVersion': i == 2 || i == 6 ? '18.1' : '${14 + i % 3}',
        'appVersion': '1.4.0',
        'country': 'FR',
        'firstSeenAt': _ago(Duration(days: 30 - i)),
        'lastSeenAt': _ago(Duration(minutes: i * 9)),
        'revokedAt': null,
        'online': i < 5,
        'sessions': 3 + i,
      },
  ];

  List<Map<String, Object?>> sessions() => [
    for (var i = 0; i < 10; i++)
      {
        'id': '20000000-0000-4000-8000-${(i + 1).toString().padLeft(12, '0')}',
        'userId': users()[i]['id'],
        'pseudonym': users()[i]['pseudonym'],
        'deviceId': devices()[i % 8]['id'],
        'brand': devices()[i % 8]['brand'],
        'model': devices()[i % 8]['model'],
        'startedAt': _ago(Duration(hours: 2 + i)),
        'lastSeenAt': _ago(Duration(seconds: 30 + i * 40)),
        'endedAt': i > 7 ? _ago(const Duration(minutes: 10)) : null,
        'endReason': i > 7 ? 'logout' : null,
        'activeSeconds': 1800 + i * 431,
        'appVersion': '1.4.0',
        'country': 'FR',
        'online': i < 6,
      },
  ];

  Map<String, Object?> _route(String method, String path, Map<String, String> q, Map<String, dynamic> body) {
    switch ((method, path)) {
      case ('GET', '/admin/health'):
        return {'status': 'ok', 'service': 'vigiroad-admin-api', 'version': '1.0.0'};
      case ('GET', '/admin/setup'):
        return {'needed': needsSetup, 'enabled': true};
      case ('POST', '/admin/setup'):
        needsSetup = false;
        return {'mfa': 'enroll', 'ticket': 'vrt_test', 'enrollment': {'secret': 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP', 'uri': 'otpauth://totp/VIGIROAD:test?secret=JBSWY3DPEHPK3PXP'}};
      case ('POST', '/admin/auth/login'):
        if (body['password'] == 'mauvais') throw const _Http(401, 'Identifiant ou mot de passe incorrect');
        return {'mfa': 'required', 'ticket': 'vrt_test'};
      case ('POST', '/admin/auth/mfa'):
        if (body['code'] != '123456') throw const _Http(401, 'Code de vérification incorrect');
        return {
          'token': 'vra_test',
          'admin': {
            'id': 'a0000000-0000-4000-8000-000000000001',
            'email': 'proprietaire@vigiroad.fr',
            'displayName': 'Codex Hempreur',
            'role': role,
            'roleLabel': role == 'owner' ? 'Propriétaire' : 'Lecture seule',
            'permissions': role == 'owner'
                ? ['read', 'serverControl', 'backups', 'usersManage', 'usersDelete', 'export', 'settings', 'adminsManage', 'deploy']
                : ['read'],
          },
        };
      case ('POST', '/admin/auth/logout'):
        return {'ok': true};
      case ('GET', '/admin/dashboard'):
        return {
          'usersTotal': 1284, 'usersDisabled': 6, 'usersNew24h': 23, 'usersOnline': 37, 'devicesTotal': 1391, 'devicesOnline': 39,
          'sessionsOpen': 1502, 'sessionsOnline': 41, 'loginsToday': 412, 'failedLogins24h': 9, 'avgSessionSeconds': 2340.5,
          'usageTodaySeconds': 311200, 'availability24h': 1.0, 'availability30d': 0.9993, 'samples24h': 1440,
          'appVersions': [
            {'version': '1.4.0', 'users': 1012},
            {'version': '1.3.0', 'users': 241},
            {'version': 'inconnue', 'users': 31},
          ],
        };
      case ('GET', '/admin/stats/activity'):
        final days = q['period'] == '30d' ? 30 : (q['period'] == '24h' ? 24 : 7);
        return {
          'period': q['period'],
          'points': [
            for (var i = days - 1; i >= 0; i--)
              {
                'at': (q['period'] == '24h' ? now.subtract(Duration(hours: i)) : now.subtract(Duration(days: i))).toIso8601String(),
                'activeUsers': 180 + (i * 37) % 90,
                'usageSeconds': 200000 + (i * 7919) % 90000,
                'logins': 300 + (i * 53) % 140,
                'failedLogins': (i * 3) % 11,
                'newUsers': 10 + (i * 7) % 15,
              },
          ],
        };
      case ('GET', '/admin/users'):
        final all = users().where((u) => (q['q'] ?? '').isEmpty || '${u['pseudonym']}'.toLowerCase().contains(q['q']!.toLowerCase())).toList();
        return {'total': all.length, 'items': all};
      case ('GET', '/admin/devices'):
        return {'total': 8, 'items': devices()};
      case ('GET', '/admin/sessions'):
        return {'total': 10, 'state': q['state'], 'items': sessions()};
      case ('GET', '/admin/sessions/concurrent'):
        return {
          'items': [
            {'userId': users()[0]['id'], 'pseudonym': 'RouteurPro', 'sessions': 2, 'devices': 2, 'countries': 'FR'},
          ],
        };
      case ('GET', '/admin/login-events'):
        return {
          'total': 3,
          'summary': {'failed24h': 9, 'failed7d': 41, 'success24h': 412},
          'items': [
            for (var i = 0; i < 3; i++)
              {'id': i, 'at': _ago(Duration(minutes: 7 * i)), 'kind': 'user', 'pseudonym': 'jules', 'success': false, 'reason': 'bad_password', 'ipPrefix': '203.0.113.0/24', 'country': 'FR'},
          ],
        };
      case ('GET', '/admin/geo'):
        return {
          'days': 30,
          'countries': [
            {'country': 'FR', 'users': 1104, 'sessions': 9120, 'logins': 8130},
            {'country': 'BE', 'users': 71, 'sessions': 512, 'logins': 470},
            {'country': 'CH', 'users': 38, 'sessions': 260, 'logins': 233},
            {'country': 'CA', 'users': 19, 'sessions': 98, 'logins': 90},
            {'country': 'MA', 'users': 12, 'sessions': 61, 'logins': 57},
          ],
          'points': [
            {'lat': 48.9, 'lng': 2.3, 'samples': 820, 'users': 61},
            {'lat': 45.8, 'lng': 4.8, 'samples': 240, 'users': 17},
            {'lat': 43.3, 'lng': 5.4, 'samples': 190, 'users': 12},
          ],
          'consents': {'region': 1201, 'location': 96, 'total': 1284},
          'geoIp': {'available': true, 'ranges': 612000, 'attribution': 'IP Geolocation by DB-IP (https://db-ip.com), CC BY 4.0'},
          'settings': {'retention.location_days': 30, 'geo.enabled': true},
        };
      case ('GET', '/admin/server/overview'):
        return {
          'system': {
            'hostname': 'vps-vigiroad', 'os': 'Ubuntu 24.04.1 LTS', 'kernel': '6.8.0-48-generic', 'cpus': 2,
            'cpuModel': 'Intel Core Processor (Haswell)', 'uptimeSeconds': 1209600, 'memTotal': 4113000000, 'docker': '27.3.1',
            'project': 'deploy', 'gui': {'xfce': true, 'xrdp': true, 'serverControl': true},
          },
          'metrics': metrics(),
          'agentError': null,
          'alerts': [],
        };
      case ('GET', '/admin/server/history'):
        return {
          'points': [
            for (var i = 47; i >= 0; i--)
              {
                'at': now.subtract(Duration(minutes: 30 * i)).toIso8601String(),
                'cpu': 15 + (i * 13) % 30, 'cpuMax': 40 + (i * 7) % 45, 'load1': 0.4, 'memUsed': 1.6e9 + (i % 7) * 4e7,
                'memTotal': 4.1e9, 'diskUsed': 1.46e10, 'diskTotal': 4.1e10, 'rx': 40000 + (i * 911) % 30000,
                'tx': 20000 + (i * 577) % 15000, 'temp': null, 'availability': 1.0, 'latency': 4,
              },
          ],
        };
      case ('GET', '/admin/server/processes'):
        return {
          'processes': [
            {'pid': 1543, 'name': 'server', 'state': 'S', 'cpuPercent': 3.2, 'rss': 61000000},
            {'pid': 1602, 'name': 'admin_api', 'state': 'S', 'cpuPercent': 1.1, 'rss': 48000000},
            {'pid': 988, 'name': 'postgres', 'state': 'S', 'cpuPercent': 0.6, 'rss': 92000000},
            {'pid': 801, 'name': 'dockerd', 'state': 'S', 'cpuPercent': 0.4, 'rss': 83000000},
            {'pid': 1101, 'name': 'caddy', 'state': 'S', 'cpuPercent': 0.2, 'rss': 39000000},
          ],
          'services': [
            {'process': 'sshd', 'label': 'SSH', 'instances': 1},
            {'process': 'dockerd', 'label': 'Docker', 'instances': 1},
            {'process': 'postgres', 'label': 'PostgreSQL', 'instances': 7},
            {'process': 'xrdp', 'label': 'Bureau à distance (xrdp)', 'instances': 1},
          ],
        };
      case ('GET', '/admin/docker/containers'):
        Map<String, Object?> c(String id, String service, String image, double cpu, int mem, List<String> actions, {List<String> ports = const []}) => {
          'id': id, 'name': 'deploy-$service-1', 'image': image, 'state': 'running', 'status': 'Up 3 days', 'service': service,
          'project': 'deploy', 'vigiroad': true, 'actions': actions, 'health': null, 'ports': ports,
          'stats': {'cpuPercent': cpu, 'memUsage': mem, 'memLimit': 4113000000},
        };
        return {
          'containers': [
            c('a1b2c3d4e5f6', 'traffic', 'vigiroad-traffic:local', 2.4, 58000000, ['restart', 'start', 'stop']),
            c('b2c3d4e5f6a1', 'admin-api', 'vigiroad-admin-api:local', 0.9, 46000000, ['restart']),
            c('c3d4e5f6a1b2', 'postgres', 'postgres:16-alpine', 0.5, 88000000, ['restart']),
            c('d4e5f6a1b2c3', 'agent', 'vigiroad-agent:local', 0.3, 21000000, []),
            c('e5f6a1b2c3d4', 'backup', 'postgres:16-alpine', 0.0, 3000000, ['restart']),
            c('f6a1b2c3d4e5', 'caddy', 'caddy:2', 0.2, 37000000, ['restart'], ports: ['80/tcp', '443/tcp']),
          ],
        };
      case ('GET', '/admin/vigiroad/status'):
        return {
          'traffic': {
            'ok': true, 'latencyMs': 4, 'error': null, 'coverage': ['FR'], 'activeSources': 1, 'totalSources': 2, 'events': 1873,
            'sources': [
              {'id': 'fr-bison-fute', 'name': 'Bison Futé — trafic routier national', 'licence': 'Licence Ouverte 2.0', 'healthy': true, 'events': 1873, 'lastSuccess': _ago(const Duration(minutes: 3)), 'lastError': null, 'usingFallback': false},
              {'id': 'gb-tfl', 'name': 'Transport for London', 'licence': 'OGL', 'healthy': false, 'events': 0, 'lastSuccess': null, 'lastError': 'clé absente', 'usingFallback': false},
            ],
          },
          'adminApi': {'ok': true, 'recentErrors': 0},
          'database': {'ok': true, 'latencyMs': 1, 'schemaVersion': 1, 'sizeBytes': 18400000, 'connections': 4},
          'agent': {'ok': true, 'error': null},
          'certificate': {'expiresAt': now.add(const Duration(days: 71)).toIso8601String(), 'error': null},
          'requests24h': [
            {'service': 'traffic', 'requests': 48211, 'errors': 3, 'p50Ms': 2.1, 'p95Ms': 11.4},
            {'service': 'admin-api', 'requests': 61002, 'errors': 0, 'p50Ms': 3.4, 'p95Ms': 18.2},
          ],
          'geoIp': true,
        };
      case ('GET', '/admin/vigiroad/requests'):
        return {
          'series': [
            for (var i = 23; i >= 0; i--)
              for (final s in ['traffic', 'admin-api'])
                {
                  'at': now.subtract(Duration(hours: i)).toIso8601String(), 'service': s, 'requests': (s == 'traffic' ? 1800 : 2400) + (i * 97) % 600,
                  'errors': i % 9 == 0 ? 1 : 0, 'p50Ms': 2.5, 'p95Ms': (s == 'traffic' ? 9 : 16) + (i % 5).toDouble(),
                },
          ],
          'routes': [
            {'service': 'admin-api', 'route': '/v1/account/heartbeat', 'requests': 58000, 'errors': 0, 'p50Ms': 3.1, 'p95Ms': 9.8},
            {'service': 'traffic', 'route': '/v1/events/route', 'requests': 21000, 'errors': 2, 'p50Ms': 3.9, 'p95Ms': 14.0},
            {'service': 'traffic', 'route': '/v1/speedlimits', 'requests': 12000, 'errors': 1, 'p50Ms': 6.2, 'p95Ms': 40.5},
          ],
        };
      case ('GET', '/admin/diagnostics'):
        return {
          'at': now.toIso8601String(),
          'checks': [
            {'id': 'database', 'label': 'Base PostgreSQL', 'ok': true, 'level': 'ok', 'detail': 'schéma v1, réponse en 2 ms'},
            {'id': 'agent', 'label': 'Agent de supervision', 'ok': true, 'level': 'ok', 'detail': 'joignable'},
            {'id': 'containers', 'label': 'Conteneurs VIGIROAD', 'ok': true, 'level': 'ok', 'detail': '6 en fonctionnement'},
            {'id': 'traffic', 'label': 'Serveur de trafic', 'ok': true, 'level': 'ok', 'detail': 'répond en 4 ms'},
            {'id': 'sources', 'label': 'Flux routiers', 'ok': false, 'level': 'warning', 'detail': 'en échec : gb-tfl'},
            {'id': 'backup', 'label': 'Sauvegarde', 'ok': true, 'level': 'ok', 'detail': 'dernière : cette nuit'},
            {'id': 'restore', 'label': 'Restauration testée', 'ok': true, 'level': 'ok', 'detail': 'dernier test : dimanche'},
          ],
        };
      case ('GET', '/admin/backups'):
        return {
          'keep': 14,
          'items': [
            {'id': 3, 'kind': 'scheduled', 'status': 'success', 'createdAt': _ago(const Duration(hours: 9)), 'finishedAt': _ago(const Duration(hours: 9)), 'fileName': 'vigiroad-20261101-030000.dump', 'sizeBytes': 4210000, 'message': '17 tables sauvegardées'},
            {'id': 2, 'kind': 'restore_test', 'status': 'success', 'createdAt': _ago(const Duration(days: 2)), 'finishedAt': _ago(const Duration(days: 2)), 'fileName': 'vigiroad-20261030-030000.dump', 'sizeBytes': null, 'message': 'restauration réussie : schéma v1, 17 tables, 1279 comptes'},
          ],
        };
      case ('POST', '/admin/backups'):
        return {'id': 4, 'status': 'pending'};
      case ('GET', '/admin/updates'):
        return {
          'deploy': {'deployed': {'commit': '9f8e7d6c5b4a', 'date': _ago(const Duration(days: 1))}, 'state': 'idle', 'log': []},
          'latestCommit': {'sha': '9f8e7d6c5b4a', 'message': 'feat(admin): VIGIROAD Control Center', 'date': _ago(const Duration(days: 1))},
          'latestRelease': {'tag': 'v1.4.0', 'publishedAt': _ago(const Duration(days: 1))},
          'updateAvailable': false,
        };
      case ('GET', '/admin/errors'):
        return {'internal': [], 'sources': [{'source': 'gb-tfl', 'error': 'clé absente', 'lastAttempt': _ago(const Duration(minutes: 2))}], 'backups': [], 'failedLogins': [], 'requestErrors': []};
      case ('GET', '/admin/app/versions'):
        return {
          'policy': {
            'blocked': false,
            'message': 'VIGIROAD est temporairement suspendu.',
            'manualMinBuild': 0,
            'forceLatest': true,
            'minBuild': 13,
            'latest': {'version': '1.7.0', 'build': 13, 'minBuild': 13, 'checkedAt': _ago(const Duration(minutes: 4))},
          },
          'desktop': {'admin-manager': '1.7.0', 'server-control': '1.7.0'},
          'counts': {'last24h': 3, 'last7d': 11},
          'events': [
            {'id': 3, 'at': _ago(const Duration(minutes: 6)), 'app': 'gps', 'platform': 'android', 'version': '1.6.0', 'build': 12, 'status': 'outdated', 'required': '1.7.0', 'source': 'app', 'model': 'Xiaomi Redmi Note 13', 'os': 'android 14', 'ipPrefix': '86.242.18.0/24', 'country': 'FR', 'pseudonym': 'Camille_75'},
            {'id': 2, 'at': _ago(const Duration(minutes: 31)), 'app': 'gps', 'platform': 'inconnu', 'version': '1.6 ou antérieure', 'build': null, 'status': 'outdated', 'required': '1.7.0', 'source': 'traffic', 'ipPrefix': '78.193.4.0/24', 'country': 'BE'},
            {'id': 1, 'at': _ago(const Duration(hours: 3)), 'app': 'admin-manager', 'platform': 'windows', 'version': '1.6.0', 'build': null, 'status': 'outdated', 'required': '1.7.0', 'source': 'admin', 'ipPrefix': '90.12.4.0/24', 'country': 'FR', 'adminEmail': 'support@vigiroad.fr'},
          ],
          'inUse': [
            {'app': 'gps', 'platform': 'android', 'version': '1.7.0', 'build': 13, 'checks': 214, 'lastDay': _ago(Duration.zero)},
            {'app': 'gps', 'platform': 'ios', 'version': '1.7.0', 'build': 13, 'checks': 38, 'lastDay': _ago(Duration.zero)},
          ],
        };
      case ('GET', '/admin/audit'):
        return {
          'total': 2,
          'items': [
            {'id': 2, 'at': _ago(const Duration(minutes: 5)), 'adminEmail': 'proprietaire@vigiroad.fr', 'action': 'user.disable', 'targetType': 'user', 'targetId': '00000000-0000-4000-8000-000000000005', 'success': true, 'details': {}},
            {'id': 1, 'at': _ago(const Duration(minutes: 9)), 'adminEmail': 'proprietaire@vigiroad.fr', 'action': 'admin.login', 'targetType': null, 'targetId': null, 'success': true, 'details': {'client': 'windows'}},
          ],
        };
      case ('GET', '/admin/admins'):
        return {
          'admins': [
            {'id': 'a0000000-0000-4000-8000-000000000001', 'email': 'proprietaire@vigiroad.fr', 'displayName': 'Codex Hempreur', 'role': 'owner', 'status': 'active', 'totpConfirmed': true, 'lastLoginAt': _ago(const Duration(minutes: 1)), 'locked': false},
            {'id': 'a0000000-0000-4000-8000-000000000002', 'email': 'support@vigiroad.fr', 'displayName': 'Support', 'role': 'viewer', 'status': 'active', 'totpConfirmed': false, 'lastLoginAt': null, 'locked': false},
          ],
          'roles': {'owner': 'Propriétaire', 'admin': 'Administrateur', 'operator': 'Opérateur serveur', 'viewer': 'Lecture seule'},
        };
      case ('GET', '/admin/settings'):
        return {
          'settings': {
            'retention.login_events_days': 180, 'retention.sessions_days': 365, 'retention.location_days': 30, 'retention.metrics_days': 30,
            'retention.audit_days': 730, 'sessions.idle_expiry_days': 30, 'geo.enabled': true, 'backups.keep': 14,
          },
          'limits': {
            'retention.login_events_days': [7, 3650], 'retention.sessions_days': [30, 3650], 'retention.location_days': [1, 365],
            'retention.metrics_days': [7, 365], 'retention.audit_days': [90, 3650], 'sessions.idle_expiry_days': [1, 365], 'backups.keep': [3, 90],
          },
        };
    }
    final user = RegExp(r'^/admin/users/([0-9a-f-]{36})$').firstMatch(path);
    if (method == 'GET' && user != null) {
      final u = users().firstWhere((x) => x['id'] == user.group(1), orElse: () => users().first);
      return {
        'user': u,
        'devices': devices().take(2).toList(),
        'sessions': sessions().take(4).toList(),
        'usage': [for (var i = 0; i < 20; i++) {'day': now.subtract(Duration(days: i)).toIso8601String(), 'activeSeconds': 900 + (i * 431) % 3600, 'sessions': 2}],
        'logins': [
          {'at': _ago(const Duration(hours: 2)), 'success': true, 'reason': 'password', 'ipPrefix': '203.0.113.0/24', 'country': 'FR'},
          {'at': _ago(const Duration(hours: 3)), 'success': false, 'reason': 'bad_password', 'ipPrefix': '203.0.113.0/24', 'country': 'FR'},
        ],
        'locations': [
          {'at': _ago(const Duration(hours: 1)), 'lat': 48.85, 'lng': 2.35, 'country': 'FR'},
        ],
      };
    }
    if (method == 'POST' && path.endsWith('/reset-access')) return {'code': 'K7QM-2XPA-W4ZT', 'expiresAt': now.add(const Duration(minutes: 30)).toIso8601String()};
    if (method == 'POST' && path.endsWith('/revoke-sessions')) return {'revoked': 2};
    if (method == 'POST' || method == 'PATCH' || method == 'PUT' || method == 'DELETE') return {'ok': true, 'user': users().first};
    throw const _Http(404, 'Ressource introuvable');
  }

  http.Client client() => MockClient.streaming((req, bodyStream) async {
    final body = await bodyStream.bytesToString();
    requests.add('${req.method} ${req.url.path}');
    if (req.url.path == '/admin/events') {
      return http.StreamedResponse(_sse.stream, 200, headers: {'content-type': 'text/event-stream'});
    }
    try {
      final r = _route(
        req.method,
        req.url.path,
        req.url.queryParameters,
        body.isEmpty ? const {} : jsonDecode(body) as Map<String, dynamic>,
      );
      return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(r))), 200, headers: {'content-type': 'application/json'});
    } on _Http catch (e) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'error': e.message}))),
        e.status,
        headers: {'content-type': 'application/json'},
      );
    }
  });
}

class _Http implements Exception {
  const _Http(this.status, this.message);
  final int status;
  final String message;
}

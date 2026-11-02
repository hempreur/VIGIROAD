@Tags(['db'])
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as c;
import 'package:test/test.dart';
import 'package:vigiroad_admin_api/admin_api.dart';

import 'support.dart';

/// Contrôle des versions : application GPS obsolète ou bloquée à distance,
/// journal, règle lue par le serveur de trafic, applications de bureau
/// déposées par la CI sur le VPS et mises à jour obligatoires.
void main() {
  late TestApp app;
  late String token;
  late String secret;

  Map<String, dynamic> m(Object? o) => o as Map<String, dynamic>;

  setUpAll(() async {
    app = await TestApp.start();
    final (s, b) = await app.call(
      'POST',
      '/admin/setup',
      body: {'setupToken': setupToken, 'email': 'proprio@vigiroad.fr', 'displayName': 'Codex', 'password': ownerPassword},
    );
    expect(s, 201, reason: '$b');
    secret = m(m(b)['enrollment'])['secret'] as String;
    final (s2, b2) = await app.call(
      'POST',
      '/admin/auth/mfa',
      body: {'ticket': m(b)['ticket'], 'code': Totp.code(secret, Totp.step(DateTime.now()))},
    );
    expect(s2, 200, reason: '$b2');
    token = m(b2)['token'] as String;
  });
  tearDownAll(() => app.close());

  Future<(int, dynamic)> status(int build, {String platform = 'android'}) => app.call(
    'POST',
    '/v1/app/status',
    appKeyHeader: true,
    body: {'platform': platform, 'version': '1.$build.0', 'build': build, 'model': 'Xiaomi 23021RAA2Y', 'os': 'Android 14'},
  );

  group('application GPS', () {
    test('sans version publiée connue : tout passe', () async {
      final (s, b) = await status(12);
      expect(s, 200);
      expect(m(b)['status'], 'ok');
    });

    test('clé d\'application exigée', () async {
      final (s, _) = await app.call('POST', '/v1/app/status', body: {'build': 12});
      expect(s, 401);
    });

    test('ancienne version : mise à jour obligatoire et journal', () async {
      await app.db.exec(
        "INSERT INTO settings (key, value) VALUES ('app.latest', CAST(@v AS jsonb)) "
        'ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value',
        {'v': jsonEncode({'version': '1.7.0', 'build': 13, 'minBuild': 13, 'checkedAt': '2026-11-02T00:00:00Z'})},
      );
      var (s, b) = await status(12);
      expect(m(b)['status'], 'update_required');
      expect(m(m(b)['latest'])['version'], '1.7.0');
      expect(m(b)['minBuild'], 13);
      (s, b) = await status(13);
      expect(m(b)['status'], 'ok');
      (s, b) = await status(0, platform: 'ios');
      expect(m(b)['status'], 'update_required');

      final (_, v) = await app.call('GET', '/admin/app/versions', token: token, headers: {'x-vigiroad-app': 'admin-manager/1.7.0'});
      final events = (m(v)['events'] as List).cast<Map<String, dynamic>>();
      expect(events, hasLength(2));
      expect(events.last['platform'], 'android');
      expect(events.last['model'], 'Xiaomi 23021RAA2Y');
      expect(events.last['country'], 'FR');
      expect(events.last['ipPrefix'], isNot(contains('203.0.113.7')));
      expect([for (final r in (m(v)['inUse'] as List).cast<Map<String, dynamic>>()) r['build']], containsAll([12, 13]));
    });

    test('blocage à distance puis déblocage (journalisés dans l\'audit)', () async {
      var (s, b) = await app.call(
        'PUT',
        '/admin/app/policy',
        token: token,
        body: {'blocked': true, 'message': 'Maintenance en cours'},
      );
      expect(s, 200, reason: '$b');
      (s, b) = await status(13);
      expect(m(b)['status'], 'blocked');
      expect(m(b)['message'], 'Maintenance en cours');
      (s, b) = await app.call('GET', '/v1/app/policy', appKeyHeader: true);
      expect(m(b)['blocked'], isTrue);
      await app.call('PUT', '/admin/app/policy', token: token, body: {'blocked': false});
      (s, b) = await status(13);
      expect(m(b)['status'], 'ok');
      final audit = await app.db.scalar<int>("SELECT count(*) FROM admin_audit_logs WHERE action IN ('app.block', 'app.policy')");
      expect(audit, 2);
    });

    test('version minimale manuelle et règle « dernière version » désactivable', () async {
      await app.call('PUT', '/admin/app/policy', token: token, body: {'forceLatest': false, 'minBuild': 10});
      var (_, b) = await status(11);
      expect(m(b)['status'], 'update_required', reason: 'minBuild du manifeste = 13');
      await app.db.exec(
        "UPDATE settings SET value = CAST(@v AS jsonb) WHERE key = 'app.latest'",
        {'v': jsonEncode({'version': '1.7.0', 'build': 13, 'minBuild': 9})},
      );
      (_, b) = await status(11);
      expect(m(b)['status'], 'ok');
      (_, b) = await status(9);
      expect(m(b)['status'], 'update_required', reason: 'minimum manuel 10');
      await app.call('PUT', '/admin/app/policy', token: token, body: {'forceLatest': true, 'minBuild': 0});
    });

    test('requête refusée par le serveur de trafic journalisée', () async {
      final (s, _) = await app.call('POST', '/v1/app/rejected', appKeyHeader: true, body: {'status': 'outdated'});
      expect(s, 200);
      final n = await app.db.scalar<int>("SELECT count(*) FROM app_version_events WHERE source = 'traffic'");
      expect(n, 1);
    });
  });

  group('applications de bureau (hors GitHub)', () {
    final exe = utf8.encode('installateur factice 1.7.0');
    final sha = c.sha256.convert(exe).toString();
    const name = 'vigiroad-1.7.0-admin-manager-setup.exe';
    Map<String, Object?> manifest(String hash) => {
      'admin-manager': {
        'version': '1.7.0',
        'notes': ['Mises à jour automatiques'],
        'files': {
          'windows-installer': {'name': name, 'sha256': hash, 'size': exe.length},
        },
      },
    };

    test('dépôt réservé à la CI (jeton)', () async {
      final (s, _) = await app.call('PUT', '/admin/releases/desktop/$name', bytes: exe, headers: {'x-release-token': 'faux'});
      expect(s, 401);
    });

    test('dépôt, puis manifeste vérifié contre les fichiers', () async {
      var (s, b) = await app.call('PUT', '/admin/releases/desktop/$name', bytes: exe, headers: {'x-release-token': releaseToken});
      expect(s, 201, reason: '$b');
      expect(m(b)['sha256'], sha);
      (s, b) = await app.call(
        'PUT',
        '/admin/releases/desktop/manifest.json',
        bytes: utf8.encode(jsonEncode(manifest('0' * 64))),
        headers: {'x-release-token': releaseToken},
      );
      expect(s, 400, reason: 'empreinte fausse');
      (s, b) = await app.call(
        'PUT',
        '/admin/releases/desktop/manifest.json',
        bytes: utf8.encode(jsonEncode(manifest(sha))),
        headers: {'x-release-token': releaseToken},
      );
      expect(s, 201, reason: '$b');
    });

    test('ancienne application de bureau : refus 426 avec la mise à jour', () async {
      var (s, b) = await app.call('GET', '/admin/me', token: token);
      expect(s, 426, reason: 'application 1.6 sans en-tête de version');
      expect(m(b)['code'], 'update_required');
      (s, b) = await app.call('GET', '/admin/me', token: token, headers: {'x-vigiroad-app': 'admin-manager/1.6.0'});
      expect(s, 426);
      final file = m(m(m(m(b)['update'])['files'])['windows-installer']);
      expect(file['sha256'], sha);
      final url = file['url'] as String;
      expect(url, startsWith('/admin/desktop/files/$name?ticket='));

      // Téléchargement avec le ticket remis (sans session).
      (s, b) = await app.call('GET', url);
      expect(s, 200);
      expect(b, 'installateur factice 1.7.0');
      (s, b) = await app.call('GET', '/admin/desktop/files/$name?ticket=1.faux');
      expect(s, 401);
      (s, b) = await app.call('GET', '/admin/desktop/files/$name');
      expect(s, 401, reason: 'jamais public');

      (s, b) = await app.call('GET', '/admin/me', token: token, headers: {'x-vigiroad-app': 'admin-manager/1.7.0'});
      expect(s, 200);
      final logged = await app.db.scalar<int>("SELECT count(*) FROM app_version_events WHERE source = 'admin'");
      expect(logged, 2);
    });

    test('connexion avec une ancienne application : refus après le mot de passe', () async {
      await app.db.exec("UPDATE admin_accounts SET totp_last_step = 0");
      var (s, b) = await app.call(
        'POST',
        '/admin/auth/login',
        body: {'email': 'proprio@vigiroad.fr', 'password': 'mauvais', 'client': 'windows'},
        headers: {'x-vigiroad-app': 'admin-manager/1.6.0'},
      );
      expect(s, 401, reason: 'aucune information sans le bon mot de passe');
      (s, b) = await app.call(
        'POST',
        '/admin/auth/login',
        body: {'email': 'proprio@vigiroad.fr', 'password': ownerPassword, 'client': 'windows'},
        headers: {'x-vigiroad-app': 'admin-manager/1.6.0'},
      );
      expect(s, 426);
      expect(m(m(b)['update'])['version'], '1.7.0');
    });

    test('manifeste public sans lien direct', () async {
      final (s, b) = await app.call('GET', '/admin/desktop/manifest');
      expect(s, 200);
      expect(m(m(b)['admin-manager'])['version'], '1.7.0');
      expect(jsonEncode(b), isNot(contains('http')));
    });
  });
}

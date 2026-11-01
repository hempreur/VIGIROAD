@Tags(['db'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:vigiroad_admin_api/admin_api.dart';

import 'support.dart';

/// Scénarios complets contre une vraie base PostgreSQL : comptes mobiles,
/// administrateurs (mot de passe + TOTP), rôles, appareils, sessions, temps
/// d'utilisation, localisation consentie, supervision, sauvegardes, audit.
void main() {
  late TestApp app;
  late String ownerToken;
  late String ownerSecret;

  setUpAll(() async {
    app = await TestApp.start();
  });
  tearDownAll(() => app.close());

  Map<String, dynamic> m(Object? o) => o as Map<String, dynamic>;

  group('installation', () {
    test('santé', () async {
      final (s, b) = await app.call('GET', '/admin/health');
      expect(s, 200);
      expect(m(b)['status'], 'ok');
    });

    test('premier administrateur : jeton d\'installation puis TOTP obligatoire', () async {
      var (s, b) = await app.call('GET', '/admin/setup');
      expect(m(b)['needed'], isTrue);

      (s, b) = await app.call('POST', '/admin/setup', body: {'setupToken': 'mauvais', 'email': 'a@b.fr', 'password': ownerPassword});
      expect(s, 403);

      (s, b) = await app.call(
        'POST',
        '/admin/setup',
        body: {'setupToken': setupToken, 'email': 'Proprio@Vigiroad.fr', 'displayName': 'Codex', 'password': 'court'},
      );
      expect(s, 400, reason: 'mot de passe trop court');

      (s, b) = await app.call(
        'POST',
        '/admin/setup',
        body: {'setupToken': setupToken, 'email': 'Proprio@Vigiroad.fr', 'displayName': 'Codex', 'password': ownerPassword},
      );
      expect(s, 201, reason: '$b');
      expect(m(b)['mfa'], 'enroll');
      ownerSecret = m(m(b)['enrollment'])['secret'] as String;
      expect(m(m(b)['enrollment'])['uri'], startsWith('otpauth://totp/'));
      final ticket = m(b)['ticket'];

      // Aucun jeton tant que le code TOTP n'est pas confirmé.
      (s, b) = await app.call('POST', '/admin/auth/mfa', body: {'ticket': ticket, 'code': '000000'});
      expect(s, 401);
      (s, b) = await app.call(
        'POST',
        '/admin/auth/mfa',
        body: {'ticket': ticket, 'code': Totp.code(ownerSecret, Totp.step(DateTime.now()))},
      );
      expect(s, 200, reason: '$b');
      ownerToken = m(b)['token'] as String;
      expect(m(m(b)['admin'])['role'], 'owner');

      (s, b) = await app.call('POST', '/admin/setup', body: {'setupToken': setupToken, 'email': 'x@y.fr', 'password': ownerPassword});
      expect(s, 409, reason: 'installation déjà faite');
      (s, b) = await app.call('GET', '/admin/setup');
      expect(m(b)['needed'], isFalse);
    });

    test('secret TOTP chiffré en base, mot de passe haché', () async {
      final row = await app.db.one('SELECT password_hash, totp_secret_enc, totp_confirmed FROM admin_accounts');
      expect(row!['password_hash'], startsWith(r'$argon2id$'));
      expect(row['totp_secret_enc'], isNot(contains(ownerSecret)));
      expect(row['totp_confirmed'], isTrue);
    });

    test('connexion : mauvais mot de passe, code réutilisé refusé, verrouillage', () async {
      var (s, b) = await app.call('POST', '/admin/auth/login', body: {'email': 'proprio@vigiroad.fr', 'password': 'faux'});
      expect(s, 401);
      expect(m(b)['code'], 'bad_credentials');
      (s, b) = await app.call('POST', '/admin/auth/login', body: {'email': 'inconnu@vigiroad.fr', 'password': 'faux'});
      expect(s, 401, reason: 'même réponse pour un compte inconnu');

      (s, b) = await app.call('POST', '/admin/auth/login', body: {'email': 'proprio@vigiroad.fr', 'password': ownerPassword});
      expect(m(b)['mfa'], 'required');
      // Le code de l'enrôlement (même pas de temps) ne peut pas resservir.
      final used = await app.db.scalar<int>('SELECT totp_last_step FROM admin_accounts');
      (s, b) = await app.call('POST', '/admin/auth/mfa', body: {'ticket': m(b)['ticket'], 'code': Totp.code(ownerSecret, used)});
      expect(s, 401);

      expect(await app.call('GET', '/admin/me'), isA<(int, dynamic)>().having((r) => r.$1, 'status', 401));
      final (s3, me) = await app.call('GET', '/admin/me', token: ownerToken);
      expect(s3, 200);
      expect(m(m(me)['admin'])['permissions'], contains('adminsManage'));
    });
  });

  group('application mobile', () {
    late String token;
    late String userId;
    late String deviceId;

    test('inscription : clé de l\'application exigée, pseudonyme unique', () async {
      final body = {
        'pseudonym': 'Conducteur_1',
        'email': 'conducteur@exemple.fr',
        'password': 'Volant2026',
        'appVersion': '1.4.0',
        'device': {
          'installationId': 'inst-0123456789abcdef',
          'brand': 'Samsung',
          'model': 'Galaxy S24',
          'os': 'android',
          'osVersion': '15',
          'appVersion': '1.4.0',
        },
      };
      var (s, b) = await app.call('POST', '/v1/account/register', body: body);
      expect(s, 401);
      (s, b) = await app.call('POST', '/v1/account/register', body: {...body, 'password': 'faible'}, appKeyHeader: true);
      expect(s, 400);
      (s, b) = await app.call('POST', '/v1/account/register', body: body, appKeyHeader: true);
      expect(s, 201, reason: '$b');
      token = m(b)['token'] as String;
      userId = m(m(b)['user'])['id'] as String;
      deviceId = m(b)['deviceId'] as String;
      expect(m(m(b)['user'])['consents'], {'region': false, 'location': false});

      (s, b) = await app.call(
        'POST',
        '/v1/account/register',
        body: {...body, 'pseudonym': 'conducteur_1', 'email': null},
        appKeyHeader: true,
      );
      expect(s, 409);
      expect(m(b)['code'], 'pseudonym_taken');
    });

    test('aucun pays sans consentement', () async {
      final u = await app.db.one('SELECT country FROM users WHERE id = CAST(@u AS uuid)', {'u': userId});
      expect(u!['country'], isNull);
    });

    test('connexion par pseudonyme ou e-mail, échecs journalisés', () async {
      var (s, b) = await app.call('POST', '/v1/account/login', body: {'login': 'conducteur_1', 'password': 'Faux2026'}, appKeyHeader: true);
      expect(s, 401);
      (s, b) = await app.call(
        'POST',
        '/v1/account/login',
        body: {'login': 'CONDUCTEUR@exemple.fr', 'password': 'Volant2026'},
        appKeyHeader: true,
      );
      expect(s, 200);
      final failures = await app.db.scalar<int>("SELECT count(*) FROM login_events WHERE kind = 'user' AND NOT success AND reason = 'bad_password'");
      expect(failures, 1);
    });

    test('temps d\'utilisation réel par battements de cœur', () async {
      // Premier battement juste après la connexion : rien à compter.
      var (s, b) = await app.call('POST', '/v1/account/heartbeat', body: {'appVersion': '1.4.0'}, token: token);
      expect(s, 200, reason: '$b');
      expect(m(b)['countedSeconds'], lessThanOrEqualTo(1));

      // 60 s d'utilisation continue.
      await app.db.exec(
        "UPDATE sessions SET last_seen_at = now() - interval '60 seconds' WHERE token_hash = @h",
        {'h': sha256Hex(token)},
      );
      (s, b) = await app.call('POST', '/v1/account/heartbeat', body: {}, token: token);
      expect(m(b)['countedSeconds'], inInclusiveRange(59, 61));

      // Application fermée 10 min : l'intervalle n'est pas compté.
      await app.db.exec(
        "UPDATE sessions SET last_seen_at = now() - interval '10 minutes' WHERE token_hash = @h",
        {'h': sha256Hex(token)},
      );
      (s, b) = await app.call('POST', '/v1/account/heartbeat', body: {}, token: token);
      expect(m(b)['countedSeconds'], 0);

      final u = await app.db.one('SELECT total_active_seconds FROM users WHERE id = CAST(@u AS uuid)', {'u': userId});
      expect(u!['total_active_seconds'], inInclusiveRange(59, 62));
      final day = await app.db.one('SELECT active_seconds, heartbeats FROM usage_statistics WHERE user_id = CAST(@u AS uuid)', {'u': userId});
      expect(day!['heartbeats'], 3);
      final hour = await app.db.scalar<int>('SELECT count(*) FROM usage_hourly WHERE user_id = CAST(@u AS uuid)', {'u': userId});
      expect(hour, 1);
    });

    test('localisation : refusée par défaut, arrondie avec consentement, effacée au retrait', () async {
      var (s, b) = await app.call('POST', '/v1/account/heartbeat', body: {'location': {'lat': 48.8566, 'lng': 2.3522}}, token: token);
      expect(m(b)['locationStored'], isFalse);

      (s, b) = await app.call('PATCH', '/v1/account/me', body: {'consents': {'location': true, 'region': true}}, token: token);
      expect(s, 200, reason: '$b');
      (s, b) = await app.call('POST', '/v1/account/heartbeat', body: {'location': {'lat': 48.8566, 'lng': 2.3522}}, token: token);
      expect(m(b)['locationStored'], isTrue);
      final loc = await app.db.one('SELECT CAST(lat AS float8) AS lat, CAST(lng AS float8) AS lng, country FROM location_history');
      expect(loc!['lat'], closeTo(48.85, 0.001));
      expect(loc['lng'], closeTo(2.35, 0.001));
      expect(loc['country'], 'FR', reason: 'pays déduit de l\'adresse avec consentement');

      (s, b) = await app.call('PATCH', '/v1/account/me', body: {'consents': {'location': false, 'region': false}}, token: token);
      expect(await app.db.scalar<int>('SELECT count(*) FROM location_history'), 0);
      final u = await app.db.one('SELECT country FROM users WHERE id = CAST(@u AS uuid)', {'u': userId});
      expect(u!['country'], isNull);
    });

    test('export des données personnelles', () async {
      final (s, b) = await app.call('GET', '/v1/account/data', token: token);
      expect(s, 200);
      expect(m(b)['user']['pseudonym'], 'Conducteur_1');
      expect((m(b)['devices'] as List).single['model'], 'Galaxy S24');
      expect(jsonEncode(b), isNot(contains('passwordHash')));
      expect(jsonEncode(b), isNot(contains('argon2')));
    });

    group('administration (application Windows)', () {
      test('tableau de bord', () async {
        final (s, b) = await app.call('GET', '/admin/dashboard', token: ownerToken);
        expect(s, 200, reason: '$b');
        expect(m(b)['usersTotal'], 1);
        expect(m(b)['usersOnline'], 1);
        expect(m(b)['devicesTotal'], 1);
        expect(m(b)['sessionsOnline'], 2);
        expect(m(b)['loginsToday'], 2);
        expect(m(b)['failedLogins24h'], 1);
      });

      test('statistiques 24 h, 7 j, 30 j', () async {
        for (final (p, n) in [('24h', 24), ('7d', 7), ('30d', 30)]) {
          final (s, b) = await app.call('GET', '/admin/stats/activity?period=$p', token: ownerToken);
          expect(s, 200, reason: '$b');
          final points = m(b)['points'] as List;
          expect(points, hasLength(n));
          expect(m(points.last)['logins'], 2);
          expect(m(points.last)['activeUsers'], 1);
        }
      });

      test('recherche, fiche détaillée, sessions simultanées', () async {
        var (s, b) = await app.call('GET', '/admin/users?q=conduc', token: ownerToken);
        expect(m(b)['total'], 1);
        expect(m((m(b)['items'] as List).first)['online'], isTrue);
        (s, b) = await app.call('GET', '/admin/users?q=personne', token: ownerToken);
        expect(m(b)['total'], 0);

        (s, b) = await app.call('GET', '/admin/users/$userId', token: ownerToken);
        expect(s, 200);
        expect((m(b)['sessions'] as List), hasLength(2));
        expect((m(b)['devices'] as List).single['brand'], 'Samsung');

        (s, b) = await app.call('GET', '/admin/sessions/concurrent', token: ownerToken);
        expect((m(b)['items'] as List).single['sessions'], 2);

        (s, b) = await app.call('GET', '/admin/users/pas-un-uuid', token: ownerToken);
        expect(s, 404);
      });

      test('rôle « lecture seule » : consultation oui, actions non (et journalisées)', () async {
        var (s, b) = await app.call(
          'POST',
          '/admin/admins',
          token: ownerToken,
          body: {'email': 'lecteur@vigiroad.fr', 'role': 'viewer', 'password': 'LecteurSecret2026'},
        );
        expect(s, 201, reason: '$b');
        final viewer = await app.adminLogin('lecteur@vigiroad.fr', 'LecteurSecret2026');
        (s, b) = await app.call('GET', '/admin/users', token: viewer);
        expect(s, 200);
        (s, b) = await app.call('POST', '/admin/users/$userId/disable', token: viewer);
        expect(s, 403);
        (s, b) = await app.call('GET', '/admin/admins', token: viewer);
        expect(s, 403);
        (s, b) = await app.call('POST', '/admin/docker/containers/abc123/restart', token: viewer);
        expect(s, 403);
        final denied = await app.db.scalar<int>("SELECT count(*) FROM admin_audit_logs WHERE action = 'denied' AND NOT success");
        expect(denied, 3);
      });

      test('il reste toujours un propriétaire', () async {
        final ownerId = await app.db.scalar<String>("SELECT CAST(id AS text) FROM admin_accounts WHERE role = 'owner'");
        final (s, b) = await app.call('PATCH', '/admin/admins/$ownerId', token: ownerToken, body: {'role': 'viewer'});
        expect(s, 409, reason: '$b');
      });

      test('désactiver un compte ferme ses sessions', () async {
        var (s, b) = await app.call('POST', '/admin/users/$userId/disable', token: ownerToken);
        expect(s, 200);
        (s, b) = await app.call('POST', '/v1/account/heartbeat', body: {}, token: token);
        expect(s, 401);
        expect(m(b)['code'], 'revoked');
        (s, b) = await app.call('POST', '/v1/account/login', body: {'login': 'conducteur_1', 'password': 'Volant2026'}, appKeyHeader: true);
        expect(s, 403);
        (s, b) = await app.call('POST', '/admin/users/$userId/enable', token: ownerToken);
        expect(m(m(b)['user'])['status'], 'active');
      });

      test('réinitialisation sécurisée de l\'accès par code à usage unique', () async {
        var (s, b) = await app.call('POST', '/admin/users/$userId/reset-access', token: ownerToken);
        expect(s, 200);
        final code = m(b)['code'] as String;
        expect(code, matches(RegExp(r'^[A-Z2-7]{4}-[A-Z2-7]{4}-[A-Z2-7]{4}$')));
        expect(await app.db.scalar<int>('SELECT count(*) FROM password_resets WHERE code_hash = @c', {'c': code}), 0,
            reason: 'jamais en clair');

        (s, b) = await app.call(
          'POST',
          '/v1/account/reset',
          body: {'login': 'conducteur_1', 'code': 'AAAA-BBBB-CCCC', 'newPassword': 'Nouveau2026'},
          appKeyHeader: true,
        );
        expect(s, 400);
        (s, b) = await app.call(
          'POST',
          '/v1/account/reset',
          body: {'login': 'conducteur_1', 'code': code.toLowerCase(), 'newPassword': 'Nouveau2026'},
          appKeyHeader: true,
        );
        expect(s, 200, reason: '$b');
        (s, b) = await app.call(
          'POST',
          '/v1/account/reset',
          body: {'login': 'conducteur_1', 'code': code, 'newPassword': 'Encore2026x'},
          appKeyHeader: true,
        );
        expect(s, 400, reason: 'code déjà utilisé');
        (s, b) = await app.call('POST', '/v1/account/login', body: {'login': 'conducteur_1', 'password': 'Nouveau2026'}, appKeyHeader: true);
        expect(s, 200);
        token = m(b)['token'] as String;
      });

      test('révocation d\'un appareil', () async {
        var (s, b) = await app.call('POST', '/v1/account/device', token: token, body: {
          'installationId': 'inst-0123456789abcdef',
          'brand': 'Samsung',
          'model': 'Galaxy S24',
          'os': 'android',
        });
        expect(m(b)['deviceId'], deviceId, reason: 'même installation, même appareil');
        (s, b) = await app.call('GET', '/admin/devices?q=galaxy', token: ownerToken);
        expect(m(b)['total'], 1);
        (s, b) = await app.call('POST', '/admin/devices/$deviceId/revoke', token: ownerToken);
        expect(s, 200);
        (s, b) = await app.call('POST', '/v1/account/heartbeat', body: {}, token: token);
        expect(s, 401);
        (s, b) = await app.call('GET', '/admin/devices/$deviceId', token: ownerToken);
        expect(m(m(b)['device'])['revokedAt'], isNotNull);
      });

      test('export CSV sans formules exécutables', () async {
        await app.db.exec("UPDATE users SET display_name = '=HYPERLINK(1)'");
        final (s, b) = await app.call('GET', '/admin/users/export', token: ownerToken);
        expect(s, 200);
        final csv = b as String;
        expect(csv, contains('pseudonym'));
        expect(csv, contains('"\'=HYPERLINK(1)"'));
        expect(csv, isNot(contains('argon2')));
      });

      test('journal d\'audit des actions sensibles', () async {
        final (s, b) = await app.call('GET', '/admin/audit?action=user.', token: ownerToken);
        expect(s, 200);
        final actions = [for (final i in m(b)['items'] as List) m(i)['action']];
        expect(actions, containsAll(['user.disable', 'user.enable', 'user.reset_access']));
      });

      test('réglages : bornes vérifiées côté serveur', () async {
        var (s, b) = await app.call('PUT', '/admin/settings', token: ownerToken, body: {'retention.location_days': 0});
        expect(s, 400);
        (s, b) = await app.call('PUT', '/admin/settings', token: ownerToken, body: {'retention.location_days': 7, 'geo.enabled': false});
        expect(s, 200, reason: '$b');
        expect(m(m(b)['settings'])['retention.location_days'], 7);
      });

      test('conservation : anciennes données supprimées', () async {
        await app.db.exec(
          "INSERT INTO login_events (at, kind, success, reason) VALUES (now() - interval '400 days', 'user', false, 'ancien')",
        );
        final r = await app.api.maintenance.applyRetention();
        expect(r['loginEvents'], 1);
        expect(await app.db.scalar<int>("SELECT count(*) FROM login_events WHERE reason = 'ancien'"), 0);
      });

      test('suppression : confirmation exigée, puis données effacées en cascade', () async {
        var (s, b) = await app.call('DELETE', '/admin/users/$userId', token: ownerToken);
        expect(s, 400);
        (s, b) = await app.call('DELETE', '/admin/users/$userId?confirm=conducteur_1', token: ownerToken);
        expect(s, 200, reason: '$b');
        for (final t in ['users', 'devices', 'sessions', 'usage_statistics', 'usage_hourly', 'location_history', 'password_resets']) {
          expect(await app.db.scalar<int>('SELECT count(*) FROM $t'), 0, reason: t);
        }
        expect(await app.db.scalar<int>('SELECT count(*) FROM login_events WHERE kind = \'user\' AND user_id IS NOT NULL'), 0);
      });
    });
  });

  test('suppression du compte par l\'utilisateur (mot de passe demandé)', () async {
    var (s, b) = await app.call(
      'POST',
      '/v1/account/register',
      body: {'pseudonym': 'temporaire', 'password': 'Temporaire1'},
      appKeyHeader: true,
      ip: '198.51.100.9',
    );
    final token = m(b)['token'] as String;
    (s, b) = await app.call('POST', '/v1/account/me/delete', token: token, body: {'password': 'mauvais'});
    expect(s, 403);
    (s, b) = await app.call('POST', '/v1/account/me/delete', token: token, body: {'password': 'Temporaire1'});
    expect(s, 200);
    expect(await app.db.scalar<int>("SELECT count(*) FROM users WHERE pseudonym = 'temporaire'"), 0);
    (s, b) = await app.call('GET', '/v1/account/me', token: token);
    expect(s, 401);
  });

  group('supervision et maintenance (application Linux)', () {
    test('vue d\'ensemble du VPS et alertes', () async {
      final (s, b) = await app.call('GET', '/admin/server/overview', token: ownerToken);
      expect(s, 200, reason: '$b');
      expect(m(m(b)['system'])['hostname'], 'vps-test');
      expect(m(m(b)['metrics'])['cpuPercent'], 12.5);
      final ids = [for (final a in m(b)['alerts'] as List) m(a)['id']];
      expect(ids, contains('disk'), reason: 'disque à 90 %');
      expect(ids, contains('backup'), reason: 'aucune sauvegarde');
    });

    test('collecte : métriques, flux routiers, requêtes', () async {
      await app.api.monitoring.collectMetrics();
      await app.api.monitoring.collectSources();
      await app.api.monitoring.collectRequests();
      expect(await app.db.scalar<int>('SELECT count(*) FROM server_metrics WHERE traffic_ok'), 1);
      expect(await app.db.scalar<int>("SELECT events FROM traffic_source_metrics WHERE source_id = 'fr-bison-fute'"), 42);
      expect(await app.db.scalar<int>("SELECT count(*) FROM request_metrics WHERE service = 'traffic'"), 1);
      final (s, b) = await app.call('GET', '/admin/server/history?period=1h', token: ownerToken);
      expect(s, 200);
      expect((m(b)['points'] as List), hasLength(1));
      final (s2, st) = await app.call('GET', '/admin/vigiroad/status', token: ownerToken);
      expect(s2, 200, reason: '$st');
      expect(m(m(st)['traffic'])['events'], 42);
      expect(m(m(st)['traffic'])['activeSources'], 1);
    });

    test('Docker : actions autorisées seulement, journalisées', () async {
      var (s, b) = await app.call('POST', '/admin/docker/containers/abc123/restart', token: ownerToken);
      expect(s, 200, reason: '$b');
      expect(app.agent.actions, ['/containers/abc123/restart']);
      (s, b) = await app.call('POST', '/admin/docker/containers/def456/stop', token: ownerToken);
      expect(s, 403);
      (s, b) = await app.call('POST', '/admin/docker/containers/abc123/delete', token: ownerToken);
      expect(s, 404);
      final audit = await app.db.query("SELECT action, success FROM admin_audit_logs WHERE action LIKE 'docker.%' ORDER BY at");
      expect([for (final r in audit) '${r['action']}:${r['success']}'], ['docker.restart:true', 'docker.stop:false']);
    });

    test('agent arrêté : erreur claire, alerte critique', () async {
      app.agent.down = true;
      final (s, b) = await app.call('GET', '/admin/docker/containers', token: ownerToken);
      expect(s, 503);
      await app.api.monitoring.collectMetrics(store: false);
      final alerts = await app.api.monitoring.alerts();
      expect(alerts.where((a) => a['id'] == 'agent' && a['level'] == 'critical'), hasLength(1));
      app.agent.down = false;
    });

    test('sauvegardes : demande mise en file, une seule à la fois', () async {
      var (s, b) = await app.call('POST', '/admin/backups', token: ownerToken, body: {'kind': 'manual'});
      expect(s, 202);
      (s, b) = await app.call('POST', '/admin/backups', token: ownerToken, body: {'kind': 'restore_test'});
      expect(s, 409);
      (s, b) = await app.call('GET', '/admin/backups', token: ownerToken);
      expect(m((m(b)['items'] as List).first)['status'], 'pending');
    });

    test('diagnostic complet', () async {
      final (s, b) = await app.call('GET', '/admin/diagnostics', token: ownerToken);
      expect(s, 200, reason: '$b');
      final checks = {for (final c in m(b)['checks'] as List) m(c)['id']: m(c)['ok']};
      expect(checks['database'], isTrue);
      expect(checks['agent'], isTrue);
      expect(checks['traffic'], isTrue);
      expect(checks['containers'], isTrue);
      expect(checks['backup'], isFalse);
    });

    test('flux temps réel (SSE)', () async {
      final res = await app.api.handler(
        Request('GET', Uri.parse('http://localhost/admin/events'), headers: {'authorization': 'Bearer $ownerToken'}),
      );
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], 'text/event-stream');
      final text = StringBuffer();
      final sub = res.read().map(utf8.decode).listen(text.write);
      for (var i = 0; i < 50 && !text.toString().contains('event: snapshot'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await sub.cancel();
      expect(text.toString(), contains('event: snapshot'));
      final data = text.toString().split('data: ')[1].split('\n').first;
      expect(m(jsonDecode(data))['counts'], contains('usersOnline'));
    });

    test('déconnexion administrateur', () async {
      var (s, b) = await app.call('POST', '/admin/auth/logout', token: ownerToken);
      expect(s, 200);
      (s, b) = await app.call('GET', '/admin/dashboard', token: ownerToken);
      expect(s, 401);
    });
  });
}

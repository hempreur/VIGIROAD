import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigiroad_admin_core/vigiroad_admin_core.dart';

void main() {
  group('mise en forme', () {
    test('nombres, octets, débits, durées', () {
      expect(Fmt.number(1234567), '1 234 567');
      expect(Fmt.number(3.14159, digits: 2), '3,14');
      expect(Fmt.bytes(1536), '1,5 Ko');
      expect(Fmt.bytes(4113000000), '3,8 Go');
      expect(Fmt.rate(125000), '1,0 Mbit/s');
      expect(Fmt.duration(42), '42 s');
      expect(Fmt.duration(3725), '1 h 02 min');
      expect(Fmt.duration(200000), '2 j 7 h');
      expect(Fmt.percent(99.93, digits: 2), '99,93 %');
    });

    test('dates relatives', () {
      final now = DateTime(2026, 11, 1, 12);
      expect(Fmt.ago(now.subtract(const Duration(minutes: 3)), now: now), 'il y a 3 min');
      expect(Fmt.ago(now.add(const Duration(days: 12)), now: now), 'dans 12 j');
      expect(Fmt.ago(null), 'jamais');
      expect(Fmt.dateTime('2026-11-01T13:05:00'), '01/11/2026 13:05');
    });

    test('pays et drapeaux', () {
      expect(Fmt.flag('FR'), '🇫🇷');
      expect(Fmt.country('BE'), 'Belgique');
      expect(Fmt.country(null), 'Inconnu');
    });
  });

  group('client', () {
    test('HTTPS obligatoire sauf ordinateur local', () {
      expect(AdminClient.parseServer('15-235-120-182.sslip.io').toString(), 'https://15-235-120-182.sslip.io');
      expect(AdminClient.parseServer('https://vps.fr/')!.host, 'vps.fr');
      expect(AdminClient.isAllowedUrl(Uri.parse('http://vps.fr')), isFalse);
      expect(AdminClient.isAllowedUrl(Uri.parse('http://127.0.0.1:8081')), isTrue);
      expect(() => AdminClient(Uri.parse('http://vps.fr')), throwsA(isA<ApiException>()));
    });

    test('erreurs de l\'API et session expirée', () async {
      ApiException? expired;
      final c = AdminClient(
        Uri.parse('https://vps.fr'),
        client: MockClient((r) async => http.Response(jsonEncode({'error': 'Session expirée', 'code': 'session_expired'}), 401)),
      )
        ..token = 'vra_x'
        ..onUnauthorized = (e) => expired = e;
      await expectLater(c.get('/admin/dashboard'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'session_expired')));
      expect(expired?.message, 'Session expirée');
    });

    test('flux temps réel (SSE)', () async {
      final c = AdminClient(
        Uri.parse('https://vps.fr'),
        client: MockClient.streaming((r, _) async => http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode('retry: 5000\n\nevent: snapshot\ndata: {"counts":'),
            utf8.encode('{"usersOnline":3}}\n\n'),
          ]),
          200,
        )),
      );
      final e = await c.events('/admin/events').first;
      expect(e.$1, 'snapshot');
      expect((e.$2['counts'] as Map)['usersOnline'], 3);
    });
  });

  group('mises à jour', () {
    test('comparaison de versions', () {
      expect(DesktopUpdater.compare('1.0.1', '1.0.0'), 1);
      expect(DesktopUpdater.compare('1.0.0', '1.0.0+5'), 0);
      expect(DesktopUpdater.compare('1.2.0', '1.10.0'), -1);
    });

    test('manifeste : version plus récente uniquement', () {
      final u = DesktopUpdater(appId: 'admin-manager', currentVersion: '1.0.0');
      Map<String, dynamic> m(String v) => {
        'admin-manager': {
          'version': v,
          'notes': ['Nouveautés'],
          'files': {
            'windows-installer': {'url': 'https://x/setup.exe', 'sha256': 'ab'},
            'deb': {'url': 'https://x/a.deb', 'sha256': 'cd'},
          },
        },
      };
      expect(u.pick(m('1.0.0')), isNull);
      expect(u.pick(m('1.1.0'))?.version, '1.1.0');
      expect(u.pick({'server-control': {}}), isNull);
    });
  });

  test('session : connexion au serveur, étape suivante', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final s = AdminSession(
      clientName: 'test',
      httpFactory: () => MockClient((r) async => switch (r.url.path) {
        '/admin/health' => http.Response('{"status":"ok"}', 200),
        '/admin/setup' => http.Response('{"needed":true,"enabled":true}', 200),
        _ => http.Response('{}', 404),
      }),
    );
    await s.connectServer('http://vps.fr');
    expect(s.error, contains('HTTPS'), reason: 'HTTP en clair refusé hors ordinateur local');
    await s.connectServer('http://127.0.0.1:8081');
    expect(s.stage, SessionStage.setup);
    expect(s.setupAvailable, isTrue);
    s.dispose();
  });
}

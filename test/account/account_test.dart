import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vigiroad/app/providers.dart';
import 'package:vigiroad/core/config/app_config.dart';
import 'package:vigiroad/features/account/application/account_controller.dart';
import 'package:vigiroad/features/account/data/account_store.dart';
import 'package:vigiroad/features/account/presentation/account_screen.dart';

const config = AppConfig(
  environment: AppEnvironment.test,
  mapStyleUrl: 'https://carte.test/style.json',
  routingBaseUrl: 'https://route.test',
  geocodingBaseUrl: 'https://geo.test',
  platesSyncUrl: '',
  userAgent: 'VIGIROAD-test',
  trafficApiUrl: 'https://vps.test',
  trafficApiKey: 'cle-application-test-123',
);

/// Faux serveur de comptes : enregistre les requêtes, peut révoquer la session.
const jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

/// Faux serveur de comptes.
class FakeAccounts {
  final calls = <String, Map<String, dynamic>>{};
  final order = <String>[];
  bool revoked = false;
  Map<String, Object?> consents = {'region': false, 'location': false};

  Map<String, Object?> user() => {'id': 'u1', 'pseudonym': 'Conducteur', 'email': 'c@exemple.fr', 'consents': consents};

  http.Client client() => MockClient((req) async {
    final body = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
    final key = '${req.method} ${req.url.path}';
    calls[key] = body;
    order.add(key);
    expect(req.headers['x-api-key'], 'cle-application-test-123');
    if (revoked && req.headers['authorization'] != null) {
      return http.Response(jsonEncode({'error': 'Accès révoqué', 'code': 'revoked'}), 401, headers: jsonHeaders);
    }
    Object out;
    switch (key) {
      case 'POST /v1/account/register':
        if (body['pseudonym'] == 'pris') return http.Response(jsonEncode({'error': 'Ce pseudonyme est déjà utilisé'}), 409, headers: jsonHeaders);
        out = {'token': 'vrs_jeton', 'sessionId': 's1', 'deviceId': body['device'] == null ? null : 'd1', 'user': user()};
      case 'POST /v1/account/login':
        out = {'token': 'vrs_jeton', 'sessionId': 's1', 'user': user()};
      case 'PATCH /v1/account/me':
        final c = body['consents'] as Map<String, dynamic>?;
        if (c != null) consents = {...consents, ...c};
        out = {'user': user()};
      case 'GET /v1/account/me':
        out = {'user': user(), 'sessionId': 's1'};
      case 'GET /v1/account/sessions':
        out = {
          'current': 's1',
          'sessions': [
            {'id': 's1', 'brand': 'Samsung', 'model': 'Galaxy S24', 'os': 'android', 'startedAt': '2026-11-01T10:00:00Z', 'online': true},
            {'id': 's2', 'brand': 'Apple', 'model': 'iPhone', 'os': 'ios', 'startedAt': '2026-10-30T08:00:00Z', 'online': false},
          ],
        };
      case 'GET /v1/account/data':
        out = {'user': user(), 'devices': []};
      default:
        out = {'ok': true, 'deviceId': 'd1'};
    }
    return http.Response(jsonEncode(out), 200, headers: jsonHeaders);
  });
}

class FakeDevice implements DeviceInfoSource {
  @override
  Future<Map<String, String?>> info() async => {'os': 'android', 'brand': 'Samsung', 'model': 'Galaxy S24', 'osVersion': '15'};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAccounts server;
  late MemoryAccountStore store;
  late ProviderContainer c;

  ProviderContainer container({AppConfig cfg = config}) => ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(cfg),
      accountStoreProvider.overrideWithValue(store),
      deviceInfoProvider.overrideWithValue(FakeDevice()),
      accountHttpProvider.overrideWithValue(server.client()),
      heartbeatIntervalProvider.overrideWithValue(const Duration(hours: 1)),
    ],
  );

  setUp(() async {
    server = FakeAccounts();
    store = MemoryAccountStore();
    c = container();
    c.listen(accountProvider, (_, _) {});
    await pumpEventQueue();
  });
  tearDown(() => c.dispose());

  AccountController ctrl() => c.read(accountProvider.notifier);
  AccountState st() => c.read(accountProvider);

  test('sans serveur configuré : compte indisponible, rien n\'est envoyé', () async {
    final c2 = container(cfg: const AppConfig(
      environment: AppEnvironment.test,
      mapStyleUrl: '',
      routingBaseUrl: '',
      geocodingBaseUrl: '',
      platesSyncUrl: '',
      userAgent: 'x',
    ));
    addTearDown(c2.dispose);
    expect(c2.read(accountProvider).status, AccountStatus.unavailable);
    expect(server.order, isEmpty);
  });

  test('inscription : appareil avec identifiant aléatoire, consentements désactivés par défaut', () async {
    expect(st().status, AccountStatus.signedOut);
    expect(await ctrl().register(pseudonym: 'Conducteur', password: 'Volant2026'), isTrue);
    expect(st().signedIn, isTrue);
    expect(st().deviceRegistered, isTrue);
    final body = server.calls['POST /v1/account/register']!;
    expect(body['consents'], {'region': false, 'location': false});
    final device = body['device'] as Map<String, dynamic>;
    expect(device['installationId'], matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(device['model'], 'Galaxy S24');
    expect(await store.read('account.token'), 'vrs_jeton');
    // Premier battement de cœur à la connexion.
    await pumpEventQueue();
    expect(server.order, contains('POST /v1/account/heartbeat'));
    expect(server.calls['POST /v1/account/heartbeat']!.containsKey('location'), isFalse);
  });

  test('pseudonyme déjà pris : message, toujours déconnecté', () async {
    expect(await ctrl().register(pseudonym: 'pris', password: 'Volant2026'), isFalse);
    expect(st().error, 'Ce pseudonyme est déjà utilisé');
    expect(st().status, AccountStatus.signedOut);
  });

  test('session révoquée par un administrateur : déconnexion locale et message', () async {
    await ctrl().login('Conducteur', 'Volant2026');
    server.revoked = true;
    await ctrl().heartbeat();
    expect(st().status, AccountStatus.signedOut);
    expect(st().error, contains('fermée'));
    expect(await store.read('account.token'), isNull);
  });

  test('session restaurée au démarrage', () async {
    await ctrl().login('Conducteur', 'Volant2026');
    final c2 = container();
    addTearDown(c2.dispose);
    c2.listen(accountProvider, (_, _) {});
    await pumpEventQueue();
    expect(c2.read(accountProvider).signedIn, isTrue);
    expect(c2.read(accountProvider).user?['pseudonym'], 'Conducteur');
  });

  test('consentements, appareil, nouvel identifiant, déconnexion', () async {
    await ctrl().login('Conducteur', 'Volant2026', registerDevice: false);
    expect(st().deviceRegistered, isFalse);
    await ctrl().setConsent(location: true);
    expect(st().locationConsent, isTrue);
    await ctrl().setDeviceRegistered(true);
    expect(server.order, contains('POST /v1/account/device'));
    final before = await store.read('account.installation');
    await ctrl().renewInstallationId();
    expect(await store.read('account.installation'), isNot(before));
    expect(server.order, contains('DELETE /v1/account/device'));
    await ctrl().logout();
    expect(st().status, AccountStatus.signedOut);
    expect(server.order.last, 'POST /v1/account/logout');
  });

  test('suppression du compte : mot de passe transmis, tout est effacé localement', () async {
    await ctrl().login('Conducteur', 'Volant2026');
    expect(await ctrl().deleteAccount('Volant2026'), isTrue);
    expect(server.calls['POST /v1/account/me/delete'], {'password': 'Volant2026'});
    expect(store.values, isEmpty);
    expect(st().status, AccountStatus.signedOut);
  });

  testWidgets('écran : connexion puis sessions', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final c2 = container();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c2,
      child: MaterialApp(home: const AccountScreen(), theme: ThemeData.dark()),
    ));
    await tester.pump();
    expect(find.text('Connexion'), findsOneWidget);
    expect(find.textContaining('jamais vos images'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('account-login')), 'Conducteur');
    await tester.enterText(find.byKey(const Key('account-password')), 'Volant2026');
    await tester.tap(find.byKey(const Key('account-login-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('account-pseudonym-label')), findsOneWidget);
    await tester.ensureVisible(find.text('Afficher mes sessions'));
    await tester.tap(find.text('Afficher mes sessions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Galaxy S24 (cet appareil)'), findsOneWidget);
    expect(find.text('Apple iPhone'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c2.dispose();
  });
}

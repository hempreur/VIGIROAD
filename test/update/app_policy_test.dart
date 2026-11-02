import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vigiroad/app/providers.dart';
import 'package:vigiroad/app/version.dart';
import 'package:vigiroad/core/config/app_config.dart';
import 'package:vigiroad/features/account/application/account_controller.dart';
import 'package:vigiroad/features/account/data/account_store.dart';
import 'package:vigiroad/features/traffic/data/traffic_client.dart';
import 'package:vigiroad/features/update/application/app_policy_controller.dart';
import 'package:vigiroad/features/update/presentation/update_gate.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

class MemoryPolicyCache implements PolicyCache {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, Object?> v) async => value = jsonDecode(jsonEncode(v)) as Map<String, dynamic>;
}

class FixedDeviceInfo implements DeviceInfoSource {
  @override
  Future<Map<String, String?>> info() async => {'os': 'android', 'brand': 'Xiaomi', 'model': 'Redmi Note 13', 'osVersion': '14'};
}

const _config = AppConfig(
  environment: AppEnvironment.test,
  mapStyleUrl: 'https://carte.test/style.json',
  routingBaseUrl: 'https://osrm.test',
  geocodingBaseUrl: 'https://photon.test',
  platesSyncUrl: '',
  userAgent: 'VIGIROAD-test',
  trafficApiUrl: 'https://vps.test',
  trafficApiKey: 'cle-de-test-0123456789',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('version de l\'application identique à pubspec.yaml', () {
    final v = RegExp(r'^version:\s*(\S+)\+(\d+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!;
    expect(appVersion, v.group(1));
    expect(appBuild, int.parse(v.group(2)!));
  });

  group('contrôle de version', () {
    late MemoryPolicyCache cache;
    late List<http.Request> requests;
    late Map<String, Object?> reply;
    late bool offline;

    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(_config),
          policyCacheProvider.overrideWithValue(cache),
          deviceInfoProvider.overrideWithValue(FixedDeviceInfo()),
          policyHttpProvider.overrideWithValue(MockClient((r) async {
            requests.add(r);
            if (offline) throw const SocketException('hors connexion');
            return http.Response(jsonEncode(reply), 200, headers: {'content-type': 'application/json; charset=utf-8'});
          })),
        ],
      );
      addTearDown(c.dispose);
      c.listen(appPolicyProvider, (_, _) {});
      return c;
    }

    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await pumpEventQueue();
      }
    }

    setUp(() {
      cache = MemoryPolicyCache();
      requests = [];
      offline = false;
      reply = {'status': 'ok', 'minBuild': appBuild};
    });

    test('version à jour : utilisable ; version et appareil envoyés', () async {
      final c = container();
      await settle();
      expect(c.read(appPolicyProvider).status, PolicyStatus.ok);
      final r = requests.single;
      expect(r.url.toString(), 'https://vps.test/v1/app/status');
      expect(r.headers['X-Api-Key'], 'cle-de-test-0123456789');
      expect(r.headers['X-App-Build'], '$appBuild');
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(body['build'], appBuild);
      expect(body['version'], appVersion);
      expect(body['model'], 'Xiaomi Redmi Note 13');
    });

    test('nouvelle version publiée : inutilisable, décision mémorisée', () async {
      reply = {'status': 'update_required', 'message': 'Installez la dernière version.', 'latest': {'version': '9.9.9', 'build': 999}};
      final c = container();
      await settle();
      final p = c.read(appPolicyProvider);
      expect(p.status, PolicyStatus.outdated);
      expect(p.latestVersion, '9.9.9');
      expect(cache.value?['status'], 'outdated');
    });

    test('hors connexion : une version déjà déclarée obsolète le reste', () async {
      cache.value = {'status': 'outdated', 'build': appBuild, 'latest': '9.9.9'};
      offline = true;
      final c = container();
      await settle();
      expect(c.read(appPolicyProvider).status, PolicyStatus.outdated);
    });

    test('décision d\'une ancienne version ignorée après mise à jour', () async {
      cache.value = {'status': 'outdated', 'build': appBuild - 1};
      offline = true;
      final c = container();
      await settle();
      expect(c.read(appPolicyProvider).status, PolicyStatus.ok);
    });

    test('blocage à distance', () async {
      reply = {'status': 'blocked', 'message': 'Maintenance en cours'};
      final c = container();
      await settle();
      expect(c.read(appPolicyProvider).status, PolicyStatus.blocked);
      expect(c.read(appPolicyProvider).message, 'Maintenance en cours');
    });

    testWidgets('écran bloquant : version obsolète', (tester) async {
      reply = {'status': 'update_required', 'latest': {'version': '9.9.9', 'build': 999}};
      await tester.runAsync(() async {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(_config),
            policyCacheProvider.overrideWithValue(cache),
            deviceInfoProvider.overrideWithValue(FixedDeviceInfo()),
            policyHttpProvider.overrideWithValue(MockClient((r) async => http.Response(jsonEncode(reply), 200))),
          ],
          child: const MaterialApp(home: UpdateGate(child: Scaffold(body: Text('Carte')))),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('Version obsolète'), findsOneWidget);
      expect(find.text('9.9.9'), findsOneWidget);
      expect(find.text('Mettre à jour'), findsOneWidget);
    });

    testWidgets('écran bloquant : application suspendue', (tester) async {
      reply = {'status': 'blocked', 'message': 'Maintenance en cours'};
      await tester.runAsync(() async {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(_config),
            policyCacheProvider.overrideWithValue(cache),
            deviceInfoProvider.overrideWithValue(FixedDeviceInfo()),
            policyHttpProvider.overrideWithValue(MockClient((r) async => http.Response(jsonEncode(reply), 200))),
          ],
          child: const MaterialApp(home: UpdateGate(child: Scaffold(body: Text('Carte')))),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('Application suspendue'), findsOneWidget);
      expect(find.text('Maintenance en cours'), findsOneWidget);
      expect(find.text('Mettre à jour'), findsNothing);
    });
  });

  test('serveur de trafic : version refusée (426) signalée', () async {
    bool? seen;
    final client = HttpTrafficClient(
      baseUrl: 'https://vps.test',
      apiKey: 'k',
      userAgent: 'ua',
      extraHeaders: {'X-App-Build': '$appBuild'},
      onRejected: ({required bool blocked, String? message}) => seen = blocked,
      client: MockClient((r) async {
        expect(r.headers['X-App-Build'], '$appBuild');
        return http.Response(jsonEncode({'error': 'Version obsolète', 'code': 'update_required'}), 426);
      }),
    );
    await expectLater(client.inBox(const BBox(2, 48, 3, 49)), throwsA(isA<TrafficException>()));
    expect(seen, isFalse);
  });
}

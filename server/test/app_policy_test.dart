import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:vigiroad_traffic_aggregator/traffic_aggregator.dart';

void main() {
  const key = 'cle-de-test-0123456789';
  final rejected = <Map<String, dynamic>>[];
  late AppPolicyClient policy;
  late Handler handler;
  var now = DateTime.utc(2026, 11, 2, 9);

  setUp(() {
    rejected.clear();
    now = DateTime.utc(2026, 11, 2, 9);
    final admin = MockClient((r) async {
      if (r.url.path == '/v1/app/policy') {
        return http.Response(jsonEncode({'minBuild': 13, 'blocked': false, 'message': 'Maintenance'}), 200);
      }
      if (r.url.path == '/v1/app/rejected') {
        rejected.add({...jsonDecode(r.body) as Map<String, dynamic>, 'ip': r.headers['x-forwarded-for']});
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('{}', 404);
    });
    policy = AppPolicyClient(adminUrl: Uri.parse('http://admin-api:8081'), apiKey: key, client: admin, clock: () => now);
    final agg = TrafficAggregator(chains: const [], client: http.Client());
    handler = TrafficApi(agg, apiKeys: {key}, appPolicy: policy).handler;
  });

  Future<Response> get(String path, {Map<String, String> headers = const {}}) async => handler(
    Request('GET', Uri.parse('http://x$path'), headers: {'x-api-key': key, 'x-forwarded-for': '198.51.100.9', ...headers}),
  );

  test('règle inconnue (API d\'administration injoignable) : rien n\'est refusé', () async {
    expect((await get('/v1/reports?bbox=2.2,48.8,2.5,48.9')).statusCode, 200);
  });

  test('ancienne application (sans numéro) ou version obsolète : 426 et journal', () async {
    await policy.refresh();
    var r = await get('/v1/reports?bbox=2.2,48.8,2.5,48.9');
    expect(r.statusCode, 426);
    expect(jsonDecode(await r.readAsString())['code'], 'update_required');
    r = await get('/v1/events?bbox=2.2,48.8,2.5,48.9', headers: {'x-app-build': '12', 'x-app-platform': 'android'});
    expect(r.statusCode, 426);
    await Future<void>.delayed(Duration.zero);
    expect(rejected, hasLength(1), reason: 'une seule trace par connexion et par 10 minutes');
    expect(rejected.single['ip'], '198.51.100.9');
    r = await get('/v1/reports?bbox=2.2,48.8,2.5,48.9', headers: {'x-app-build': '13'});
    expect(r.statusCode, 200);
    expect((await get('/v1/sources')).statusCode, 200, reason: 'supervision non concernée');
    expect((await get('/health')).statusCode, 200);
  });

  test('blocage à distance : même la dernière version est refusée', () async {
    policy.apply(minBuild: 13, blocked: true, message: 'Maintenance');
    final r = await get('/v1/reports?bbox=2.2,48.8,2.5,48.9', headers: {'x-app-build': '13'});
    expect(r.statusCode, 426);
    final j = jsonDecode(await r.readAsString());
    expect(j['code'], 'app_blocked');
    expect(j['error'], 'Maintenance');
  });

  test('règle périmée (plus de réponse depuis 15 min) : plus de refus', () async {
    await policy.refresh();
    now = now.add(const Duration(minutes: 16));
    expect((await get('/v1/reports?bbox=2.2,48.8,2.5,48.9')).statusCode, 200);
  });
}

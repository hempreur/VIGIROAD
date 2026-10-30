import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';
import 'package:vigiroad_traffic_aggregator/traffic_aggregator.dart';

const _east30m = 30 / (111195 * 0.6578);

Map<String, Object?> way(int id, List<(double, double)> pts, Map<String, String> tags) => {
  'type': 'way',
  'id': id,
  'tags': {'highway': 'primary', ...tags},
  'geometry': [for (final (lat, lon) in pts) {'lat': lat, 'lon': lon}],
};

/// Rue nord-sud limitée à 50, rue transversale à 30, voie parallèle à 90
/// à 30 m, puis un tronçon à sens unique numérisé vers le sud.
final overpassBody = jsonEncode({
  'elements': [
    way(1, [(48.8500, 2.35), (48.8510, 2.35), (48.8520, 2.35)], {'maxspeed': '50'}),
    way(2, [(48.8505, 2.3490), (48.8505, 2.3510)], {'maxspeed': '30'}),
    way(3, [(48.8500, 2.35 + _east30m), (48.8520, 2.35 + _east30m)], {'maxspeed': '90'}),
    way(4, [(48.8530, 2.35), (48.8520, 2.35)], {'maxspeed': '70', 'oneway': 'yes'}),
    {'type': 'node', 'id': 9, 'lat': 48.85, 'lon': 2.35},
  ],
});

const route = [LatLng(48.8500, 2.35), LatLng(48.8510, 2.35), LatLng(48.8520, 2.35), LatLng(48.8530, 2.35)];

void main() {
  group('balise maxspeed', () {
    test('valeurs explicites et implicites légales', () {
      expect(parseMaxspeed('50'), 50);
      expect(parseMaxspeed('30 mph'), 48);
      expect(parseMaxspeed('FR:urban'), 50);
      expect(parseMaxspeed('FR:motorway'), 130);
      expect(parseMaxspeed('FR:zone30'), 30);
    });

    test('valeurs ambiguës : inconnues', () {
      expect(parseMaxspeed('FR:rural'), isNull, reason: '80 ou 90 selon le département');
      expect(parseMaxspeed('50;30'), isNull);
      expect(parseMaxspeed('none'), isNull);
      expect(parseMaxspeed('signals'), isNull);
      expect(parseMaxspeed('999'), isNull);
      expect(parseMaxspeed(null), isNull);
    });

    test('sens de circulation', () {
      final w = OsmWay.fromOverpass(way(5, [(1, 1), (1.001, 1)], {'maxspeed:forward': '50', 'maxspeed:backward': '70'}) as Map<String, dynamic>)!;
      expect((w.forward, w.backward), (50, 70));
      final oneway = OsmWay.fromOverpass(way(6, [(1, 1), (1.001, 1)], {'maxspeed': '90', 'oneway': 'yes'}) as Map<String, dynamic>)!;
      expect((oneway.forward, oneway.backward), (90, null));
    });
  });

  test('correspondance : bonne voie, bon sens, jamais la rue transversale ni la voie parallèle', () {
    final ways = [
      for (final e in (jsonDecode(overpassBody) as Map<String, dynamic>)['elements'] as List<dynamic>)
        ?OsmWay.fromOverpass(e as Map<String, dynamic>),
    ];
    expect(const SpeedLimitMatcher().match(route, ways), [50, 50, null]);
  });

  test('voie la plus proche sans limitation : inconnue (pas celle de la voie voisine)', () {
    final ways = [
      OsmWay.fromOverpass(way(7, [(48.85, 2.35), (48.851, 2.35)], {}) as Map<String, dynamic>)!,
      OsmWay.fromOverpass(way(8, [(48.85, 2.35 + 8 / (111195 * 0.6578)), (48.851, 2.35 + 8 / (111195 * 0.6578))], {'maxspeed': '30'}) as Map<String, dynamic>)!,
    ];
    expect(const SpeedLimitMatcher().match(route.sublist(0, 2), ways), [null]);
  });

  group('service Overpass', () {
    test('tuiles en cache : une seule requête', () async {
      var calls = 0;
      late String query;
      final s = SpeedLimitService(client: MockClient((r) async {
        calls++;
        query = r.bodyFields['data']!;
        return http.Response(overpassBody, 200);
      }));
      final a = await s.along(route);
      expect(a.limits, [50, 50, null]);
      expect(a.complete, isTrue);
      expect(query, contains('way["highway"~'));
      expect(query, contains('out tags geom'));
      await s.along(route);
      expect(calls, 1);
    });

    test('préchargement puis demande servie depuis le cache', () async {
      var calls = 0;
      final s = SpeedLimitService(client: MockClient((_) async {
        calls++;
        return http.Response(overpassBody, 200);
      }));
      await s.warm(route);
      expect(calls, 1);
      expect((await s.along(route)).limits, [50, 50, null]);
      expect(calls, 1);
    });

    test('Overpass saturé : inconnu, pause avant nouvel essai', () async {
      var calls = 0;
      final s = SpeedLimitService(client: MockClient((_) async {
        calls++;
        return http.Response('rate_limited', 429);
      }));
      final a = await s.along(route);
      expect(a.complete, isFalse);
      expect(a.limits, everyElement(isNull));
      await s.along(route);
      expect(calls, 1, reason: 'pas de nouvelle requête pendant la pause');
    });
  });

  group('API /v1/speedlimits', () {
    const key = 'cle-de-test-1234567890';
    final agg = TrafficAggregator(chains: const [], client: http.Client());

    Future<Response> post(TrafficApi api, Object body) async => api.handler(Request(
      'POST',
      Uri.parse('http://x/v1/speedlimits'),
      headers: {'x-api-key': key},
      body: jsonEncode(body),
    ));

    test('limitations et mention OpenStreetMap', () async {
      final api = TrafficApi(agg, apiKeys: {key}, speedLimits: SpeedLimitService(client: MockClient((_) async => http.Response(overpassBody, 200))));
      final r = await post(api, {'route': [for (final p in route) p.toJson()]});
      final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
      expect(body['limits'], [50, 50, null]);
      expect(body['attribution'], contains('OpenStreetMap'));
    });

    test('service désactivé, tronçon trop long', () async {
      expect((await post(TrafficApi(agg, apiKeys: {key}), {'route': [[2, 48], [2, 48.1]]})).statusCode, 503);
      final api = TrafficApi(agg, apiKeys: {key}, speedLimits: SpeedLimitService(client: MockClient((_) async => http.Response('{}', 200))));
      expect((await post(api, {'route': [[2, 48], [2, 49]]})).statusCode, 400);
    });
  });
}

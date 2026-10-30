import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';
import 'package:vigiroad_traffic_aggregator/traffic_aggregator.dart';

/// Source simulée (tests uniquement).
class FakeConnector extends TrafficConnector {
  FakeConnector(this.id, {this.countries = const ['FR'], this.interval = const Duration(minutes: 2)});
  final String id;
  final List<String> countries;
  final Duration interval;
  List<TrafficEvent> next = [];
  bool failing = false;
  int calls = 0;

  @override
  SourceInfo get info => SourceInfo(
    id: id,
    name: id,
    countries: countries,
    licence: 'test',
    attribution: 'Mention $id',
    minInterval: interval,
    homepage: 'https://example.org/$id',
  );

  @override
  Future<List<TrafficEvent>> fetch(http.Client client, DateTime now) async {
    calls++;
    if (failing) throw SourceException('$id : HTTP 503');
    return [for (final e in next) e.copyWith(fetchedAt: now)];
  }
}

TrafficEvent ev(String source, String id, double lat, double lng, DateTime updated,
        {TrafficEventType type = TrafficEventType.accident, String road = 'N20'}) =>
    TrafficEvent(
      id: '$source:$id',
      type: type,
      position: LatLng(lat, lng),
      road: road,
      severity: Severity.medium,
      updatedAt: updated,
      fetchedAt: updated,
      sources: [source],
    );

void main() {
  var now = DateTime.utc(2026, 10, 30, 21);
  late FakeConnector primary, fallback, other;
  late TrafficAggregator agg;

  setUp(() {
    now = DateTime.utc(2026, 10, 30, 21);
    primary = FakeConnector('fr-primary');
    fallback = FakeConnector('fr-fallback', interval: const Duration(minutes: 5));
    other = FakeConnector('gb-src', countries: ['GB']);
    agg = TrafficAggregator(
      chains: [SourceChain(primary, fallback), SourceChain(other)],
      client: http.Client(),
      clock: () => now,
    );
  });

  test('fusion entre sources et respect de la fréquence autorisée', () async {
    primary.next = [ev('fr-primary', '1', 48.0, 2.0, now)];
    other.next = [ev('gb-src', 'x', 48.0009, 2.0, now.subtract(const Duration(minutes: 5)))];
    await agg.tickOnce();
    expect(agg.events(), hasLength(1));
    expect(agg.events().single.sources, ['fr-primary', 'gb-src']);

    now = now.add(const Duration(seconds: 30));
    await agg.tickOnce();
    expect(primary.calls, 1, reason: 'pas avant 2 minutes');
    now = now.add(const Duration(minutes: 2));
    await agg.tickOnce();
    expect(primary.calls, 2);
  });

  test('basculement vers la source de secours puis retour', () async {
    primary.failing = true;
    fallback.next = [ev('fr-fallback', 'f', 47.0, 1.0, now)];
    for (var i = 0; i < 4; i++) {
      await agg.tickOnce();
      now = now.add(const Duration(minutes: 20));
    }
    expect(agg.status('fr-primary')!.consecutiveFailures, greaterThanOrEqualTo(3));
    expect(agg.status('fr-primary')!.usingFallback, isTrue);
    expect(fallback.calls, greaterThan(0));
    expect(agg.events().map((e) => e.id), contains('fr-fallback:f'));

    primary.failing = false;
    primary.next = [ev('fr-primary', 'p', 46.0, 1.0, now)];
    now = now.add(const Duration(minutes: 31));
    await agg.tickOnce();
    await agg.tickOnce();
    expect(agg.status('fr-primary')!.usingFallback, isFalse);
    expect(agg.events().map((e) => e.id), ['fr-primary:p']);
  });

  test('attente exponentielle plafonnée après échecs', () async {
    other.failing = true;
    await agg.tickOnce();
    final s = agg.status('gb-src')!;
    expect(s.nextPoll.difference(now), const Duration(minutes: 2));
    now = s.nextPoll;
    await agg.tickOnce();
    expect(s.nextPoll.difference(now), const Duration(minutes: 4));
    expect(s.lastError, contains('503'));
  });

  test('données obsolètes exclues et couverture inconnue sans collecte récente', () async {
    primary.next = [
      ev('fr-primary', 'old', 48.0, 2.0, now.subtract(const Duration(hours: 5))),
      ev('fr-primary', 'new', 47.0, 2.0, now),
    ];
    await agg.tickOnce();
    expect(agg.events().map((e) => e.id), ['fr-primary:new']);
    expect(agg.coverage(), {'FR', 'GB'});

    // Plus aucune collecte réussie pendant 31 min : plus rien n'est diffusé.
    primary.failing = true;
    other.failing = true;
    now = now.add(const Duration(minutes: 31));
    await agg.tickOnce();
    expect(agg.events(), isEmpty, reason: 'jamais de données périmées présentées comme actuelles');
    expect(agg.coverage(), isEmpty);
  });

  test('événements le long d\'un itinéraire, dans l\'ordre', () async {
    primary.next = [
      ev('fr-primary', 'b', 48.008, 2.0001, now),
      ev('fr-primary', 'a', 48.002, 2.0, now),
      ev('fr-primary', 'far', 48.005, 2.05, now),
    ];
    await agg.tickOnce();
    final hits = agg.alongRoute(const [LatLng(48.0, 2.0), LatLng(48.01, 2.0)]);
    expect(hits.map((h) => h.event.id), ['fr-primary:a', 'fr-primary:b']);
    expect(hits.first.along, closeTo(222, 3));
  });

  group('API', () {
    late Handler handler;
    const key = 'cle-de-test-1234567890';

    setUp(() async {
      primary.next = [ev('fr-primary', '1', 48.0, 2.0, now)];
      await agg.tickOnce();
      handler = TrafficApi(agg, apiKeys: {key}, limiter: RateLimiter(capacity: 3, refillPerMinute: 1)).handler;
    });

    Future<Response> get(String path, {String? k = key}) =>
        Future.value(handler(Request('GET', Uri.parse('http://x$path'), headers: {'x-api-key': ?k})));

    test('santé sans clé', () async {
      final r = await get('/health', k: null);
      expect(r.statusCode, 200);
      expect(jsonDecode(await r.readAsString())['coverage'], ['FR', 'GB']);
    });

    test('clé obligatoire', () async {
      expect((await get('/v1/events?bbox=1,47,3,49', k: null)).statusCode, 401);
      expect((await get('/v1/events?bbox=1,47,3,49', k: 'mauvaise-cle-xxxxxxxx')).statusCode, 401);
    });

    test('événements d\'une zone avec mentions des sources', () async {
      final r = await get('/v1/events?bbox=1,47,3,49');
      final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
      expect((body['events'] as List).single['id'], 'fr-primary:1');
      expect((body['attributions'] as List).single['text'], 'Mention fr-primary');
      expect(body['coverage'], ['FR', 'GB']);
    });

    test('zone invalide ou trop grande', () async {
      expect((await get('/v1/events?bbox=a')).statusCode, 400);
      expect((await get('/v1/events?bbox=-50,-50,50,50')).statusCode, 400);
    });

    test('itinéraire', () async {
      final r = await handler(Request(
        'POST',
        Uri.parse('http://x/v1/events/route'),
        headers: {'x-api-key': key},
        body: jsonEncode({'route': [[2.0, 47.999], [2.0, 48.01]], 'bufferMeters': 100}),
      ));
      final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
      expect((body['along'] as List).single['alongMeters'], closeTo(111, 3));
    });

    test('limite de débit', () async {
      for (var i = 0; i < 3; i++) {
        expect((await get('/v1/sources')).statusCode, 200);
      }
      expect((await get('/v1/sources')).statusCode, 429);
    });
  });

  test('configuration : sources selon les clés fournies, flux NAP additionnels', () {
    final c = ServerConfig({
      'VR_API_KEYS': 'courte,cle-suffisamment-longue',
      'VR_TFL_APP_KEY': 'abc',
      'VR_DATEX2_FEEDS': 'si-nap|si|https://example.org/d2.xml|Vir: NAP Slovenija|CC BY 4.0',
      'VR_DISABLE_SOURCES': 'gb-tfl',
    });
    expect(c.apiKeys, {'cle-suffisamment-longue'});
    final ids = c.chains().map((s) => s.primary.info.id).toList();
    expect(ids, ['fr-bison-fute', 'si-nap']);
    expect(c.chains().first.fallback?.info.id, 'fr-pan-transport-data-gouv');
  });
}

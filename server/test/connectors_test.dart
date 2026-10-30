import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';
import 'package:vigiroad_traffic_aggregator/traffic_aggregator.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
final now = DateTime.utc(2026, 10, 30, 21);

void main() {
  group('DATEX II (Bison Futé)', () {
    final c = Datex2Connector.bisonFute();
    final events = c.parse(fixture('bison_fute.xml'), fetchedAt: now);

    test('situations réelles et localisées uniquement', () {
      expect(events.map((e) => e.id), ['fr-bison-fute:TEST-1-1', 'fr-bison-fute:TEST-2-1'],
          reason: 'TEST-3 = essai, TEST-4 = sans coordonnées');
    });

    test('accident : type, position, route, sens, gravité, horodatages, description', () {
      final a = events.first;
      expect(a.type, TrafficEventType.accident);
      expect(a.position, const LatLng(48.5869, 2.2475));
      expect(a.road, 'N20');
      expect(a.direction, TrafficDirection.positive);
      expect(a.severity, Severity.high);
      expect(a.updatedAt, DateTime.utc(2026, 10, 30, 20, 40));
      expect(a.startTime, DateTime.utc(2026, 10, 30, 19, 5));
      expect(a.description, 'Accident, voie de gauche neutralisée');
      expect(a.country, 'FR');
    });

    test('travaux linéaires : tracé du début à la fin, fin planifiée', () {
      final w = events[1];
      expect(w.type, TrafficEventType.roadworks);
      expect(w.road, 'A6');
      expect(w.direction, TrafficDirection.both);
      expect(w.position, const LatLng(45.76, 4.83));
      expect(w.geometry, hasLength(2));
      expect(w.endTime, DateTime.utc(2026, 11, 5, 17));
    });

    test('XML invalide : erreur de source explicite', () {
      expect(() => c.parse('<oops', fetchedAt: now), throwsA(isA<SourceException>()));
    });

    test('lecture HTTP réelle via le client', () async {
      final client = MockClient((r) async {
        expect(r.url.host, 'tipi.bison-fute.gouv.fr');
        expect(r.headers['User-Agent'], startsWith('VigiRoadTrafficAggregator'));
        return http.Response.bytes(File('test/fixtures/bison_fute.xml').readAsBytesSync(), 200);
      });
      expect(await c.fetch(client, now), hasLength(2));
      final failing = MockClient((_) async => http.Response('', 503));
      expect(() => c.fetch(failing, now), throwsA(isA<SourceException>()));
    });
  });

  group('WZDx (511 SF Bay)', () {
    final events = WzdxConnector.sfBay('k').parse(fixture('wzdx.json'), fetchedAt: now);
    test('conversion', () {
      expect(events, hasLength(2), reason: 'wz-3 sans date de mise à jour');
      final a = events.first;
      expect(a.road, 'I80');
      expect(a.direction, TrafficDirection.eastbound);
      expect(a.type, TrafficEventType.roadworks);
      expect(a.severity, Severity.unknown, reason: 'WZDx ne donne pas de gravité : pas d\'invention');
      expect(a.position, const LatLng(37.82, -122.30));
      expect(a.geometry, hasLength(2));
      expect(events[1].type, TrafficEventType.closure);
      expect(events[1].severity, Severity.high);
    });
  });

  group('511 v2 (Arizona)', () {
    final events = Us511V2Connector.arizona('k').parse(fixture('az511.json'), fetchedAt: now);
    test('conversion, dates Unix, polyligne', () {
      expect(events, hasLength(2));
      final a = events.first;
      expect(a.type, TrafficEventType.accident);
      expect(a.severity, Severity.high);
      expect(a.road, 'I10');
      expect(a.direction, TrafficDirection.eastbound);
      expect(a.updatedAt, DateTime.utc(2026, 10, 30, 20, 10));
      expect(a.endTime, isNull, reason: 'PlannedEndDate à 0 = non renseignée');
      expect(a.geometry.first.lat, closeTo(38.5, 1e-9));
      expect(events[1].type, TrafficEventType.closure);
      expect(events[1].direction, TrafficDirection.both);
    });
  });

  group('TfL', () {
    final events = TflConnector('k').parse(fixture('tfl.json'), fetchedAt: now);
    test('conversion', () {
      expect(events, hasLength(2), reason: 'TIMS-3 sans position');
      expect(events.first.type, TrafficEventType.accident);
      expect(events.first.position, const LatLng(51.5072, -0.1276));
      expect(events.first.road, 'A40');
      expect(events.first.severity, Severity.high);
      expect(events[1].type, TrafficEventType.closure);
      expect(events[1].severity, Severity.low);
    });
  });

  group('Waze for Cities (partenaire)', () {
    test('alertes fiables seulement', () {
      final events = WazePartnerConnector(Uri.parse('https://example.org/feed')).parse(fixture('waze.json'), fetchedAt: now);
      expect(events.single.id, 'waze-partner:a1');
      expect(events.single.road, 'A6');
    });
  });

  test('polyligne Google', () {
    final p = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(p, hasLength(3));
    expect(p[2].lat, closeTo(43.252, 1e-9));
    expect(p[2].lng, closeTo(-126.453, 1e-9));
  });
}

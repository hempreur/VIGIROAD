import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';
import 'package:vigiroad_traffic_aggregator/traffic_aggregator.dart';

void main() {
  var now = DateTime.utc(2026, 11, 1, 20);
  const paris = LatLng(48.8566, 2.3522);
  // ≈ 100 m plus au nord.
  const near = LatLng(48.8575, 2.3522);
  // ≈ 2 km plus au nord.
  const far = LatLng(48.8746, 2.3522);

  ReportStore store({File? file}) => ReportStore(clock: () => now, file: file);

  group('signalements', () {
    test('visible 2 h puis retiré', () {
      final s = store();
      final r = s.submit(position: paris, heading: 90, side: ReportSide.mine, client: 'a');
      expect(r.heading, 90);
      expect(r.expiresAt, now.add(const Duration(hours: 2)));
      now = now.add(const Duration(minutes: 119));
      expect(s.active(), hasLength(1));
      now = now.add(const Duration(minutes: 2));
      expect(s.active(), isEmpty);
    });

    test('route en face : sens concerné opposé', () {
      final r = store().submit(position: paris, heading: 350, side: ReportSide.opposite, client: 'a');
      expect(r.heading, closeTo(170, 1e-9));
      expect(r.concerns(175), isTrue);
      expect(r.concerns(350), isFalse);
      expect(r.concerns(null), isTrue);
    });

    test('même endroit et même sens : confirmation et 2 h de plus', () {
      final s = store();
      final a = s.submit(position: paris, heading: 90, side: ReportSide.mine, client: 'a');
      now = now.add(const Duration(minutes: 30));
      final b = s.submit(position: near, heading: 100, side: ReportSide.mine, client: 'b');
      expect(b.id, a.id);
      expect(b.confirmations, 2);
      expect(b.expiresAt, now.add(const Duration(hours: 2)));
      expect(s.active(), hasLength(1));
    });

    test('sens opposé ou plus loin : nouveau marqueur', () {
      final s = store();
      s.submit(position: paris, heading: 90, side: ReportSide.mine, client: 'a');
      s.submit(position: near, heading: 270, side: ReportSide.mine, client: 'b');
      s.submit(position: far, heading: 90, side: ReportSide.mine, client: 'c');
      expect(s.active(), hasLength(3));
    });

    test('anti-abus : une fois par minute, douze par heure', () {
      final s = store();
      s.submit(position: paris, heading: 0, side: ReportSide.mine, client: 'a');
      expect(
        () => s.submit(position: far, heading: 0, side: ReportSide.mine, client: 'a'),
        throwsA(isA<ReportRejected>().having((e) => e.status, 'status', 429)),
      );
      expect(s.submit(position: far, heading: 0, side: ReportSide.mine, client: 'b').confirmations, 1);
      for (var i = 0; i < 11; i++) {
        now = now.add(const Duration(minutes: 2));
        s.submit(position: LatLng(45 + i * 0.1, 3), heading: 0, side: ReportSide.mine, client: 'a');
      }
      now = now.add(const Duration(minutes: 2));
      expect(() => s.submit(position: const LatLng(40, 3), heading: 0, side: ReportSide.mine, client: 'a'), throwsA(isA<ReportRejected>()));
    });

    test('valeurs invalides refusées', () {
      final s = store();
      expect(() => s.submit(position: const LatLng(95, 2), side: ReportSide.mine, client: 'a'), throwsA(isA<ReportRejected>()));
      expect(() => s.submit(position: paris, heading: 400, side: ReportSide.mine, client: 'a'), throwsA(isA<ReportRejected>()));
    });

    test('persistance : seuls position, sens et dates sont écrits', () async {
      final dir = await Directory.systemTemp.createTemp('vr_reports');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/reports.json');
      final s = store(file: file);
      s.submit(position: paris, heading: 45, side: ReportSide.mine, client: '203.0.113.7');
      await s.flush();
      final text = await file.readAsString();
      expect(text, isNot(contains('203.0.113')), reason: 'aucune adresse IP sur disque');
      final reloaded = store(file: file);
      await reloaded.load();
      expect(reloaded.active().single.heading, 45);
      now = now.add(const Duration(hours: 3));
      final expired = store(file: file);
      await expired.load();
      expect(expired.active(), isEmpty);
    });
  });

  group('API', () {
    const key = 'cle-de-test-0123456789';
    late Handler handler;

    setUp(() {
      now = DateTime.utc(2026, 11, 1, 20);
      final agg = TrafficAggregator(chains: const [], client: http.Client());
      handler = TrafficApi(agg, apiKeys: {key}, reports: ReportStore(clock: () => now)).handler;
    });

    Future<(int, Map<String, dynamic>)> call(String method, String path, {Object? body, String ip = '198.51.100.1'}) async {
      final r = await handler(Request(
        method,
        Uri.parse('http://x$path'),
        headers: {'x-api-key': key, 'x-forwarded-for': '$ip, 10.0.0.2', 'content-type': 'application/json'},
        body: body == null ? null : jsonEncode(body),
      ));
      return (r.statusCode, jsonDecode(await r.readAsString()) as Map<String, dynamic>);
    }

    test('signaler puis voir le marqueur dans la zone', () async {
      final (code, created) = await call('POST', '/v1/reports', body: {'position': [2.3522, 48.8566], 'heading': 120.0, 'side': 'mine'});
      expect(code, 201);
      expect((created['report'] as Map)['side'], 'mine');
      final (ok, list) = await call('GET', '/v1/reports?bbox=2.2,48.8,2.5,48.9');
      expect(ok, 200);
      expect(list['reports'], hasLength(1));
      expect(list['lifetimeMinutes'], 120);
      final (_, elsewhere) = await call('GET', '/v1/reports?bbox=4.7,45.7,4.9,45.8');
      expect(elsewhere['reports'], isEmpty);
    });

    test('requêtes invalides', () async {
      expect((await call('POST', '/v1/reports', body: {'position': [2.35], 'side': 'mine'})).$1, 400);
      expect((await call('POST', '/v1/reports', body: {'position': [2.35, 48.85], 'side': 'gauche'})).$1, 400);
      expect((await call('POST', '/v1/reports', body: {'position': [2.35, 48.85], 'heading': 'nord', 'side': 'mine'})).$1, 400);
      expect((await call('GET', '/v1/reports')).$1, 400);
    });

    test('limite par connexion', () async {
      final body = {'position': [2.3522, 48.8566], 'side': 'opposite'};
      expect((await call('POST', '/v1/reports', body: body)).$1, 201);
      expect((await call('POST', '/v1/reports', body: body)).$1, 429);
      expect((await call('POST', '/v1/reports', body: body, ip: '198.51.100.2')).$1, 201, reason: 'autre conducteur');
    });
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vigiroad/features/navigation/application/navigation_providers.dart';
import 'package:vigiroad/features/navigation/application/navigation_session.dart';
import 'package:vigiroad/features/navigation/domain/geo_fix.dart';
import 'package:vigiroad/features/navigation/presentation/widgets/traffic_legend.dart';
import 'package:vigiroad/features/settings/application/settings_controller.dart';
import 'package:vigiroad/features/traffic/application/speed_limit_controller.dart';
import 'package:vigiroad/features/traffic/application/traffic_announcer.dart';
import 'package:vigiroad/features/traffic/application/traffic_controller.dart';
import 'package:vigiroad/features/traffic/application/traffic_summary.dart';
import 'package:vigiroad/features/traffic/data/traffic_client.dart';
import 'package:vigiroad/features/traffic/domain/traffic_labels.dart';
import 'package:vigiroad/features/traffic/domain/traffic_snapshot.dart';
import 'package:vigiroad/features/sentrix/application/sentrix_controller.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

const _bison = TrafficAttribution(source: 'fr-bison-fute', text: 'Information fournie par Bison Futé');

TrafficEvent _event(String id, GeoPoint at, {Severity severity = Severity.high, TrafficEventType type = TrafficEventType.accident}) =>
    TrafficEvent(
      id: 'fr-bison-fute:$id',
      type: type,
      position: LatLng(at.latitude, at.longitude),
      road: 'N20',
      severity: severity,
      updatedAt: DateTime.utc(2026, 10, 30, 14),
      fetchedAt: DateTime.utc(2026, 10, 30, 14),
      sources: const ['fr-bison-fute'],
    );

TrafficSnapshot _snap(List<TrafficEvent> events, {bool known = true}) => TrafficSnapshot(
  events: events,
  known: known,
  updatedAt: known ? DateTime.utc(2026, 10, 30, 14, 2) : null,
  attributions: known ? const [_bison] : const [],
  receivedAt: DateTime.utc(2026, 10, 30, 14, 3),
);

/// Serveur de trafic simulé.
class FakeTrafficClient implements TrafficClient {
  TrafficSnapshot area = _snap(const []);
  TrafficSnapshot route = _snap(const []);
  TrafficException? error;
  int boxCalls = 0, routeCalls = 0, speedCalls = 0;
  List<int?> Function(int segments) limits = (n) => List.filled(n, 50);
  bool limitsComplete = true;

  @override
  Future<TrafficSnapshot> inBox(BBox box) async {
    boxCalls++;
    if (error != null) throw error!;
    return area;
  }

  @override
  Future<TrafficSnapshot> alongRoute(List<LatLng> r, {double bufferM = 150}) async {
    routeCalls++;
    if (error != null) throw error!;
    return route;
  }

  @override
  Future<({List<int?> limits, bool complete})> speedLimits(List<LatLng> r) async {
    speedCalls++;
    return (limits: limits(r.length - 1), complete: limitsComplete);
  }
}

class _Env {
  _Env({bool trafficOn = true}) {
    container = ProviderContainer(
      overrides: [
        locationSourceProvider.overrideWithValue(location),
        routeServiceProvider.overrideWithValue(FakeRouteService()),
        speakerProvider.overrideWithValue(speaker),
        wakelockProvider.overrideWithValue((_) {}),
        clockProvider.overrideWithValue(() => now),
        notificationPermissionProvider.overrideWithValue(() async {}),
        settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
        trafficClientProvider.overrideWithValue(trafficOn ? client : null),
        sentrixBubbleDurationProvider.overrideWithValue(Duration.zero),
      ],
    );
    container.listen(navigationSessionProvider, (_, _) {});
    container.listen(positionProvider, (_, _) {});
    container.listen(trafficProvider, (_, _) {});
    container.listen(trafficAnnouncerProvider, (_, _) {});
    container.listen(speedLimitProvider, (_, _) {});
  }

  final location = FakeLocationSource();
  final speaker = FakeSpeaker();
  final client = FakeTrafficClient();
  DateTime now = DateTime(2026, 10, 30, 15);
  late final ProviderContainer container;

  TrafficState get traffic => container.read(trafficProvider);

  Future<void> fix(GeoPoint p) async {
    await pumpEventQueue();
    location.push(fixAt(p));
    await pumpEventQueue();
  }

  Future<void> go() async {
    container.read(destinationProvider.notifier).set(
      Destination(label: 'Arrivée', detail: '', point: testRoute().geometry.last),
    );
    await pumpEventQueue();
  }
}

void main() {
  group('libellés', () {
    test('distances parlées', () {
      expect(TrafficLabels.spokenDistance(380), '400 mètres');
      expect(TrafficLabels.spokenDistance(2450), '2,5 kilomètres');
      expect(TrafficLabels.spokenDistance(3020), '3 kilomètres');
      expect(TrafficLabels.spokenDistance(12400), '12 kilomètres');
    });

    test('annonces', () {
      final e = _event('1', north(0));
      expect(TrafficLabels.announcement(e, 2000), 'Attention, accident sur la N20 dans 2 kilomètres.');
      final works = e.copyWith(type: TrafficEventType.roadworks, severity: Severity.low, road: 'A6');
      expect(TrafficLabels.announcement(works, 600), 'Travaux sur l\'A6 dans 600 mètres.');
    });
  });

  group('client HTTP', () {
    test('zone : clé, emprise, état connu et mentions', () async {
      late http.Request sent;
      final c = HttpTrafficClient(
        baseUrl: 'https://trafic.example.org/',
        apiKey: 'cle-de-test-1234567890',
        userAgent: 'VIGIROAD/test',
        client: MockClient((r) async {
          sent = r;
          return http.Response.bytes(utf8.encode(jsonEncode({
            'area': {'known': true, 'updatedAt': '2026-10-30T14:02:00Z', 'sources': [{'source': 'fr-bison-fute', 'coverage': 'réseau national'}]},
            'attributions': [{'source': 'fr-bison-fute', 'text': 'Information fournie par Bison Futé', 'updatedAt': '2026-10-30T14:02:00Z'}],
            'events': [_event('1', north(0)).toJson()],
          })), 200);
        }),
      );
      final s = await c.inBox(const BBox(2, 48, 3, 49));
      expect(sent.url.path, '/v1/events');
      expect(sent.url.queryParameters['bbox'], '2.00000,48.00000,3.00000,49.00000');
      expect(sent.headers['X-Api-Key'], 'cle-de-test-1234567890');
      expect(s.known, isTrue);
      expect(s.events.single.road, 'N20');
      expect(s.attributions.single.text, contains('Bison Futé'));
      expect(s.coverageNotes, ['réseau national']);
    });

    test('réponse sans état de zone : jamais présumée connue', () async {
      final c = HttpTrafficClient(
        baseUrl: 'https://t',
        apiKey: 'k',
        userAgent: 'u',
        client: MockClient((_) async => http.Response('{"events": []}', 200)),
      );
      expect((await c.inBox(const BBox(0, 0, 1, 1))).known, isFalse);
    });

    test('clé refusée : erreur explicite', () async {
      final c = HttpTrafficClient(baseUrl: 'https://t', apiKey: 'k', userAgent: 'u', client: MockClient((_) async => http.Response('', 401)));
      expect(() => c.inBox(const BBox(0, 0, 1, 1)), throwsA(isA<TrafficException>()));
    });

    test('itinéraire allégé avant envoi', () {
      final pts = [for (var i = 0; i < 5000; i++) LatLng(48 + i * 1e-5, 2)];
      final t = thin(pts, 1500);
      expect(t, hasLength(1500));
      expect(t.first, pts.first);
      expect(t.last, pts.last);
    });
  });

  group('état du trafic', () {
    test('sans serveur configuré : désactivé, aucune requête', () async {
      final env = _Env(trafficOn: false);
      addTearDown(env.container.dispose);
      await env.fix(north(0));
      expect(env.traffic.status, TrafficStatus.disabled);
    });

    test('zone couverte, zone inconnue', () async {
      final env = _Env();
      addTearDown(env.container.dispose);
      env.client.area = _snap([_event('1', north(300))]);
      await env.fix(north(0));
      expect(env.traffic.status, TrafficStatus.known);
      expect(env.traffic.visible, hasLength(1));
      expect(env.traffic.attributions.single.text, contains('Bison Futé'));

      env.client.area = _snap(const [], known: false);
      await env.container.read(trafficProvider.notifier).refresh();
      expect(env.traffic.status, TrafficStatus.unknown);
      expect(trafficSummary(env.traffic, env.container.read(navigationSessionProvider)).text, contains('inconnu'));
    });

    test('serveur injoignable : données conservées 5 min, puis plus rien', () async {
      final env = _Env();
      addTearDown(env.container.dispose);
      env.client.area = _snap([_event('1', north(300))]);
      await env.fix(north(0));
      env.client.error = const TrafficException('Serveur de trafic injoignable');

      env.now = env.now.add(const Duration(minutes: 2));
      await env.container.read(trafficProvider.notifier).refresh();
      expect(env.traffic.status, TrafficStatus.known);

      env.now = env.now.add(const Duration(minutes: 4));
      await env.container.read(trafficProvider.notifier).refresh();
      expect(env.traffic.status, TrafficStatus.error);
      expect(env.traffic.visible, isEmpty, reason: 'jamais de données périmées affichées');
    });
  });

  group('SENTRIX et itinéraire', () {
    test('annonce une fois la perturbation située devant', () async {
      final env = _Env();
      addTearDown(env.container.dispose);
      env.client.route = _snap([_event('acc', north(800))]);
      await env.fix(north(0));
      await env.go();
      await pumpEventQueue();
      expect(env.client.routeCalls, greaterThan(0));
      expect(env.traffic.onRoute.single.alongM, closeTo(800, 2));

      await env.fix(north(100));
      await pumpEventQueue();
      final said = env.speaker.spoken.where((t) => t.contains('accident sur la N20')).toList();
      expect(said, hasLength(1));
      expect(said.single, startsWith('Attention, accident sur la N20 dans'));

      await env.fix(north(200));
      await env.fix(north(300));
      expect(env.speaker.spoken.where((t) => t.contains('accident')), hasLength(1), reason: 'une seule annonce');

      final summary = trafficSummary(env.traffic, env.container.read(navigationSessionProvider));
      expect(summary.text, startsWith('Une perturbation signalée sur votre itinéraire.'));
    });

    test('perturbation déjà dépassée ou guidage vocal coupé : silence', () async {
      final env = _Env();
      addTearDown(env.container.dispose);
      env.client.route = _snap([_event('acc', north(800))]);
      await env.fix(north(0));
      env.container.read(voiceGuidanceProvider.notifier).toggle();
      await env.go();
      await env.fix(north(100));
      await pumpEventQueue();
      expect(env.speaker.spoken.where((t) => t.contains('accident')), isEmpty);
    });
  });

  group('limitations de vitesse OpenStreetMap', () {
    test('client : une valeur par segment, valeurs aberrantes écartées', () async {
      final c = HttpTrafficClient(
        baseUrl: 'https://t',
        apiKey: 'k',
        userAgent: 'u',
        client: MockClient((r) async {
          expect(r.url.path, '/v1/speedlimits');
          return http.Response(jsonEncode({'limits': [50, null, 900], 'complete': true}), 200);
        }),
      );
      final r = await c.speedLimits(const [LatLng(48, 2), LatLng(48.001, 2), LatLng(48.002, 2), LatLng(48.003, 2)]);
      expect(r.limits, [50, null, null]);
      expect(r.complete, isTrue);
    });

    test('chargées pour l\'itinéraire, segment par segment', () async {
      final env = _Env();
      addTearDown(env.container.dispose);
      env.client.limits = (n) => [for (var i = 0; i < n; i++) i < 10 ? 50 : null];
      await env.fix(north(0));
      await env.go();
      await env.fix(north(100));
      await pumpEventQueue();
      final s = env.container.read(speedLimitProvider);
      expect(env.client.speedCalls, 1, reason: 'itinéraire court : une seule fenêtre');
      expect(s.at(0), 50);
      expect(s.at(12), isNull, reason: 'inconnue : jamais devinée');
      await env.fix(north(200));
      expect(env.client.speedCalls, 1);
    });

    test('réponse partielle : nouvel essai après une pause', () async {
      final env = _Env();
      addTearDown(env.container.dispose);
      env.client.limitsComplete = false;
      await env.fix(north(0));
      await env.go();
      await env.fix(north(100));
      expect(env.client.speedCalls, 1);
      env.now = env.now.add(const Duration(seconds: 50));
      env.client.limitsComplete = true;
      await env.fix(north(150));
      await pumpEventQueue();
      expect(env.client.speedCalls, 2);
    });

    test('sans serveur : rien n\'est demandé', () async {
      final env = _Env(trafficOn: false);
      addTearDown(env.container.dispose);
      await env.fix(north(0));
      await env.go();
      await env.fix(north(100));
      expect(env.container.read(speedLimitProvider).limits, isEmpty);
    });
  });

  group('légende', () {
    Future<void> pump(WidgetTester t, TrafficState s, {bool route = true, double? along}) =>
        t.pumpWidget(wrapDark(Center(child: TrafficLegend(state: s, hasRoute: route, alongM: along))));

    TrafficEvent ev(String id, Severity sev) => TrafficEvent(
      id: id,
      type: TrafficEventType.roadworks,
      severity: sev,
      position: const LatLng(48.9, 2.35),
      sources: const ['fr-bison-fute'],
      updatedAt: DateTime(2026, 10, 30, 14),
      fetchedAt: DateTime(2026, 10, 30, 14),
    );

    testWidgets('zone inconnue : jamais « fluide »', (t) async {
      await pump(t, const TrafficState(status: TrafficStatus.unknown));
      expect(find.text('État inconnu'), findsOneWidget);
      expect(find.textContaining('luide'), findsNothing);
    });

    testWidgets('sans trajet : aucun compte', (t) async {
      await pump(t, const TrafficState(status: TrafficStatus.known), route: false);
      expect(find.text('Aucun trajet'), findsOneWidget);
    });

    testWidgets('compte les seules perturbations du trajet encore devant, sans mention de source', (t) async {
      await pump(
        t,
        TrafficState(
          status: TrafficStatus.known,
          attributions: const [_bison],
          updatedAt: DateTime(2026, 10, 30, 14, 2),
          nearby: [ev('zone', Severity.high)],
          onRoute: [
            RouteTrafficEvent(ev('passee', Severity.high), 500),
            RouteTrafficEvent(ev('a', Severity.low), 4000),
            RouteTrafficEvent(ev('b', Severity.medium), 9000),
          ],
        ),
        along: 2000,
      );
      expect(find.text('2 perturbations'), findsOneWidget);
      expect(find.textContaining('Information fournie'), findsNothing);
      expect(find.textContaining('Mise à jour'), findsNothing);
    });

    testWidgets('trajet sans perturbation', (t) async {
      await pump(t, const TrafficState(status: TrafficStatus.known));
      expect(find.text('0 perturbation'), findsOneWidget);
    });
  });
}

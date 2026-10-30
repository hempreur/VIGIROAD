import 'package:test/test.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

final t0 = DateTime.utc(2026, 10, 30, 20);

TrafficEvent ev(
  String id, {
  double lat = 48.0,
  double lng = 2.0,
  TrafficEventType type = TrafficEventType.accident,
  String? road = 'N20',
  TrafficDirection dir = TrafficDirection.unknown,
  Severity sev = Severity.medium,
  Duration age = Duration.zero,
  DateTime? end,
  String source = 'fr-bison-fute',
}) => TrafficEvent(
  id: '$source:$id',
  type: type,
  position: LatLng(lat, lng),
  road: road,
  direction: dir,
  severity: sev,
  updatedAt: t0.subtract(age),
  fetchedAt: t0,
  endTime: end,
  sources: [source],
);

void main() {
  group('normalisation', () {
    test('routes', () {
      expect(normalizeRoad('N0020'), 'N20');
      expect(normalizeRoad('a 6'), 'A6');
      expect(normalizeRoad('RN7'), 'RN7');
      expect(normalizeRoad('D 120 A'), 'D120A');
      expect(normalizeRoad('M25'), 'M25');
      expect(normalizeRoad('  '), isNull);
    });

    test('JSON aller-retour', () {
      final e = ev('1', end: t0.add(const Duration(hours: 1))).copyWith(
        geometry: const [LatLng(48, 2), LatLng(48.01, 2.01)],
        description: 'Accident',
        country: 'FR',
      );
      final back = TrafficEvent.fromJson(e.toJson());
      expect(back.toJson(), e.toJson());
    });

    test('valeurs inconnues', () {
      expect(TrafficEventType.parse('tornado'), TrafficEventType.other);
      expect(Severity.parse(null), Severity.unknown);
    });
  });

  group('fusion des doublons', () {
    const m = EventMerger();

    test('deux sources, même accident à 150 m : un seul événement', () {
      final a = ev('1', age: const Duration(minutes: 10), sev: Severity.low);
      final b = ev('9', lat: 48.0013, source: 'eu-nap', sev: Severity.high);
      final out = m.merge([a, b]);
      expect(out, hasLength(1));
      expect(out.single.sources, ['eu-nap', 'fr-bison-fute']);
      expect(out.single.severity, Severity.high);
      expect(out.single.id, 'eu-nap:9', reason: 'information la plus récente');
    });

    test('routes différentes, sens opposés, familles différentes : distincts', () {
      expect(m.merge([ev('1'), ev('2', road: 'A10')]), hasLength(2));
      expect(m.merge([ev('1', dir: TrafficDirection.positive), ev('2', dir: TrafficDirection.negative)]), hasLength(2));
      expect(m.merge([ev('1'), ev('2', type: TrafficEventType.roadworks)]), hasLength(2));
    });

    test('trop éloignés : distincts', () {
      expect(m.merge([ev('1'), ev('2', lat: 48.01)]), hasLength(2));
    });

    test('accident et obstacle = même famille', () {
      expect(m.merge([ev('1'), ev('2', type: TrafficEventType.obstruction)]), hasLength(1));
    });

    test('grande liste : fusion locale correcte', () {
      final list = [
        for (var i = 0; i < 500; i++) ev('$i', lat: 45 + i * 0.05, lng: 2),
        for (var i = 0; i < 500; i++) ev('d$i', lat: 45 + i * 0.05 + 0.0005, lng: 2, source: 'x'),
      ];
      expect(m.merge(list), hasLength(500));
    });
  });

  group('fraîcheur', () {
    const f = FreshnessPolicy();
    test('incident récent / ancien', () {
      expect(f.isFresh(ev('1', age: const Duration(hours: 1)), t0), isTrue);
      expect(f.isFresh(ev('1', age: const Duration(hours: 4)), t0), isFalse);
    });
    test('fin passée', () {
      expect(f.isFresh(ev('1', end: t0.subtract(const Duration(minutes: 1))), t0), isFalse);
    });
    test('travaux planifiés encore en cours', () {
      final w = ev('1', type: TrafficEventType.roadworks, age: const Duration(days: 10), end: t0.add(const Duration(days: 3)));
      expect(f.isFresh(w, t0), isTrue);
    });
    test('collecte trop ancienne (source injoignable)', () {
      final e = ev('1').copyWith(fetchedAt: t0.subtract(const Duration(hours: 1)));
      expect(f.isFresh(e, t0), isFalse);
    });
  });

  group('géométrie', () {
    test('distance à une polyligne et position le long', () {
      const line = [LatLng(48, 2), LatLng(48.01, 2)];
      final r = distanceToPolyline(const LatLng(48.005, 2.001), line);
      expect(r.distance, closeTo(74, 2));
      expect(r.along, closeTo(556, 3));
    });
    test('bbox', () {
      expect(BBox.tryParse('2,48,3,49')!.contains(const LatLng(48.5, 2.5)), isTrue);
      expect(BBox.tryParse('3,48,2,49'), isNull);
      expect(BBox.tryParse('a,b'), isNull);
    });
  });
}

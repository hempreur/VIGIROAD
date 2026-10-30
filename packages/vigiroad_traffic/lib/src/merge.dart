import 'geo.dart';
import 'traffic_event.dart';

/// Règles de fraîcheur : un événement trop ancien n'est plus diffusé.
class FreshnessPolicy {
  const FreshnessPolicy({
    this.maxAgeIncident = const Duration(hours: 3),
    this.maxAgePlanned = const Duration(days: 2),
    this.maxCollectionAge = const Duration(minutes: 30),
  });

  /// Événement imprévu (accident, bouchon, obstacle…) sans mise à jour depuis.
  final Duration maxAgeIncident;

  /// Événement planifié (travaux, fermeture) sans mise à jour depuis.
  final Duration maxAgePlanned;

  /// Donnée collectée il y a plus longtemps (source injoignable depuis).
  final Duration maxCollectionAge;

  bool isPlanned(TrafficEventType t) =>
      t == TrafficEventType.roadworks || t == TrafficEventType.closure || t == TrafficEventType.restriction ||
      t == TrafficEventType.event;

  /// L'événement est-il encore exploitable à [now] ?
  bool isFresh(TrafficEvent e, DateTime now) {
    if (e.endTime != null && e.endTime!.isBefore(now)) return false;
    if (now.difference(e.fetchedAt) > maxCollectionAge) return false;
    final maxAge = isPlanned(e.type) ? maxAgePlanned : maxAgeIncident;
    // Un événement planifié encore en cours (fin dans le futur) reste valable.
    if (isPlanned(e.type) && e.endTime != null && e.endTime!.isAfter(now)) return true;
    return now.difference(e.updatedAt) <= maxAge;
  }
}

/// Familles d'événements comparables entre sources.
int _family(TrafficEventType t) => switch (t) {
  TrafficEventType.accident || TrafficEventType.obstruction => 0,
  TrafficEventType.roadworks || TrafficEventType.closure || TrafficEventType.restriction => 1,
  TrafficEventType.congestion => 2,
  TrafficEventType.weather => 3,
  TrafficEventType.event => 4,
  TrafficEventType.other => 5,
};

/// Détecte et fusionne les doublons (même événement signalé par plusieurs
/// sources ou plusieurs fois par une même source).
///
/// Deux événements sont considérés identiques s'ils sont de la même famille,
/// à moins de [radiusM] l'un de l'autre, sur la même route (quand les deux
/// routes sont connues), dans des sens compatibles, et actifs sur des
/// périodes qui se recoupent. L'événement fusionné garde l'information la
/// plus récente, la gravité la plus élevée et la liste des sources.
class EventMerger {
  const EventMerger({this.radiusM = 300});

  final double radiusM;

  bool sameEvent(TrafficEvent a, TrafficEvent b) {
    if (_family(a.type) != _family(b.type)) return false;
    if (a.road != null && b.road != null && a.road != b.road) return false;
    final da = a.direction, db = b.direction;
    if (da != TrafficDirection.unknown &&
        db != TrafficDirection.unknown &&
        da != TrafficDirection.both &&
        db != TrafficDirection.both &&
        da != db) {
      return false;
    }
    final aEnd = a.endTime, bEnd = b.endTime, aStart = a.startTime, bStart = b.startTime;
    if (aEnd != null && bStart != null && aEnd.isBefore(bStart)) return false;
    if (bEnd != null && aStart != null && bEnd.isBefore(aStart)) return false;
    return haversine(a.position, b.position) <= radiusM;
  }

  TrafficEvent combine(TrafficEvent a, TrafficEvent b) {
    final newer = a.updatedAt.isAfter(b.updatedAt) ? a : b;
    final older = identical(newer, a) ? b : a;
    final sev = a.severity.index >= b.severity.index ? a.severity : b.severity;
    return newer.copyWith(
      severity: sev,
      geometry: newer.geometry.isNotEmpty ? newer.geometry : older.geometry,
      road: newer.road ?? older.road,
      description: newer.description ?? older.description,
      startTime: _min(a.startTime, b.startTime),
      endTime: newer.endTime ?? older.endTime,
      fetchedAt: a.fetchedAt.isAfter(b.fetchedAt) ? a.fetchedAt : b.fetchedAt,
      sources: {...a.sources, ...b.sources}.toList()..sort(),
    );
  }

  static DateTime? _min(DateTime? a, DateTime? b) =>
      a == null ? b : (b == null ? a : (a.isBefore(b) ? a : b));

  /// Fusionne une liste d'événements (O(n²) par cellule de grille ≈ linéaire).
  List<TrafficEvent> merge(Iterable<TrafficEvent> events) {
    // Grille d'environ 0,01° (~1 km) pour ne comparer que les voisins.
    String cell(LatLng p, int dx, int dy) => '${(p.lat * 100).floor() + dy}:${(p.lng * 100).floor() + dx}';
    final grid = <String, List<int>>{};
    final out = <TrafficEvent>[];
    for (final e in events) {
      int? target;
      search:
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          for (final i in grid[cell(e.position, dx, dy)] ?? const <int>[]) {
            if (sameEvent(out[i], e)) {
              target = i;
              break search;
            }
          }
        }
      }
      if (target != null) {
        out[target] = combine(out[target], e);
      } else {
        out.add(e);
        grid.putIfAbsent(cell(e.position, 0, 0), () => []).add(out.length - 1);
      }
    }
    return out;
  }
}

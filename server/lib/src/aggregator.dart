import 'dart:async';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import 'source.dart';

/// État d'une source pour la supervision (`/v1/sources`).
class SourceStatus {
  SourceStatus(this.connector);

  final TrafficConnector connector;
  List<TrafficEvent> events = const [];
  DateTime? lastAttempt;
  DateTime? lastSuccess;
  String? lastError;
  int consecutiveFailures = 0;
  DateTime nextPoll = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// Source de secours en cours d'utilisation.
  bool usingFallback = false;

  Map<String, Object?> toJson(DateTime now) => {
    ...connector.info.toJson(),
    'healthy': consecutiveFailures == 0 && lastSuccess != null,
    'events': events.length,
    'lastSuccess': lastSuccess?.toIso8601String(),
    'lastAttempt': lastAttempt?.toIso8601String(),
    'lastError': lastError,
    'usingFallback': usingFallback,
  };
}

/// Source principale et, éventuellement, source de secours pour la même zone.
class SourceChain {
  const SourceChain(this.primary, [this.fallback]);
  final TrafficConnector primary;
  final TrafficConnector? fallback;
}

/// VigiRoadTrafficAggregator : interroge chaque source à la fréquence
/// autorisée, normalise, fusionne les doublons, écarte les données obsolètes.
///
/// Règle : aucune circulation simulée. Une zone sans donnée récente est
/// signalée comme inconnue (absente de [coverage]).
class TrafficAggregator {
  TrafficAggregator({
    required List<SourceChain> chains,
    required this.client,
    DateTime Function()? clock,
    this.freshness = const FreshnessPolicy(),
    this.merger = const EventMerger(),
    this.failoverAfter = 3,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()) {
    for (final c in chains) {
      _chains.add(c);
      _status[c.primary.info.id] = SourceStatus(c.primary);
      if (c.fallback != null) _status[c.fallback!.info.id] = SourceStatus(c.fallback!);
    }
  }

  final http.Client client;
  final DateTime Function() _clock;
  final FreshnessPolicy freshness;
  final EventMerger merger;

  /// Nombre d'échecs consécutifs avant de basculer sur la source de secours.
  final int failoverAfter;

  final _chains = <SourceChain>[];
  final _status = <String, SourceStatus>{};
  Timer? _timer;
  List<TrafficEvent>? _merged;

  Iterable<SourceStatus> get statuses => _status.values;
  SourceStatus? status(String id) => _status[id];

  void start({Duration tick = const Duration(seconds: 15)}) {
    _timer?.cancel();
    unawaited(tickOnce());
    _timer = Timer.periodic(tick, (_) => unawaited(tickOnce()));
  }

  void stop() => _timer?.cancel();

  /// Interroge les sources dont l'échéance est atteinte.
  Future<void> tickOnce() async {
    final now = _clock();
    final jobs = <Future<void>>[];
    for (final chain in _chains) {
      final primary = _status[chain.primary.info.id]!;
      if (!now.isBefore(primary.nextPoll)) jobs.add(_poll(primary, now));
      final fb = chain.fallback;
      if (fb != null) {
        final fallback = _status[fb.info.id]!;
        final needed = primary.consecutiveFailures >= failoverAfter;
        primary.usingFallback = needed;
        if (needed && !now.isBefore(fallback.nextPoll)) jobs.add(_poll(fallback, now));
        if (!needed) fallback.events = const [];
      }
    }
    await Future.wait(jobs);
  }

  Future<void> _poll(SourceStatus s, DateTime now) async {
    s.lastAttempt = now;
    try {
      final events = await s.connector.fetch(client, now);
      s
        ..events = events
        ..lastSuccess = now
        ..lastError = null
        ..consecutiveFailures = 0
        ..nextPoll = now.add(s.connector.info.minInterval);
    } on SourceException catch (e) {
      _failed(s, now, e.message);
    } on Exception catch (e) {
      _failed(s, now, '${s.connector.info.id} : $e');
    }
    _merged = null;
  }

  /// Échec : nouvel essai avec attente exponentielle (plafonnée à 30 min),
  /// jamais plus tôt que la fréquence autorisée.
  void _failed(SourceStatus s, DateTime now, String message) {
    s.consecutiveFailures++;
    s.lastError = message;
    final backoff = s.connector.info.minInterval * math.pow(2, math.min(s.consecutiveFailures - 1, 4)).toInt();
    s.nextPoll = now.add(backoff > const Duration(minutes: 30) ? const Duration(minutes: 30) : backoff);
  }

  /// Événements frais, fusionnés, toutes sources confondues.
  List<TrafficEvent> events() {
    final now = _clock();
    final all = <TrafficEvent>[
      for (final s in _status.values)
        for (final e in s.events)
          if (freshness.isFresh(e, now)) e,
    ];
    _merged ??= merger.merge(all);
    // La fraîcheur évolue avec le temps même sans nouvelle collecte.
    return [for (final e in _merged!) if (freshness.isFresh(e, now)) e];
  }

  List<TrafficEvent> inBox(BBox box) => [for (final e in events()) if (box.contains(e.position)) e];

  /// Événements à moins de [bufferM] d'un itinéraire, avec leur distance
  /// depuis le départ, triés dans l'ordre de rencontre.
  List<({TrafficEvent event, double along, double offset})> alongRoute(List<LatLng> route, {double bufferM = 150}) {
    if (route.length < 2) return const [];
    var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
    for (final p in route) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    final pad = bufferM / 111000 * 2;
    final box = BBox(minLng - pad, minLat - pad, maxLng + pad, maxLat + pad);
    final out = <({TrafficEvent event, double along, double offset})>[];
    for (final e in inBox(box)) {
      final r = distanceToPolyline(e.position, route);
      if (r.distance <= bufferM) out.add((event: e, along: r.along, offset: r.distance));
    }
    out.sort((a, b) => a.along.compareTo(b.along));
    return out;
  }

  /// Sources dont l'emprise touche [box] et dont la dernière collecte réussie
  /// est récente. Vide : l'état du trafic y est **inconnu**.
  List<SourceStatus> coveringFresh(BBox box) {
    final now = _clock();
    return [
      for (final s in _status.values)
        if (s.lastSuccess != null &&
            now.difference(s.lastSuccess!) <= freshness.maxCollectionAge &&
            s.connector.info.areas.any(box.intersects))
          s,
    ];
  }

  /// Pays disposant actuellement de données fraîches (sinon : état inconnu).
  Set<String> coverage() {
    final now = _clock();
    return {
      for (final s in _status.values)
        if (s.lastSuccess != null && now.difference(s.lastSuccess!) <= freshness.maxCollectionAge)
          ...s.connector.info.countries,
    };
  }
}

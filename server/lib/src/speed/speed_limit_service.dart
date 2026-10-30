import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../source.dart';
import 'matcher.dart';
import 'osm_way.dart';

/// Limitations de vitesse OpenStreetMap le long d'un itinéraire, via une
/// instance Overpass.
///
/// Respect de la politique d'usage d'Overpass : découpage en tuiles mises en
/// cache [cacheTtl], une seule requête à la fois, attente après un refus
/// (429/504). Les tuiles non obtenues laissent les segments en « inconnu ».
class SpeedLimitService {
  SpeedLimitService({
    required this.client,
    Uri? overpassUrl,
    this.cacheTtl = const Duration(days: 7),
    this.maxTiles = 4000,
    this.tilesPerQuery = 12,
    this.matcher = const SpeedLimitMatcher(),
    DateTime Function()? clock,
  }) : overpassUrl = overpassUrl ?? Uri.parse('https://overpass-api.de/api/interpreter'),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final http.Client client;
  final Uri overpassUrl;
  final Duration cacheTtl;
  final int maxTiles;
  final int tilesPerQuery;
  final SpeedLimitMatcher matcher;
  final DateTime Function() _clock;

  static const tileDeg = 0.02; // ≈ 2 km
  static const attribution = '© contributeurs OpenStreetMap (ODbL)';

  /// Types de voies routières interrogés. Ni chemins piétons ou cyclables,
  /// ni voies de service (allées de parking…) : très nombreuses en ville,
  /// elles alourdiraient fortement les réponses sans servir au guidage.
  static const _highways =
      'motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|'
      'tertiary|tertiary_link|unclassified|residential|living_street|road';

  /// Préchargement : nombre maximal de tuiles (≈ 2 km) par itinéraire.
  static const maxWarmTiles = 150;

  final _cache = <(int, int), ({List<OsmWay> ways, DateTime at})>{};
  Future<void> _lock = Future.value();
  DateTime? _pausedUntil;
  int overpassQueries = 0;

  ({int y, int x}) _tile(LatLng p) => (y: (p.lat / tileDeg).floor(), x: (p.lng / tileDeg).floor());

  /// Limitation (km/h) de chaque segment de [route] (`null` = inconnue),
  /// et `complete` faux si des tuiles n'ont pas pu être obtenues.
  Future<({List<int?> limits, bool complete})> along(List<LatLng> route) async {
    final needed = <(int, int)>{for (final p in route) (_tile(p).y, _tile(p).x)};
    final missing = await _ensure(needed);
    final ways = <int, OsmWay>{
      for (final t in needed)
        if (_cache[t] case final entry?)
          for (final w in entry.ways) w.id: w,
    };
    return (limits: matcher.match(route, ways.values.toList()), complete: missing.isEmpty);
  }

  /// Précharge les tuiles d'un itinéraire (appelé dès son calcul) pour que
  /// les demandes de limitations suivantes soient servies depuis le cache.
  Future<void> warm(List<LatLng> route) async {
    final tiles = <(int, int)>{};
    for (final p in route) {
      tiles.add((_tile(p).y, _tile(p).x));
      if (tiles.length >= maxWarmTiles) break;
    }
    // Par lots : une demande de limitations arrivée entre-temps passe avant
    // la suite du préchargement au lieu d'attendre l'itinéraire entier.
    final list = tiles.toList();
    for (var i = 0; i < list.length; i += tilesPerQuery) {
      await _ensure(list.sublist(i, math.min(list.length, i + tilesPerQuery)).toSet());
    }
  }

  /// Charge les tuiles absentes ou périmées ; renvoie celles restées absentes.
  Future<Set<(int, int)>> _ensure(Set<(int, int)> tiles) {
    final done = Completer<Set<(int, int)>>();
    _lock = _lock.then((_) async {
      final now = _clock();
      final todo = [
        for (final t in tiles)
          if (_cache[t] == null || now.difference(_cache[t]!.at) > cacheTtl) t,
      ];
      final failed = <(int, int)>{};
      for (var i = 0; i < todo.length; i += tilesPerQuery) {
        final batch = todo.sublist(i, math.min(todo.length, i + tilesPerQuery));
        final paused = _pausedUntil;
        if (paused != null && now.isBefore(paused)) {
          failed.addAll(batch);
          continue;
        }
        try {
          await _fetch(batch);
        } on Object {
          // Overpass refuse ou ne répond pas : pause d'une minute.
          _pausedUntil = _clock().add(const Duration(minutes: 1));
          failed.addAll(batch);
        }
      }
      done.complete(failed);
    }).catchError((Object _) {
      if (!done.isCompleted) done.complete(tiles);
    });
    return done.future;
  }

  Future<void> _fetch(List<(int, int)> batch) async {
    String box((int, int) t) {
      final s = t.$1 * tileDeg, w = t.$2 * tileDeg;
      return '${s.toStringAsFixed(4)},${w.toStringAsFixed(4)},${(s + tileDeg).toStringAsFixed(4)},${(w + tileDeg).toStringAsFixed(4)}';
    }

    final query = '[out:json][timeout:40];('
        '${batch.map((t) => 'way["highway"~"^($_highways)\$"](${box(t)});').join()}'
        ');out tags geom;';
    overpassQueries++;
    final http.Response res;
    try {
      res = await client
          .post(overpassUrl, headers: {'User-Agent': 'VigiRoadTrafficAggregator/1.0 (+https://github.com/hempreur/VIGIROAD)'}, body: {'data': query})
          .timeout(const Duration(seconds: 60));
    } on Exception catch (e) {
      throw SourceException('overpass : réseau indisponible ($e)');
    }
    if (res.statusCode != 200) throw SourceException('overpass : HTTP ${res.statusCode}');
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw const SourceException('overpass : réponse illisible');
    }
    final elements = json is Map<String, dynamic> ? json['elements'] : null;
    if (elements is! List) throw const SourceException('overpass : réponse inattendue');
    final ways = [
      for (final e in elements)
        if (e is Map<String, dynamic>) ?OsmWay.fromOverpass(e),
    ];
    final at = _clock();
    for (final t in batch) {
      final tb = BBox(t.$2 * tileDeg, t.$1 * tileDeg, (t.$2 + 1) * tileDeg, (t.$1 + 1) * tileDeg);
      _cache.remove(t);
      _cache[t] = (ways: [for (final w in ways) if (w.bbox.intersects(tb)) w], at: at);
    }
    while (_cache.length > maxTiles) {
      _cache.remove(_cache.keys.first); // plus ancienne tuile chargée
    }
  }
}

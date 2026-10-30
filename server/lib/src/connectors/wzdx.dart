import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../source.dart';

/// Connecteur WZDx (Work Zone Data Exchange, norme USDOT, GeoJSON).
///
/// Format publié par de nombreux services 511 américains, dont 511 SF Bay.
/// Spécification : https://github.com/usdot-jpo-ode/wzdx
class WzdxConnector extends TrafficConnector {
  WzdxConnector({required this.info, required this.url});

  /// 511 SF Bay (MTC) : jeton gratuit, 60 requêtes/heure par défaut.
  factory WzdxConnector.sfBay(String apiKey) => WzdxConnector(
    url: Uri.parse('https://api.511.org/traffic/wzdx').replace(queryParameters: {'api_key': apiKey}),
    info: const SourceInfo(
      id: 'us-ca-511-sfbay',
      name: '511 SF Bay — zones de travaux (WZDx)',
      countries: ['US'],
      licence: 'Conditions d\'utilisation 511 SF Bay Open Data',
      attribution: 'Données : 511 SF Bay',
      // 60 requêtes/heure autorisées par clé : une toutes les 2 minutes reste en dessous.
      minInterval: Duration(minutes: 2),
      homepage: 'https://511.org/open-data/traffic',
      areas: [BBox(-123.1, 36.9, -121.2, 38.9)],
      coverageNote: 'baie de San Francisco, zones de travaux uniquement',
      requiresKey: true,
    ),
  );

  @override
  final SourceInfo info;
  final Uri url;

  @override
  Future<List<TrafficEvent>> fetch(http.Client client, DateTime now) async =>
      parse(await getText(client, url), fetchedAt: now);

  List<TrafficEvent> parse(String body, {required DateTime fetchedAt}) {
    final Object? json;
    try {
      json = jsonDecode(body.startsWith('﻿') ? body.substring(1) : body);
    } on FormatException catch (e) {
      throw SourceException('${info.id} : JSON invalide (${e.message})');
    }
    if (json is! Map<String, dynamic> || json['features'] is! List) {
      throw SourceException('${info.id} : flux WZDx inattendu');
    }
    final events = <TrafficEvent>[];
    for (final f in (json['features'] as List<dynamic>).whereType<Map<String, dynamic>>()) {
      final props = f['properties'];
      if (props is! Map<String, dynamic>) continue;
      final core = props['core_details'] is Map<String, dynamic> ? props['core_details'] as Map<String, dynamic> : props;
      final coords = _coords(f['geometry']);
      if (coords.isEmpty) continue;
      final updated = DateTime.tryParse('${core['update_date'] ?? props['update_date'] ?? ''}')?.toUtc();
      if (updated == null) continue;
      final eventType = '${core['event_type'] ?? 'work-zone'}';
      final impact = '${props['vehicle_impact'] ?? ''}';
      final roads = core['road_names'];
      events.add(TrafficEvent(
        id: '${info.id}:${f['id'] ?? props['road_event_id'] ?? coords.first}',
        type: impact == 'all-lanes-closed' ? TrafficEventType.closure : (eventType == 'detour' ? TrafficEventType.restriction : TrafficEventType.roadworks),
        position: coords.first,
        geometry: coords.length > 1 ? coords : const [],
        road: roads is List && roads.isNotEmpty ? normalizeRoad('${roads.first}') : null,
        direction: switch ('${core['direction'] ?? ''}') {
          'northbound' => TrafficDirection.northbound,
          'southbound' => TrafficDirection.southbound,
          'eastbound' => TrafficDirection.eastbound,
          'westbound' => TrafficDirection.westbound,
          'inner-loop' || 'outer-loop' || 'undefined' || 'unknown' || '' => TrafficDirection.unknown,
          _ => TrafficDirection.unknown,
        },
        // WZDx ne fournit pas de gravité normalisée : on n'en invente pas.
        severity: impact == 'all-lanes-closed' ? Severity.high : Severity.unknown,
        startTime: DateTime.tryParse('${props['start_date'] ?? ''}')?.toUtc(),
        endTime: DateTime.tryParse('${props['end_date'] ?? ''}')?.toUtc(),
        updatedAt: updated,
        fetchedAt: fetchedAt,
        sources: [info.id],
        description: core['description'] as String?,
        country: 'US',
      ));
    }
    return events;
  }

  /// Point ou ligne GeoJSON (longitude, latitude).
  static List<LatLng> _coords(Object? geometry) {
    if (geometry is! Map<String, dynamic>) return const [];
    final c = geometry['coordinates'];
    LatLng? pt(Object? v) => v is List && v.length >= 2 && v[0] is num && v[1] is num
        ? LatLng((v[1] as num).toDouble(), (v[0] as num).toDouble())
        : null;
    return switch (geometry['type']) {
      'Point' => [?pt(c)],
      'LineString' || 'MultiPoint' => c is List ? [for (final p in c) ?pt(p)] : const [],
      'MultiLineString' => c is List && c.isNotEmpty && c.first is List ? [for (final p in c.first as List<dynamic>) ?pt(p)] : const [],
      _ => const [],
    };
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../source.dart';

/// Transport for London — perturbations routières (Unified API).
///
/// Endpoint : `https://api.tfl.gov.uk/Road/all/Disruption` (+ `app_key`).
/// Champs lus de façon tolérante : la documentation publique ne détaille
/// pas tout le schéma ; format à confirmer sur le flux réel (verified=false).
class TflConnector extends TrafficConnector {
  TflConnector(this.appKey);

  final String appKey;

  @override
  SourceInfo get info => const SourceInfo(
    id: 'gb-tfl',
    name: 'Transport for London — perturbations routières',
    countries: ['GB'],
    licence: 'Transport for London Open Data (conditions TfL)',
    attribution: 'Powered by TfL Open Data',
    minInterval: Duration(minutes: 2),
    homepage: 'https://tfl.gov.uk/info-for/open-data-users/',
    requiresKey: true,
  );

  @override
  Future<List<TrafficEvent>> fetch(http.Client client, DateTime now) async {
    final uri = Uri.parse('https://api.tfl.gov.uk/Road/all/Disruption').replace(queryParameters: {'app_key': appKey});
    return parse(await getText(client, uri), fetchedAt: now);
  }

  List<TrafficEvent> parse(String body, {required DateTime fetchedAt}) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException catch (e) {
      throw SourceException('${info.id} : JSON invalide (${e.message})');
    }
    if (json is! List) throw SourceException('${info.id} : liste de perturbations attendue');
    final out = <TrafficEvent>[];
    for (final d in json.whereType<Map<String, dynamic>>()) {
      final p = _point(d['point']);
      if (p == null) continue;
      final updated = DateTime.tryParse('${d['lastModifiedTime'] ?? d['currentUpdateDateTime'] ?? ''}')?.toUtc();
      if (updated == null) continue;
      final category = '${d['category'] ?? ''}'.toLowerCase();
      final sub = '${d['subCategory'] ?? ''}'.toLowerCase();
      final hasClosures = d['hasClosures'] == true;
      out.add(TrafficEvent(
        id: '${info.id}:${d['id']}',
        type: hasClosures
            ? TrafficEventType.closure
            : category.contains('collision') || sub.contains('collision')
            ? TrafficEventType.accident
            : category.contains('works')
            ? TrafficEventType.roadworks
            : category.contains('event')
            ? TrafficEventType.event
            : category.contains('weather') || category.contains('environment')
            ? TrafficEventType.weather
            : category.contains('traffic')
            ? TrafficEventType.congestion
            : category.contains('hazard') || category.contains('incident')
            ? TrafficEventType.obstruction
            : TrafficEventType.other,
        position: p,
        road: _road(d),
        severity: switch ('${d['severity'] ?? ''}'.toLowerCase()) {
          'minimal' => Severity.low,
          'moderate' => Severity.medium,
          'serious' => Severity.high,
          'severe' => Severity.critical,
          _ => Severity.unknown,
        },
        startTime: DateTime.tryParse('${d['startDateTime'] ?? ''}')?.toUtc(),
        endTime: DateTime.tryParse('${d['endDateTime'] ?? ''}')?.toUtc(),
        updatedAt: updated,
        fetchedAt: fetchedAt,
        sources: [info.id],
        description: (d['comments'] ?? d['currentUpdate'] ?? d['location']) as String?,
        country: 'GB',
      ));
    }
    return out;
  }

  /// `point` est une chaîne « [longitude,latitude] » dans l'API TfL.
  static LatLng? _point(Object? v) {
    try {
      final list = v is String ? jsonDecode(v) : v;
      if (list is List && list.length >= 2 && list[0] is num && list[1] is num) {
        return LatLng((list[1] as num).toDouble(), (list[0] as num).toDouble());
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static String? _road(Map<String, dynamic> d) {
    final ids = d['corridorIds'];
    if (ids is List && ids.isNotEmpty) return normalizeRoad('${ids.first}');
    return null;
  }
}

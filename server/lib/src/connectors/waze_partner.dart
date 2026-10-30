import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../source.dart';

/// Waze for Cities (programme partenaire « Waze for Cities / Partner Hub »).
///
/// N'est activé **que** si une URL de flux partenaire a été obtenue auprès
/// de Waze et configurée (`VR_WAZE_FEED_URL`) : l'accès est réservé aux
/// partenaires et ses conditions interdisent tout autre usage. Lit les
/// alertes du flux JSON partenaire (`alerts`).
class WazePartnerConnector extends TrafficConnector {
  WazePartnerConnector(this.feedUrl);

  final Uri feedUrl;

  @override
  SourceInfo get info => const SourceInfo(
    id: 'waze-partner',
    name: 'Waze for Cities (flux partenaire)',
    countries: [],
    licence: 'Accord de partenariat Waze for Cities',
    attribution: 'Données Waze',
    minInterval: Duration(minutes: 2),
    homepage: 'https://www.waze.com/wazeforcities/',
    requiresKey: true,
  );

  @override
  Future<List<TrafficEvent>> fetch(http.Client client, DateTime now) async =>
      parse(await getText(client, feedUrl), fetchedAt: now);

  List<TrafficEvent> parse(String body, {required DateTime fetchedAt}) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException catch (e) {
      throw SourceException('${info.id} : JSON invalide (${e.message})');
    }
    final alerts = json is Map<String, dynamic> ? json['alerts'] : null;
    if (alerts is! List) return const [];
    final out = <TrafficEvent>[];
    for (final a in alerts.whereType<Map<String, dynamic>>()) {
      final loc = a['location'];
      if (loc is! Map<String, dynamic> || loc['x'] is! num || loc['y'] is! num) continue;
      final ms = a['pubMillis'];
      if (ms is! num) continue;
      final reliability = (a['reliability'] as num?)?.toInt() ?? 0;
      if (reliability < 5) continue; // signalements peu confirmés écartés
      out.add(TrafficEvent(
        id: '${info.id}:${a['uuid']}',
        type: switch (a['type']) {
          'ACCIDENT' => TrafficEventType.accident,
          'JAM' => TrafficEventType.congestion,
          'ROAD_CLOSED' => TrafficEventType.closure,
          'WEATHERHAZARD' || 'HAZARD' => TrafficEventType.obstruction,
          _ => TrafficEventType.other,
        },
        position: LatLng((loc['y'] as num).toDouble(), (loc['x'] as num).toDouble()),
        road: normalizeRoad(a['street'] as String?),
        severity: Severity.unknown,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true),
        fetchedAt: fetchedAt,
        sources: [info.id],
        country: a['country'] as String?,
      ));
    }
    return out;
  }
}

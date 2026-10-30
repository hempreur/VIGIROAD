import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../polyline.dart';
import '../source.dart';

/// Connecteur des services 511 américains sur la plateforme « 511 API v2 »
/// (`/api/v2/get/event`) : Arizona, et autres États utilisant ce socle.
///
/// Documentation : https://www.az511.com/help/endpoint/event — dates en
/// secondes Unix, limitation à 10 appels par minute.
class Us511V2Connector extends TrafficConnector {
  Us511V2Connector({required this.info, required this.baseUrl, required this.apiKey});

  factory Us511V2Connector.arizona(String apiKey) => Us511V2Connector(
    baseUrl: 'https://az511.com',
    apiKey: apiKey,
    info: const SourceInfo(
      id: 'us-az-511',
      name: 'AZ511 — événements routiers (Arizona)',
      countries: ['US'],
      licence: 'Conditions d\'utilisation AZ511 (clé développeur)',
      attribution: 'Données : AZ511 / ADOT',
      minInterval: Duration(minutes: 2),
      homepage: 'https://www.az511.com/developers/doc',
      requiresKey: true,
    ),
  );

  @override
  final SourceInfo info;
  final String baseUrl;
  final String apiKey;

  @override
  Future<List<TrafficEvent>> fetch(http.Client client, DateTime now) async {
    final uri = Uri.parse('$baseUrl/api/v2/get/event').replace(queryParameters: {'key': apiKey, 'format': 'json'});
    return parse(await getText(client, uri), fetchedAt: now);
  }

  List<TrafficEvent> parse(String body, {required DateTime fetchedAt}) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException catch (e) {
      throw SourceException('${info.id} : JSON invalide (${e.message})');
    }
    if (json is! List) throw SourceException('${info.id} : liste d\'événements attendue');
    DateTime? unix(Object? v) =>
        v is num && v > 0 ? DateTime.fromMillisecondsSinceEpoch((v * 1000).round(), isUtc: true) : null;

    final out = <TrafficEvent>[];
    for (final e in json.whereType<Map<String, dynamic>>()) {
      final lat = (e['Latitude'] as num?)?.toDouble();
      final lng = (e['Longitude'] as num?)?.toDouble();
      final updated = unix(e['LastUpdated']) ?? unix(e['Reported']);
      if (lat == null || lng == null || updated == null) continue;
      List<LatLng> line = const [];
      final enc = e['EncodedPolyline'];
      if (enc is String && enc.isNotEmpty) {
        try {
          line = decodePolyline(enc);
        } on FormatException {
          line = const [];
        }
      }
      final closure = e['IsFullClosure'] == true;
      out.add(TrafficEvent(
        id: '${info.id}:${e['ID']}',
        type: closure
            ? TrafficEventType.closure
            : switch (e['EventType']) {
                'accidentsAndIncidents' => TrafficEventType.accident,
                'roadwork' => TrafficEventType.roadworks,
                'closures' => TrafficEventType.closure,
                'specialEvents' => TrafficEventType.event,
                'winterDrivingIndex' => TrafficEventType.weather,
                _ => TrafficEventType.other,
              },
        position: LatLng(lat, lng),
        geometry: line.length > 1 ? line : const [],
        road: normalizeRoad(e['RoadwayName'] as String?),
        direction: switch ('${e['DirectionOfTravel'] ?? ''}'.toLowerCase()) {
          'northbound' => TrafficDirection.northbound,
          'southbound' => TrafficDirection.southbound,
          'eastbound' => TrafficDirection.eastbound,
          'westbound' => TrafficDirection.westbound,
          'both directions' || 'all directions' => TrafficDirection.both,
          _ => TrafficDirection.unknown,
        },
        severity: switch ('${e['Severity'] ?? ''}'.toLowerCase()) {
          'minor' || 'low' => Severity.low,
          'moderate' || 'medium' => Severity.medium,
          'major' || 'high' => Severity.high,
          'critical' || 'severe' => Severity.critical,
          _ => closure ? Severity.high : Severity.unknown,
        },
        startTime: unix(e['StartDate']),
        endTime: unix(e['PlannedEndDate']),
        updatedAt: updated,
        fetchedAt: fetchedAt,
        sources: [info.id],
        description: e['Description'] as String?,
        country: 'US',
      ));
    }
    return out;
  }
}

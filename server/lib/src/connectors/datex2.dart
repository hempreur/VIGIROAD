import 'package:http/http.dart' as http;
import 'package:vigiroad_traffic/vigiroad_traffic.dart';
import 'package:xml/xml.dart';

import '../source.dart';

/// Connecteur DATEX II 2.x (publications `SituationPublication`).
///
/// Utilisé pour Bison Futé (point d'accès national français) et pour les
/// points d'accès nationaux européens (réseau NAPCORE) qui publient en
/// DATEX II 2.x. Tolère l'enveloppe SOAP et les préfixes d'espace de noms.
class Datex2Connector extends TrafficConnector {
  Datex2Connector({required this.info, required this.url, this.country});

  /// Flux temps réel officiel de Bison Futé (Licence Ouverte 2.0 /
  /// licence de réutilisation des données dynamiques).
  factory Datex2Connector.bisonFute() => Datex2Connector(
    country: 'FR',
    url: Uri.parse('http://tipi.bison-fute.gouv.fr/bison-fute-ouvert/publicationsDIR/Evenementiel-DIR/grt/RRN/content.xml'),
    info: const SourceInfo(
      id: 'fr-bison-fute',
      name: 'Bison Futé — réseau routier national non concédé',
      countries: ['FR'],
      licence: 'Licence de réutilisation des données d\'information routière (Bison Futé) / Licence Ouverte 2.0',
      attribution: 'Information fournie par Bison Futé',
      minInterval: Duration(minutes: 2),
      homepage: 'https://www.bison-fute.gouv.fr/s-abonner.html',
      verified: true,
    ),
  );

  @override
  final SourceInfo info;
  final Uri url;
  final String? country;

  @override
  Future<List<TrafficEvent>> fetch(http.Client client, DateTime now) async =>
      parse(await getText(client, url), fetchedAt: now);

  /// Conversion d'une publication DATEX II en événements.
  List<TrafficEvent> parse(String xmlText, {required DateTime fetchedAt}) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlText);
    } on XmlException catch (e) {
      throw SourceException('${info.id} : XML invalide (${e.message})');
    }
    final events = <TrafficEvent>[];
    for (final situation in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'situation')) {
      final status = _text(situation, 'informationStatus');
      if (status != null && status != 'real') continue; // essais, exercices
      final situationSeverity = _text(situation, 'overallSeverity', direct: true);
      for (final rec in situation.childElements.where((e) => e.name.local == 'situationRecord')) {
        final e = _record(rec, situationSeverity, fetchedAt);
        if (e != null) events.add(e);
      }
    }
    return events;
  }

  TrafficEvent? _record(XmlElement rec, String? situationSeverity, DateTime fetchedAt) {
    if (_text(rec, 'probabilityOfOccurrence') == 'improbable') return null;
    final type = _type(_xsiType(rec), rec);
    final coords = <LatLng>[];
    for (final pc in rec.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'pointCoordinates' || e.name.local == 'locationForDisplay',
    )) {
      final lat = double.tryParse(_text(pc, 'latitude') ?? '');
      final lng = double.tryParse(_text(pc, 'longitude') ?? '');
      if (lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180) {
        final p = LatLng(lat, lng);
        if (!coords.contains(p)) coords.add(p);
      }
    }
    if (coords.isEmpty) return null; // non localisable : inexploitable sur une carte
    // Zone linéaire : DATEX II publie « to » avant « from » ; on part du début.
    final from = rec.descendants.whereType<XmlElement>().where((e) => e.name.local == 'from').firstOrNull;
    if (from != null && coords.length > 1) {
      final lat = double.tryParse(_text(from, 'latitude') ?? '');
      final lng = double.tryParse(_text(from, 'longitude') ?? '');
      if (lat != null && lng != null) {
        final start = LatLng(lat, lng);
        coords
          ..remove(start)
          ..insert(0, start);
      }
    }

    final updated = _time(rec, 'situationRecordVersionTime') ??
        _time(rec, 'situationRecordObservationTime') ??
        _time(rec, 'situationRecordCreationTime');
    if (updated == null) return null;

    String? comment;
    for (final c in rec.childElements.where((e) => e.name.local == 'generalPublicComment')) {
      final value = _text(c, 'value');
      if (value == null) continue;
      if (_text(c, 'commentType') == 'description' || comment == null) comment = value;
    }

    return TrafficEvent(
      id: '${info.id}:${rec.getAttribute('id') ?? updated.millisecondsSinceEpoch}',
      type: type,
      position: coords.first,
      geometry: coords.length > 1 ? coords : const [],
      road: normalizeRoad(_text(rec, 'roadNumber')),
      direction: _direction(_text(rec, 'tpegDirection') ?? _text(rec, 'alertCDirectionCoded') ?? _text(rec, 'directionRelativeAtPoint')),
      severity: _severity(_text(rec, 'severity') ?? situationSeverity),
      startTime: _time(rec, 'overallStartTime'),
      endTime: _time(rec, 'overallEndTime'),
      updatedAt: updated,
      fetchedAt: fetchedAt,
      sources: [info.id],
      description: comment,
      country: country,
    );
  }

  static String? _xsiType(XmlElement e) {
    final t = e.attributes.where((a) => a.name.local == 'type').map((a) => a.value).firstOrNull;
    return t?.split(':').last;
  }

  static String? _text(XmlElement parent, String localName, {bool direct = false}) {
    final it = direct ? parent.childElements : parent.descendants.whereType<XmlElement>();
    final e = it.where((x) => x.name.local == localName).firstOrNull;
    final t = e?.innerText.trim();
    return t == null || t.isEmpty ? null : t;
  }

  static DateTime? _time(XmlElement parent, String localName) {
    final t = _text(parent, localName);
    return t == null ? null : DateTime.tryParse(t)?.toUtc();
  }

  static TrafficEventType _type(String? xsiType, XmlElement rec) {
    switch (xsiType) {
      case 'Accident':
        return TrafficEventType.accident;
      case 'AbnormalTraffic':
        return TrafficEventType.congestion;
      case 'MaintenanceWorks' || 'ConstructionWorks' || 'Roadworks':
        return TrafficEventType.roadworks;
      case 'GeneralObstruction' ||
          'VehicleObstruction' ||
          'AnimalPresenceObstruction' ||
          'EnvironmentalObstruction' ||
          'InfrastructureDamageObstruction' ||
          'Obstruction':
        return TrafficEventType.obstruction;
      case 'WeatherRelatedRoadConditions' || 'PoorEnvironmentConditions' || 'NonWeatherRelatedRoadConditions':
        return TrafficEventType.weather;
      case 'PublicEvent' || 'DisturbanceActivity':
        return TrafficEventType.event;
      case 'SpeedManagement' || 'ReroutingManagement' || 'WinterDrivingManagement':
        return TrafficEventType.restriction;
      case 'RoadOrCarriagewayOrLaneManagement':
        final m = (_text(rec, 'roadOrCarriagewayOrLaneManagementType') ?? '').toLowerCase();
        return m.contains('closed') || m.contains('closure') ? TrafficEventType.closure : TrafficEventType.restriction;
      default:
        return TrafficEventType.other;
    }
  }

  static Severity _severity(String? s) => switch (s) {
    'lowest' || 'low' => Severity.low,
    'medium' => Severity.medium,
    'high' => Severity.high,
    'highest' => Severity.critical,
    _ => Severity.unknown,
  };

  static TrafficDirection _direction(String? d) => switch (d) {
    'bothWays' || 'both' || 'allDirections' => TrafficDirection.both,
    'positive' || 'aligned' => TrafficDirection.positive,
    'negative' || 'opposite' => TrafficDirection.negative,
    'northBound' => TrafficDirection.northbound,
    'southBound' => TrafficDirection.southbound,
    'eastBound' => TrafficDirection.eastbound,
    'westBound' => TrafficDirection.westbound,
    _ => TrafficDirection.unknown,
  };
}

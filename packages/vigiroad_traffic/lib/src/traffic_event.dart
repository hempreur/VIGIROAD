/// Modèle unique des perturbations routières, quelle que soit la source
/// (DATEX II, JSON, GeoJSON, WZDx…).
library;

/// Nature de l'événement.
enum TrafficEventType {
  accident,
  congestion,
  roadworks,
  closure,
  obstruction,
  weather,
  restriction,
  event,
  other;

  static TrafficEventType parse(String? v) =>
      values.where((e) => e.name == v).firstOrNull ?? other;
}

/// Gravité normalisée. [unknown] quand la source ne la fournit pas : on ne
/// l'invente jamais.
enum Severity {
  unknown,
  low,
  medium,
  high,
  critical;

  static Severity parse(String? v) => values.where((e) => e.name == v).firstOrNull ?? unknown;
}

/// Sens de circulation concerné.
enum TrafficDirection {
  both,
  positive,
  negative,
  northbound,
  southbound,
  eastbound,
  westbound,
  unknown;

  static TrafficDirection parse(String? v) =>
      values.where((e) => e.name == v).firstOrNull ?? unknown;
}

/// Coordonnée WGS84.
class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;

  List<double> toJson() => [lng, lat];
  static LatLng fromJson(List<dynamic> j) => LatLng((j[1] as num).toDouble(), (j[0] as num).toDouble());

  @override
  bool operator ==(Object o) => o is LatLng && o.lat == lat && o.lng == lng;
  @override
  int get hashCode => Object.hash(lat, lng);
  @override
  String toString() => '($lat, $lng)';
}

/// Événement de trafic normalisé.
class TrafficEvent {
  const TrafficEvent({
    required this.id,
    required this.type,
    required this.position,
    required this.severity,
    required this.sources,
    required this.updatedAt,
    required this.fetchedAt,
    this.geometry = const [],
    this.road,
    this.direction = TrafficDirection.unknown,
    this.startTime,
    this.endTime,
    this.description,
    this.country,
  });

  /// Identifiant stable : `<source>:<identifiant chez la source>` (ou celui
  /// de l'événement principal après fusion).
  final String id;
  final TrafficEventType type;

  /// Point représentatif (début de la zone ou point unique).
  final LatLng position;

  /// Tracé de la zone concernée si la source le fournit (sinon vide).
  final List<LatLng> geometry;

  /// Numéro ou nom de la route (normalisé : « N20 », « A6 », « M25 »).
  final String? road;
  final TrafficDirection direction;
  final Severity severity;
  final DateTime? startTime;
  final DateTime? endTime;

  /// Dernière mise à jour de l'information **par la source**.
  final DateTime updatedAt;

  /// Moment où l'agrégateur a lu la source (fraîcheur de la collecte).
  final DateTime fetchedAt;

  /// Identifiants des sources ayant signalé l'événement (après fusion).
  final List<String> sources;
  final String? description;

  /// Code pays ISO 3166-1 alpha-2.
  final String? country;

  TrafficEvent copyWith({
    String? id,
    TrafficEventType? type,
    LatLng? position,
    List<LatLng>? geometry,
    String? road,
    TrafficDirection? direction,
    Severity? severity,
    DateTime? startTime,
    DateTime? endTime,
    DateTime? updatedAt,
    DateTime? fetchedAt,
    List<String>? sources,
    String? description,
    String? country,
  }) => TrafficEvent(
    id: id ?? this.id,
    type: type ?? this.type,
    position: position ?? this.position,
    geometry: geometry ?? this.geometry,
    road: road ?? this.road,
    direction: direction ?? this.direction,
    severity: severity ?? this.severity,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    updatedAt: updatedAt ?? this.updatedAt,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    sources: sources ?? this.sources,
    description: description ?? this.description,
    country: country ?? this.country,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'position': position.toJson(),
    if (geometry.isNotEmpty) 'geometry': [for (final p in geometry) p.toJson()],
    if (road != null) 'road': road,
    'direction': direction.name,
    'severity': severity.name,
    if (startTime != null) 'startTime': startTime!.toUtc().toIso8601String(),
    if (endTime != null) 'endTime': endTime!.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'sources': sources,
    if (description != null) 'description': description,
    if (country != null) 'country': country,
  };

  static TrafficEvent fromJson(Map<String, dynamic> j) {
    DateTime? t(String k) => j[k] == null ? null : DateTime.parse(j[k] as String);
    return TrafficEvent(
      id: j['id'] as String,
      type: TrafficEventType.parse(j['type'] as String?),
      position: LatLng.fromJson(j['position'] as List<dynamic>),
      geometry: [for (final p in (j['geometry'] as List<dynamic>? ?? const [])) LatLng.fromJson(p as List<dynamic>)],
      road: j['road'] as String?,
      direction: TrafficDirection.parse(j['direction'] as String?),
      severity: Severity.parse(j['severity'] as String?),
      startTime: t('startTime'),
      endTime: t('endTime'),
      updatedAt: t('updatedAt')!,
      fetchedAt: t('fetchedAt')!,
      sources: [for (final s in j['sources'] as List<dynamic>) s as String],
      description: j['description'] as String?,
      country: j['country'] as String?,
    );
  }
}

/// Normalise un numéro de route : « N0020 » → « N20 », « a 6 » → « A6 ».
String? normalizeRoad(String? raw) {
  if (raw == null) return null;
  final s = raw.toUpperCase().replaceAll(RegExp(r'[\s\-_]'), '');
  if (s.isEmpty) return null;
  final m = RegExp(r'^([A-Z]+)0*(\d+)([A-Z]?)$').firstMatch(s);
  if (m == null) return s;
  return '${m.group(1)}${m.group(2)}${m.group(3)}';
}

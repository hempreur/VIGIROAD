import 'package:vigiroad_traffic/vigiroad_traffic.dart';

/// Mention d'une source, à afficher avec sa date de mise à jour.
class TrafficAttribution {
  const TrafficAttribution({required this.source, required this.text, this.url, this.updatedAt});

  factory TrafficAttribution.fromJson(Map<String, dynamic> j) => TrafficAttribution(
    source: j['source'] as String,
    text: j['text'] as String,
    url: j['url'] as String?,
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
  );

  final String source;
  final String text;
  final String? url;
  final DateTime? updatedAt;
}

/// Réponse du serveur de trafic pour une zone ou un itinéraire.
class TrafficSnapshot {
  const TrafficSnapshot({
    required this.events,
    required this.known,
    required this.attributions,
    required this.receivedAt,
    this.updatedAt,
    this.coverageNotes = const [],
  });

  /// Réponse JSON de `/v1/events` ou `/v1/events/route`.
  factory TrafficSnapshot.fromJson(Map<String, dynamic> j, {required DateTime receivedAt}) {
    final area = j['area'] as Map<String, dynamic>? ?? const {};
    return TrafficSnapshot(
      events: [
        for (final e in j['events'] as List<dynamic>? ?? const [])
          TrafficEvent.fromJson(e as Map<String, dynamic>),
      ],
      // Ancien serveur sans `area` : jamais présumé connu.
      known: area['known'] == true,
      updatedAt: DateTime.tryParse(area['updatedAt'] as String? ?? ''),
      coverageNotes: [
        for (final s in area['sources'] as List<dynamic>? ?? const [])
          if ((s as Map<String, dynamic>)['coverage'] case final String note) note,
      ],
      attributions: [
        for (final a in j['attributions'] as List<dynamic>? ?? const [])
          TrafficAttribution.fromJson(a as Map<String, dynamic>),
      ],
      receivedAt: receivedAt,
    );
  }

  final List<TrafficEvent> events;

  /// Une source à jour couvre la zone. Faux : état **inconnu** (et non
  /// « fluide ») — aucune circulation n'est jamais supposée.
  final bool known;

  /// Collecte la plus ancienne parmi les sources couvrant la zone.
  final DateTime? updatedAt;

  /// Réseau couvert (« réseau routier national non concédé »…).
  final List<String> coverageNotes;
  final List<TrafficAttribution> attributions;

  /// Réception par l'application (au-delà d'un délai, l'état redevient inconnu).
  final DateTime receivedAt;
}

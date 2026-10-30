import 'package:http/http.dart' as http;
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

/// Description d'une source : droits, contraintes et fréquence autorisée.
///
/// Chaque connecteur déclare ces informations, vérifiées avant intégration
/// (voir server/SOURCES.md). L'agrégateur ne l'interroge jamais plus souvent
/// que [minInterval].
class SourceInfo {
  const SourceInfo({
    required this.id,
    required this.name,
    required this.countries,
    required this.licence,
    required this.attribution,
    required this.minInterval,
    required this.homepage,
    this.areas = const [],
    this.coverageNote,
    this.requiresKey = false,
    this.verified = false,
  });

  /// Identifiant court et stable (`fr-bison-fute`, `gb-tfl`…).
  final String id;
  final String name;
  final List<String> countries;
  final String licence;

  /// Mention à afficher dans l'application (exigée par la licence).
  final String attribution;

  /// Intervalle minimal entre deux interrogations (fréquence autorisée).
  final Duration minInterval;
  final String homepage;

  /// Emprise couverte par la source. Hors de ces zones, l'état du trafic est
  /// inconnu. Une source sans emprise ne rend aucune zone « connue ».
  final List<BBox> areas;

  /// Réseau effectivement couvert (affiché avec la mention).
  final String? coverageNote;
  final bool requiresKey;

  /// Format confirmé sur le flux réel (et non seulement sur la documentation).
  final bool verified;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'countries': countries,
    'licence': licence,
    'attribution': attribution,
    'minIntervalSeconds': minInterval.inSeconds,
    'homepage': homepage,
    'areas': [for (final a in areas) a.toJson()],
    'coverageNote': coverageNote,
    'verified': verified,
  };
}

/// Erreur d'une source (réseau, format…), sans arrêter les autres.
class SourceException implements Exception {
  const SourceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Connecteur vers un fournisseur : lit son flux et le convertit vers le
/// modèle unique [TrafficEvent].
abstract class TrafficConnector {
  SourceInfo get info;

  Future<List<TrafficEvent>> fetch(http.Client client, DateTime now);

  /// Lecture HTTP commune : délai, User-Agent, code de retour.
  Future<String> getText(http.Client client, Uri uri, {Map<String, String> headers = const {}}) async {
    final http.Response res;
    try {
      res = await client
          .get(uri, headers: {'User-Agent': 'VigiRoadTrafficAggregator/1.0', ...headers})
          .timeout(const Duration(seconds: 30));
    } on Exception catch (e) {
      throw SourceException('${info.id} : réseau indisponible ($e)');
    }
    if (res.statusCode == 429) throw SourceException('${info.id} : fréquence limite dépassée (429)');
    if (res.statusCode != 200) throw SourceException('${info.id} : HTTP ${res.statusCode}');
    return res.body;
  }
}

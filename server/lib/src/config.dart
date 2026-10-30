import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import 'aggregator.dart';
import 'connectors/datex2.dart';
import 'connectors/tfl.dart';
import 'connectors/us511.dart';
import 'connectors/waze_partner.dart';
import 'connectors/wzdx.dart';
import 'source.dart';

/// Configuration par variables d'environnement (aucun secret dans le code).
class ServerConfig {
  ServerConfig(this.env);

  final Map<String, String> env;

  int get port => int.tryParse(env['PORT'] ?? '') ?? 8080;

  /// Clés autorisées à interroger l'API (séparées par des virgules).
  Set<String> get apiKeys => {
    for (final k in (env['VR_API_KEYS'] ?? '').split(',')) if (k.trim().length >= 16) k.trim(),
  };

  Set<String> get disabled => {for (final s in (env['VR_DISABLE_SOURCES'] ?? '').split(',')) if (s.trim().isNotEmpty) s.trim()};

  String? _key(String name) {
    final v = env[name]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  /// Sources actives : celles sans clé, plus celles dont la clé est fournie.
  /// Les points d'accès nationaux supplémentaires (NAPCORE) s'ajoutent via
  /// `VR_DATEX2_FEEDS` sans modifier le code.
  List<SourceChain> chains() {
    final out = <SourceChain>[
      SourceChain(
        Datex2Connector.bisonFute(),
        // Secours : même publication via le point d'accès national.
        Datex2Connector(
          country: 'FR',
          url: Uri.parse('https://transport.data.gouv.fr/resources/79173/download'),
          info: const SourceInfo(
            id: 'fr-pan-transport-data-gouv',
            name: 'Point d\'accès national transport.data.gouv.fr (secours Bison Futé)',
            countries: ['FR'],
            licence: 'Licence Ouverte 2.0',
            attribution: 'Information fournie par Bison Futé — transport.data.gouv.fr',
            minInterval: Duration(minutes: 5),
            homepage: 'https://transport.data.gouv.fr/datasets/evenements-routiers-sur-le-reseau-routier-national-non-concede',
            areas: [BBox(-5.3, 41.3, 9.7, 51.2)],
            coverageNote: 'réseau routier national non concédé (hors autoroutes concédées et routes locales)',
          ),
        ),
      ),
      if (_key('VR_TFL_APP_KEY') case final k?) SourceChain(TflConnector(k)),
      if (_key('VR_511_SFBAY_KEY') case final k?) SourceChain(WzdxConnector.sfBay(k)),
      if (_key('VR_AZ511_KEY') case final k?) SourceChain(Us511V2Connector.arizona(k)),
      if (_key('VR_WAZE_FEED_URL') case final u?)
        SourceChain(WazePartnerConnector(Uri.parse(u), areas: [?BBox.tryParse(_key('VR_WAZE_BBOX'))])),
      ...datex2Feeds(),
    ];
    return [for (final c in out) if (!disabled.contains(c.primary.info.id)) c];
  }

  /// `VR_DATEX2_FEEDS` = `id|PAYS|url|mention|licence|minLng,minLat,maxLng,maxLat;…`
  /// (DATEX II 2.x). Sans emprise, la source alimente la carte mais ne rend
  /// aucune zone « connue ».
  List<SourceChain> datex2Feeds() => [
    for (final entry in (env['VR_DATEX2_FEEDS'] ?? '').split(';'))
      if (entry.split('|') case [final id, final country, final url, final attribution, final licence, ...final rest]
          when rest.length <= 1)
        SourceChain(
          Datex2Connector(
            country: country.trim().toUpperCase(),
            url: Uri.parse(url.trim()),
            info: SourceInfo(
              id: id.trim(),
              name: 'Point d\'accès national ${country.trim().toUpperCase()} (DATEX II)',
              countries: [country.trim().toUpperCase()],
              licence: licence.trim(),
              attribution: attribution.trim(),
              minInterval: const Duration(minutes: 5),
              homepage: url.trim(),
              areas: [if (rest.isNotEmpty) ?BBox.tryParse(rest.first.trim())],
            ),
          ),
        ),
  ];
}

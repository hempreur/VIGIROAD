/// Environnement d'exécution, fixé à la compilation.
enum AppEnvironment { dev, test, prod }

/// Configuration de l'application, injectée à la compilation par
/// `--dart-define-from-file=config/<env>.env` (voir `.env.example`).
///
/// Aucune clé secrète n'est nécessaire avec la pile cartographique actuelle
/// (MapLibre + OpenStreetMap). Les URL sont configurables pour pouvoir
/// pointer vers des serveurs auto-hébergés en production.
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.mapStyleUrl,
    required this.routingBaseUrl,
    required this.geocodingBaseUrl,
    required this.platesSyncUrl,
    required this.userAgent,
    this.trafficApiUrl = '',
    this.trafficApiKey = '',
  });

  /// Lit les valeurs `--dart-define`. Les valeurs par défaut pointent vers des
  /// services publics adaptés au développement — voir `docs/API_CONFIG.md`
  /// pour leurs conditions d'utilisation.
  factory AppConfig.fromEnvironment() {
    const env = String.fromEnvironment('VR_ENV', defaultValue: 'dev');
    return AppConfig(
      environment: AppEnvironment.values.firstWhere(
        (e) => e.name == env,
        orElse: () => AppEnvironment.dev,
      ),
      mapStyleUrl: const String.fromEnvironment(
        'VR_MAP_STYLE_URL',
        defaultValue:
            'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json',
      ),
      routingBaseUrl: const String.fromEnvironment(
        'VR_ROUTING_URL',
        defaultValue: 'https://router.project-osrm.org',
      ),
      geocodingBaseUrl: const String.fromEnvironment(
        'VR_GEOCODING_URL',
        defaultValue: 'https://photon.komoot.io',
      ),
      platesSyncUrl: const String.fromEnvironment('VR_PLATES_SYNC_URL'),
      userAgent: const String.fromEnvironment(
        'VR_USER_AGENT',
        defaultValue: 'VIGIROAD/1.0 (+https://github.com/hempreur/VIGIROAD)',
      ),
      trafficApiUrl: const String.fromEnvironment('VR_TRAFFIC_API_URL'),
      trafficApiKey: const String.fromEnvironment('VR_TRAFFIC_API_KEY'),
    );
  }

  final AppEnvironment environment;
  final String mapStyleUrl;
  final String routingBaseUrl;
  final String geocodingBaseUrl;

  /// Source distante optionnelle de la liste de plaques (vide = désactivée).
  final String platesSyncUrl;

  /// User-Agent identifiant l'application auprès des services OSM
  /// (exigé par leurs politiques d'utilisation).
  final String userAgent;

  /// Serveur VigiRoadTrafficAggregator (vide = trafic désactivé, affiché
  /// comme « source non configurée »).
  final String trafficApiUrl;

  /// Clé d'accès au serveur de trafic. Elle limite l'accès au service mais,
  /// embarquée dans l'application, n'est pas un secret : les clés des
  /// fournisseurs (TfL, 511…) restent sur le serveur.
  final String trafficApiKey;

  bool get trafficEnabled => trafficApiUrl.isNotEmpty && trafficApiKey.isNotEmpty;

  bool get isProduction => environment == AppEnvironment.prod;
  bool get platesSyncEnabled => platesSyncUrl.isNotEmpty;
}

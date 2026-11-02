import 'dart:convert';

/// Configuration par variables d'environnement (secrets dans .env, jamais
/// dans le dépôt).
class AdminConfig {
  AdminConfig(this.env);

  final Map<String, String> env;

  String? _v(String name) {
    final v = env[name]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  int get port => int.tryParse(_v('PORT') ?? '') ?? 8081;

  String get dbHost => _v('VR_DB_HOST') ?? 'postgres';
  int get dbPort => int.tryParse(_v('VR_DB_PORT') ?? '') ?? 5432;
  String get dbName => _v('VR_DB_NAME') ?? 'vigiroad';
  String get dbUser => _v('VR_DB_USER') ?? 'vigiroad';
  String get dbPassword => _v('VR_DB_PASSWORD') ?? '';

  /// Dossier des migrations SQL (server/database/migrations).
  String get migrationsDir => _v('VR_MIGRATIONS_DIR') ?? '/app/database/migrations';

  /// Clés de l'application mobile (mêmes que le serveur de trafic) : exigées
  /// pour créer un compte ou se connecter.
  Set<String> get appKeys => {
    for (final k in (_v('VR_API_KEYS') ?? '').split(',')) if (k.trim().length >= 16) k.trim(),
  };

  /// Clé maîtresse (64 caractères hexadécimaux) : chiffrement des secrets
  /// TOTP et empreintes des adresses.
  List<int> get masterKey {
    final hex = _v('VR_ADMIN_SECRET') ?? '';
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) {
      throw StateError('VR_ADMIN_SECRET : 64 caractères hexadécimaux attendus (openssl rand -hex 32)');
    }
    return [for (var i = 0; i < 64; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  }

  /// Jeton à usage unique permettant de créer le premier administrateur.
  String? get setupToken => _v('VR_ADMIN_SETUP_TOKEN');

  /// Agent de supervision (réseau Docker interne uniquement).
  Uri? get agentUrl => _v('VR_AGENT_URL') == null ? null : Uri.parse(_v('VR_AGENT_URL')!);
  String get agentToken => _v('VR_AGENT_TOKEN') ?? '';

  /// Serveur de trafic interne.
  Uri get trafficUrl => Uri.parse(_v('VR_TRAFFIC_URL') ?? 'http://traffic:8080');

  /// Adresse publique (contrôle du certificat HTTPS).
  String? get publicDomain => _v('VR_DOMAIN');

  /// Base de géolocalisation par adresse IP (DB-IP Lite, CC BY 4.0).
  String get geoIpFile => _v('VR_GEOIP_FILE') ?? '/geoip/dbip-country-lite.csv.gz';

  /// Coût Argon2id (réduit uniquement pour les tests).
  int get argonMemoryKb => int.tryParse(_v('VR_ARGON_MEMORY_KB') ?? '') ?? 19456;
  int get argonIterations => int.tryParse(_v('VR_ARGON_ITERATIONS') ?? '') ?? 2;

  /// Inscriptions autorisées par heure et par réseau (/24) ; relevé pour les
  /// tests de charge.
  int get registerLimitPerHour => int.tryParse(_v('VR_REGISTER_LIMIT') ?? '') ?? 10;

  /// Dépôt GitHub (vérification des mises à jour).
  String get githubRepo => _v('VR_GITHUB_REPO') ?? 'hempreur/VIGIROAD';

  /// Dossier des applications de bureau publiées (jamais sur GitHub).
  String get desktopDir => _v('VR_DESKTOP_DIR') ?? '/desktop';

  /// Jeton de la CI pour déposer les applications de bureau sur le VPS.
  String? get releaseToken {
    final t = _v('VR_RELEASE_TOKEN');
    return t != null && t.length >= 24 ? t : null;
  }

  /// Manifeste de l'application GPS publié avec chaque release (dernière version).
  String get mobileManifestUrl =>
      _v('VR_MOBILE_MANIFEST_URL') ?? 'https://github.com/$githubRepo/releases/latest/download/vigiroad-update.json';

  /// Désactive les collecteurs périodiques (tests).
  bool get backgroundJobs => _v('VR_BACKGROUND_JOBS') != 'off';

  @override
  String toString() => jsonEncode({'port': port, 'db': '$dbUser@$dbHost:$dbPort/$dbName', 'agent': agentUrl?.toString()});
}

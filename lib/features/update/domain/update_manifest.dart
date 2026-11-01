/// Fichier `vigiroad-update.json` publié avec chaque release par la CI.
class UpdateApk {
  const UpdateApk({required this.url, required this.sha256, required this.size});

  factory UpdateApk.fromJson(Map<String, dynamic> j) => UpdateApk(
    url: j['url'] as String,
    sha256: (j['sha256'] as String).toLowerCase(),
    size: (j['size'] as num).toInt(),
  );

  final String url;

  /// Empreinte vérifiée après téléchargement, avant toute installation.
  final String sha256;
  final int size;
}

class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.build,
    required this.minBuild,
    required this.notes,
    required this.apks,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> j) => UpdateManifest(
    version: j['version'] as String,
    build: (j['build'] as num).toInt(),
    minBuild: (j['minBuild'] as num?)?.toInt() ?? (j['build'] as num).toInt(),
    notes: [for (final n in j['notes'] as List<dynamic>? ?? const []) n as String],
    apks: {
      for (final MapEntry(:key, :value) in (j['apks'] as Map<String, dynamic>).entries)
        key: UpdateApk.fromJson(value as Map<String, dynamic>),
    },
  );

  /// Version affichée (« 1.3.0 ») et numéro de compilation (pubspec `+N`).
  final String version;
  final int build;

  /// Versions dont le numéro est inférieur : obsolètes, mise à jour obligatoire.
  final int minBuild;
  final List<String> notes;

  /// APK par architecture (`arm64-v8a`, `armeabi-v7a`).
  final Map<String, UpdateApk> apks;

  bool isNewerThan(int installedBuild) => build > installedBuild;
  bool isMandatoryFor(int installedBuild) => installedBuild < minBuild;

  /// APK de l'architecture principale du téléphone. Toujours la principale :
  /// Android refuserait une version au numéro inférieur (arm32 = 1000 + N,
  /// arm64 = 2000 + N).
  UpdateApk? apkFor(List<String> supportedAbis) {
    for (final abi in supportedAbis) {
      if (apks[abi] case final apk?) return apk;
    }
    return null;
  }
}

/// Version installée, d'après Android.
class InstalledApp {
  const InstalledApp({required this.versionName, required this.versionCode, required this.abis});

  final String versionName;

  /// Code de version Android : Flutter ajoute 1000 × code d'architecture
  /// (arm32 = 1, arm64 = 2) au numéro de compilation lors du découpage par ABI.
  final int versionCode;
  final List<String> abis;

  int get build => versionCode % 1000;
}

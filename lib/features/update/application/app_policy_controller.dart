import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import '../../../app/version.dart';
import '../../account/application/account_controller.dart';

/// Décision du serveur VIGIROAD sur la version installée.
enum PolicyStatus {
  /// Version acceptée (ou serveur jamais joint : rien n'est bloqué sans preuve).
  ok,

  /// Version antérieure à la dernière publiée : inutilisable, mise à jour obligatoire.
  outdated,

  /// Application bloquée à distance depuis ADMIN MANAGER.
  blocked,
}

class AppPolicyState {
  const AppPolicyState({this.status = PolicyStatus.ok, this.message, this.latestVersion, this.downloadUrl});

  final PolicyStatus status;
  final String? message;
  final String? latestVersion;

  /// Page de téléchargement (iPhone, ou Android sans fichier de mise à jour).
  final String? downloadUrl;

  bool get locked => status != PolicyStatus.ok;

  Map<String, Object?> toJson() => {
    'status': status.name,
    'message': message,
    'latest': latestVersion,
    'downloadUrl': downloadUrl,
    'build': appBuild,
  };

  static AppPolicyState? fromCache(Map<String, dynamic> j) {
    // Décision prise pour une autre version (l'application a été mise à
    // jour depuis) : sans valeur.
    if (j['build'] != appBuild) return null;
    final status = PolicyStatus.values.where((s) => s.name == j['status']).firstOrNull;
    if (status == null) return null;
    return AppPolicyState(
      status: status,
      message: j['message'] as String?,
      latestVersion: j['latest'] as String?,
      downloadUrl: j['downloadUrl'] as String?,
    );
  }
}

/// Mémoire de la dernière décision (hors connexion : une version déclarée
/// obsolète le reste).
abstract interface class PolicyCache {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, Object?> value);
}

class PrefsPolicyCache implements PolicyCache {
  static const _key = 'vr.app_policy';

  @override
  Future<Map<String, dynamic>?> read() async {
    final t = (await SharedPreferences.getInstance()).getString(_key);
    if (t == null) return null;
    try {
      return jsonDecode(t) as Map<String, dynamic>;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(Map<String, Object?> value) async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode(value));
}

final policyCacheProvider = Provider<PolicyCache>((ref) => PrefsPolicyCache());

/// Client HTTP du contrôle de version (remplacé dans les tests).
final policyHttpProvider = Provider<http.Client>((ref) => http.Client());

String get _platform => Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : Platform.operatingSystem);

final _versionHeaders = <String, String>{
  'X-App-Build': '$appBuild',
  'X-App-Version': appVersion,
  'X-App-Platform': _platform,
};

/// En-têtes envoyés au serveur VIGIROAD à chaque requête (même objet,
/// complété par l'identifiant d'installation dès qu'il est chargé).
Map<String, String> appVersionHeaders() => _versionHeaders;

/// Identifiant d'installation : aléatoire (aucun identifiant matériel),
/// créé au premier lancement, conservé lors des mises à jour. Il permet à
/// l'administrateur de bloquer un appareil précis ; effacé avec les données
/// de l'application.
abstract interface class InstallIdStore {
  Future<String> load();
}

class PrefsInstallIdStore implements InstallIdStore {
  static const _key = 'vr.install_id';

  @override
  Future<String> load() async {
    final p = await SharedPreferences.getInstance();
    final existing = p.getString(_key);
    if (existing != null && RegExp(r'^[0-9a-f]{32}$').hasMatch(existing)) return existing;
    final r = Random.secure();
    final id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await p.setString(_key, id);
    return id;
  }
}

final installIdStoreProvider = Provider<InstallIdStore>((ref) => PrefsInstallIdStore());

final appPolicyProvider = NotifierProvider<AppPolicyController, AppPolicyState>(AppPolicyController.new);

/// Contrôle de version auprès du serveur VIGIROAD : au démarrage, au retour
/// dans l'application et toutes les 30 minutes. Une version obsolète ou
/// bloquée à distance devient inutilisable : seul l'écran de mise à jour
/// reste accessible.
class AppPolicyController extends Notifier<AppPolicyState> {
  static const checkEvery = Duration(minutes: 30);

  Timer? _timer;
  bool _checking = false;
  String? _install;
  DateTime? _lastCheck;

  @override
  AppPolicyState build() {
    final config = ref.watch(appConfigProvider);
    if (!config.trafficEnabled) return const AppPolicyState();
    final lifecycle = AppLifecycleListener(onResume: () => unawaited(check()));
    _timer = Timer.periodic(checkEvery, (_) => unawaited(check()));
    ref.onDispose(() {
      _timer?.cancel();
      lifecycle.dispose();
    });
    unawaited(Future.microtask(() async {
      try {
        _install = await ref.read(installIdStoreProvider).load();
        _versionHeaders['X-App-Install'] = _install!;
      } on Object {
        // Sans stockage : pas de blocage par appareil possible.
      }
      await check();
    }));
    return const AppPolicyState();
  }

  Future<void> check() async {
    if (_checking || !ref.mounted) return;
    final config = ref.read(appConfigProvider);
    if (!config.trafficEnabled) return;
    _checking = true;
    _lastCheck = DateTime.now();
    var answered = false;
    try {
      final info = await ref.read(deviceInfoProvider).info().catchError((Object _) => <String, String?>{});
      final base = config.trafficApiUrl.endsWith('/')
          ? config.trafficApiUrl.substring(0, config.trafficApiUrl.length - 1)
          : config.trafficApiUrl;
      final res = await ref
          .read(policyHttpProvider)
          .post(
            Uri.parse('$base/v1/app/status'),
            headers: {
              'X-Api-Key': config.trafficApiKey,
              'User-Agent': config.userAgent,
              'Content-Type': 'application/json',
              ...appVersionHeaders(),
            },
            body: jsonEncode({
              'install': ?_install,
              'platform': _platform,
              'version': appVersion,
              'build': appBuild,
              'model': [info['brand'], info['model']].whereType<String>().join(' ').trim(),
              'os': [info['os'], info['osVersion']].whereType<String>().join(' ').trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw HttpException('statut ${res.statusCode}');
      if (!ref.mounted) return;
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      answered = true;
      final next = AppPolicyState(
        status: switch (j['status']) {
          'blocked' => PolicyStatus.blocked,
          'update_required' => PolicyStatus.outdated,
          _ => PolicyStatus.ok,
        },
        message: j['message'] as String?,
        latestVersion: (j['latest'] as Map<String, dynamic>?)?['version'] as String?,
        downloadUrl: j['downloadUrl'] as String?,
      );
      await _apply(next);
    } on Object {
      // Réponse illisible : traitée comme une absence de réponse.
    } finally {
      _checking = false;
    }
    // Serveur injoignable : la dernière décision connue reste en vigueur
    // (jamais affichée avant la réponse du serveur : pas de clignotement).
    if (!answered && ref.mounted && state.status == PolicyStatus.ok) {
      final cached = await ref.read(policyCacheProvider).read().catchError((Object _) => null);
      final c = cached == null ? null : AppPolicyState.fromCache(cached);
      if (c != null && ref.mounted) state = c;
    }
  }

  /// Refus 426 reçu d'un autre service (trafic, signalements) : on
  /// demande la décision au serveur, seule source de vérité (le serveur de
  /// trafic peut garder quelques secondes une règle déjà levée).
  Future<void> rejected({required bool blocked, String? message}) async {
    final last = _lastCheck;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 20)) return;
    await check();
  }

  Future<void> _apply(AppPolicyState next) async {
    if (!ref.mounted) return;
    state = next;
    try {
      await ref.read(policyCacheProvider).write(next.toJson());
    } on Object {
      // Mémoire indisponible : la décision vaut pour cette session.
    }
  }

  /// Ouvre la page de téléchargement de la dernière version.
  Future<void> openDownloadPage() async {
    final url = state.downloadUrl ?? 'https://github.com/hempreur/VIGIROAD/releases/latest';
    try {
      await const MethodChannel('fr.vigiroad/updater').invokeMethod<bool>('openUrl', {'url': url});
    } on Object {
      // Pas de navigateur : l'adresse reste affichée à l'écran.
    }
  }
}

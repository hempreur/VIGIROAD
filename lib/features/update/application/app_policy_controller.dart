import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

/// En-têtes envoyés au serveur VIGIROAD à chaque requête.
Map<String, String> appVersionHeaders() => {
  'X-App-Build': '$appBuild',
  'X-App-Version': appVersion,
  'X-App-Platform': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : Platform.operatingSystem),
};

final appPolicyProvider = NotifierProvider<AppPolicyController, AppPolicyState>(AppPolicyController.new);

/// Contrôle de version auprès du serveur VIGIROAD : au démarrage, au retour
/// dans l'application et toutes les 30 minutes. Une version obsolète ou
/// bloquée à distance devient inutilisable : seul l'écran de mise à jour
/// reste accessible.
class AppPolicyController extends Notifier<AppPolicyState> {
  static const checkEvery = Duration(minutes: 30);

  Timer? _timer;
  bool _checking = false;

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
      final cached = await ref.read(policyCacheProvider).read();
      final c = cached == null ? null : AppPolicyState.fromCache(cached);
      if (c != null && ref.mounted && state.status == PolicyStatus.ok) state = c;
      await check();
    }));
    return const AppPolicyState();
  }

  Future<void> check() async {
    if (_checking || !ref.mounted) return;
    final config = ref.read(appConfigProvider);
    if (!config.trafficEnabled) return;
    _checking = true;
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
              'platform': appVersionHeaders()['X-App-Platform'],
              'version': appVersion,
              'build': appBuild,
              'model': [info['brand'], info['model']].whereType<String>().join(' ').trim(),
              'os': [info['os'], info['osVersion']].whereType<String>().join(' ').trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 || !ref.mounted) return;
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
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
      // Serveur injoignable : la dernière décision connue reste en vigueur.
    } finally {
      _checking = false;
    }
  }

  /// Refus 426 reçu d'un autre service (trafic, signalements).
  Future<void> rejected({required bool blocked, String? message}) async {
    if (!ref.mounted) return;
    await _apply(AppPolicyState(
      status: blocked ? PolicyStatus.blocked : PolicyStatus.outdated,
      message: message,
      latestVersion: state.latestVersion,
      downloadUrl: state.downloadUrl,
    ));
    unawaited(check());
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

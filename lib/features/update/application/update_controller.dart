import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/providers.dart';
import '../../navigation/application/navigation_session.dart';
import '../data/update_platform.dart';
import '../data/update_source.dart';
import '../domain/update_manifest.dart';

enum UpdateStatus {
  /// Aucune mise à jour connue (ou vérification impossible : l'application reste utilisable).
  none,

  /// Nouvelle version disponible : fenêtre affichée.
  available,

  /// L'utilisateur doit autoriser VIGIROAD à installer des applications.
  needsPermission,
  downloading,

  /// Confirmation d'Android affichée.
  installing,

  /// Échec (téléchargement, empreinte, installation refusée) : nouvel essai possible.
  failed,
}

class UpdateState {
  const UpdateState({
    this.status = UpdateStatus.none,
    this.manifest,
    this.installed,
    this.progress = 0,
    this.message,
  });

  final UpdateStatus status;
  final UpdateManifest? manifest;
  final InstalledApp? installed;
  final double progress;
  final String? message;

  bool get pending => status != UpdateStatus.none && manifest != null;
  bool get mandatory => manifest != null && installed != null && manifest!.isMandatoryFor(installed!.build);

  UpdateState copyWith({UpdateStatus? status, double? progress, String? message}) => UpdateState(
    status: status ?? this.status,
    manifest: manifest,
    installed: installed,
    progress: progress ?? this.progress,
    message: message,
  );
}

/// Android uniquement (l'application iOS installée hors App Store ne peut pas
/// se mettre à jour elle-même).
final updatePlatformProvider = Provider<UpdatePlatform?>(
  (ref) => Platform.isAndroid ? MethodChannelUpdatePlatform() : null,
);

final updateSourceProvider = Provider<UpdateSource?>((ref) {
  final c = ref.watch(appConfigProvider);
  if (c.updateManifestUrl.isEmpty) return null;
  return UpdateSource(manifestUrl: c.updateManifestUrl, userAgent: c.userAgent);
});

/// Dossier de téléchargement de l'APK (remplacé dans les tests).
final updateDownloadDirProvider = Provider<Future<Directory> Function()>((ref) => getTemporaryDirectory);

final updateProvider = NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

/// Mises à jour hors Play Store : vérification au démarrage puis toutes les
/// [checkEvery], fenêtre obligatoire, téléchargement vérifié, installation
/// confirmée par Android.
class UpdateController extends Notifier<UpdateState> {
  static const checkEvery = Duration(hours: 6);

  Timer? _timer;
  DateTime? _lastCheck;
  bool _checking = false;
  StreamSubscription<String>? _failures;

  @override
  UpdateState build() {
    final platform = ref.watch(updatePlatformProvider);
    final source = ref.watch(updateSourceProvider);
    if (platform == null || source == null) return const UpdateState();

    _failures = platform.installFailures.listen((m) {
      if (ref.mounted) state = state.copyWith(status: UpdateStatus.failed, message: 'Installation refusée : $m');
    });
    final lifecycle = AppLifecycleListener(onResume: _onResume);
    _timer = Timer.periodic(checkEvery, (_) => unawaited(check()));
    ref.onDispose(() {
      _timer?.cancel();
      lifecycle.dispose();
      unawaited(_failures?.cancel());
    });
    unawaited(Future.microtask(check));
    return const UpdateState();
  }

  DateTime _now() => ref.read(clockProvider)();

  /// Retour dans l'application : après le réglage « installer des
  /// applications », on reprend ; après une longue absence, on revérifie.
  void _onResume() {
    if (state.status == UpdateStatus.needsPermission) {
      unawaited(updateNow());
    } else if (state.status == UpdateStatus.installing) {
      // L'utilisateur a quitté la confirmation d'Android sans installer.
      state = state.copyWith(status: UpdateStatus.available);
    } else if (_lastCheck == null || _now().difference(_lastCheck!) >= checkEvery) {
      unawaited(check());
    }
  }

  Future<void> check() async {
    final platform = ref.read(updatePlatformProvider);
    final source = ref.read(updateSourceProvider);
    if (platform == null || source == null || _checking || state.pending) return;
    _checking = true;
    try {
      final installed = await platform.appInfo();
      final manifest = await source.manifest();
      _lastCheck = _now();
      if (!ref.mounted) return;
      if (manifest.isNewerThan(installed.build) && manifest.apkFor(installed.abis) != null) {
        state = UpdateState(status: UpdateStatus.available, manifest: manifest, installed: installed);
      }
    } on Object {
      // Hors connexion ou serveur indisponible : aucune version n'est
      // déclarée obsolète sans preuve, l'application reste utilisable.
    } finally {
      _checking = false;
    }
  }

  /// « Mettre à jour maintenant ».
  Future<void> updateNow() async {
    final platform = ref.read(updatePlatformProvider);
    final source = ref.read(updateSourceProvider);
    final manifest = state.manifest;
    final installed = state.installed;
    if (platform == null || source == null || manifest == null || installed == null) return;
    if (state.status == UpdateStatus.downloading || state.status == UpdateStatus.installing) return;

    if (!await platform.canInstall()) {
      state = state.copyWith(status: UpdateStatus.needsPermission);
      return;
    }
    final apk = manifest.apkFor(installed.abis)!;
    state = state.copyWith(status: UpdateStatus.downloading, progress: 0);
    try {
      final dir = await ref.read(updateDownloadDirProvider)();
      final file = await source.download(
        apk,
        File('${dir.path}/vigiroad-${manifest.version}.apk'),
        onProgress: (p) {
          if (ref.mounted) state = state.copyWith(status: UpdateStatus.downloading, progress: p);
        },
      );
      if (!ref.mounted) return;
      state = state.copyWith(status: UpdateStatus.installing, progress: 1);
      await platform.install(file.path);
    } on UpdateException catch (e) {
      if (ref.mounted) state = state.copyWith(status: UpdateStatus.failed, message: e.message);
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(status: UpdateStatus.failed, message: 'Installation impossible : $e');
    }
  }

  Future<void> openInstallSettings() async => ref.read(updatePlatformProvider)?.openInstallSettings();
}

/// La fenêtre de mise à jour n'interrompt jamais un guidage en cours : elle
/// apparaît à l'arrivée ou à l'arrêt du guidage.
final updatePromptVisibleProvider = Provider<bool>((ref) {
  final u = ref.watch(updateProvider);
  // Sans écran de navigation ouvert, pas de guidage — et on ne démarre pas
  // la session (ni le GPS) juste pour le savoir.
  final guiding = ref.exists(navigationSessionProvider) &&
      ref.watch(navigationSessionProvider.select((s) => s.hasRoute));
  return u.pending && !guiding;
});

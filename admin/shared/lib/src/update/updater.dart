import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/client.dart';

/// Version publiée des applications d'administration.
class DesktopUpdate {
  const DesktopUpdate({required this.version, required this.notes, required this.url, required this.sha256, required this.kind});
  final String version;
  final List<String> notes;

  /// Chemin sur le serveur VIGIROAD (`/admin/desktop/files/…`, éventuellement
  /// avec un ticket de téléchargement).
  final String url;
  final String sha256;

  /// `windows-installer`, `appimage` ou `deb`.
  final String kind;
}

/// Mises à jour des applications de bureau, **jamais publiées sur GitHub** :
/// la CI les dépose sur le serveur VIGIROAD, qui ne les remet qu'à un
/// administrateur connecté (ou avec le ticket joint à un refus 426).
///
/// Vérification à la connexion puis toutes les [checkEvery] ; dès qu'une
/// version plus récente existe, elle est téléchargée, vérifiée (SHA-256) et
/// installée automatiquement, puis l'application redémarre.
class DesktopUpdater {
  DesktopUpdater({
    required this.appId,
    required this.currentVersion,
    this.autoInstall = true,
    this.checkEvery = const Duration(minutes: 15),
    Future<void> Function(File file, DesktopUpdate u)? installer,
  }) : _installer = installer;

  /// `admin-manager` (Windows) ou `server-control` (Linux).
  final String appId;
  final String currentVersion;

  /// Installation sans clic (désactivée dans les tests d'écran).
  final bool autoInstall;
  final Duration checkEvery;
  final Future<void> Function(File file, DesktopUpdate u)? _installer;

  /// Étiquette envoyée au serveur (`x-vigiroad-app`).
  String get appTag => '$appId/$currentVersion';

  final available = ValueNotifier<DesktopUpdate?>(null);

  /// Progression du téléchargement (null = inactif).
  final progress = ValueNotifier<double?>(null);

  /// Dernière erreur de mise à jour (affichée dans le bandeau).
  final error = ValueNotifier<String?>(null);

  AdminClient? _client;
  Timer? _timer;
  bool _installing = false;

  /// Serveur et session en cours (après connexion).
  void attach(AdminClient client) {
    _client = client;
    _timer?.cancel();
    _timer = Timer.periodic(checkEvery, (_) => unawaited(check()));
    unawaited(check());
  }

  /// Serveur connu sans session ouverte (refus 426 à la connexion).
  void prepare(AdminClient client) => _client = client;

  void detach() {
    _timer?.cancel();
    _timer = null;
  }

  static int compare(String a, String b) {
    List<int> p(String v) => [for (final x in v.split('+').first.split('.')) int.tryParse(x) ?? 0];
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d.sign;
    }
    return 0;
  }

  static String get platformKind => Platform.isWindows
      ? 'windows-installer'
      : (Platform.environment['APPIMAGE'] != null ? 'appimage' : 'deb');

  /// Choix du fichier dans le manifeste déposé sur le serveur.
  DesktopUpdate? pick(Map<String, dynamic> manifest, {String? kind}) {
    final app = manifest[appId] as Map<String, dynamic>?;
    if (app == null) return null;
    return _fromEntry(app, kind: kind, onlyNewer: true);
  }

  DesktopUpdate? _fromEntry(Map<String, dynamic> app, {String? kind, required bool onlyNewer}) {
    final version = app['version'] as String? ?? '0.0.0';
    if (onlyNewer && compare(version, currentVersion) <= 0) return null;
    final notes = ((app['notes'] as List<dynamic>?) ?? const []).cast<String>();
    final files = (app['files'] as Map<String, dynamic>?) ?? const {};
    final k = kind ?? platformKind;
    final f = files[k] as Map<String, dynamic>?;
    if (f == null) return null;
    final url = f['url'] as String? ?? '/admin/desktop/files/${f['name']}';
    return DesktopUpdate(version: version, notes: notes, url: url, sha256: f['sha256'] as String, kind: k);
  }

  /// Interroge le serveur ; installe aussitôt une version plus récente.
  Future<void> check() async {
    final c = _client;
    if (c == null) return;
    try {
      final m = await c.get('/admin/desktop/manifest');
      final u = pick(m);
      available.value = u;
      if (u != null && autoInstall) unawaited(_auto(u));
    } on ApiException {
      // Aucune version déposée sur ce serveur, ou hors connexion.
    }
  }

  /// Version refusée par le serveur (426) : la mise à jour jointe est
  /// installée immédiatement.
  Future<void> installRequired(Map<String, dynamic> update) async {
    final u = _fromEntry(update, onlyNewer: false);
    if (u == null) return;
    available.value = u;
    if (autoInstall) await _auto(u);
  }

  Future<void> _auto(DesktopUpdate u) async {
    try {
      await install(u);
    } on Object catch (e) {
      error.value = '$e';
    }
  }

  /// Télécharge, vérifie l'empreinte, puis installe et redémarre.
  Future<void> install(DesktopUpdate u) async {
    final c = _client;
    if (c == null) throw StateError('Serveur VIGIROAD inconnu');
    if (_installing) return;
    _installing = true;
    error.value = null;
    progress.value = 0;
    try {
      final dir = await getTemporaryDirectory();
      final uri = c.resolve(u.url);
      final name = uri.pathSegments.last;
      final file = File('${dir.path}/$name');
      final req = http.Request('GET', uri);
      if (c.token != null && !u.url.contains('ticket=')) req.headers['authorization'] = 'Bearer ${c.token}';
      final tag = c.appTag;
      if (tag != null) req.headers['x-vigiroad-app'] = tag;
      final res = await c.httpClient.send(req);
      if (res.statusCode != 200) {
        await res.stream.drain<void>();
        throw Exception('Téléchargement de la mise à jour impossible (HTTP ${res.statusCode})');
      }
      final total = res.contentLength ?? 0;
      final sink = file.openWrite();
      final digest = AccumulatorSink<Digest>();
      final hasher = sha256.startChunkedConversion(digest);
      var got = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        got += chunk.length;
        if (total > 0) progress.value = got / total;
      }
      hasher.close();
      await sink.close();
      if (digest.events.single.toString() != u.sha256.toLowerCase()) {
        await file.delete();
        throw Exception('Fichier téléchargé altéré (empreinte SHA-256 différente) : installation annulée');
      }
      await (_installer ?? _install)(file, u);
    } finally {
      progress.value = null;
      _installing = false;
    }
  }

  static Future<void> _install(File file, DesktopUpdate u) async {
    switch (u.kind) {
      case 'windows-installer':
        // L'installateur relance l'application à la fin (section [Run]).
        await Process.start(file.path, ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/RELAUNCH=1'],
            mode: ProcessStartMode.detached);
        exit(0);
      case 'appimage':
        final target = Platform.environment['APPIMAGE']!;
        await Process.run('chmod', ['+x', file.path]);
        await file.copy('$target.new');
        await Process.run('chmod', ['+x', '$target.new']);
        await File('$target.new').rename(target);
        await Process.start(target, const [], mode: ProcessStartMode.detached);
        exit(0);
      default:
        final r = await Process.run('pkexec', ['apt-get', 'install', '-y', file.path]);
        if (r.exitCode != 0) {
          throw Exception('Installez la mise à jour dans un terminal : sudo apt install ${file.path}');
        }
        await Process.start(Platform.resolvedExecutable, const [], mode: ProcessStartMode.detached);
        exit(0);
    }
  }
}

/// Collecteur du condensé SHA-256 calculé par blocs.
class AccumulatorSink<T> implements Sink<T> {
  final events = <T>[];
  @override
  void add(T event) => events.add(event);
  @override
  void close() {}
}

/// Conversion utilitaire (tests).
Map<String, dynamic> decodeManifest(String text) => jsonDecode(text) as Map<String, dynamic>;

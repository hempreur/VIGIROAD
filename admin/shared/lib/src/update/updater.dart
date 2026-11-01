import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Version publiée des applications d'administration.
class DesktopUpdate {
  const DesktopUpdate({required this.version, required this.notes, required this.url, required this.sha256, required this.kind});
  final String version;
  final List<String> notes;
  final String url;
  final String sha256;

  /// `windows-installer`, `appimage` ou `deb`.
  final String kind;
}

/// Mises à jour des applications de bureau : manifeste publié avec chaque
/// version sur GitHub, téléchargement vérifié (SHA-256), puis installateur
/// Windows, remplacement de l'AppImage ou paquet .deb.
class DesktopUpdater {
  DesktopUpdater({
    required this.appId,
    required this.currentVersion,
    this.manifestUrl = 'https://github.com/hempreur/VIGIROAD/releases/latest/download/vigiroad-admin-update.json',
    http.Client? client,
  }) : _http = client ?? http.Client();

  /// `admin-manager` (Windows) ou `server-control` (Linux).
  final String appId;
  final String currentVersion;
  final String manifestUrl;
  final http.Client _http;

  final available = ValueNotifier<DesktopUpdate?>(null);

  /// Progression du téléchargement (null = inactif).
  final progress = ValueNotifier<double?>(null);

  static int compare(String a, String b) {
    List<int> p(String v) => [for (final x in v.split('+').first.split('.')) int.tryParse(x) ?? 0];
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d.sign;
    }
    return 0;
  }

  /// Choix du fichier selon le système et le mode d'installation.
  DesktopUpdate? pick(Map<String, dynamic> manifest) {
    final app = manifest[appId] as Map<String, dynamic>?;
    if (app == null) return null;
    final version = app['version'] as String? ?? '0.0.0';
    if (compare(version, currentVersion) <= 0) return null;
    final notes = ((app['notes'] as List<dynamic>?) ?? const []).cast<String>();
    final files = (app['files'] as Map<String, dynamic>?) ?? const {};
    final kind = Platform.isWindows
        ? 'windows-installer'
        : (Platform.environment['APPIMAGE'] != null ? 'appimage' : 'deb');
    final f = files[kind] as Map<String, dynamic>?;
    if (f == null) return null;
    return DesktopUpdate(version: version, notes: notes, url: f['url'] as String, sha256: f['sha256'] as String, kind: kind);
  }

  Future<void> check() async {
    try {
      final r = await _http
          .get(Uri.parse(manifestUrl).replace(queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'}))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return;
      available.value = pick(jsonDecode(r.body) as Map<String, dynamic>);
    } catch (_) {
      // Hors connexion : pas de mise à jour proposée.
    }
  }

  /// Télécharge, vérifie l'empreinte, puis installe et redémarre.
  Future<void> install(DesktopUpdate u) async {
    progress.value = 0;
    try {
      final dir = await getTemporaryDirectory();
      final name = Uri.parse(u.url).pathSegments.last;
      final file = File('${dir.path}/$name');
      final res = await _http.send(http.Request('GET', Uri.parse(u.url)));
      if (res.statusCode != 200) throw Exception('Téléchargement impossible (HTTP ${res.statusCode})');
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
      switch (u.kind) {
        case 'windows-installer':
          await Process.start(file.path, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
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
    } finally {
      progress.value = null;
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

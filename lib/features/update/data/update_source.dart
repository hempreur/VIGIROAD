import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../domain/update_manifest.dart';

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lecture du fichier de version et téléchargement vérifié de l'APK.
class UpdateSource {
  UpdateSource({required this.manifestUrl, required this.userAgent, http.Client? client})
    : _client = client ?? http.Client();

  final String manifestUrl;
  final String userAgent;
  final http.Client _client;

  Future<UpdateManifest> manifest() async {
    final http.Response res;
    try {
      // Paramètre anti-cache : la dernière release doit être vue tout de suite.
      final uri = Uri.parse(manifestUrl).replace(
        queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch ~/ 60000}'},
      );
      res = await _client.get(uri, headers: {'User-Agent': userAgent}).timeout(const Duration(seconds: 20));
    } on Exception {
      throw const UpdateException('Vérification des mises à jour impossible (réseau)');
    }
    if (res.statusCode != 200) throw UpdateException('Vérification des mises à jour : HTTP ${res.statusCode}');
    try {
      return UpdateManifest.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
    } on Object {
      throw const UpdateException('Fichier de mise à jour illisible');
    }
  }

  /// Télécharge l'APK dans [dest] ; [onProgress] reçoit 0–1. L'empreinte
  /// SHA-256 est vérifiée : un fichier altéré ou incomplet est supprimé.
  Future<File> download(UpdateApk apk, File dest, {void Function(double progress)? onProgress}) async {
    final http.StreamedResponse res;
    try {
      res = await _client
          .send(http.Request('GET', Uri.parse(apk.url))..headers['User-Agent'] = userAgent)
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw const UpdateException('Téléchargement impossible : vérifiez la connexion');
    }
    if (res.statusCode != 200) throw UpdateException('Téléchargement : HTTP ${res.statusCode}');
    final total = res.contentLength ?? apk.size;
    final sink = dest.openWrite();
    final hasher = AccumulatorSink<Digest>();
    final hash = sha256.startChunkedConversion(hasher);
    var received = 0;
    try {
      await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
        sink.add(chunk);
        hash.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
    } on Exception {
      await sink.close();
      if (await dest.exists()) await dest.delete();
      throw const UpdateException('Téléchargement interrompu : vérifiez la connexion');
    }
    await sink.close();
    hash.close();
    final digest = hasher.events.single.toString();
    if (digest != apk.sha256 || (apk.size > 0 && received != apk.size)) {
      await dest.delete();
      throw const UpdateException('Fichier téléchargé invalide (empreinte différente) : nouvel essai nécessaire');
    }
    return dest;
  }
}

/// Récepteur minimal pour le hachage par morceaux.
class AccumulatorSink<T> implements Sink<T> {
  final events = <T>[];
  @override
  void add(T event) => events.add(event);
  @override
  void close() {}
}

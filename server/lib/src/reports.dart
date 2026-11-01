import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:vigiroad_traffic/vigiroad_traffic.dart';

/// Refus d'un signalement.
class ReportRejected implements Exception {
  const ReportRejected(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Signalements « Chicken » des conducteurs : visibles 2 h par tous ceux
/// qui circulent à proximité.
///
/// - Un signalement au même endroit (moins de [mergeRadiusM]) et dans le
///   même sens qu'un signalement actif le confirme et prolonge son affichage
///   de 2 h, au lieu d'empiler les marqueurs.
/// - Anti-abus : un signalement par minute et douze par heure au plus pour
///   une même connexion. La clé de connexion n'est gardée qu'en mémoire,
///   sous forme d'empreinte, jamais écrite sur disque.
/// - Seuls la position, le sens et les dates sont conservés ; fichier
///   [file] réécrit à chaque changement (le serveur peut redémarrer sans
///   perdre les signalements en cours).
class ReportStore {
  ReportStore({
    DateTime Function()? clock,
    this.file,
    this.mergeRadiusM = 200,
    this.maxActive = 5000,
    this.minGap = const Duration(seconds: 60),
    this.maxPerHour = 12,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final File? file;
  final double mergeRadiusM;
  final int maxActive;
  final Duration minGap;
  final int maxPerHour;

  final _reports = <String, ChickenReport>{};
  final _clients = <int, List<DateTime>>{};
  final _salt = math.Random.secure().nextInt(1 << 32);
  final _rand = math.Random.secure();
  Future<void> _writing = Future.value();

  int get activeCount => active().length;

  /// Charge les signalements encore actifs.
  Future<void> load() async {
    final f = file;
    if (f == null || !await f.exists()) return;
    try {
      final raw = jsonDecode(await f.readAsString());
      final now = _clock();
      for (final j in (raw as Map<String, dynamic>)['reports'] as List<dynamic>) {
        final r = ChickenReport.fromJson(j as Map<String, dynamic>);
        if (r.activeAt(now)) _reports[r.id] = r;
      }
    } on Object catch (e) {
      stderr.writeln('Signalements : fichier illisible, ignoré ($e)');
    }
  }

  List<ChickenReport> active() {
    final now = _clock();
    _reports.removeWhere((_, r) => !r.activeAt(now));
    return _reports.values.toList();
  }

  List<ChickenReport> inBox(BBox box) => [for (final r in active()) if (box.contains(r.position)) r];

  /// Enregistre un signalement. [heading] est le cap du conducteur (null à
  /// l'arrêt) ; le sens concerné est l'opposé pour « route en face ».
  ChickenReport submit({required LatLng position, double? heading, required ReportSide side, required String client}) {
    if (position.lat.abs() > 90 || position.lng.abs() > 180 || (position.lat == 0 && position.lng == 0)) {
      throw const ReportRejected(400, 'Position invalide');
    }
    if (heading != null && (heading.isNaN || heading < 0 || heading >= 360)) {
      throw const ReportRejected(400, 'Cap invalide (0 à 360°)');
    }
    final now = _clock();
    _checkRate(client, now);

    final concerned = heading == null ? null : (side == ReportSide.opposite ? (heading + 180) % 360 : heading);
    final expires = now.add(ChickenReport.lifetime);
    for (final r in active()) {
      final sameDirection = r.heading == null || concerned == null || headingDelta(r.heading!, concerned) <= 45;
      if (sameDirection && haversine(r.position, position) <= mergeRadiusM) {
        final merged = r.copyWith(expiresAt: expires, confirmations: r.confirmations + 1);
        _reports[r.id] = merged;
        _persist();
        return merged;
      }
    }
    if (_reports.length >= maxActive) throw const ReportRejected(503, 'Trop de signalements en cours');
    final report = ChickenReport(
      id: _newId(),
      // Arrondi à ~1 m : inutile d'en garder davantage.
      position: LatLng(_round(position.lat, 5), _round(position.lng, 5)),
      heading: concerned,
      side: side,
      createdAt: now,
      expiresAt: expires,
    );
    _reports[report.id] = report;
    _persist();
    return report;
  }

  void _checkRate(String client, DateTime now) {
    final key = Object.hash(_salt, client);
    final times = _clients.putIfAbsent(key, () => [])..removeWhere((t) => now.difference(t) >= const Duration(hours: 1));
    if (times.isNotEmpty && now.difference(times.last) < minGap) {
      throw const ReportRejected(429, 'Un signalement par minute au plus');
    }
    if (times.length >= maxPerHour) throw const ReportRejected(429, 'Trop de signalements cette heure-ci');
    times.add(now);
    if (_clients.length > 50000) _clients.removeWhere((_, t) => t.isEmpty || now.difference(t.last) >= const Duration(hours: 1));
  }

  String _newId() => List.generate(12, (_) => _rand.nextInt(36).toRadixString(36)).join();

  static double _round(double v, int digits) {
    final f = math.pow(10, digits);
    return (v * f).round() / f;
  }

  void _persist() {
    final f = file;
    if (f == null) return;
    final body = jsonEncode({'reports': [for (final r in _reports.values) r.toJson()]});
    _writing = _writing.then((_) async {
      try {
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(body, flush: true);
        await tmp.rename(f.path);
      } on Object catch (e) {
        stderr.writeln('Signalements : écriture impossible ($e)');
      }
    });
  }

  /// Attend la fin des écritures (arrêt, tests).
  Future<void> flush() => _writing;
}

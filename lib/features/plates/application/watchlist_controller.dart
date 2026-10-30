import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../app/providers.dart';
import '../data/repositories.dart';
import '../data/vigiroad_database.dart';
import '../domain/watch_entry.dart';
import '../domain/watchlist_import.dart';

/// Base chiffrée, ouverte une fois.
final databaseProvider = FutureProvider<VigiroadDatabase>((ref) async {
  final db = await VigiroadDatabase.open();
  ref.onDispose(() => unawaited(db.close()));
  return db;
});

final watchlistRepositoryProvider = FutureProvider<WatchlistRepository>(
  (ref) async => SqlWatchlistRepository(await ref.watch(databaseProvider.future)),
);

final detectionLogProvider = FutureProvider<DetectionLog>(
  (ref) async => SqlDetectionLog(await ref.watch(databaseProvider.future)),
);

/// Résumé d'un import ou d'une synchronisation.
class ImportSummary {
  const ImportSummary({required this.added, required this.updated, required this.report});
  final int added;
  final int updated;
  final ImportReport report;
}

final watchlistProvider = AsyncNotifierProvider<WatchlistController, List<WatchEntry>>(WatchlistController.new);

/// Index de correspondance en mémoire : recherche O(1) pendant la lecture.
final watchlistIndexProvider = Provider<Map<String, WatchEntry>>((ref) {
  final list = ref.watch(watchlistProvider).value ?? const [];
  return {for (final e in list) e.plate: e};
});

class WatchlistController extends AsyncNotifier<List<WatchEntry>> {
  Future<WatchlistRepository> get _repo => ref.read(watchlistRepositoryProvider.future);

  @override
  Future<List<WatchEntry>> build() async => (await ref.watch(watchlistRepositoryProvider.future)).all();

  Future<void> _reload() async => state = AsyncData(await (await _repo).all());

  Future<void> save(WatchEntry entry, {String? replacing}) async {
    final repo = await _repo;
    if (replacing != null && replacing != entry.plate) await repo.delete(replacing);
    await repo.upsert(entry.copyWith(updatedAt: DateTime.now()));
    await _reload();
  }

  Future<void> remove(String plate) async {
    await (await _repo).delete(plate);
    await _reload();
  }

  Future<void> clear() async {
    await (await _repo).clear();
    await _reload();
  }

  /// Importe un fichier déjà analysé.
  Future<ImportSummary> importReport(ImportReport report, {ImportMode mode = ImportMode.merge}) async {
    final (added, updated) = await (await _repo).importAll(report.entries, mode: mode);
    await _reload();
    return ImportSummary(added: added, updated: updated, report: report);
  }

  /// Télécharge la liste distante configurée (VR_PLATES_SYNC_URL) et remplace
  /// les plaques issues d'une synchronisation précédente.
  Future<ImportSummary> sync({http.Client? client}) async {
    final config = ref.read(appConfigProvider);
    if (!config.platesSyncEnabled) {
      throw const ImportFormatException('Aucune source de synchronisation configurée.');
    }
    final uri = Uri.parse(config.platesSyncUrl);
    if (!uri.isScheme('https')) {
      throw const ImportFormatException('La source de synchronisation doit être en HTTPS.');
    }
    final c = client ?? http.Client();
    final http.Response res;
    try {
      res = await c.get(uri, headers: {'User-Agent': config.userAgent}).timeout(const Duration(seconds: 20));
    } on Exception {
      throw const ImportFormatException('Synchronisation impossible : vérifiez la connexion réseau.');
    }
    if (res.statusCode != 200) {
      throw ImportFormatException('La source de synchronisation a répondu ${res.statusCode}.');
    }
    final report = parseWatchlist(utf8.decode(res.bodyBytes), fileName: uri.path);
    final synced = ImportReport(
      entries: [for (final e in report.entries) e.copyWith(source: EntrySource.sync)],
      duplicates: report.duplicates,
      issues: report.issues,
    );
    return importReport(synced, mode: ImportMode.replaceSource);
  }
}

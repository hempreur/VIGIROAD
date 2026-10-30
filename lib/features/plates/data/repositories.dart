import 'package:sqflite_sqlcipher/sqflite.dart';

import '../domain/plate_models.dart';
import '../domain/watch_entry.dart';
import 'vigiroad_database.dart';

/// Correspondance enregistrée dans l'historique.
class DetectionRecord {
  const DetectionRecord({
    this.id,
    required this.plate,
    required this.display,
    required this.country,
    required this.category,
    required this.priority,
    required this.confidence,
    required this.at,
    this.latitude,
    this.longitude,
  });

  final int? id;
  final String plate;
  final String display;
  final String country;
  final String category;
  final WatchPriority priority;
  final double confidence;
  final DateTime at;
  final double? latitude;
  final double? longitude;
}

enum ImportMode {
  /// Ajoute et met à jour, conserve les autres plaques.
  merge,

  /// Remplace toutes les plaques de la même origine (import ou synchro).
  replaceSource,
}

abstract interface class WatchlistRepository {
  Future<List<WatchEntry>> all();
  Future<void> upsert(WatchEntry entry);
  Future<void> delete(String plate);

  /// Retourne (ajoutées, mises à jour).
  Future<(int, int)> importAll(List<WatchEntry> entries, {ImportMode mode = ImportMode.merge});
  Future<void> clear();
}

abstract interface class DetectionLog {
  Future<void> add(DetectionRecord r);
  Future<List<DetectionRecord>> recent({int limit = 500});
  Future<void> delete(int id);
  Future<int> purgeOlderThan(DateTime limit);
  Future<void> clear();
}

int _prio(WatchPriority p) => p.index;
WatchPriority _prioFrom(Object? v) => WatchPriority.values[(v as int).clamp(0, 2)];

class SqlWatchlistRepository implements WatchlistRepository {
  SqlWatchlistRepository(this._db);
  final VigiroadDatabase _db;
  Database get _d => _db.db;

  Map<String, Object?> _row(WatchEntry e) => {
    'plate': e.plate,
    'country': e.country,
    'category': e.category,
    'priority': _prio(e.priority),
    'note': e.note,
    'source': e.source.name,
    'updated_at': (e.updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
  };

  @override
  Future<List<WatchEntry>> all() async {
    final rows = await _d.query('watchlist', orderBy: 'priority DESC, plate ASC');
    return [
      for (final r in rows)
        WatchEntry(
          plate: r['plate']! as String,
          country: r['country']! as String,
          category: r['category']! as String,
          priority: _prioFrom(r['priority']),
          note: (r['note'] as String?) ?? '',
          source: EntrySource.values.firstWhere((s) => s.name == r['source'], orElse: () => EntrySource.manual),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at']! as int),
        ),
    ];
  }

  @override
  Future<void> upsert(WatchEntry entry) =>
      _d.insert('watchlist', _row(entry), conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> delete(String plate) => _d.delete('watchlist', where: 'plate = ?', whereArgs: [plate]);

  @override
  Future<(int, int)> importAll(List<WatchEntry> entries, {ImportMode mode = ImportMode.merge}) {
    return _d.transaction((txn) async {
      if (mode == ImportMode.replaceSource && entries.isNotEmpty) {
        await txn.delete('watchlist', where: 'source = ?', whereArgs: [entries.first.source.name]);
      }
      final existing = {
        for (final r in await txn.query('watchlist', columns: ['plate'])) r['plate']! as String,
      };
      var added = 0, updated = 0;
      final batch = txn.batch();
      for (final e in entries) {
        existing.contains(e.plate) ? updated++ : added++;
        batch.insert('watchlist', _row(e), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      return (added, updated);
    });
  }

  @override
  Future<void> clear() => _d.delete('watchlist');
}

class SqlDetectionLog implements DetectionLog {
  SqlDetectionLog(this._db);
  final VigiroadDatabase _db;
  Database get _d => _db.db;

  @override
  Future<void> add(DetectionRecord r) => _d.insert('detections', {
    'plate': r.plate,
    'display': r.display,
    'country': r.country,
    'category': r.category,
    'priority': _prio(r.priority),
    'confidence': r.confidence,
    'at': r.at.millisecondsSinceEpoch,
    'lat': r.latitude,
    'lng': r.longitude,
  });

  @override
  Future<List<DetectionRecord>> recent({int limit = 500}) async {
    final rows = await _d.query('detections', orderBy: 'at DESC', limit: limit);
    return [
      for (final r in rows)
        DetectionRecord(
          id: r['id'] as int?,
          plate: r['plate']! as String,
          display: r['display']! as String,
          country: r['country']! as String,
          category: r['category']! as String,
          priority: _prioFrom(r['priority']),
          confidence: (r['confidence']! as num).toDouble(),
          at: DateTime.fromMillisecondsSinceEpoch(r['at']! as int),
          latitude: (r['lat'] as num?)?.toDouble(),
          longitude: (r['lng'] as num?)?.toDouble(),
        ),
    ];
  }

  @override
  Future<void> delete(int id) => _d.delete('detections', where: 'id = ?', whereArgs: [id]);

  @override
  Future<int> purgeOlderThan(DateTime limit) =>
      _d.delete('detections', where: 'at < ?', whereArgs: [limit.millisecondsSinceEpoch]);

  @override
  Future<void> clear() => _d.delete('detections');
}

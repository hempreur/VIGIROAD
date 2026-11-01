import 'dart:io';

import 'package:postgres/postgres.dart';

/// Accès PostgreSQL : requêtes paramétrées uniquement (jamais de
/// concaténation de valeurs dans le SQL).
class Db {
  Db(this._session) : _executor = _session is SessionExecutor ? _session as SessionExecutor : null;

  /// Pool (production) ou connexion/transaction.
  final Session _session;

  /// Pool ou connexion capable d'ouvrir des transactions (null dans une
  /// transaction déjà ouverte).
  final SessionExecutor? _executor;

  static Future<Db> connect({
    required String host,
    required int port,
    required String database,
    required String user,
    required String password,
    int maxConnections = 10,
  }) async {
    final pool = Pool.withEndpoints(
      [Endpoint(host: host, port: port, database: database, username: user, password: password)],
      settings: PoolSettings(maxConnectionCount: maxConnections, sslMode: SslMode.disable),
    );
    return Db(pool);
  }

  /// Seuls les paramètres présents dans la requête sont transmis (le pilote
  /// refuse les paramètres superflus).
  static Map<String, Object?> _used(String sql, Map<String, Object?> params) => {
    for (final e in params.entries)
      if (RegExp('@${RegExp.escape(e.key)}(?![A-Za-z0-9_])').hasMatch(sql)) e.key: e.value,
  };

  Future<List<Map<String, dynamic>>> query(String sql, [Map<String, Object?> params = const {}]) async {
    final r = await _session.execute(Sql.named(sql), parameters: _used(sql, params));
    return [for (final row in r) row.toColumnMap()];
  }

  Future<Map<String, dynamic>?> one(String sql, [Map<String, Object?> params = const {}]) async {
    final rows = await query(sql, params);
    return rows.isEmpty ? null : rows.first;
  }

  Future<T> scalar<T>(String sql, [Map<String, Object?> params = const {}]) async {
    final r = await _session.execute(Sql.named(sql), parameters: _used(sql, params));
    return r.first.first as T;
  }

  /// Nombre de lignes modifiées.
  Future<int> exec(String sql, [Map<String, Object?> params = const {}]) async {
    final r = await _session.execute(Sql.named(sql), parameters: _used(sql, params));
    return r.affectedRows;
  }

  Future<T> tx<T>(Future<T> Function(Db db) body) async {
    final e = _executor;
    if (e != null) return e.runTx((tx) => body(Db(tx)));
    return body(this);
  }

  Future<void> close() async {
    await _executor?.close();
  }

  /// Applique dans l'ordre les fichiers `NNN_nom.sql` non encore appliqués,
  /// chacun dans une transaction, sous verrou (plusieurs instances possibles).
  Future<List<int>> migrate(String dir) async {
    final files = Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.sql')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final applied = <int>[];
    final e = _executor;
    if (e == null) throw StateError('migrate : pool ou connexion attendu');
    await e.runTx((tx) async {
      await tx.execute('SELECT pg_advisory_xact_lock(727274)');
      await tx.execute(
        'CREATE TABLE IF NOT EXISTS schema_migrations (version integer PRIMARY KEY, name text NOT NULL, '
        'applied_at timestamptz NOT NULL DEFAULT now())',
      );
      final done = {for (final r in await tx.execute('SELECT version FROM schema_migrations')) r.first as int};
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        final m = RegExp(r'^(\d+)_').firstMatch(name);
        if (m == null) continue;
        final version = int.parse(m.group(1)!);
        if (done.contains(version)) continue;
        await tx.execute(await f.readAsString(), queryMode: QueryMode.simple);
        await tx.execute(
          Sql.named('INSERT INTO schema_migrations (version, name) VALUES (@v, @n)'),
          parameters: {'v': version, 'n': name},
        );
        applied.add(version);
      }
    });
    return applied;
  }
}

/// Conversion d'une ligne en JSON (dates ISO 8601).
Map<String, Object?> jsonRow(Map<String, dynamic> row) => {
  for (final e in row.entries) _camel(e.key): _jsonValue(e.value),
};

Object? _jsonValue(Object? v) => switch (v) {
  DateTime d => d.toUtc().toIso8601String(),
  _ => v,
};

String _camel(String snake) {
  final parts = snake.split('_');
  return parts.first + parts.skip(1).map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1)).join();
}

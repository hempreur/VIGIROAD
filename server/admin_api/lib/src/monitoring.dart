import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

import 'accounts.dart';
import 'admin_auth.dart';
import 'context.dart';
import 'db.dart';
import 'http_kit.dart';

class AgentUnavailable implements Exception {
  AgentUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Client de l'agent de supervision (réseau Docker interne).
class AgentClient {
  AgentClient(this.base, this.token, {http.Client? client}) : _http = client ?? http.Client();

  final Uri? base;
  final String token;
  final http.Client _http;

  bool get configured => base != null;

  Future<Map<String, dynamic>> call(
    String method,
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final b = base;
    if (b == null) throw AgentUnavailable('Agent de supervision non configuré');
    final uri = b.replace(path: path, queryParameters: query);
    final http.Response r;
    try {
      final req = http.Request(method, uri)..headers['x-agent-token'] = token;
      r = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on Object catch (e) {
      throw AgentUnavailable('Agent injoignable : $e');
    }
    final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 400) throw ApiError(r.statusCode == 401 ? 502 : r.statusCode, '${body['error'] ?? 'Erreur agent'}');
    return body;
  }
}

/// Client du serveur de trafic (même réseau interne, clé API de l'appli).
class TrafficProbe {
  TrafficProbe(this.base, this.key, {http.Client? client}) : _http = client ?? http.Client();

  final Uri base;
  final String? key;
  final http.Client _http;

  Future<(Map<String, dynamic>?, int, String?)> get(String path) async {
    final sw = Stopwatch()..start();
    try {
      final r = await _http
          .get(base.replace(path: path), headers: {'x-api-key': ?key})
          .timeout(const Duration(seconds: 10));
      final ms = sw.elapsedMilliseconds;
      if (r.statusCode != 200) return (null, ms, 'HTTP ${r.statusCode}');
      return (jsonDecode(r.body) as Map<String, dynamic>, ms, null);
    } on Object catch (e) {
      return (null, sw.elapsedMilliseconds, '$e');
    }
  }
}

/// Supervision : VPS, Docker, flux routiers, requêtes, alertes et flux
/// d'événements temps réel (Server-Sent Events).
class MonitoringService {
  MonitoringService(this.ctx, this.auth, this.agent, this.traffic);

  final AppContext ctx;
  final AdminAuthService auth;
  final AgentClient agent;
  final TrafficProbe traffic;
  Db get db => ctx.db;

  Map<String, dynamic>? lastMetrics;
  DateTime? lastMetricsAt;
  Map<String, dynamic>? lastTrafficHealth;
  int? lastTrafficLatency;
  String? lastTrafficError;
  Map<String, dynamic>? lastSources;
  String? agentError;
  DateTime? certificateExpiry;
  String? certificateError;

  final _timers = <Timer>[];
  final _sseClients = <StreamController<String>>{};
  Timer? _sseTimer;

  void register(Router r) {
    r.get('/admin/server/overview', (req, _) => _overview(req));
    r.get('/admin/server/history', (req, _) => _history(req));
    r.get('/admin/server/processes', (req, _) => _passthrough(req, '/processes'));
    r.get('/admin/docker/containers', (req, _) => _containers(req));
    r.get('/admin/docker/containers/:id/logs', (req, p) => _logs(req, p['id']!));
    r.post('/admin/docker/containers/:id/:action', (req, p) => _action(req, p['id']!, p['action']!));
    r.get('/admin/docker/volumes', (req, _) => _passthrough(req, '/volumes', timeout: const Duration(seconds: 40)));
    r.get('/admin/docker/networks', (req, _) => _passthrough(req, '/networks'));
    r.get('/admin/docker/images', (req, _) => _passthrough(req, '/images'));
    r.get('/admin/vigiroad/status', (req, _) => _status(req));
    r.get('/admin/vigiroad/requests', (req, _) => _requests(req));
    r.get('/admin/vigiroad/sources/history', (req, _) => _sourceHistory(req));
    r.get('/admin/alerts', (req, _) async {
      await auth.authenticate(req);
      return jsonOk({'alerts': await alerts()});
    });
    r.get('/admin/events', (req, _) => _events(req));
  }

  // ---------------------------------------------------------------- collecte

  void start() {
    unawaited(collectMetrics());
    unawaited(collectSources());
    unawaited(checkCertificate());
    _timers
      ..add(Timer.periodic(const Duration(minutes: 1), (_) => unawaited(collectMetrics())))
      ..add(Timer.periodic(const Duration(minutes: 1), (_) => unawaited(collectRequests())))
      ..add(Timer.periodic(const Duration(minutes: 5), (_) => unawaited(collectSources())))
      ..add(Timer.periodic(const Duration(hours: 12), (_) => unawaited(checkCertificate())));
  }

  void stop() {
    for (final t in _timers) {
      t.cancel();
    }
    _sseTimer?.cancel();
    for (final c in _sseClients) {
      unawaited(c.close());
    }
  }

  /// Une mesure par minute dans server_metrics (et disponibilité du trafic).
  Future<void> collectMetrics({bool store = true}) async {
    final (health, latency, error) = await traffic.get('/health');
    lastTrafficHealth = health;
    lastTrafficLatency = latency;
    lastTrafficError = error;
    Map<String, dynamic>? m;
    try {
      m = await agent.call('GET', '/metrics');
      lastMetrics = m;
      lastMetricsAt = DateTime.now();
      agentError = null;
    } on AgentUnavailable catch (e) {
      agentError = e.message;
    } on Object catch (e) {
      agentError = '$e';
    }
    if (!store) return;
    try {
      final mem = m?['memory'] as Map<String, dynamic>?;
      final disk = (m?['disks'] as List<dynamic>?)?.cast<Map<String, dynamic>>().firstOrNull;
      final net = m?['network'] as Map<String, dynamic>?;
      final load = (m?['load'] as List<dynamic>?)?.cast<num>();
      final temps = (m?['temperatures'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? const [];
      await db.exec(
        'INSERT INTO server_metrics (at, cpu_percent, load1, load5, load15, mem_total, mem_used, mem_available, '
        'disk_total, disk_used, net_rx_bps, net_tx_bps, temp_c, traffic_ok, traffic_latency_ms) '
        "VALUES (date_trunc('minute', now()), @cpu, @l1, @l5, @l15, @mt, @mu, @ma, @dt, @du, @rx, @tx, @t, @ok, @lat) "
        'ON CONFLICT (at) DO NOTHING',
        {
          'cpu': (m?['cpuPercent'] as num?)?.toDouble(),
          'l1': load != null && load.isNotEmpty ? load[0].toDouble() : null,
          'l5': load != null && load.length > 1 ? load[1].toDouble() : null,
          'l15': load != null && load.length > 2 ? load[2].toDouble() : null,
          'mt': (mem?['total'] as num?)?.toInt(),
          'mu': (mem?['used'] as num?)?.toInt(),
          'ma': (mem?['available'] as num?)?.toInt(),
          'dt': (disk?['total'] as num?)?.toInt(),
          'du': (disk?['used'] as num?)?.toInt(),
          'rx': (net?['rxBps'] as num?)?.toInt(),
          'tx': (net?['txBps'] as num?)?.toInt(),
          't': temps.isEmpty
              ? null
              : temps.map((t) => (t['celsius'] as num).toDouble()).reduce((a, b) => a > b ? a : b),
          'ok': health != null && health['status'] == 'ok',
          'lat': latency,
        },
      );
    } catch (e) {
      ctx.recordError('collectMetrics', e);
    }
  }

  /// Statistiques de requêtes du serveur de trafic et de l'API d'administration.
  Future<void> collectRequests() async {
    final (t, _, _) = await traffic.get('/v1/metrics');
    final rows = <(String, Map<String, dynamic>)>[
      for (final m in (t?['minutes'] as List<dynamic>?) ?? const []) ('traffic', m as Map<String, dynamic>),
      for (final m in ctx.requestStats.snapshot()) ('admin-api', m.cast<String, dynamic>()),
    ];
    for (final (service, m) in rows) {
      try {
        await db.exec(
          'INSERT INTO request_metrics (minute, service, route, count, errors, p50_ms, p95_ms) '
          'VALUES (CAST(@m AS timestamptz), @s, @r, @c, @e, @p50, @p95) '
          'ON CONFLICT (service, route, minute) DO UPDATE SET count = EXCLUDED.count, errors = EXCLUDED.errors, '
          'p50_ms = EXCLUDED.p50_ms, p95_ms = EXCLUDED.p95_ms',
          {
            'm': m['minute'],
            's': service,
            'r': m['route'],
            'c': (m['count'] as num).toInt(),
            'e': (m['errors'] as num).toInt(),
            'p50': (m['p50Ms'] as num?)?.toDouble(),
            'p95': (m['p95Ms'] as num?)?.toDouble(),
          },
        );
      } catch (e) {
        ctx.recordError('collectRequests', e);
      }
    }
  }

  /// État de chaque flux routier, toutes les 5 minutes.
  Future<void> collectSources() async {
    final (s, _, error) = await traffic.get('/v1/sources');
    if (s == null) {
      lastTrafficError ??= error;
      return;
    }
    lastSources = s;
    for (final src in (s['sources'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>()) {
      try {
        await db.exec(
          'INSERT INTO traffic_source_metrics (at, source_id, healthy, events, last_success, last_error) '
          "VALUES (date_trunc('minute', now()), @id, @h, @e, CAST(@ls AS timestamptz), @err) ON CONFLICT DO NOTHING",
          {
            'id': src['id'],
            'h': src['healthy'] == true,
            'e': (src['events'] as num?)?.toInt(),
            'ls': src['lastSuccess'],
            'err': src['lastError'],
          },
        );
      } catch (e) {
        ctx.recordError('collectSources', e);
      }
    }
  }

  /// Date d'expiration du certificat HTTPS public.
  Future<void> checkCertificate() async {
    final domain = ctx.config.publicDomain;
    if (domain == null || domain == 'localhost') return;
    try {
      final s = await SecureSocket.connect(domain, 443, timeout: const Duration(seconds: 10));
      certificateExpiry = s.peerCertificate?.endValidity.toUtc();
      certificateError = null;
      s.destroy();
    } on Object catch (e) {
      certificateError = '$e';
    }
  }

  // ------------------------------------------------------------------ alertes

  /// Alertes actives sur les ressources critiques et les services.
  Future<List<Map<String, Object?>>> alerts() async {
    final out = <Map<String, Object?>>[];
    void add(String level, String id, String title, String detail) =>
        out.add({'level': level, 'id': id, 'title': title, 'detail': detail});

    final m = lastMetrics;
    if (agentError != null) add('critical', 'agent', 'Agent de supervision injoignable', agentError!);
    if (m != null) {
      final cpu = (m['cpuPercent'] as num?)?.toDouble();
      final recent = await db.one(
        "SELECT CAST(avg(cpu_percent) AS float8) AS cpu FROM server_metrics WHERE at > now() - interval '5 minutes'",
      );
      final cpu5 = (recent?['cpu'] as num?)?.toDouble() ?? cpu;
      if (cpu5 != null && cpu5 >= 90) {
        add('critical', 'cpu', 'Processeur saturé', 'CPU à ${cpu5.toStringAsFixed(0)} % sur 5 minutes');
      } else if (cpu5 != null && cpu5 >= 75) {
        add('warning', 'cpu', 'Processeur très sollicité', 'CPU à ${cpu5.toStringAsFixed(0)} % sur 5 minutes');
      }
      final mem = m['memory'] as Map<String, dynamic>? ?? const {};
      final total = (mem['total'] as num?) ?? 0, used = (mem['used'] as num?) ?? 0;
      if (total > 0) {
        final pct = used / total * 100;
        if (pct >= 92) {
          add('critical', 'memory', 'Mémoire presque pleine', 'RAM utilisée à ${pct.toStringAsFixed(0)} %');
        } else if (pct >= 80) {
          add('warning', 'memory', 'Mémoire élevée', 'RAM utilisée à ${pct.toStringAsFixed(0)} %');
        }
      }
      for (final d in (m['disks'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>()) {
        final t = (d['total'] as num?) ?? 0, u = (d['used'] as num?) ?? 0;
        if (t <= 0) continue;
        final pct = u / t * 100;
        if (pct >= 92) {
          add('critical', 'disk', 'Disque presque plein', 'Disque ${d['mount']} utilisé à ${pct.toStringAsFixed(0)} %');
        } else if (pct >= 80) {
          add('warning', 'disk', 'Espace disque faible', 'Disque ${d['mount']} utilisé à ${pct.toStringAsFixed(0)} %');
        }
      }
      for (final t in (m['temperatures'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>()) {
        final c = (t['celsius'] as num).toDouble();
        if (c >= 85) add('critical', 'temperature', 'Température élevée', '${t['sensor']} : ${c.toStringAsFixed(0)} °C');
      }
    }
    if (lastTrafficHealth == null) {
      add('critical', 'traffic', 'Serveur de trafic indisponible', lastTrafficError ?? 'aucune réponse');
    }
    final now = DateTime.now().toUtc();
    for (final s in (lastSources?['sources'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>()) {
      final last = DateTime.tryParse(s['lastSuccess'] as String? ?? '');
      final stale = last == null || now.difference(last) > const Duration(minutes: 30);
      if (s['healthy'] != true || stale) {
        add(
          stale ? 'critical' : 'warning',
          'source:${s['id']}',
          'Flux « ${s['name'] ?? s['id']} » en échec',
          last == null ? 'jamais synchronisé' : 'dernière synchronisation : ${last.toIso8601String()} — ${s['lastError'] ?? ''}',
        );
      }
    }
    final backup = await db.one(
      "SELECT max(finished_at) AS last_ok FROM backup_jobs WHERE status = 'success' AND kind IN ('scheduled', 'manual')",
    );
    final lastOk = backup?['last_ok'] as DateTime?;
    if (lastOk == null) {
      add('warning', 'backup', 'Aucune sauvegarde réussie', 'La première sauvegarde automatique a lieu chaque nuit');
    } else if (now.difference(lastOk) > const Duration(hours: 30)) {
      add('critical', 'backup', 'Sauvegarde en retard', 'Dernière réussie : ${lastOk.toUtc().toIso8601String()}');
    }
    final failed = await db.one(
      "SELECT kind, message, finished_at FROM backup_jobs WHERE status = 'failed' AND finished_at > now() - interval '24 hours' "
      'ORDER BY finished_at DESC LIMIT 1',
    );
    if (failed != null) {
      add('critical', 'backup_failed', 'Sauvegarde en échec', '${failed['kind']} : ${failed['message'] ?? ''}');
    }
    final exp = certificateExpiry;
    if (exp != null && exp.difference(now) < const Duration(days: 14)) {
      add('critical', 'certificate', 'Certificat HTTPS bientôt expiré', 'Expire le ${exp.toIso8601String()}');
    }
    final failedLogins = await db.scalar<int>(
      "SELECT count(*) FROM login_events WHERE NOT success AND at > now() - interval '15 minutes'",
    );
    if (failedLogins >= 30) {
      add('warning', 'logins', 'Nombreux échecs de connexion', '$failedLogins échecs en 15 minutes');
    }
    return out;
  }

  // ---------------------------------------------------------------- routes

  Future<Response> _overview(Request req) async {
    await auth.authenticate(req);
    Map<String, dynamic>? system, metrics;
    String? error;
    try {
      final r = await Future.wait([agent.call('GET', '/system'), agent.call('GET', '/metrics')]);
      system = r[0];
      metrics = r[1];
    } on AgentUnavailable catch (e) {
      error = e.message;
    }
    return jsonOk({
      'system': system,
      'metrics': metrics ?? lastMetrics,
      'agentError': error,
      'alerts': await alerts(),
    });
  }

  Future<Response> _history(Request req) async {
    await auth.authenticate(req);
    final (interval, bucket) = switch (req.url.queryParameters['period']) {
      '1h' => ('1 hour', 60),
      '7d' => ('7 days', 3600),
      '30d' => ('30 days', 6 * 3600),
      _ => ('24 hours', 600),
    };
    final rows = await db.query(
      'SELECT to_timestamp(floor(extract(epoch FROM at) / @b) * @b) AS at, '
      'CAST(avg(cpu_percent) AS float8) AS cpu, CAST(max(cpu_percent) AS float8) AS cpu_max, '
      'CAST(avg(load1) AS float8) AS load1, CAST(avg(mem_used) AS float8) AS mem_used, CAST(max(mem_total) AS float8) AS mem_total, '
      'CAST(avg(disk_used) AS float8) AS disk_used, CAST(max(disk_total) AS float8) AS disk_total, '
      'CAST(avg(net_rx_bps) AS float8) AS rx, CAST(avg(net_tx_bps) AS float8) AS tx, CAST(max(temp_c) AS float8) AS temp, '
      'CAST(avg(CASE WHEN traffic_ok THEN 1.0 ELSE 0.0 END) AS float8) AS availability, '
      'CAST(avg(traffic_latency_ms) AS float8) AS latency '
      'FROM server_metrics WHERE at > now() - CAST(@i AS interval) GROUP BY 1 ORDER BY 1',
      {'b': bucket, 'i': interval},
    );
    return jsonOk({'period': req.url.queryParameters['period'] ?? '24h', 'points': rows.map(jsonRow).toList()});
  }

  Future<Response> _passthrough(Request req, String path, {Duration timeout = const Duration(seconds: 15)}) async {
    await auth.authenticate(req);
    return jsonOk(await _agent('GET', path, timeout: timeout));
  }

  Future<Map<String, dynamic>> _agent(String method, String path, {Map<String, String>? query, Duration? timeout}) async {
    try {
      return await agent.call(method, path, query: query, timeout: timeout ?? const Duration(seconds: 15));
    } on AgentUnavailable catch (e) {
      throw ApiError(503, e.message, code: 'agent_unavailable');
    }
  }

  Future<Response> _containers(Request req) async {
    await auth.authenticate(req);
    return jsonOk(await _agent('GET', '/containers', query: {'stats': 'true'}, timeout: const Duration(seconds: 30)));
  }

  static final _idRe = RegExp(r'^[A-Za-z0-9_.\-]{1,128}$');

  Future<Response> _logs(Request req, String id) async {
    await auth.authenticate(req);
    if (!_idRe.hasMatch(id)) throw ApiError.notFound;
    final tail = req.url.queryParameters['tail'] ?? '200';
    return jsonOk(await _agent('GET', '/containers/$id/logs', query: {'tail': tail}));
  }

  Future<Response> _action(Request req, String id, String action) async {
    final a = await auth.authenticate(req, Perm.serverControl);
    if (!_idRe.hasMatch(id) || !const {'start', 'stop', 'restart'}.contains(action)) throw ApiError.notFound;
    try {
      final r = await _agent('POST', '/containers/$id/$action', timeout: const Duration(seconds: 90));
      await ctx.audit(a, 'docker.$action', targetType: 'container', targetId: id, details: {'service': r['service']});
      return jsonOk(r);
    } on ApiError catch (e) {
      await ctx.audit(a, 'docker.$action', targetType: 'container', targetId: id, success: false, details: {'error': e.message});
      rethrow;
    }
  }

  Future<Response> _status(Request req) async {
    await auth.authenticate(req);
    final (health, latency, error) = await traffic.get('/health');
    final (sources, _, sourcesError) = await traffic.get('/v1/sources');
    if (sources != null) lastSources = sources;
    final dbSw = Stopwatch()..start();
    final dbStats = await db.one('''
      SELECT (SELECT max(version) FROM schema_migrations) AS schema_version,
             pg_database_size(current_database()) AS size_bytes,
             (SELECT count(*) FROM pg_stat_activity WHERE datname = current_database()) AS connections
    ''');
    final dbMs = dbSw.elapsedMilliseconds;
    final req24 = await db.query('''
      SELECT service, CAST(sum(count) AS bigint) AS requests, CAST(sum(errors) AS bigint) AS errors,
             CAST(avg(p50_ms) AS float8) AS p50_ms, CAST(max(p95_ms) AS float8) AS p95_ms
      FROM request_metrics WHERE minute > now() - interval '24 hours' GROUP BY service
    ''');
    final srcList = (sources?['sources'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    return jsonOk({
      'traffic': {
        'ok': health?['status'] == 'ok',
        'latencyMs': latency,
        'error': error ?? sourcesError,
        'coverage': health?['coverage'],
        'activeSources': srcList.where((s) => s['healthy'] == true).length,
        'totalSources': srcList.length,
        'events': srcList.fold<int>(0, (a, s) => a + ((s['events'] as num?)?.toInt() ?? 0)),
        'sources': srcList,
      },
      'adminApi': {'ok': true, 'recentErrors': ctx.recentErrors.length},
      'database': {'ok': true, 'latencyMs': dbMs, ...jsonRow(dbStats!)},
      'agent': {'ok': agentError == null && lastMetricsAt != null, 'error': agentError},
      'certificate': {'expiresAt': certificateExpiry?.toIso8601String(), 'error': certificateError},
      'requests24h': req24.map(jsonRow).toList(),
      'geoIp': ctx.geo.available,
    });
  }

  Future<Response> _requests(Request req) async {
    await auth.authenticate(req);
    final (interval, bucket) = switch (req.url.queryParameters['period']) {
      '1h' => ('1 hour', 60),
      '7d' => ('7 days', 3600),
      _ => ('24 hours', 900),
    };
    final series = await db.query(
      'SELECT to_timestamp(floor(extract(epoch FROM minute) / @b) * @b) AS at, service, '
      'CAST(sum(count) AS bigint) AS requests, CAST(sum(errors) AS bigint) AS errors, '
      'CAST(avg(p50_ms) AS float8) AS p50_ms, CAST(max(p95_ms) AS float8) AS p95_ms '
      'FROM request_metrics WHERE minute > now() - CAST(@i AS interval) GROUP BY 1, 2 ORDER BY 1',
      {'b': bucket, 'i': interval},
    );
    final routes = await db.query(
      'SELECT service, route, CAST(sum(count) AS bigint) AS requests, CAST(sum(errors) AS bigint) AS errors, '
      'CAST(avg(p50_ms) AS float8) AS p50_ms, CAST(max(p95_ms) AS float8) AS p95_ms '
      'FROM request_metrics WHERE minute > now() - CAST(@i AS interval) GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 50',
      {'i': interval},
    );
    return jsonOk({'series': series.map(jsonRow).toList(), 'routes': routes.map(jsonRow).toList()});
  }

  Future<Response> _sourceHistory(Request req) async {
    await auth.authenticate(req);
    final rows = await db.query(
      'SELECT at, source_id, healthy, events, last_success, last_error FROM traffic_source_metrics '
      "WHERE at > now() - interval '24 hours' ORDER BY at",
    );
    return jsonOk({'points': rows.map(jsonRow).toList()});
  }

  // -------------------------------------------------------- temps réel (SSE)

  /// Flux d'événements : métriques, compteurs et alertes toutes les 5 s.
  Future<Response> _events(Request req) async {
    await auth.authenticate(req);
    late final StreamController<String> c;
    c = StreamController<String>(
      onCancel: () {
        _sseClients.remove(c);
        if (_sseClients.isEmpty) {
          _sseTimer?.cancel();
          _sseTimer = null;
        }
      },
    );
    _sseClients.add(c);
    c.add('retry: 5000\n\n');
    _sseTimer ??= Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_broadcast()));
    unawaited(_broadcast(only: c));
    return Response.ok(
      c.stream.map(utf8.encode),
      headers: {'content-type': 'text/event-stream', 'cache-control': 'no-cache', 'x-accel-buffering': 'no'},
      context: {'shelf.io.buffer_output': false},
    );
  }

  Future<void> _broadcast({StreamController<String>? only}) async {
    try {
      Map<String, dynamic>? m;
      try {
        m = await agent.call('GET', '/metrics', timeout: const Duration(seconds: 4));
        lastMetrics = m;
        lastMetricsAt = DateTime.now();
        agentError = null;
      } on AgentUnavailable catch (e) {
        agentError = e.message;
      }
      final counts = await db.one('''
        SELECT (SELECT count(DISTINCT user_id) FROM sessions WHERE ended_at IS NULL
                  AND last_seen_at > now() - make_interval(secs => ${AccountService.onlineWindowSeconds})) AS users_online,
               (SELECT count(*) FROM sessions WHERE ended_at IS NULL
                  AND last_seen_at > now() - make_interval(secs => ${AccountService.onlineWindowSeconds})) AS sessions_online
      ''');
      final payload = jsonEncode({
        'at': DateTime.now().toUtc().toIso8601String(),
        'metrics': m ?? lastMetrics,
        'counts': jsonRow(counts!),
        'alerts': await alerts(),
        'traffic': {'ok': lastTrafficHealth?['status'] == 'ok', 'latencyMs': lastTrafficLatency},
      });
      final msg = 'event: snapshot\ndata: $payload\n\n';
      for (final c in only == null ? _sseClients.toList() : [only]) {
        if (!c.isClosed) c.add(msg);
      }
    } catch (e) {
      ctx.recordError('sse', e);
    }
  }
}

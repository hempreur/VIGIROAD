import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

import 'admin_auth.dart';
import 'context.dart';
import 'db.dart';
import 'http_kit.dart';
import 'monitoring.dart';

/// Maintenance : diagnostic, erreurs, sauvegardes, mises à jour et règles de
/// conservation des données.
class MaintenanceService {
  MaintenanceService(this.ctx, this.auth, this.monitoring, {http.Client? client}) : _http = client ?? http.Client();

  final AppContext ctx;
  final AdminAuthService auth;
  final MonitoringService monitoring;
  final http.Client _http;
  Db get db => ctx.db;
  Timer? _retention;

  void register(Router r) {
    r.get('/admin/diagnostics', (req, _) => _diagnostics(req));
    r.get('/admin/errors', (req, _) => _errors(req));
    r.get('/admin/backups', (req, _) => _backups(req));
    r.post('/admin/backups', (req, _) => _requestBackup(req));
    r.get('/admin/updates', (req, _) => _updates(req));
    r.post('/admin/updates/deploy', (req, _) => _deploy(req));
    r.post('/admin/maintenance/retention', (req, _) async {
      final a = await auth.authenticate(req, Perm.settings);
      final r = await applyRetention();
      await ctx.audit(a, 'maintenance.retention', details: r);
      return jsonOk(r);
    });
  }

  void start() {
    unawaited(applyRetention());
    _retention = Timer.periodic(const Duration(hours: 1), (_) => unawaited(applyRetention()));
  }

  void stop() => _retention?.cancel();

  /// Suppression des données au-delà des durées de conservation réglées, et
  /// expiration des sessions inactives.
  Future<Map<String, Object?>> applyRetention() async {
    final s = await ctx.settings();
    int days(String k, int d) => (s[k] is num) ? (s[k] as num).toInt() : d;
    final out = <String, Object?>{};
    Future<void> run(String name, String sql, int value) async {
      try {
        out[name] = await db.exec(sql, {'d': value});
      } catch (e) {
        ctx.recordError('retention:$name', e);
      }
    }

    await run(
      'expiredSessions',
      "UPDATE sessions SET ended_at = now(), end_reason = 'expired' WHERE ended_at IS NULL "
          'AND last_seen_at < now() - make_interval(days => CAST(@d AS int))',
      days('sessions.idle_expiry_days', 30),
    );
    await run(
      'loginEvents',
      'DELETE FROM login_events WHERE at < now() - make_interval(days => CAST(@d AS int))',
      days('retention.login_events_days', 180),
    );
    await run(
      'sessions',
      'DELETE FROM sessions WHERE ended_at IS NOT NULL AND ended_at < now() - make_interval(days => CAST(@d AS int))',
      days('retention.sessions_days', 365),
    );
    await run(
      'locations',
      'DELETE FROM location_history WHERE at < now() - make_interval(days => CAST(@d AS int))',
      days('retention.location_days', 30),
    );
    final metricsDays = days('retention.metrics_days', 30);
    await run('serverMetrics', 'DELETE FROM server_metrics WHERE at < now() - make_interval(days => CAST(@d AS int))', metricsDays);
    await run(
      'sourceMetrics',
      'DELETE FROM traffic_source_metrics WHERE at < now() - make_interval(days => CAST(@d AS int))',
      metricsDays,
    );
    await run(
      'requestMetrics',
      'DELETE FROM request_metrics WHERE minute < now() - make_interval(days => CAST(@d AS int))',
      metricsDays,
    );
    await run('usageHourly', 'DELETE FROM usage_hourly WHERE hour < now() - make_interval(days => CAST(@d AS int))', 35);
    await run(
      'audit',
      'DELETE FROM admin_audit_logs WHERE at < now() - make_interval(days => CAST(@d AS int))',
      days('retention.audit_days', 730),
    );
    await run(
      'passwordResets',
      'DELETE FROM password_resets WHERE expires_at < now() - make_interval(days => CAST(@d AS int))',
      7,
    );
    await run(
      'adminSessions',
      'DELETE FROM admin_sessions WHERE expires_at < now() - make_interval(days => CAST(@d AS int))',
      30,
    );
    return out;
  }

  Future<Response> _diagnostics(Request req) async {
    await auth.authenticate(req);
    final checks = <Map<String, Object?>>[];
    void check(String id, String label, bool ok, String detail, {String level = 'critical'}) =>
        checks.add({'id': id, 'label': label, 'ok': ok, 'level': ok ? 'ok' : level, 'detail': detail});

    final sw = Stopwatch()..start();
    try {
      final v = await db.scalar<int>('SELECT max(version) FROM schema_migrations');
      check('database', 'Base PostgreSQL', true, 'schéma v$v, réponse en ${sw.elapsedMilliseconds} ms');
    } catch (e) {
      check('database', 'Base PostgreSQL', false, '$e');
    }

    Map<String, dynamic>? containers;
    try {
      await monitoring.collectMetrics(store: false);
      check('agent', 'Agent de supervision', monitoring.agentError == null, monitoring.agentError ?? 'joignable');
      containers = await monitoring.agent.call('GET', '/containers', timeout: const Duration(seconds: 20));
    } on Object catch (e) {
      check('agent', 'Agent de supervision', false, '$e');
    }
    if (containers != null) {
      final list = (containers['containers'] as List<dynamic>).cast<Map<String, dynamic>>().where((c) => c['vigiroad'] == true);
      final down = list.where((c) => c['state'] != 'running').map((c) => c['service'] ?? c['name']).toList();
      final unhealthy = list.where((c) => c['health'] == 'unhealthy').map((c) => c['service']).toList();
      check(
        'containers',
        'Conteneurs VIGIROAD',
        down.isEmpty && unhealthy.isEmpty,
        down.isEmpty && unhealthy.isEmpty
            ? '${list.length} en fonctionnement'
            : 'arrêtés : ${down.join(', ')} ${unhealthy.isEmpty ? '' : '— en mauvaise santé : ${unhealthy.join(', ')}'}',
      );
    }
    final health = monitoring.lastTrafficHealth;
    check(
      'traffic',
      'Serveur de trafic',
      health?['status'] == 'ok',
      health == null ? (monitoring.lastTrafficError ?? 'injoignable') : 'répond en ${monitoring.lastTrafficLatency} ms',
    );
    await monitoring.collectSources();
    final sources = (monitoring.lastSources?['sources'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final bad = sources.where((s) => s['healthy'] != true).map((s) => s['id']).toList();
    check(
      'sources',
      'Flux routiers',
      sources.isNotEmpty && bad.isEmpty,
      sources.isEmpty ? 'aucun flux' : (bad.isEmpty ? '${sources.length} flux à jour' : 'en échec : ${bad.join(', ')}'),
      level: bad.length == sources.length ? 'critical' : 'warning',
    );
    final m = monitoring.lastMetrics;
    if (m != null) {
      final mem = m['memory'] as Map<String, dynamic>;
      final memPct = (mem['used'] as num) / ((mem['total'] as num) == 0 ? 1 : mem['total'] as num) * 100;
      check('memory', 'Mémoire', memPct < 90, '${memPct.toStringAsFixed(0)} % utilisée', level: 'warning');
      for (final d in (m['disks'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final pct = (d['used'] as num) / ((d['total'] as num) == 0 ? 1 : d['total'] as num) * 100;
        check('disk', 'Disque ${d['mount']}', pct < 85, '${pct.toStringAsFixed(0)} % utilisé', level: 'warning');
      }
    }
    final b = await db.one('''
      SELECT (SELECT max(finished_at) FROM backup_jobs WHERE status = 'success' AND kind <> 'restore_test') AS last_backup,
             (SELECT max(finished_at) FROM backup_jobs WHERE status = 'success' AND kind = 'restore_test') AS last_restore,
             (SELECT count(*) FROM backup_jobs WHERE status = 'failed' AND finished_at > now() - interval '7 days') AS failed7d
    ''');
    final lastBackup = b?['last_backup'] as DateTime?;
    check(
      'backup',
      'Sauvegarde',
      lastBackup != null && DateTime.now().difference(lastBackup) < const Duration(hours: 30),
      lastBackup == null ? 'aucune sauvegarde réussie' : 'dernière : ${lastBackup.toUtc().toIso8601String()}',
      level: 'warning',
    );
    final lastRestore = b?['last_restore'] as DateTime?;
    check(
      'restore',
      'Restauration testée',
      lastRestore != null && DateTime.now().difference(lastRestore) < const Duration(days: 8),
      lastRestore == null ? 'aucun test de restauration réussi' : 'dernier test : ${lastRestore.toUtc().toIso8601String()}',
      level: 'warning',
    );
    final exp = monitoring.certificateExpiry;
    if (exp != null || monitoring.certificateError != null) {
      check(
        'certificate',
        'Certificat HTTPS',
        exp != null && exp.difference(DateTime.now()) > const Duration(days: 14),
        exp == null ? '${monitoring.certificateError}' : 'expire le ${exp.toIso8601String()}',
        level: 'warning',
      );
    }
    final mfa = await db.scalar<int>("SELECT count(*) FROM admin_accounts WHERE status = 'active' AND NOT totp_confirmed");
    check(
      'mfa',
      'Double authentification des administrateurs',
      mfa == 0,
      mfa == 0 ? 'tous les comptes actifs sont protégés' : '$mfa compte(s) sans application d\'authentification',
      level: 'warning',
    );
    check(
      'geoip',
      'Base de géolocalisation IP',
      ctx.geo.available,
      ctx.geo.available ? '${ctx.geo.ranges} plages (DB-IP Lite)' : 'absente : pays inconnu',
      level: 'info',
    );
    return jsonOk({'at': DateTime.now().toUtc().toIso8601String(), 'checks': checks});
  }

  Future<Response> _errors(Request req) async {
    await auth.authenticate(req);
    final sources = (monitoring.lastSources?['sources'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((s) => s['lastError'] != null)
        .map((s) => {'source': s['id'], 'error': s['lastError'], 'lastAttempt': s['lastAttempt']})
        .toList();
    final backups = await db.query(
      "SELECT id, kind, finished_at, message FROM backup_jobs WHERE status = 'failed' ORDER BY finished_at DESC LIMIT 20",
    );
    final logins = await db.query('''
      SELECT reason, kind, count(*) AS count, max(at) AS last_at FROM login_events
      WHERE NOT success AND at > now() - interval '24 hours' GROUP BY reason, kind ORDER BY count DESC
    ''');
    final requests = await db.query('''
      SELECT service, route, CAST(sum(errors) AS bigint) AS errors, max(minute) AS last_at FROM request_metrics
      WHERE errors > 0 AND minute > now() - interval '24 hours' GROUP BY service, route ORDER BY errors DESC LIMIT 20
    ''');
    return jsonOk({
      'internal': ctx.recentErrors,
      'sources': sources,
      'backups': backups.map(jsonRow).toList(),
      'failedLogins': logins.map(jsonRow).toList(),
      'requestErrors': requests.map(jsonRow).toList(),
    });
  }

  Future<Response> _backups(Request req) async {
    await auth.authenticate(req);
    final rows = await db.query(
      'SELECT b.id, b.kind, b.status, b.created_at, b.started_at, b.finished_at, b.file_name, b.size_bytes, b.sha256, '
      'b.message, a.email AS requested_by FROM backup_jobs b LEFT JOIN admin_accounts a ON a.id = b.requested_by '
      'ORDER BY b.created_at DESC LIMIT 100',
    );
    return jsonOk({'items': rows.map(jsonRow).toList(), 'keep': await ctx.intSetting('backups.keep', 14)});
  }

  /// Sauvegarde immédiate ou test de restauration, exécutés par le service
  /// « backup » (qui surveille cette file d'attente).
  Future<Response> _requestBackup(Request req) async {
    final a = await auth.authenticate(req, Perm.backups);
    final b = await readJson(req);
    final kind = b.str('kind', max: 16) ?? 'manual';
    if (kind != 'manual' && kind != 'restore_test') throw ApiError.badRequest('kind : manual ou restore_test');
    final pending = await db.one("SELECT id FROM backup_jobs WHERE status IN ('pending', 'running') LIMIT 1");
    if (pending != null) throw const ApiError(409, 'Une opération de sauvegarde est déjà en cours', code: 'busy');
    final id = await db.scalar<int>(
      'INSERT INTO backup_jobs (kind, requested_by) VALUES (@k, CAST(@a AS uuid)) RETURNING id',
      {'k': kind, 'a': a.id},
    );
    await ctx.audit(a, 'backup.$kind', targetType: 'backup', targetId: '$id');
    return jsonOk({'id': id, 'status': 'pending'}, status: 202);
  }

  /// Version déployée sur le VPS et dernière version publiée sur GitHub.
  Future<Response> _updates(Request req) async {
    await auth.authenticate(req);
    Map<String, dynamic>? deploy;
    String? deployError;
    try {
      deploy = await monitoring.agent.call('GET', '/deploy');
    } on Object catch (e) {
      deployError = '$e';
    }
    Map<String, dynamic>? latestCommit, latestRelease;
    String? githubError;
    try {
      final repo = ctx.config.githubRepo;
      final headers = {'accept': 'application/vnd.github+json', 'user-agent': 'VIGIROAD-admin-api'};
      final c = await _http
          .get(Uri.parse('https://api.github.com/repos/$repo/commits/main'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (c.statusCode == 200) {
        final j = jsonDecode(c.body) as Map<String, dynamic>;
        final commit = j['commit'] as Map<String, dynamic>;
        latestCommit = {
          'sha': j['sha'],
          'message': (commit['message'] as String).split('\n').first,
          'date': (commit['committer'] as Map<String, dynamic>)['date'],
        };
      } else {
        githubError = 'GitHub : HTTP ${c.statusCode}';
      }
      final r = await _http
          .get(Uri.parse('https://api.github.com/repos/$repo/releases/latest'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        latestRelease = {'tag': j['tag_name'], 'name': j['name'], 'publishedAt': j['published_at'], 'url': j['html_url']};
      }
    } on Object catch (e) {
      githubError = '$e';
    }
    final deployedSha = (deploy?['deployed'] as Map<String, dynamic>?)?['commit'] as String?;
    return jsonOk({
      'deploy': deploy,
      'deployError': deployError,
      'latestCommit': latestCommit,
      'latestRelease': latestRelease,
      'githubError': githubError,
      'updateAvailable': deployedSha != null && latestCommit != null && latestCommit['sha'] != deployedSha,
    });
  }

  Future<Response> _deploy(Request req) async {
    final a = await auth.authenticate(req, Perm.deploy);
    try {
      final r = await monitoring.agent.call('POST', '/deploy', query: {'by': a.email});
      await ctx.audit(a, 'deploy.request');
      return jsonOk(r, status: 202);
    } on AgentUnavailable catch (e) {
      await ctx.audit(a, 'deploy.request', success: false, details: {'error': e.message});
      throw ApiError(503, e.message, code: 'agent_unavailable');
    }
  }
}

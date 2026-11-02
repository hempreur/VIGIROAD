import 'dart:convert';

import 'package:postgres/postgres.dart' show ServerException;
import 'package:shelf/shelf.dart';

import 'accounts.dart';
import 'admin_auth.dart';
import 'context.dart';
import 'db.dart';
import 'geoip.dart';
import 'http_kit.dart';
import 'security.dart';

/// Tableau de bord, utilisateurs, appareils, sessions, statistiques,
/// géographie, réglages et journal d'audit (application Windows).
class AdminUsersService {
  AdminUsersService(this.ctx, this.auth);

  final AppContext ctx;
  final AdminAuthService auth;
  Db get db => ctx.db;

  static const _online = 'make_interval(secs => ${AccountService.onlineWindowSeconds})';

  void register(Router r) {
    r.get('/admin/dashboard', (req, _) => _dashboard(req));
    r.get('/admin/stats/activity', (req, _) => _activity(req));
    r.get('/admin/users', (req, _) => _users(req));
    r.get('/admin/users/export', (req, _) => _exportUsers(req));
    r.get('/admin/users/:id', (req, p) => _user(req, p['id']!));
    r.patch('/admin/users/:id', (req, p) => _updateUser(req, p['id']!));
    r.post('/admin/users/:id/disable', (req, p) => _setStatus(req, p['id']!, 'disabled'));
    r.post('/admin/users/:id/enable', (req, p) => _setStatus(req, p['id']!, 'active'));
    r.post('/admin/users/:id/revoke-sessions', (req, p) => _revokeUserSessions(req, p['id']!));
    r.post('/admin/users/:id/reset-access', (req, p) => _resetAccess(req, p['id']!));
    r.get('/admin/users/:id/export', (req, p) => _exportUser(req, p['id']!));
    r.delete('/admin/users/:id', (req, p) => _deleteUser(req, p['id']!));
    r.get('/admin/devices', (req, _) => _devices(req));
    r.get('/admin/devices/:id', (req, p) => _device(req, p['id']!));
    r.post('/admin/devices/:id/revoke', (req, p) => _revokeDevice(req, p['id']!));
    r.get('/admin/sessions', (req, _) => _sessions(req));
    r.get('/admin/sessions/concurrent', (req, _) => _concurrent(req));
    r.post('/admin/sessions/:id/revoke', (req, p) => _revokeSession(req, p['id']!));
    r.get('/admin/login-events', (req, _) => _loginEvents(req));
    r.get('/admin/geo', (req, _) => _geo(req));
    r.get('/admin/settings', (req, _) => _settings(req));
    r.put('/admin/settings', (req, _) => _putSettings(req));
    r.get('/admin/audit', (req, _) => _audit(req));
  }

  int _int(Request req, String k, int def, {int min = 0, int max = 1000}) =>
      (int.tryParse(req.url.queryParameters[k] ?? '') ?? def).clamp(min, max);

  String? _q(Request req, String k) {
    final v = req.url.queryParameters[k]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  Future<Response> _dashboard(Request req) async {
    await auth.authenticate(req);
    final r = await db.one('''
      SELECT
        (SELECT count(*) FROM users) AS users_total,
        (SELECT count(*) FROM users WHERE status = 'disabled') AS users_disabled,
        (SELECT count(*) FROM users WHERE created_at > now() - interval '24 hours') AS users_new24h,
        (SELECT count(DISTINCT user_id) FROM sessions WHERE ended_at IS NULL AND last_seen_at > now() - $_online) AS users_online,
        (SELECT count(*) FROM devices WHERE revoked_at IS NULL) AS devices_total,
        (SELECT count(*) FROM devices WHERE revoked_at IS NULL AND last_seen_at > now() - $_online) AS devices_online,
        (SELECT count(*) FROM sessions WHERE ended_at IS NULL) AS sessions_open,
        (SELECT count(*) FROM sessions WHERE ended_at IS NULL AND last_seen_at > now() - $_online) AS sessions_online,
        (SELECT count(*) FROM login_events WHERE kind = 'user' AND success AND at >= date_trunc('day', now())) AS logins_today,
        (SELECT count(*) FROM login_events WHERE kind = 'user' AND NOT success AND at > now() - interval '24 hours') AS failed_logins24h,
        (SELECT CAST(COALESCE(avg(active_seconds), 0) AS float8) FROM sessions
           WHERE started_at > now() - interval '30 days' AND active_seconds > 0) AS avg_session_seconds,
        (SELECT CAST(COALESCE(sum(active_seconds), 0) AS bigint) FROM usage_statistics WHERE day = current_date) AS usage_today_seconds,
        (SELECT CAST(COALESCE(avg(CASE WHEN traffic_ok THEN 1.0 ELSE 0.0 END), 0) AS float8) FROM server_metrics
           WHERE at > now() - interval '24 hours' AND traffic_ok IS NOT NULL) AS availability24h,
        (SELECT CAST(COALESCE(avg(CASE WHEN traffic_ok THEN 1.0 ELSE 0.0 END), 0) AS float8) FROM server_metrics
           WHERE at > now() - interval '30 days' AND traffic_ok IS NOT NULL) AS availability30d,
        (SELECT count(*) FROM server_metrics WHERE at > now() - interval '24 hours') AS samples24h
    ''');
    final versions = await db.query(
      'SELECT COALESCE(app_version, \'inconnue\') AS version, count(*) AS users FROM users '
      'GROUP BY 1 ORDER BY 2 DESC LIMIT 8',
    );
    return jsonOk({
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      ...jsonRow(r!),
      'appVersions': versions.map(jsonRow).toList(),
    });
  }

  /// Activité sur 24 h (par heure), 7 ou 30 jours (par jour).
  Future<Response> _activity(Request req) async {
    await auth.authenticate(req);
    final period = req.url.queryParameters['period'] ?? '7d';
    final List<Map<String, dynamic>> rows;
    if (period == '24h') {
      rows = await db.query('''
        WITH b AS (SELECT generate_series(date_trunc('hour', now()) - interval '23 hours', date_trunc('hour', now()), interval '1 hour') AS t)
        SELECT b.t AS at,
          (SELECT count(DISTINCT user_id) FROM usage_hourly WHERE hour = b.t) AS active_users,
          (SELECT CAST(COALESCE(sum(active_seconds), 0) AS bigint) FROM usage_hourly WHERE hour = b.t) AS usage_seconds,
          (SELECT count(*) FROM login_events WHERE kind = 'user' AND success AND at >= b.t AND at < b.t + interval '1 hour') AS logins,
          (SELECT count(*) FROM login_events WHERE kind = 'user' AND NOT success AND at >= b.t AND at < b.t + interval '1 hour') AS failed_logins,
          (SELECT count(*) FROM users WHERE created_at >= b.t AND created_at < b.t + interval '1 hour') AS new_users
        FROM b ORDER BY b.t
      ''');
    } else {
      final days = period == '30d' ? 30 : 7;
      rows = await db.query('''
        WITH b AS (SELECT CAST(generate_series(current_date - (CAST(@d AS int) - 1), current_date, interval '1 day') AS date) AS t)
        SELECT b.t AS at,
          (SELECT count(*) FROM usage_statistics WHERE day = b.t AND (active_seconds > 0 OR sessions > 0)) AS active_users,
          (SELECT CAST(COALESCE(sum(active_seconds), 0) AS bigint) FROM usage_statistics WHERE day = b.t) AS usage_seconds,
          (SELECT count(*) FROM login_events WHERE kind = 'user' AND success AND CAST(at AS date) = b.t) AS logins,
          (SELECT count(*) FROM login_events WHERE kind = 'user' AND NOT success AND CAST(at AS date) = b.t) AS failed_logins,
          (SELECT count(*) FROM users WHERE CAST(created_at AS date) = b.t) AS new_users
        FROM b ORDER BY b.t
      ''', {'d': days});
    }
    return jsonOk({'period': period, 'points': rows.map(jsonRow).toList()});
  }

  static const _userCols = '''
    u.id, u.pseudonym, u.display_name, u.email, u.status, u.created_at, u.last_login_at, u.last_seen_at,
    u.total_active_seconds, u.country, u.app_version, u.region_consent, u.location_consent,
    (SELECT count(*) FROM devices d WHERE d.user_id = u.id AND d.revoked_at IS NULL) AS devices,
    (SELECT count(*) FROM sessions s WHERE s.user_id = u.id AND s.ended_at IS NULL) AS open_sessions,
    EXISTS (SELECT 1 FROM sessions s WHERE s.user_id = u.id AND s.ended_at IS NULL
      AND s.last_seen_at > now() - $_online) AS online
  ''';

  Future<Response> _users(Request req) async {
    await auth.authenticate(req);
    final q = _q(req, 'q');
    final status = _q(req, 'status');
    final online = _q(req, 'online') == 'true';
    final sort = switch (_q(req, 'sort')) {
      'lastSeen' => 'u.last_seen_at DESC NULLS LAST',
      'usage' => 'u.total_active_seconds DESC',
      'pseudonym' => 'lower(u.pseudonym)',
      _ => 'u.created_at DESC',
    };
    const where = '''
      WHERE (CAST(@q AS text) IS NULL OR u.pseudonym ILIKE '%' || @q || '%' OR u.email ILIKE '%' || @q || '%'
             OR u.display_name ILIKE '%' || @q || '%' OR CAST(u.id AS text) = @q)
        AND (CAST(@st AS text) IS NULL OR u.status = @st)
        AND (NOT CAST(@on AS boolean) OR EXISTS (SELECT 1 FROM sessions s WHERE s.user_id = u.id AND s.ended_at IS NULL
             AND s.last_seen_at > now() - make_interval(secs => 150)))
    ''';
    final params = {
      'q': q?.replaceAll('%', '').replaceAll('_', r'\_'),
      'st': status,
      'on': online,
      'l': _int(req, 'limit', 50, min: 1, max: 500),
      'o': _int(req, 'offset', 0, max: 1000000),
    };
    final total = await db.scalar<int>('SELECT count(*) FROM users u $where', params);
    final rows = await db.query('SELECT $_userCols FROM users u $where ORDER BY $sort LIMIT @l OFFSET @o', params);
    return jsonOk({'total': total, 'items': rows.map(jsonRow).toList()});
  }

  Future<Map<String, dynamic>> _userRow(String id) async {
    final u = await db.one('SELECT $_userCols FROM users u WHERE u.id = CAST(@id AS uuid)', {'id': uuidParam(id)});
    if (u == null) throw ApiError.notFound;
    return u;
  }

  Future<Response> _user(Request req, String id) async {
    await auth.authenticate(req);
    final u = await _userRow(id);
    final p = {'id': id};
    return jsonOk({
      'user': jsonRow(u),
      'devices': (await db.query(
        'SELECT id, installation_id, brand, model, os, os_version, app_version, country, first_seen_at, last_seen_at, '
        'revoked_at, (revoked_at IS NULL AND last_seen_at > now() - $_online) AS online '
        'FROM devices WHERE user_id = CAST(@id AS uuid) ORDER BY last_seen_at DESC',
        p,
      )).map(jsonRow).toList(),
      'sessions': (await db.query(
        'SELECT s.id, s.device_id, s.started_at, s.last_seen_at, s.ended_at, s.end_reason, s.active_seconds, '
        's.app_version, s.country, s.ip_prefix, d.model AS device_model, '
        '(s.ended_at IS NULL AND s.last_seen_at > now() - $_online) AS online '
        'FROM sessions s LEFT JOIN devices d ON d.id = s.device_id WHERE s.user_id = CAST(@id AS uuid) '
        'ORDER BY s.started_at DESC LIMIT 100',
        p,
      )).map(jsonRow).toList(),
      'usage': (await db.query(
        'SELECT day, active_seconds, sessions FROM usage_statistics WHERE user_id = CAST(@id AS uuid) '
        "AND day > current_date - 30 ORDER BY day",
        p,
      )).map(jsonRow).toList(),
      'logins': (await db.query(
        'SELECT at, success, reason, ip_prefix, country FROM login_events WHERE user_id = CAST(@id AS uuid) '
        'ORDER BY at DESC LIMIT 30',
        p,
      )).map(jsonRow).toList(),
      'locations': (await db.query(
        'SELECT at, CAST(lat AS float8) AS lat, CAST(lng AS float8) AS lng, country FROM location_history '
        'WHERE user_id = CAST(@id AS uuid) ORDER BY at DESC LIMIT 50',
        p,
      )).map(jsonRow).toList(),
    });
  }

  /// Informations modifiables par un administrateur : pseudonyme, nom, e-mail.
  Future<Response> _updateUser(Request req, String id) async {
    final a = await auth.authenticate(req, Perm.usersManage);
    await _userRow(id);
    final b = await readJson(req);
    final pseudonym = b.str('pseudonym', max: 32);
    if (pseudonym != null && !RegExp(r'^[A-Za-z0-9_.\-]{3,32}$').hasMatch(pseudonym)) {
      throw ApiError.badRequest('Pseudonyme invalide');
    }
    final email = b.str('email', max: 254)?.toLowerCase();
    if (email != null && !email.contains('@')) throw ApiError.badRequest('Adresse e-mail invalide');
    try {
      await db.exec(
        'UPDATE users SET pseudonym = COALESCE(@p, pseudonym), '
        'display_name = CASE WHEN CAST(@hn AS boolean) THEN CAST(@n AS text) ELSE display_name END, '
        'email = CASE WHEN CAST(@he AS boolean) THEN CAST(@e AS text) ELSE email END, updated_at = now() '
        'WHERE id = CAST(@id AS uuid)',
        {
          'p': pseudonym,
          'hn': b.containsKey('displayName'),
          'n': b.str('displayName', max: 80),
          'he': b.containsKey('email'),
          'e': email,
          'id': id,
        },
      );
    } on ServerException catch (e) {
      if (e.code == '23505') throw const ApiError(409, 'Pseudonyme ou e-mail déjà utilisé', code: 'taken');
      rethrow;
    }
    await ctx.audit(a, 'user.update', targetType: 'user', targetId: id, details: {'fields': b.keys.toList()});
    return jsonOk({'user': jsonRow(await _userRow(id))});
  }

  Future<Response> _setStatus(Request req, String id, String status) async {
    final a = await auth.authenticate(req, Perm.usersManage);
    await _userRow(id);
    await db.tx((t) async {
      await t.exec('UPDATE users SET status = @s, updated_at = now() WHERE id = CAST(@id AS uuid)', {'s': status, 'id': id});
      if (status == 'disabled') {
        await t.exec(
          "UPDATE sessions SET ended_at = now(), end_reason = 'disabled' WHERE user_id = CAST(@id AS uuid) AND ended_at IS NULL",
          {'id': id},
        );
      }
    });
    await ctx.audit(a, status == 'disabled' ? 'user.disable' : 'user.enable', targetType: 'user', targetId: id);
    return jsonOk({'user': jsonRow(await _userRow(id))});
  }

  Future<Response> _revokeUserSessions(Request req, String id) async {
    final a = await auth.authenticate(req, Perm.usersManage);
    await _userRow(id);
    final n = await db.exec(
      "UPDATE sessions SET ended_at = now(), end_reason = 'revoked' WHERE user_id = CAST(@id AS uuid) AND ended_at IS NULL",
      {'id': id},
    );
    await ctx.audit(a, 'user.revoke_sessions', targetType: 'user', targetId: id, details: {'sessions': n});
    return jsonOk({'revoked': n});
  }

  /// Code à usage unique (30 min) à transmettre à l'utilisateur par un canal
  /// sûr ; ses sessions sont fermées. Le code n'est jamais enregistré en clair.
  Future<Response> _resetAccess(Request req, String id) async {
    final a = await auth.authenticate(req, Perm.usersManage);
    await _userRow(id);
    final raw = base32Encode(randomBytes(8)).substring(0, 12);
    final code = '${raw.substring(0, 4)}-${raw.substring(4, 8)}-${raw.substring(8, 12)}';
    final expires = await db.tx((t) async {
      await t.exec('UPDATE password_resets SET used_at = now() WHERE user_id = CAST(@id AS uuid) AND used_at IS NULL', {'id': id});
      final e = await t.scalar<DateTime>(
        'INSERT INTO password_resets (user_id, code_hash, created_by, expires_at) '
        "VALUES (CAST(@id AS uuid), @h, CAST(@by AS uuid), now() + interval '30 minutes') RETURNING expires_at",
        {'id': id, 'h': sha256Hex(raw), 'by': a.id},
      );
      await t.exec(
        "UPDATE sessions SET ended_at = now(), end_reason = 'password_reset' WHERE user_id = CAST(@id AS uuid) AND ended_at IS NULL",
        {'id': id},
      );
      return e;
    });
    await ctx.audit(a, 'user.reset_access', targetType: 'user', targetId: id);
    return jsonOk({'code': code, 'expiresAt': expires.toUtc().toIso8601String()});
  }

  Future<Map<String, Object?>> _userExport(String id) async {
    final p = {'id': id};
    final u = await db.one(
      'SELECT id, pseudonym, display_name, email, status, region_consent, location_consent, country, app_version, '
      'total_active_seconds, created_at, updated_at, last_login_at, last_seen_at FROM users WHERE id = CAST(@id AS uuid)',
      p,
    );
    if (u == null) throw ApiError.notFound;
    Future<List<Map<String, Object?>>> rows(String sql) async => (await db.query(sql, p)).map(jsonRow).toList();
    return {
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'user': jsonRow(u),
      'devices': await rows(
        'SELECT id, installation_id, brand, model, os, os_version, app_version, country, first_seen_at, last_seen_at, '
        'revoked_at FROM devices WHERE user_id = CAST(@id AS uuid)',
      ),
      'sessions': await rows(
        'SELECT id, device_id, started_at, last_seen_at, ended_at, end_reason, active_seconds, app_version, country '
        'FROM sessions WHERE user_id = CAST(@id AS uuid) ORDER BY started_at DESC',
      ),
      'usage': await rows(
        'SELECT day, active_seconds, sessions FROM usage_statistics WHERE user_id = CAST(@id AS uuid) ORDER BY day',
      ),
      'logins': await rows(
        'SELECT at, success, reason, country FROM login_events WHERE user_id = CAST(@id AS uuid) ORDER BY at DESC',
      ),
      'locations': await rows(
        'SELECT at, CAST(lat AS float8) AS lat, CAST(lng AS float8) AS lng, country FROM location_history '
        'WHERE user_id = CAST(@id AS uuid) ORDER BY at DESC',
      ),
    };
  }

  Future<Response> _exportUser(Request req, String id) async {
    final a = await auth.authenticate(req, Perm.export);
    final data = await _userExport(uuidParam(id));
    await ctx.audit(a, 'user.export', targetType: 'user', targetId: id);
    return jsonOk(data);
  }

  /// Liste CSV des comptes (champs autorisés, sans mot de passe ni jeton).
  Future<Response> _exportUsers(Request req) async {
    final a = await auth.authenticate(req, Perm.export);
    final rows = await db.query('SELECT $_userCols FROM users u ORDER BY u.created_at');
    String cell(Object? v) {
      final s = v is DateTime ? v.toUtc().toIso8601String() : (v?.toString() ?? '');
      // Neutralise les formules dans les tableurs.
      final safe = RegExp(r'^[=+\-@]').hasMatch(s) ? "'$s" : s;
      return '"${safe.replaceAll('"', '""')}"';
    }

    const cols = [
      'id',
      'pseudonym',
      'display_name',
      'email',
      'status',
      'created_at',
      'last_login_at',
      'last_seen_at',
      'total_active_seconds',
      'devices',
      'country',
      'app_version',
    ];
    final csv = StringBuffer('\u{FEFF}${cols.join(';')}\r\n');
    for (final r in rows) {
      csv.write('${cols.map((c) => cell(r[c])).join(';')}\r\n');
    }
    await ctx.audit(a, 'users.export', details: {'count': rows.length});
    return Response.ok(
      csv.toString(),
      headers: {
        'content-type': 'text/csv; charset=utf-8',
        'content-disposition': 'attachment; filename="vigiroad-utilisateurs.csv"',
        'cache-control': 'no-store',
      },
    );
  }

  /// Suppression définitive : le pseudonyme doit être confirmé.
  Future<Response> _deleteUser(Request req, String id) async {
    final a = await auth.authenticate(req, Perm.usersDelete);
    final u = await _userRow(id);
    final confirm = req.url.queryParameters['confirm'];
    if (confirm == null || confirm.toLowerCase() != (u['pseudonym'] as String).toLowerCase()) {
      throw const ApiError(400, 'Confirmez la suppression en saisissant le pseudonyme', code: 'confirm');
    }
    await db.exec('DELETE FROM users WHERE id = CAST(@id AS uuid)', {'id': id});
    await ctx.audit(a, 'user.delete', targetType: 'user', targetId: id, details: {'pseudonym': u['pseudonym']});
    return jsonOk({'deleted': true});
  }

  Future<Response> _devices(Request req) async {
    await auth.authenticate(req);
    final params = {
      'q': _q(req, 'q')?.replaceAll('%', ''),
      'u': _q(req, 'userId') == null ? null : uuidParam(_q(req, 'userId')!),
      'on': _q(req, 'online') == 'true',
      'rev': _q(req, 'revoked') == 'true',
      'l': _int(req, 'limit', 100, min: 1, max: 500),
      'o': _int(req, 'offset', 0, max: 1000000),
    };
    final where = '''
      WHERE (CAST(@q AS text) IS NULL OR d.model ILIKE '%' || @q || '%' OR d.brand ILIKE '%' || @q || '%'
             OR u.pseudonym ILIKE '%' || @q || '%' OR d.installation_id = @q OR CAST(d.id AS text) = @q)
        AND (CAST(@u AS uuid) IS NULL OR d.user_id = CAST(@u AS uuid))
        AND (CAST(@rev AS boolean) OR d.revoked_at IS NULL)
        AND (NOT CAST(@on AS boolean) OR (d.revoked_at IS NULL AND d.last_seen_at > now() - $_online))
    ''';
    final total = await db.scalar<int>('SELECT count(*) FROM devices d JOIN users u ON u.id = d.user_id $where', params);
    final rows = await db.query(
      'SELECT d.id, d.user_id, u.pseudonym, d.installation_id, d.brand, d.model, d.os, d.os_version, d.app_version, '
      'd.country, d.first_seen_at, d.last_seen_at, d.revoked_at, '
      '(d.revoked_at IS NULL AND d.last_seen_at > now() - $_online) AS online, '
      '(SELECT count(*) FROM sessions s WHERE s.device_id = d.id) AS sessions '
      'FROM devices d JOIN users u ON u.id = d.user_id $where ORDER BY d.last_seen_at DESC LIMIT @l OFFSET @o',
      params,
    );
    return jsonOk({'total': total, 'items': rows.map(jsonRow).toList()});
  }

  Future<Response> _device(Request req, String id) async {
    await auth.authenticate(req);
    final d = await db.one(
      'SELECT d.*, u.pseudonym, (d.revoked_at IS NULL AND d.last_seen_at > now() - $_online) AS online '
      'FROM devices d JOIN users u ON u.id = d.user_id WHERE d.id = CAST(@id AS uuid)',
      {'id': uuidParam(id)},
    );
    if (d == null) throw ApiError.notFound;
    final sessions = await db.query(
      'SELECT id, started_at, last_seen_at, ended_at, end_reason, active_seconds, app_version, country, '
      '(ended_at IS NULL AND last_seen_at > now() - $_online) AS online '
      'FROM sessions WHERE device_id = CAST(@id AS uuid) ORDER BY started_at DESC LIMIT 100',
      {'id': id},
    );
    return jsonOk({'device': jsonRow(d), 'sessions': sessions.map(jsonRow).toList()});
  }

  Future<Response> _revokeDevice(Request req, String id) async {
    final a = await auth.authenticate(req, Perm.usersManage);
    final n = await db.tx((t) async {
      final n = await t.exec(
        'UPDATE devices SET revoked_at = now() WHERE id = CAST(@id AS uuid) AND revoked_at IS NULL',
        {'id': uuidParam(id)},
      );
      await t.exec(
        "UPDATE sessions SET ended_at = now(), end_reason = 'device_revoked' WHERE device_id = CAST(@id AS uuid) AND ended_at IS NULL",
        {'id': id},
      );
      return n;
    });
    if (n == 0) throw ApiError.notFound;
    await ctx.audit(a, 'device.revoke', targetType: 'device', targetId: id);
    return jsonOk({'ok': true});
  }

  Future<Response> _sessions(Request req) async {
    await auth.authenticate(req);
    final state = _q(req, 'state') ?? 'open';
    final stateSql = switch (state) {
      'online' => 's.ended_at IS NULL AND s.last_seen_at > now() - $_online',
      'ended' => 's.ended_at IS NOT NULL',
      'all' => 'true',
      _ => 's.ended_at IS NULL',
    };
    final params = {
      'u': _q(req, 'userId') == null ? null : uuidParam(_q(req, 'userId')!),
      'd': _q(req, 'deviceId') == null ? null : uuidParam(_q(req, 'deviceId')!),
      'l': _int(req, 'limit', 100, min: 1, max: 500),
      'o': _int(req, 'offset', 0, max: 1000000),
    };
    final where = 'WHERE $stateSql AND (CAST(@u AS uuid) IS NULL OR s.user_id = CAST(@u AS uuid)) '
        'AND (CAST(@d AS uuid) IS NULL OR s.device_id = CAST(@d AS uuid))';
    final total = await db.scalar<int>('SELECT count(*) FROM sessions s $where', params);
    final rows = await db.query(
      'SELECT s.id, s.user_id, u.pseudonym, s.device_id, d.brand, d.model, d.os, s.started_at, s.last_seen_at, '
      's.ended_at, s.end_reason, s.active_seconds, s.app_version, s.country, s.ip_prefix, '
      '(s.ended_at IS NULL AND s.last_seen_at > now() - $_online) AS online, '
      'CAST(EXTRACT(EPOCH FROM COALESCE(s.ended_at, s.last_seen_at) - s.started_at) AS bigint) AS span_seconds '
      'FROM sessions s JOIN users u ON u.id = s.user_id LEFT JOIN devices d ON d.id = s.device_id '
      '$where ORDER BY s.last_seen_at DESC LIMIT @l OFFSET @o',
      params,
    );
    return jsonOk({'total': total, 'state': state, 'items': rows.map(jsonRow).toList()});
  }

  /// Comptes connectés simultanément depuis plusieurs appareils ou sessions.
  Future<Response> _concurrent(Request req) async {
    await auth.authenticate(req);
    final rows = await db.query('''
      SELECT u.id AS user_id, u.pseudonym, count(*) AS sessions,
             count(DISTINCT s.device_id) AS devices, string_agg(DISTINCT COALESCE(s.country, '?'), ', ') AS countries,
             max(s.last_seen_at) AS last_seen_at
      FROM sessions s JOIN users u ON u.id = s.user_id
      WHERE s.ended_at IS NULL AND s.last_seen_at > now() - $_online
      GROUP BY u.id, u.pseudonym HAVING count(*) > 1 ORDER BY count(*) DESC
    ''');
    return jsonOk({'items': rows.map(jsonRow).toList()});
  }

  Future<Response> _revokeSession(Request req, String id) async {
    final a = await auth.authenticate(req, Perm.usersManage);
    final n = await db.exec(
      "UPDATE sessions SET ended_at = now(), end_reason = 'revoked' WHERE id = CAST(@id AS uuid) AND ended_at IS NULL",
      {'id': uuidParam(id)},
    );
    if (n == 0) throw ApiError.notFound;
    await ctx.audit(a, 'session.revoke', targetType: 'session', targetId: id);
    return jsonOk({'ok': true});
  }

  Future<Response> _loginEvents(Request req) async {
    await auth.authenticate(req);
    final success = _q(req, 'success');
    final params = {
      'k': _q(req, 'kind'),
      's': success == null ? null : success == 'true',
      'u': _q(req, 'userId') == null ? null : uuidParam(_q(req, 'userId')!),
      'l': _int(req, 'limit', 100, min: 1, max: 1000),
      'o': _int(req, 'offset', 0, max: 1000000),
    };
    const where = 'WHERE (CAST(@k AS text) IS NULL OR e.kind = @k) AND (CAST(@s AS boolean) IS NULL OR e.success = @s) '
        'AND (CAST(@u AS uuid) IS NULL OR e.user_id = CAST(@u AS uuid))';
    final total = await db.scalar<int>('SELECT count(*) FROM login_events e $where', params);
    final rows = await db.query(
      'SELECT e.id, e.at, e.kind, e.user_id, u.pseudonym, e.admin_id, a.email AS admin_email, e.success, e.reason, '
      'e.ip_prefix, e.country FROM login_events e LEFT JOIN users u ON u.id = e.user_id '
      'LEFT JOIN admin_accounts a ON a.id = e.admin_id $where ORDER BY e.at DESC LIMIT @l OFFSET @o',
      params,
    );
    final summary = await db.one('''
      SELECT count(*) FILTER (WHERE NOT success AND at > now() - interval '24 hours') AS failed24h,
             count(*) FILTER (WHERE NOT success AND at > now() - interval '7 days') AS failed7d,
             count(*) FILTER (WHERE success AND at > now() - interval '24 hours') AS success24h
      FROM login_events
    ''');
    return jsonOk({'total': total, 'summary': jsonRow(summary!), 'items': rows.map(jsonRow).toList()});
  }

  /// Répartition par pays (consentement « région ») et positions
  /// approximatives agrégées (consentement « localisation »).
  Future<Response> _geo(Request req) async {
    await auth.authenticate(req);
    final days = _int(req, 'days', 30, min: 1, max: 365);
    final countries = await db.query('''
      SELECT c.country,
        (SELECT count(*) FROM users u WHERE u.country = c.country) AS users,
        (SELECT count(*) FROM sessions s WHERE s.country = c.country AND s.started_at > now() - make_interval(days => CAST(@d AS int))) AS sessions,
        (SELECT count(*) FROM login_events e WHERE e.kind = 'user' AND e.success AND e.country = c.country
           AND e.at > now() - make_interval(days => CAST(@d AS int))) AS logins
      FROM (SELECT DISTINCT country FROM users WHERE country IS NOT NULL
            UNION SELECT DISTINCT country FROM sessions WHERE country IS NOT NULL) c
      ORDER BY users DESC, sessions DESC
    ''', {'d': days});
    final points = await db.query('''
      SELECT CAST(round(lat, 1) AS float8) AS lat, CAST(round(lng, 1) AS float8) AS lng, count(*) AS samples,
             count(DISTINCT user_id) AS users
      FROM location_history WHERE at > now() - make_interval(days => CAST(@d AS int))
      GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 2000
    ''', {'d': days});
    final consent = await db.one('''
      SELECT count(*) FILTER (WHERE region_consent) AS region, count(*) FILTER (WHERE location_consent) AS location,
             count(*) AS total FROM users
    ''');
    return jsonOk({
      'days': days,
      'countries': countries.map(jsonRow).toList(),
      'points': points.map(jsonRow).toList(),
      'consents': jsonRow(consent!),
      'geoIp': {'available': ctx.geo.available, 'ranges': ctx.geo.ranges, 'attribution': GeoIp.attribution},
      'settings': await ctx.settings(),
    });
  }

  static const _editableSettings = {
    'retention.login_events_days': (7, 3650),
    'retention.sessions_days': (30, 3650),
    'retention.location_days': (1, 365),
    'retention.metrics_days': (7, 365),
    'retention.audit_days': (90, 3650),
    'sessions.idle_expiry_days': (1, 365),
    'backups.keep': (3, 90),
    'retention.version_events_days': (7, 3650),
  };

  Future<Response> _settings(Request req) async {
    await auth.authenticate(req);
    return jsonOk({
      'settings': await ctx.settings(),
      'limits': {for (final e in _editableSettings.entries) e.key: [e.value.$1, e.value.$2]},
    });
  }

  Future<Response> _putSettings(Request req) async {
    final a = await auth.authenticate(req, Perm.settings);
    final b = await readJson(req);
    final changed = <String, Object?>{};
    for (final e in b.entries) {
      final Object value;
      if (e.key == 'geo.enabled') {
        if (e.value is! bool) throw ApiError.badRequest('geo.enabled : booléen attendu');
        value = e.value as bool;
      } else {
        final range = _editableSettings[e.key];
        if (range == null) throw ApiError.badRequest('Réglage inconnu : ${e.key}');
        final v = e.value;
        if (v is! int || v < range.$1 || v > range.$2) {
          throw ApiError.badRequest('${e.key} : entier entre ${range.$1} et ${range.$2} attendu');
        }
        value = v;
      }
      await db.exec(
        'INSERT INTO settings (key, value, updated_at, updated_by) VALUES (@k, CAST(@v AS jsonb), now(), CAST(@a AS uuid)) '
        'ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = EXCLUDED.updated_by',
        {'k': e.key, 'v': jsonEncode(value), 'a': a.id},
      );
      changed[e.key] = value;
    }
    await ctx.audit(a, 'settings.update', details: changed);
    return jsonOk({'settings': await ctx.settings()});
  }

  Future<Response> _audit(Request req) async {
    await auth.authenticate(req);
    final params = {
      'a': _q(req, 'action'),
      'l': _int(req, 'limit', 100, min: 1, max: 1000),
      'o': _int(req, 'offset', 0, max: 1000000),
    };
    const where = "WHERE (CAST(@a AS text) IS NULL OR action LIKE @a || '%')";
    final total = await db.scalar<int>('SELECT count(*) FROM admin_audit_logs $where', params);
    final rows = await db.query(
      'SELECT id, at, admin_id, admin_email, action, target_type, target_id, success, details, ip_prefix '
      'FROM admin_audit_logs $where ORDER BY at DESC LIMIT @l OFFSET @o',
      params,
    );
    return jsonOk({'total': total, 'items': rows.map(jsonRow).toList()});
  }
}

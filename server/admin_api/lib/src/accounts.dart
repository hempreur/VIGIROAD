import 'package:postgres/postgres.dart' show ServerException;
import 'package:shelf/shelf.dart';

import 'context.dart';
import 'db.dart';
import 'http_kit.dart';
import 'security.dart';

/// Utilisateur mobile authentifié (jeton de session).
class UserPrincipal {
  const UserPrincipal(this.userId, this.sessionId, this.deviceId, this.regionConsent, this.locationConsent);

  final String userId;
  final String sessionId;
  final String? deviceId;
  final bool regionConsent;
  final bool locationConsent;
}

/// Comptes de l'application mobile : inscription, connexion, appareil,
/// battements de cœur (temps d'utilisation réel), déconnexion, export et
/// suppression des données. Aucune image, plaque ni voix n'est reçue ici.
class AccountService {
  AccountService(this.ctx)
    : _registerLimiter = SlidingLimiter(max: ctx.config.registerLimitPerHour, window: const Duration(hours: 1));

  final AppContext ctx;
  Db get db => ctx.db;

  final SlidingLimiter _registerLimiter;
  final _loginIpLimiter = SlidingLimiter(max: 30, window: const Duration(minutes: 15));
  final _loginIdLimiter = SlidingLimiter(max: 10, window: const Duration(minutes: 15));

  /// Une session sans battement depuis cette durée n'est plus « connectée ».
  static const onlineWindowSeconds = 150;

  /// Écart maximal entre deux battements compté comme utilisation continue.
  static const maxHeartbeatGapSeconds = 90;
  static const heartbeatEverySeconds = 60;

  static final _pseudonymRe = RegExp(r'^[A-Za-z0-9_.\-]{3,32}$');
  static final _emailRe = RegExp(r'^[^@\s]{1,64}@[^@\s]+\.[^@\s]{2,}$');

  void register(Router r) {
    r.post('/v1/account/register', (req, _) => _register(req));
    r.post('/v1/account/login', (req, _) => _login(req));
    r.post('/v1/account/reset', (req, _) => _reset(req));
    r.post('/v1/account/logout', (req, _) => _logout(req));
    r.post('/v1/account/heartbeat', (req, _) => _heartbeat(req));
    r.get('/v1/account/me', (req, _) => _me(req));
    r.patch('/v1/account/me', (req, _) => _update(req));
    r.delete('/v1/account/me', (req, _) => _delete(req));
    r.post('/v1/account/me/delete', (req, _) => _delete(req));
    r.get('/v1/account/data', (req, _) => _export(req));
    r.post('/v1/account/device', (req, _) => _device(req));
    r.delete('/v1/account/device', (req, _) => _forgetDevice(req));
    r.get('/v1/account/sessions', (req, _) => _sessions(req));
    r.post('/v1/account/sessions/:id/revoke', (req, p) => _revokeOwn(req, p['id']!));
    r.delete('/v1/account/location', (req, _) => _clearLocation(req));
  }

  void _requireAppKey(Request req) {
    final key = req.headers['x-api-key'] ?? '';
    if (!ctx.config.appKeys.any((k) => secureEquals(k, key))) {
      throw const ApiError(401, 'Application non reconnue', code: 'app_key');
    }
  }

  Future<Response> _register(Request req) async {
    _requireAppKey(req);
    final ip = clientIp(req);
    if (!_registerLimiter.allow(ipPrefix(ip) ?? '?')) throw ApiError.tooMany;
    final b = await readJson(req);
    final pseudonym = b.need('pseudonym', max: 32);
    if (!_pseudonymRe.hasMatch(pseudonym)) {
      throw ApiError.badRequest('Pseudonyme : 3 à 32 lettres, chiffres, « . », « _ » ou « - »');
    }
    final email = b.str('email', max: 254)?.toLowerCase();
    if (email != null && !_emailRe.hasMatch(email)) throw ApiError.badRequest('Adresse e-mail invalide');
    final password = b.need('password', max: 128);
    final weak = PasswordHasher.validate(password);
    if (weak != null) throw ApiError.badRequest(weak);
    final displayName = b.str('displayName', max: 80);
    final consents = b['consents'] is Map<String, dynamic> ? b['consents'] as Map<String, dynamic> : <String, dynamic>{};
    final region = consents.flag('region') ?? false;
    final location = consents.flag('location') ?? false;

    if (await db.one('SELECT 1 FROM users WHERE lower(pseudonym) = lower(@p)', {'p': pseudonym}) != null) {
      throw const ApiError(409, 'Ce pseudonyme est déjà utilisé', code: 'pseudonym_taken');
    }
    if (email != null && await db.one('SELECT 1 FROM users WHERE lower(email) = @e', {'e': email}) != null) {
      throw const ApiError(409, 'Cette adresse e-mail est déjà utilisée', code: 'email_taken');
    }
    final hash = await ctx.hasher.hash(password);
    final String userId;
    try {
      userId = await db.scalar<String>(
        'INSERT INTO users (pseudonym, display_name, email, password_hash, region_consent, location_consent, app_version) '
        'VALUES (@p, @d, @e, @h, @rc, @lc, @v) RETURNING id',
        {
          'p': pseudonym,
          'd': displayName,
          'e': email,
          'h': hash,
          'rc': region,
          'lc': location,
          'v': b.str('appVersion', max: 32),
        },
      );
    } on ServerException catch (e) {
      if (e.code == '23505') throw const ApiError(409, 'Ce compte existe déjà', code: 'taken');
      rethrow;
    }
    final out = await _openSession(req, userId, b, regionConsent: region);
    await _loginEvent(userId, true, 'register', ip, out.$3, regionConsent: region);
    return jsonOk({'token': out.$1, 'sessionId': out.$2, 'deviceId': out.$3, 'user': await _profile(userId)}, status: 201);
  }

  Future<Response> _login(Request req) async {
    _requireAppKey(req);
    final ip = clientIp(req);
    final b = await readJson(req);
    final login = b.need('login', max: 254).toLowerCase();
    final password = b.need('password', max: 128);
    if (!_loginIpLimiter.allow(ipPrefix(ip) ?? '?') || !_loginIdLimiter.allow(login)) {
      await _loginEvent(null, false, 'rate_limited', ip, null);
      throw ApiError.tooMany;
    }
    final u = await db.one(
      'SELECT id, password_hash, status, region_consent FROM users WHERE lower(pseudonym) = @l OR lower(email) = @l',
      {'l': login},
    );
    if (u == null) {
      await ctx.hasher.dummyVerify(password);
      await _loginEvent(null, false, 'unknown_account', ip, null);
      throw const ApiError(401, 'Identifiant ou mot de passe incorrect', code: 'bad_credentials');
    }
    final userId = u['id'] as String;
    if (!await ctx.hasher.verify(password, u['password_hash'] as String)) {
      await _loginEvent(userId, false, 'bad_password', ip, null);
      throw const ApiError(401, 'Identifiant ou mot de passe incorrect', code: 'bad_credentials');
    }
    if (u['status'] != 'active') {
      await _loginEvent(userId, false, 'disabled', ip, null);
      throw const ApiError(403, 'Ce compte est désactivé', code: 'disabled');
    }
    _loginIdLimiter.reset(login);
    final region = u['region_consent'] as bool;
    final out = await _openSession(req, userId, b, regionConsent: region);
    await _loginEvent(userId, true, 'password', ip, out.$3, regionConsent: region);
    return jsonOk({'token': out.$1, 'sessionId': out.$2, 'deviceId': out.$3, 'user': await _profile(userId)});
  }

  /// Code de réinitialisation remis par un administrateur.
  Future<Response> _reset(Request req) async {
    _requireAppKey(req);
    final ip = clientIp(req);
    final b = await readJson(req);
    final login = b.need('login', max: 254).toLowerCase();
    final code = b.need('code', max: 32).toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final password = b.need('newPassword', max: 128);
    final weak = PasswordHasher.validate(password);
    if (weak != null) throw ApiError.badRequest(weak);
    if (!_loginIdLimiter.allow('reset:$login')) throw ApiError.tooMany;
    final r = await db.one(
      'SELECT pr.id, pr.user_id FROM password_resets pr JOIN users u ON u.id = pr.user_id '
      'WHERE (lower(u.pseudonym) = @l OR lower(u.email) = @l) AND pr.code_hash = @c '
      'AND pr.used_at IS NULL AND pr.expires_at > now()',
      {'l': login, 'c': sha256Hex(code)},
    );
    if (r == null) {
      await _loginEvent(null, false, 'bad_reset_code', ip, null);
      throw const ApiError(400, 'Code invalide ou expiré', code: 'bad_code');
    }
    final hash = await ctx.hasher.hash(password);
    await db.tx((t) async {
      await t.exec('UPDATE users SET password_hash = @h, updated_at = now() WHERE id = CAST(@u AS uuid)', {
        'h': hash,
        'u': r['user_id'],
      });
      await t.exec('UPDATE password_resets SET used_at = now() WHERE id = CAST(@id AS uuid)', {'id': r['id']});
      await t.exec(
        "UPDATE sessions SET ended_at = now(), end_reason = 'password_reset' WHERE user_id = CAST(@u AS uuid) AND ended_at IS NULL",
        {'u': r['user_id']},
      );
    });
    await _loginEvent(r['user_id'] as String, true, 'password_reset', ip, null);
    return jsonOk({'ok': true});
  }

  /// Ouvre une session (et enregistre l'appareil si l'utilisateur l'a choisi).
  Future<(String, String, String?)> _openSession(
    Request req,
    String userId,
    Map<String, dynamic> body, {
    required bool regionConsent,
  }) async {
    final ip = clientIp(req);
    final country = regionConsent ? ctx.geo.country(ip) : null;
    final token = newToken('vrs');
    String? deviceId;
    final device = body['device'];
    if (device is Map<String, dynamic>) deviceId = await _upsertDevice(userId, device, country);
    final appVersion = body.str('appVersion', max: 32) ?? (device is Map<String, dynamic> ? device.str('appVersion', max: 32) : null);
    final sessionId = await db.tx((t) async {
      final id = await t.scalar<String>(
        'INSERT INTO sessions (user_id, device_id, token_hash, app_version, country, ip_prefix) '
        'VALUES (CAST(@u AS uuid), CAST(@d AS uuid), @h, @v, @c, @ip) RETURNING id',
        {'u': userId, 'd': deviceId, 'h': sha256Hex(token), 'v': appVersion, 'c': country, 'ip': ipPrefix(ip)},
      );
      await t.exec(
        'UPDATE users SET last_login_at = now(), last_seen_at = now(), app_version = COALESCE(@v, app_version), '
        'country = COALESCE(@c, country) WHERE id = CAST(@u AS uuid)',
        {'u': userId, 'v': appVersion, 'c': country},
      );
      await t.exec(
        'INSERT INTO usage_statistics (day, user_id, sessions) VALUES (current_date, CAST(@u AS uuid), 1) '
        'ON CONFLICT (day, user_id) DO UPDATE SET sessions = usage_statistics.sessions + 1',
        {'u': userId},
      );
      return id;
    });
    return (token, sessionId, deviceId);
  }

  Future<String> _upsertDevice(String userId, Map<String, dynamic> d, String? country) async {
    final installation = d.need('installationId', max: 64);
    if (installation.length < 16) throw ApiError.badRequest('installationId : 16 caractères minimum');
    final os = switch (d.str('os', max: 16)?.toLowerCase()) {
      'android' => 'android',
      'ios' => 'ios',
      _ => 'other',
    };
    final params = {
      'u': userId,
      'i': installation,
      'b': d.str('brand', max: 64),
      'm': d.str('model', max: 64),
      'o': os,
      'ov': d.str('osVersion', max: 32),
      'v': d.str('appVersion', max: 32),
      'c': country,
    };
    final existing = await db.one('SELECT id FROM devices WHERE installation_id = @i AND revoked_at IS NULL', params);
    if (existing != null) {
      await db.exec(
        'UPDATE devices SET user_id = CAST(@u AS uuid), brand = @b, model = @m, os = @o, os_version = @ov, '
        'app_version = @v, country = COALESCE(@c, country), last_seen_at = now() WHERE id = CAST(@id AS uuid)',
        {...params, 'id': existing['id']},
      );
      return existing['id'] as String;
    }
    return db.scalar<String>(
      'INSERT INTO devices (user_id, installation_id, brand, model, os, os_version, app_version, country) '
      'VALUES (CAST(@u AS uuid), @i, @b, @m, @o, @ov, @v, @c) RETURNING id',
      params,
    );
  }

  Future<void> _loginEvent(String? userId, bool ok, String reason, String? ip, String? deviceId,
      {bool regionConsent = false}) async {
    await db.exec(
      "INSERT INTO login_events (kind, user_id, device_id, success, reason, ip_prefix, country) "
      "VALUES ('user', CAST(@u AS uuid), CAST(@d AS uuid), @s, @r, @ip, @c)",
      {
        'u': userId,
        'd': deviceId,
        's': ok,
        'r': reason,
        'ip': ipPrefix(ip),
        'c': regionConsent ? ctx.geo.country(ip) : null,
      },
    );
  }

  /// Vérifie le jeton : session ouverte, non expirée, compte actif.
  Future<UserPrincipal> authenticate(Request req) async {
    final h = req.headers['authorization'] ?? '';
    if (!h.startsWith('Bearer vrs_')) throw ApiError.unauthorized;
    final token = h.substring(7).trim();
    final idleDays = await ctx.intSetting('sessions.idle_expiry_days', 30);
    final s = await db.one(
      'SELECT s.id, s.user_id, s.device_id, s.ended_at, s.end_reason, u.status, u.region_consent, u.location_consent, '
      'd.revoked_at AS device_revoked, (s.last_seen_at < now() - make_interval(days => CAST(@idle AS int))) AS idle '
      'FROM sessions s JOIN users u ON u.id = s.user_id LEFT JOIN devices d ON d.id = s.device_id '
      'WHERE s.token_hash = @h',
      {'h': sha256Hex(token), 'idle': idleDays},
    );
    if (s == null) throw const ApiError(401, 'Session inconnue', code: 'revoked');
    if (s['ended_at'] != null) {
      throw ApiError(401, 'Session terminée (${s['end_reason']})', code: s['end_reason'] == 'logout' ? 'logged_out' : 'revoked');
    }
    if (s['idle'] == true) {
      await db.exec("UPDATE sessions SET ended_at = now(), end_reason = 'expired' WHERE id = CAST(@id AS uuid)", {'id': s['id']});
      throw const ApiError(401, 'Session expirée après une longue inactivité', code: 'expired');
    }
    if (s['status'] != 'active' || s['device_revoked'] != null) {
      await db.exec(
        'UPDATE sessions SET ended_at = now(), end_reason = @r WHERE id = CAST(@id AS uuid)',
        {'id': s['id'], 'r': s['status'] != 'active' ? 'disabled' : 'device_revoked'},
      );
      throw const ApiError(401, 'Accès révoqué', code: 'revoked');
    }
    return UserPrincipal(
      s['user_id'] as String,
      s['id'] as String,
      s['device_id'] as String?,
      s['region_consent'] as bool,
      s['location_consent'] as bool,
    );
  }

  /// Battement de cœur (toutes les 60 s, application au premier plan) : le
  /// temps écoulé depuis le précédent compte comme utilisation s'il est
  /// inférieur à 90 s ; au-delà, l'application était fermée.
  Future<Response> _heartbeat(Request req) async {
    final p = await authenticate(req);
    final b = await readJson(req);
    final ip = clientIp(req);
    final country = p.regionConsent ? ctx.geo.country(ip) : null;
    final appVersion = b.str('appVersion', max: 32);
    final added = await db.tx((t) async {
      final gap = await t.scalar<double>(
        'SELECT CAST(EXTRACT(EPOCH FROM now() - last_seen_at) AS float8) FROM sessions WHERE id = CAST(@s AS uuid) FOR UPDATE',
        {'s': p.sessionId},
      );
      final add = gap > 0 && gap <= maxHeartbeatGapSeconds ? gap.round() : 0;
      await t.exec(
        'UPDATE sessions SET last_seen_at = now(), active_seconds = active_seconds + @a, heartbeats = heartbeats + 1, '
        'app_version = COALESCE(@v, app_version), country = COALESCE(@c, country) WHERE id = CAST(@s AS uuid)',
        {'a': add, 'v': appVersion, 'c': country, 's': p.sessionId},
      );
      await t.exec(
        'INSERT INTO usage_statistics (day, user_id, active_seconds, heartbeats) VALUES (current_date, CAST(@u AS uuid), @a, 1) '
        'ON CONFLICT (day, user_id) DO UPDATE SET active_seconds = usage_statistics.active_seconds + @a, '
        'heartbeats = usage_statistics.heartbeats + 1',
        {'u': p.userId, 'a': add},
      );
      if (add > 0) {
        await t.exec(
          "INSERT INTO usage_hourly (hour, user_id, active_seconds) VALUES (date_trunc('hour', now()), CAST(@u AS uuid), @a) "
          'ON CONFLICT (hour, user_id) DO UPDATE SET active_seconds = usage_hourly.active_seconds + @a',
          {'u': p.userId, 'a': add},
        );
      }
      await t.exec(
        'UPDATE users SET last_seen_at = now(), total_active_seconds = total_active_seconds + @a, '
        'app_version = COALESCE(@v, app_version), country = COALESCE(@c, country) WHERE id = CAST(@u AS uuid)',
        {'u': p.userId, 'a': add, 'v': appVersion, 'c': country},
      );
      if (p.deviceId != null) {
        await t.exec(
          'UPDATE devices SET last_seen_at = now(), app_version = COALESCE(@v, app_version), '
          'country = COALESCE(@c, country) WHERE id = CAST(@d AS uuid)',
          {'d': p.deviceId, 'v': appVersion, 'c': country},
        );
      }
      return add;
    });

    // Position approximative : uniquement avec consentement, arrondie à
    // 0,05° (~5 km), au plus une fois toutes les 15 minutes.
    final loc = b['location'];
    var locationStored = false;
    if (p.locationConsent && loc is Map<String, dynamic>) {
      final lat = loc.number('lat')?.toDouble(), lng = loc.number('lng')?.toDouble();
      if (lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180) {
        final n = await db.exec(
          'INSERT INTO location_history (user_id, lat, lng, country) SELECT CAST(@u AS uuid), CAST(@lat AS float8), CAST(@lng AS float8), CAST(@c AS text) '
          "WHERE NOT EXISTS (SELECT 1 FROM location_history WHERE user_id = CAST(@u AS uuid) AND at > now() - interval '15 minutes')",
          {'u': p.userId, 'lat': _round(lat), 'lng': _round(lng), 'c': country},
        );
        locationStored = n > 0;
      }
    }
    return jsonOk({'ok': true, 'countedSeconds': added, 'nextInSeconds': heartbeatEverySeconds, 'locationStored': locationStored});
  }

  static double _round(double v) => (v / 0.05).round() * 0.05;

  Future<Response> _logout(Request req) async {
    final p = await authenticate(req);
    await db.exec("UPDATE sessions SET ended_at = now(), end_reason = 'logout' WHERE id = CAST(@s AS uuid)", {'s': p.sessionId});
    return jsonOk({'ok': true});
  }

  Future<Map<String, Object?>> _profile(String userId) async {
    final u = await db.one(
      'SELECT id, pseudonym, display_name, email, status, region_consent, location_consent, country, created_at, '
      'last_login_at, total_active_seconds FROM users WHERE id = CAST(@u AS uuid)',
      {'u': userId},
    );
    if (u == null) throw ApiError.notFound;
    final j = jsonRow(u);
    j.remove('regionConsent');
    j.remove('locationConsent');
    j['consents'] = {'region': u['region_consent'], 'location': u['location_consent']};
    return j;
  }

  Future<Response> _me(Request req) async {
    final p = await authenticate(req);
    final devices = await db.query(
      'SELECT id, brand, model, os, os_version, app_version, first_seen_at, last_seen_at FROM devices '
      'WHERE user_id = CAST(@u AS uuid) AND revoked_at IS NULL ORDER BY last_seen_at DESC',
      {'u': p.userId},
    );
    return jsonOk({
      'user': await _profile(p.userId),
      'sessionId': p.sessionId,
      'deviceId': p.deviceId,
      'devices': devices.map(jsonRow).toList(),
    });
  }

  Future<Response> _update(Request req) async {
    final p = await authenticate(req);
    final b = await readJson(req);
    final pseudonym = b.str('pseudonym', max: 32);
    if (pseudonym != null && !_pseudonymRe.hasMatch(pseudonym)) throw ApiError.badRequest('Pseudonyme invalide');
    final email = b.containsKey('email') ? b.str('email', max: 254)?.toLowerCase() : null;
    if (email != null && !_emailRe.hasMatch(email)) throw ApiError.badRequest('Adresse e-mail invalide');
    final consents = b['consents'] is Map<String, dynamic> ? b['consents'] as Map<String, dynamic> : <String, dynamic>{};
    final region = consents.flag('region'), location = consents.flag('location');
    try {
      await db.tx((t) async {
        await t.exec(
          'UPDATE users SET pseudonym = COALESCE(@p, pseudonym), '
          'display_name = CASE WHEN CAST(@hasName AS boolean) THEN CAST(@d AS text) ELSE display_name END, '
          'email = CASE WHEN CAST(@hasEmail AS boolean) THEN CAST(@e AS text) ELSE email END, '
          'region_consent = COALESCE(@rc, region_consent), location_consent = COALESCE(@lc, location_consent), '
          'updated_at = now() WHERE id = CAST(@u AS uuid)',
          {
            'p': pseudonym,
            'hasName': b.containsKey('displayName'),
            'd': b.str('displayName', max: 80),
            'hasEmail': b.containsKey('email'),
            'e': email,
            'rc': region,
            'lc': location,
            'u': p.userId,
          },
        );
        // Retrait du consentement : les données correspondantes sont effacées.
        if (region == false) {
          await t.exec('UPDATE users SET country = NULL WHERE id = CAST(@u AS uuid)', {'u': p.userId});
          await t.exec('UPDATE devices SET country = NULL WHERE user_id = CAST(@u AS uuid)', {'u': p.userId});
          await t.exec('UPDATE sessions SET country = NULL WHERE user_id = CAST(@u AS uuid)', {'u': p.userId});
          await t.exec('UPDATE login_events SET country = NULL WHERE user_id = CAST(@u AS uuid)', {'u': p.userId});
        }
        if (location == false) {
          await t.exec('DELETE FROM location_history WHERE user_id = CAST(@u AS uuid)', {'u': p.userId});
        }
      });
    } on ServerException catch (e) {
      if (e.code == '23505') throw const ApiError(409, 'Pseudonyme ou e-mail déjà utilisé', code: 'taken');
      rethrow;
    }
    return jsonOk({'user': await _profile(p.userId)});
  }

  /// Suppression définitive du compte et de toutes ses données (mot de passe
  /// demandé).
  Future<Response> _delete(Request req) async {
    final p = await authenticate(req);
    final b = await readJson(req);
    final hash = await db.scalar<String>('SELECT password_hash FROM users WHERE id = CAST(@u AS uuid)', {'u': p.userId});
    if (!await ctx.hasher.verify(b.need('password', max: 128), hash)) {
      throw const ApiError(403, 'Mot de passe incorrect', code: 'bad_credentials');
    }
    await db.exec('DELETE FROM users WHERE id = CAST(@u AS uuid)', {'u': p.userId});
    return jsonOk({'deleted': true});
  }

  /// Copie de toutes les données enregistrées sur le compte.
  Future<Response> _export(Request req) async {
    final p = await authenticate(req);
    final u = {'u': p.userId};
    return jsonOk({
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'user': await _profile(p.userId),
      'devices': (await db.query(
        'SELECT id, installation_id, brand, model, os, os_version, app_version, country, first_seen_at, last_seen_at, revoked_at '
        'FROM devices WHERE user_id = CAST(@u AS uuid)',
        u,
      )).map(jsonRow).toList(),
      'sessions': (await db.query(
        'SELECT id, device_id, started_at, last_seen_at, ended_at, end_reason, active_seconds, app_version, country, ip_prefix '
        'FROM sessions WHERE user_id = CAST(@u AS uuid) ORDER BY started_at DESC',
        u,
      )).map(jsonRow).toList(),
      'usage': (await db.query(
        'SELECT day, active_seconds, sessions FROM usage_statistics WHERE user_id = CAST(@u AS uuid) ORDER BY day',
        u,
      )).map(jsonRow).toList(),
      'logins': (await db.query(
        'SELECT at, success, reason, ip_prefix, country FROM login_events WHERE user_id = CAST(@u AS uuid) ORDER BY at DESC',
        u,
      )).map(jsonRow).toList(),
      'locations': (await db.query(
        'SELECT at, CAST(lat AS float8) AS lat, CAST(lng AS float8) AS lng, country FROM location_history '
        'WHERE user_id = CAST(@u AS uuid) ORDER BY at DESC',
        u,
      )).map(jsonRow).toList(),
    });
  }

  Future<Response> _device(Request req) async {
    final p = await authenticate(req);
    final b = await readJson(req);
    final country = p.regionConsent ? ctx.geo.country(clientIp(req)) : null;
    final id = await _upsertDevice(p.userId, b, country);
    await db.exec('UPDATE sessions SET device_id = CAST(@d AS uuid) WHERE id = CAST(@s AS uuid)', {
      'd': id,
      's': p.sessionId,
    });
    return jsonOk({'deviceId': id});
  }

  /// L'utilisateur retire cet appareil (il pourra en enregistrer un nouveau
  /// avec un nouvel identifiant d'installation).
  Future<Response> _forgetDevice(Request req) async {
    final p = await authenticate(req);
    if (p.deviceId == null) return jsonOk({'ok': true});
    await db.tx((t) async {
      await t.exec('UPDATE sessions SET device_id = NULL WHERE id = CAST(@s AS uuid)', {'s': p.sessionId});
      await t.exec('UPDATE devices SET revoked_at = now() WHERE id = CAST(@d AS uuid)', {'d': p.deviceId});
    });
    return jsonOk({'ok': true});
  }

  Future<Response> _sessions(Request req) async {
    final p = await authenticate(req);
    final rows = await db.query(
      'SELECT s.id, s.started_at, s.last_seen_at, s.active_seconds, s.app_version, d.brand, d.model, d.os, '
      '(s.last_seen_at > now() - make_interval(secs => @w)) AS online '
      'FROM sessions s LEFT JOIN devices d ON d.id = s.device_id '
      'WHERE s.user_id = CAST(@u AS uuid) AND s.ended_at IS NULL ORDER BY s.last_seen_at DESC',
      {'u': p.userId, 'w': onlineWindowSeconds},
    );
    return jsonOk({
      'current': p.sessionId,
      'sessions': [for (final r in rows) jsonRow(r)],
    });
  }

  Future<Response> _revokeOwn(Request req, String id) async {
    final p = await authenticate(req);
    final n = await db.exec(
      "UPDATE sessions SET ended_at = now(), end_reason = 'revoked' WHERE id = CAST(@id AS uuid) "
      'AND user_id = CAST(@u AS uuid) AND ended_at IS NULL',
      {'id': _uuid(id), 'u': p.userId},
    );
    if (n == 0) throw ApiError.notFound;
    return jsonOk({'ok': true});
  }

  Future<Response> _clearLocation(Request req) async {
    final p = await authenticate(req);
    final n = await db.exec('DELETE FROM location_history WHERE user_id = CAST(@u AS uuid)', {'u': p.userId});
    return jsonOk({'deleted': n});
  }
}

final _uuidRe = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// Identifiant validé (évite une erreur SQL sur une valeur mal formée).
String uuidParam(String id) => _uuid(id);

String _uuid(String id) {
  if (!_uuidRe.hasMatch(id)) throw ApiError.notFound;
  return id;
}

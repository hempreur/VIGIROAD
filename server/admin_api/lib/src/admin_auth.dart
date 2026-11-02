import 'package:postgres/postgres.dart' show ServerException;
import 'package:shelf/shelf.dart';

import 'accounts.dart' show uuidParam;
import 'context.dart';
import 'db.dart';
import 'http_kit.dart';
import 'security.dart';

/// Étape intermédiaire entre le mot de passe et le code TOTP.
class _Ticket {
  _Ticket(this.adminId, this.enroll, this.expires, this.client, this.ipPrefix);
  final String adminId;
  final bool enroll;
  final DateTime expires;
  final String? client;
  final String? ipPrefix;
  int attempts = 0;
}

/// Authentification des administrateurs : mot de passe (Argon2id) puis code
/// TOTP obligatoire ; verrouillage après 5 échecs ; sessions de 12 h au plus,
/// fermées après 30 min d'inactivité ; gestion des comptes administrateurs.
class AdminAuthService {
  AdminAuthService(this.ctx);

  final AppContext ctx;
  Db get db => ctx.db;

  static const sessionMaxAge = Duration(hours: 12);
  static const idleTimeout = Duration(minutes: 30);
  static const maxFailures = 5;
  static const lockFor = Duration(minutes: 15);

  final _tickets = <String, _Ticket>{};
  final _ipLimiter = SlidingLimiter(max: 20, window: const Duration(minutes: 15));

  void register(Router r) {
    r.get('/admin/setup', (req, _) => _setupStatus());
    r.post('/admin/setup', (req, _) => _setup(req));
    r.post('/admin/auth/login', (req, _) => _login(req));
    r.post('/admin/auth/mfa', (req, _) => _mfa(req));
    r.post('/admin/auth/logout', (req, _) => _logout(req));
    r.get('/admin/me', (req, _) async => jsonOk({'admin': (await authenticate(req)).toJson()}));
    r.post('/admin/me/password', (req, _) => _changePassword(req));
    r.get('/admin/admins', (req, _) => _list(req));
    r.post('/admin/admins', (req, _) => _create(req));
    r.patch('/admin/admins/:id', (req, p) => _update(req, p['id']!));
    r.post('/admin/admins/:id/reset-mfa', (req, p) => _resetMfa(req, p['id']!));
    r.delete('/admin/admins/:id', (req, p) => _remove(req, p['id']!));
  }

  Future<bool> _hasAdmin() async => await db.one('SELECT 1 FROM admin_accounts LIMIT 1') != null;

  Future<Response> _setupStatus() async =>
      jsonOk({'needed': !await _hasAdmin(), 'enabled': ctx.config.setupToken != null});

  /// Création du premier administrateur (propriétaire) avec le jeton
  /// d'installation affiché par install.sh. Désactivée ensuite.
  Future<Response> _setup(Request req) async {
    final ip = clientIp(req);
    if (!_ipLimiter.allow('setup:${ipPrefix(ip)}')) throw ApiError.tooMany;
    final b = await readJson(req);
    final token = ctx.config.setupToken;
    if (token == null || !secureEquals(token, b.need('setupToken', max: 128))) {
      await ctx.audit(null, 'admin.setup', success: false, ipPrefix: ipPrefix(ip));
      throw const ApiError(403, 'Jeton d\'installation invalide', code: 'bad_setup_token');
    }
    final email = b.need('email', max: 254).toLowerCase();
    if (!email.contains('@')) throw ApiError.badRequest('Adresse e-mail invalide');
    final password = b.need('password', max: 128);
    final weak = _adminPasswordProblem(password);
    if (weak != null) throw ApiError.badRequest(weak);
    final hash = await ctx.hasher.hash(password);
    final secret = Totp.newSecret();
    final sealed = await ctx.boxer.seal(secret);
    final id = await db.tx((t) async {
      await t.exec('LOCK TABLE admin_accounts IN EXCLUSIVE MODE');
      if (await t.one('SELECT 1 FROM admin_accounts LIMIT 1') != null) {
        throw const ApiError(409, 'Un administrateur existe déjà', code: 'setup_done');
      }
      return t.scalar<String>(
        "INSERT INTO admin_accounts (email, display_name, password_hash, role, totp_secret_enc) "
        "VALUES (@e, @n, @h, 'owner', @s) RETURNING id",
        {'e': email, 'n': b.str('displayName', max: 80) ?? email.split('@').first, 'h': hash, 's': sealed},
      );
    });
    await ctx.audit(null, 'admin.setup', targetType: 'admin', targetId: id, email: email, ipPrefix: ipPrefix(ip));
    return jsonOk({
      'mfa': 'enroll',
      'ticket': _newTicket(id, enroll: true, client: b.str('client', max: 32), ip: ip),
      'enrollment': {'secret': secret, 'uri': Totp.uri(secret, email)},
    }, status: 201);
  }

  static String? _adminPasswordProblem(String p) {
    if (p.length < 12) return 'Mot de passe administrateur : 12 caractères minimum';
    return PasswordHasher.validate(p);
  }

  String _newTicket(String adminId, {required bool enroll, String? client, String? ip}) {
    final now = DateTime.now();
    _tickets.removeWhere((_, t) => t.expires.isBefore(now));
    final t = newToken('vrt');
    _tickets[sha256Hex(t)] = _Ticket(adminId, enroll, now.add(const Duration(minutes: 5)), client, ipPrefix(ip));
    return t;
  }

  Future<Response> _login(Request req) async {
    final ip = clientIp(req);
    final b = await readJson(req);
    final email = b.need('email', max: 254).toLowerCase();
    final password = b.need('password', max: 128);
    if (!_ipLimiter.allow(ipPrefix(ip) ?? '?')) {
      await _event(null, false, 'rate_limited', ip);
      throw ApiError.tooMany;
    }
    final a = await db.one(
      'SELECT id, password_hash, status, totp_confirmed, totp_secret_enc, (locked_until > now()) AS locked '
      'FROM admin_accounts WHERE lower(email) = @e',
      {'e': email},
    );
    if (a == null) {
      await ctx.hasher.dummyVerify(password);
      await _event(null, false, 'unknown_account', ip);
      throw const ApiError(401, 'Identifiant ou mot de passe incorrect', code: 'bad_credentials');
    }
    final id = a['id'] as String;
    if (a['locked'] == true) {
      await _event(id, false, 'locked', ip);
      throw const ApiError(423, 'Compte verrouillé après plusieurs échecs : réessayez dans 15 minutes', code: 'locked');
    }
    if (!await ctx.hasher.verify(password, a['password_hash'] as String)) {
      await _fail(id, 'bad_password', ip);
      throw const ApiError(401, 'Identifiant ou mot de passe incorrect', code: 'bad_credentials');
    }
    if (a['status'] != 'active') {
      await _event(id, false, 'disabled', ip);
      throw const ApiError(403, 'Compte administrateur désactivé', code: 'disabled');
    }
    // Application de bureau obsolète : refus avec la mise à jour à installer.
    await desktopGuard?.call(req, adminId: id, adminEmail: email);
    final client = b.str('client', max: 32);
    if (a['totp_confirmed'] != true) {
      // Première connexion : enrôlement de l'application d'authentification.
      var secret = a['totp_secret_enc'] == null ? null : await ctx.boxer.open(a['totp_secret_enc'] as String);
      if (secret == null) {
        secret = Totp.newSecret();
        await db.exec('UPDATE admin_accounts SET totp_secret_enc = @s WHERE id = CAST(@id AS uuid)', {
          's': await ctx.boxer.seal(secret),
          'id': id,
        });
      }
      return jsonOk({
        'mfa': 'enroll',
        'ticket': _newTicket(id, enroll: true, client: client, ip: ip),
        'enrollment': {'secret': secret, 'uri': Totp.uri(secret, email)},
      });
    }
    return jsonOk({'mfa': 'required', 'ticket': _newTicket(id, enroll: false, client: client, ip: ip)});
  }

  Future<void> _fail(String id, String reason, String? ip) async {
    await db.exec(
      'UPDATE admin_accounts SET failed_attempts = failed_attempts + 1, '
      'locked_until = CASE WHEN failed_attempts + 1 >= @max THEN now() + make_interval(mins => @lock) ELSE locked_until END '
      'WHERE id = CAST(@id AS uuid)',
      {'id': id, 'max': maxFailures, 'lock': lockFor.inMinutes},
    );
    await _event(id, false, reason, ip);
  }

  Future<void> _event(String? adminId, bool ok, String reason, String? ip) => db.exec(
    "INSERT INTO login_events (kind, admin_id, success, reason, ip_prefix, country) "
    "VALUES ('admin', CAST(@a AS uuid), @s, @r, @ip, @c)",
    {'a': adminId, 's': ok, 'r': reason, 'ip': ipPrefix(ip), 'c': ctx.geo.country(ip)},
  );

  Future<Response> _mfa(Request req) async {
    final ip = clientIp(req);
    final b = await readJson(req);
    final key = sha256Hex(b.need('ticket', max: 128));
    final t = _tickets[key];
    if (t == null || t.expires.isBefore(DateTime.now())) {
      _tickets.remove(key);
      throw const ApiError(401, 'Étape expirée : reconnectez-vous', code: 'ticket_expired');
    }
    final a = await db.one(
      'SELECT id, email, display_name, role, status, totp_secret_enc, totp_last_step FROM admin_accounts '
      'WHERE id = CAST(@id AS uuid)',
      {'id': t.adminId},
    );
    if (a == null || a['status'] != 'active' || a['totp_secret_enc'] == null) {
      _tickets.remove(key);
      throw ApiError.unauthorized;
    }
    final secret = await ctx.boxer.open(a['totp_secret_enc'] as String);
    final step = Totp.verify(secret, b.need('code', max: 16), DateTime.now(), lastStep: a['totp_last_step'] as int);
    if (step == null) {
      t.attempts++;
      if (t.attempts >= 5) _tickets.remove(key);
      await _fail(t.adminId, 'bad_totp', ip);
      throw const ApiError(401, 'Code de vérification incorrect', code: 'bad_code');
    }
    _tickets.remove(key);
    final token = newToken('vra');
    final sessionId = await db.tx((tx) async {
      await tx.exec(
        'UPDATE admin_accounts SET totp_last_step = @s, totp_confirmed = true, failed_attempts = 0, locked_until = NULL, '
        'last_login_at = now() WHERE id = CAST(@id AS uuid)',
        {'s': step, 'id': t.adminId},
      );
      return tx.scalar<String>(
        'INSERT INTO admin_sessions (admin_id, token_hash, client, ip_prefix, expires_at) '
        'VALUES (CAST(@a AS uuid), @h, @c, @ip, now() + make_interval(hours => @age)) RETURNING id',
        {'a': t.adminId, 'h': sha256Hex(token), 'c': t.client, 'ip': ipPrefix(ip), 'age': sessionMaxAge.inHours},
      );
    });
    await _event(t.adminId, true, t.enroll ? 'mfa_enrolled' : 'password+totp', ip);
    final principal = AdminPrincipal(
      id: t.adminId,
      email: a['email'] as String,
      displayName: a['display_name'] as String,
      role: a['role'] as String,
      sessionId: sessionId,
      ipPrefix: ipPrefix(ip),
    );
    await ctx.audit(principal, t.enroll ? 'admin.mfa_enrolled' : 'admin.login', details: {'client': t.client});
    return jsonOk({
      'token': token,
      'expiresAt': DateTime.now().toUtc().add(sessionMaxAge).toIso8601String(),
      'idleTimeoutSeconds': idleTimeout.inSeconds,
      'admin': principal.toJson(),
    });
  }

  /// Vérifie le jeton administrateur et, si demandé, le droit [perm].
  /// Contrôle de version des applications de bureau (branché par l'API).
  Future<void> Function(Request req, {String? adminId, String? adminEmail})? desktopGuard;

  Future<AdminPrincipal> authenticate(Request req, [Perm perm = Perm.read, bool versionCheck = true]) async {
    final h = req.headers['authorization'] ?? '';
    // Flux d'événements : jeton accepté en paramètre (pas d'en-tête possible
    // pour certains clients SSE).
    final token = h.startsWith('Bearer vra_') ? h.substring(7).trim() : '';
    if (token.isEmpty) throw ApiError.unauthorized;
    final s = await db.one(
      'SELECT s.id, s.admin_id, s.ip_prefix, a.email, a.display_name, a.role, a.status, '
      '(s.revoked_at IS NOT NULL OR s.expires_at < now()) AS ended, '
      '(s.last_seen_at < now() - make_interval(mins => @idle)) AS idle, '
      '(s.last_seen_at < now() - interval \'30 seconds\') AS stale '
      'FROM admin_sessions s JOIN admin_accounts a ON a.id = s.admin_id WHERE s.token_hash = @h',
      {'h': sha256Hex(token), 'idle': idleTimeout.inMinutes},
    );
    if (s == null || s['ended'] == true) {
      throw const ApiError(401, 'Session administrateur expirée : reconnectez-vous', code: 'session_expired');
    }
    if (s['idle'] == true) {
      await db.exec('UPDATE admin_sessions SET revoked_at = now() WHERE id = CAST(@id AS uuid)', {'id': s['id']});
      throw const ApiError(401, 'Session fermée après 30 minutes d\'inactivité', code: 'session_expired');
    }
    if (s['status'] != 'active') throw const ApiError(401, 'Compte désactivé', code: 'disabled');
    if (s['stale'] == true) {
      await db.exec('UPDATE admin_sessions SET last_seen_at = now() WHERE id = CAST(@id AS uuid)', {'id': s['id']});
    }
    final p = AdminPrincipal(
      id: s['admin_id'] as String,
      email: s['email'] as String,
      displayName: s['display_name'] as String,
      role: s['role'] as String,
      sessionId: s['id'] as String,
      ipPrefix: ipPrefix(clientIp(req)) ?? s['ip_prefix'] as String?,
    );
    if (versionCheck) await desktopGuard?.call(req, adminId: p.id, adminEmail: p.email);
    if (!p.can(perm)) {
      await ctx.audit(p, 'denied', details: {'perm': perm.name, 'path': req.url.path}, success: false);
      throw ApiError.forbidden;
    }
    return p;
  }

  Future<Response> _logout(Request req) async {
    final p = await authenticate(req);
    await db.exec('UPDATE admin_sessions SET revoked_at = now() WHERE id = CAST(@id AS uuid)', {'id': p.sessionId});
    await ctx.audit(p, 'admin.logout');
    return jsonOk({'ok': true});
  }

  Future<Response> _changePassword(Request req) async {
    final p = await authenticate(req);
    final b = await readJson(req);
    final hash = await db.scalar<String>('SELECT password_hash FROM admin_accounts WHERE id = CAST(@id AS uuid)', {
      'id': p.id,
    });
    if (!await ctx.hasher.verify(b.need('current', max: 128), hash)) {
      await ctx.audit(p, 'admin.password_change', success: false);
      throw const ApiError(403, 'Mot de passe actuel incorrect', code: 'bad_credentials');
    }
    final next = b.need('new', max: 128);
    final weak = _adminPasswordProblem(next);
    if (weak != null) throw ApiError.badRequest(weak);
    await db.exec('UPDATE admin_accounts SET password_hash = @h WHERE id = CAST(@id AS uuid)', {
      'h': await ctx.hasher.hash(next),
      'id': p.id,
    });
    // Les autres sessions de cet administrateur sont fermées.
    await db.exec(
      'UPDATE admin_sessions SET revoked_at = now() WHERE admin_id = CAST(@a AS uuid) AND id <> CAST(@s AS uuid) AND revoked_at IS NULL',
      {'a': p.id, 's': p.sessionId},
    );
    await ctx.audit(p, 'admin.password_change');
    return jsonOk({'ok': true});
  }

  Future<Response> _list(Request req) async {
    await authenticate(req, Perm.adminsManage);
    final rows = await db.query(
      'SELECT a.id, a.email, a.display_name, a.role, a.status, a.totp_confirmed, a.created_at, a.last_login_at, '
      '(a.locked_until > now()) AS locked, '
      '(SELECT count(*) FROM admin_sessions s WHERE s.admin_id = a.id AND s.revoked_at IS NULL AND s.expires_at > now() '
      "AND s.last_seen_at > now() - interval '30 minutes') AS active_sessions "
      'FROM admin_accounts a ORDER BY a.created_at',
    );
    return jsonOk({'admins': rows.map(jsonRow).toList(), 'roles': roleLabels});
  }

  Future<Response> _create(Request req) async {
    final p = await authenticate(req, Perm.adminsManage);
    final b = await readJson(req);
    final email = b.need('email', max: 254).toLowerCase();
    if (!email.contains('@')) throw ApiError.badRequest('Adresse e-mail invalide');
    final role = b.need('role', max: 16);
    if (!rolePerms.containsKey(role)) throw ApiError.badRequest('Rôle inconnu');
    final password = b.need('password', max: 128);
    final weak = _adminPasswordProblem(password);
    if (weak != null) throw ApiError.badRequest(weak);
    try {
      final id = await db.scalar<String>(
        'INSERT INTO admin_accounts (email, display_name, password_hash, role, created_by) '
        'VALUES (@e, @n, @h, @r, CAST(@by AS uuid)) RETURNING id',
        {
          'e': email,
          'n': b.str('displayName', max: 80) ?? email.split('@').first,
          'h': await ctx.hasher.hash(password),
          'r': role,
          'by': p.id,
        },
      );
      await ctx.audit(p, 'admin.create', targetType: 'admin', targetId: id, details: {'email': email, 'role': role});
      return jsonOk({'id': id}, status: 201);
    } on ServerException catch (e) {
      if (e.code == '23505') throw const ApiError(409, 'Cet administrateur existe déjà', code: 'taken');
      rethrow;
    }
  }

  Future<void> _keepOneOwner(Db t, String id) async {
    final owners = await t.scalar<int>(
      "SELECT count(*) FROM admin_accounts WHERE role = 'owner' AND status = 'active' AND id <> CAST(@id AS uuid)",
      {'id': id},
    );
    if (owners == 0) throw const ApiError(409, 'Il doit rester au moins un propriétaire actif', code: 'last_owner');
  }

  Future<Response> _update(Request req, String rawId) async {
    final p = await authenticate(req, Perm.adminsManage);
    final id = uuidParam(rawId);
    final b = await readJson(req);
    final role = b.str('role', max: 16);
    final status = b.str('status', max: 16);
    if (role != null && !rolePerms.containsKey(role)) throw ApiError.badRequest('Rôle inconnu');
    if (status != null && status != 'active' && status != 'disabled') throw ApiError.badRequest('Statut inconnu');
    await db.tx((t) async {
      final current = await t.one('SELECT role FROM admin_accounts WHERE id = CAST(@id AS uuid) FOR UPDATE', {'id': id});
      if (current == null) throw ApiError.notFound;
      if (current['role'] == 'owner' && ((role != null && role != 'owner') || status == 'disabled')) {
        await _keepOneOwner(t, id);
      }
      await t.exec(
        'UPDATE admin_accounts SET role = COALESCE(@r, role), status = COALESCE(@s, status), '
        'display_name = COALESCE(@n, display_name) WHERE id = CAST(@id AS uuid)',
        {'r': role, 's': status, 'n': b.str('displayName', max: 80), 'id': id},
      );
      if (status == 'disabled' || role != null) {
        await t.exec('UPDATE admin_sessions SET revoked_at = now() WHERE admin_id = CAST(@id AS uuid) AND revoked_at IS NULL', {
          'id': id,
        });
      }
    });
    await ctx.audit(p, 'admin.update', targetType: 'admin', targetId: id, details: {'role': role, 'status': status});
    return jsonOk({'ok': true});
  }

  Future<Response> _resetMfa(Request req, String rawId) async {
    final p = await authenticate(req, Perm.adminsManage);
    final id = uuidParam(rawId);
    final n = await db.exec(
      'UPDATE admin_accounts SET totp_confirmed = false, totp_secret_enc = NULL, totp_last_step = 0 WHERE id = CAST(@id AS uuid)',
      {'id': id},
    );
    if (n == 0) throw ApiError.notFound;
    await db.exec('UPDATE admin_sessions SET revoked_at = now() WHERE admin_id = CAST(@id AS uuid) AND revoked_at IS NULL', {
      'id': id,
    });
    await ctx.audit(p, 'admin.reset_mfa', targetType: 'admin', targetId: id);
    return jsonOk({'ok': true});
  }

  Future<Response> _remove(Request req, String rawId) async {
    final p = await authenticate(req, Perm.adminsManage);
    final id = uuidParam(rawId);
    if (id == p.id) throw const ApiError(409, 'Vous ne pouvez pas supprimer votre propre compte', code: 'self');
    await db.tx((t) async {
      final current = await t.one('SELECT role FROM admin_accounts WHERE id = CAST(@id AS uuid) FOR UPDATE', {'id': id});
      if (current == null) throw ApiError.notFound;
      if (current['role'] == 'owner') await _keepOneOwner(t, id);
      await t.exec('DELETE FROM admin_accounts WHERE id = CAST(@id AS uuid)', {'id': id});
    });
    await ctx.audit(p, 'admin.delete', targetType: 'admin', targetId: id);
    return jsonOk({'ok': true});
  }
}

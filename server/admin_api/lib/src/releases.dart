import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as c;
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

import 'accounts.dart';
import 'admin_auth.dart';
import 'context.dart';
import 'db.dart';
import 'http_kit.dart';
import 'security.dart';

/// Compare deux versions « 1.7.0 » (−1, 0, 1).
int compareVersions(String a, String b) {
  List<int> p(String v) => [for (final x in v.split('+').first.split('.')) int.tryParse(x) ?? 0];
  final x = p(a), y = p(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Règle de version de l'application GPS.
class AppPolicy {
  const AppPolicy({
    required this.blocked,
    required this.message,
    required this.manualMinBuild,
    required this.forceLatest,
    this.latestVersion,
    this.latestBuild,
    this.latestMinBuild,
    this.latestAt,
  });

  final bool blocked;
  final String message;
  final int manualMinBuild;

  /// Toute version antérieure à la dernière publiée est obsolète.
  final bool forceLatest;
  final String? latestVersion;
  final int? latestBuild;
  final int? latestMinBuild;
  final DateTime? latestAt;

  /// Numéro de compilation minimal accepté.
  int get minBuild {
    final published = forceLatest ? (latestBuild ?? 0) : (latestMinBuild ?? 0);
    return manualMinBuild > published ? manualMinBuild : published;
  }

  /// `ok`, `outdated` ou `blocked`.
  String statusFor(int? build) {
    if (blocked) return 'blocked';
    if (build == null || build < minBuild) return 'outdated';
    return 'ok';
  }

  Map<String, Object?> toJson() => {
    'blocked': blocked,
    'message': message,
    'manualMinBuild': manualMinBuild,
    'forceLatest': forceLatest,
    'minBuild': minBuild,
    'latest': latestVersion == null
        ? null
        : {'version': latestVersion, 'build': latestBuild, 'minBuild': latestMinBuild, 'checkedAt': latestAt?.toUtc().toIso8601String()},
  };
}

/// Versions des applications :
///
/// - application GPS : `POST /v1/app/status` au démarrage → `ok`,
///   `update_required` (version antérieure à la dernière publiée) ou
///   `blocked` (blocage à distance depuis ADMIN MANAGER) ; chaque tentative
///   avec une version obsolète ou bloquée est journalisée ;
/// - serveur de trafic : `GET /v1/app/policy` (règle en vigueur) et
///   `POST /v1/app/rejected` (requête refusée d'une ancienne application) ;
/// - applications de bureau : déposées sur le VPS par la CI (jamais publiées
///   sur GitHub), téléchargeables seulement par un administrateur connecté ;
///   une version antérieure à la dernière déposée est refusée (426) avec la
///   mise à jour à installer.
class ReleaseService {
  ReleaseService(this.ctx, this.auth, this.accounts, {http.Client? client}) : _http = client ?? http.Client();

  final AppContext ctx;
  final AdminAuthService auth;
  final AccountService accounts;
  final http.Client _http;
  Db get db => ctx.db;
  Timer? _timer;

  static const desktopApps = {'admin-manager', 'server-control'};
  static final _fileName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$');

  void register(Router r) {
    r.post('/v1/app/status', (req, _) => _status(req));
    r.get('/v1/app/policy', (req, _) => _policyForTraffic(req));
    r.post('/v1/app/rejected', (req, _) => _rejected(req));
    r.get('/admin/app/versions', (req, _) => _versions(req));
    r.put('/admin/app/policy', (req, _) => _putPolicy(req));
    r.post('/admin/app/devices/:hash/block', (req, p) => _blockDevice(req, p['hash']!));
    r.delete('/admin/app/devices/:hash', (req, p) => _unblockDevice(req, p['hash']!));
    r.put('/admin/releases/desktop/:name', (req, p) => _upload(req, p['name']!));
    r.get('/admin/desktop/manifest', (req, _) => _desktopManifest(req));
    r.get('/admin/desktop/files/:name', (req, p) => _download(req, p['name']!));
  }

  void start() {
    unawaited(refreshMobile());
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => unawaited(refreshMobile()));
  }

  void stop() => _timer?.cancel();

  // --- Application GPS ------------------------------------------------------

  /// Dernière version publiée (manifeste de la release GitHub), gardée en
  /// réglage pour survivre aux redémarrages.
  Future<void> refreshMobile() async {
    try {
      final r = await _http.get(Uri.parse(ctx.config.mobileManifestUrl)).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final latest = {
        'version': j['version'] as String,
        'build': (j['build'] as num).toInt(),
        'minBuild': (j['minBuild'] as num?)?.toInt() ?? (j['build'] as num).toInt(),
        'checkedAt': DateTime.now().toUtc().toIso8601String(),
      };
      await _setSetting('app.latest', latest, null);
    } on Object catch (e) {
      ctx.recordError('versions:manifeste', e);
    }
  }

  Future<AppPolicy> policy() async {
    final s = await ctx.settings();
    final latest = s['app.latest'] is Map ? (s['app.latest'] as Map).cast<String, dynamic>() : null;
    return AppPolicy(
      blocked: s['app.blocked'] == true,
      message: s['app.block_message'] as String? ?? 'VIGIROAD est temporairement suspendu.',
      manualMinBuild: (s['app.min_build'] as num?)?.toInt() ?? 0,
      forceLatest: s['app.force_latest'] != false,
      latestVersion: latest?['version'] as String?,
      latestBuild: (latest?['build'] as num?)?.toInt(),
      latestMinBuild: (latest?['minBuild'] as num?)?.toInt(),
      latestAt: DateTime.tryParse(latest?['checkedAt'] as String? ?? ''),
    );
  }

  void _requireAppKey(Request req) {
    final key = req.headers['x-api-key'] ?? '';
    if (!ctx.config.appKeys.any((k) => secureEquals(k, key))) {
      throw const ApiError(401, 'Application non reconnue', code: 'app_key');
    }
  }

  Future<Response> _status(Request req) async {
    _requireAppKey(req);
    final b = await readJson(req);
    final platform = (b.str('platform', max: 16) ?? 'inconnu').toLowerCase();
    final version = b.str('version', max: 32) ?? 'inconnue';
    final build = b.number('build')?.toInt();
    final install = installHash(b.str('install', max: 64));
    final p = await policy();
    final deviceBlock = install == null
        ? null
        : await db.one('SELECT reason FROM blocked_installs WHERE install_hash = @h', {'h': install});
    final status = deviceBlock != null ? 'blocked' : p.statusFor(build);
    final ip = clientIp(req);
    if (status == 'ok') {
      await db.exec(
        "INSERT INTO app_version_daily (day, app, platform, version, build, checks) VALUES (current_date, 'gps', @p, @v, @b, 1) "
        'ON CONFLICT (day, app, platform, version, build) DO UPDATE SET checks = app_version_daily.checks + 1',
        {'p': platform, 'v': version, 'b': build ?? 0},
      );
    } else {
      String? userId;
      try {
        if ((req.headers['authorization'] ?? '').startsWith('Bearer vrs_')) userId = (await accounts.authenticate(req)).userId;
      } on ApiError {
        userId = null;
      }
      await logEvent(
        app: 'gps',
        platform: platform,
        version: version,
        build: build,
        status: status,
        required: p.latestVersion,
        userId: userId,
        model: b.str('model', max: 80),
        os: b.str('os', max: 80),
        ip: ip,
        installHash: install,
      );
    }
    return jsonOk({
      'status': switch (status) {
        'blocked' => 'blocked',
        'outdated' => 'update_required',
        _ => 'ok',
      },
      'scope': deviceBlock != null ? 'device' : (status == 'blocked' ? 'all' : null),
      'message': switch (status) {
        'blocked' when deviceBlock != null =>
          'Cet appareil a été bloqué par l\'administrateur VIGIROAD.${deviceBlock['reason'] == null ? '' : ' ${deviceBlock['reason']}'}',
        'blocked' => p.message,
        'outdated' => 'Cette version de VIGIROAD n\'est plus utilisable : installez la dernière version.',
        _ => null,
      },
      'minBuild': p.minBuild,
      'latest': p.latestVersion == null ? null : {'version': p.latestVersion, 'build': p.latestBuild},
      'downloadUrl': 'https://github.com/${ctx.config.githubRepo}/releases/latest',
    });
  }

  Future<void> logEvent({
    required String app,
    required String platform,
    required String version,
    int? build,
    required String status,
    String? required,
    String source = 'app',
    String? userId,
    String? adminId,
    String? model,
    String? os,
    String? ip,
    String? installHash,
  }) async {
    try {
      await db.exec(
        'INSERT INTO app_version_events (app, platform, version, build, status, required, source, user_id, admin_id, model, os, ip_prefix, country, install_hash) '
        'VALUES (@app, @p, @v, @b, @s, @r, @src, CAST(@u AS uuid), CAST(@a AS uuid), @m, @os, @ip, @c, @ih)',
        {
          'ih': installHash,
          'app': app,
          'p': platform,
          'v': version,
          'b': build,
          's': status,
          'r': required,
          'src': source,
          'u': userId,
          'a': adminId,
          'm': model,
          'os': os,
          'ip': ipPrefix(ip),
          'c': ctx.geo.country(ip),
        },
      );
    } catch (e) {
      ctx.recordError('versions:journal', e);
    }
  }

  /// Règle lue par le serveur de trafic (réseau interne).
  Future<Response> _policyForTraffic(Request req) async {
    _requireAppKey(req);
    final p = await policy();
    final devices = await db.query('SELECT install_hash FROM blocked_installs');
    return jsonOk({
      'blocked': p.blocked,
      'message': p.message,
      'minBuild': p.minBuild,
      'latest': p.latestVersion,
      'blockedInstalls': [for (final d in devices) d['install_hash']],
    });
  }

  /// Requête d'une ancienne application refusée par le serveur de trafic.
  Future<Response> _rejected(Request req) async {
    _requireAppKey(req);
    final b = await readJson(req);
    await logEvent(
      app: 'gps',
      platform: b.str('platform', max: 16) ?? 'inconnu',
      version: b.str('version', max: 32) ?? '1.6 ou antérieure',
      build: b.number('build')?.toInt(),
      status: b.str('status', max: 16) == 'blocked' ? 'blocked' : 'outdated',
      required: (await policy()).latestVersion,
      source: 'traffic',
      ip: clientIp(req),
      installHash: installHash(b.str('install', max: 64)),
    );
    return jsonOk({'ok': true});
  }

  Future<Response> _versions(Request req) async {
    await auth.authenticate(req);
    final limit = (int.tryParse(req.url.queryParameters['limit'] ?? '') ?? 200).clamp(1, 1000);
    final events = await db.query(
      'SELECT e.id, e.at, e.app, e.platform, e.version, e.build, e.status, e.required, e.source, e.model, e.os, '
      'e.ip_prefix, e.country, e.install_hash, (bi.install_hash IS NOT NULL) AS device_blocked, u.pseudonym, a.email AS admin_email '
      'FROM app_version_events e LEFT JOIN users u ON u.id = e.user_id LEFT JOIN admin_accounts a ON a.id = e.admin_id '
      'LEFT JOIN blocked_installs bi ON bi.install_hash = e.install_hash '
      'ORDER BY e.at DESC LIMIT @l',
      {'l': limit},
    );
    final summary = await db.query('''
      SELECT app, platform, version, build, CAST(sum(checks) AS bigint) AS checks, max(day) AS last_day
      FROM app_version_daily WHERE day > current_date - 7
      GROUP BY app, platform, version, build ORDER BY build DESC, version DESC
    ''');
    final counts = await db.one('''
      SELECT (SELECT count(*) FROM app_version_events WHERE at > now() - interval '24 hours') AS last24h,
             (SELECT count(*) FROM app_version_events WHERE at > now() - interval '7 days') AS last7d
    ''');
    final blockedDevices = await db.query(
      'SELECT b.install_hash, b.reason, b.platform, b.model, b.version, b.blocked_at, a.email AS blocked_by '
      'FROM blocked_installs b LEFT JOIN admin_accounts a ON a.id = b.blocked_by ORDER BY b.blocked_at DESC',
    );
    return jsonOk({
      'policy': (await policy()).toJson(),
      'blockedDevices': blockedDevices.map(jsonRow).toList(),
      'desktop': _desktopLatest(),
      'events': events.map(jsonRow).toList(),
      'inUse': summary.map(jsonRow).toList(),
      'counts': jsonRow(counts!),
    });
  }

  Future<Response> _putPolicy(Request req) async {
    final a = await auth.authenticate(req, Perm.settings);
    final b = await readJson(req);
    final changed = <String, Object?>{};
    if (b.flag('blocked') case final v?) changed['app.blocked'] = v;
    if (b.flag('forceLatest') case final v?) changed['app.force_latest'] = v;
    if (b.containsKey('message')) {
      changed['app.block_message'] = b.str('message', max: 300) ?? 'VIGIROAD est temporairement suspendu.';
    }
    if (b.number('minBuild') case final v?) {
      if (v < 0 || v > 1000000 || v != v.toInt()) throw ApiError.badRequest('minBuild : entier positif attendu');
      changed['app.min_build'] = v.toInt();
    }
    if (changed.isEmpty) throw ApiError.badRequest('Aucun changement');
    for (final e in changed.entries) {
      await _setSetting(e.key, e.value, a.id);
    }
    await ctx.audit(a, changed['app.blocked'] == true ? 'app.block' : 'app.policy', details: changed);
    return jsonOk({'policy': (await policy()).toJson()});
  }

  /// Empreinte d'un identifiant d'installation (aléatoire, envoyé par
  /// l'application) ; null si absent ou mal formé.
  static String? installHash(String? id) {
    if (id == null || !RegExp(r'^[0-9a-f]{16,64}$').hasMatch(id)) return null;
    return sha256Hex('vigiroad-install:$id');
  }

  static final _hash = RegExp(r'^[0-9a-f]{64}$');

  /// Blocage d'un appareil vu dans le journal (empreinte de son installation).
  Future<Response> _blockDevice(Request req, String hash) async {
    final a = await auth.authenticate(req, Perm.settings);
    if (!_hash.hasMatch(hash)) throw ApiError.badRequest('Appareil inconnu');
    final b = await readJson(req);
    final last = await db.one(
      'SELECT platform, model, version FROM app_version_events WHERE install_hash = @h ORDER BY at DESC LIMIT 1',
      {'h': hash},
    );
    if (last == null) throw ApiError.notFound;
    await db.exec(
      'INSERT INTO blocked_installs (install_hash, reason, platform, model, version, blocked_by) '
      'VALUES (@h, @r, @p, @m, @v, CAST(@a AS uuid)) ON CONFLICT (install_hash) DO UPDATE SET reason = EXCLUDED.reason',
      {'h': hash, 'r': b.str('reason', max: 300), 'p': last['platform'], 'm': last['model'], 'v': last['version'], 'a': a.id},
    );
    await ctx.audit(a, 'app.device_block', targetType: 'install', targetId: hash.substring(0, 12), details: {'model': last['model']});
    return jsonOk({'blocked': true});
  }

  Future<Response> _unblockDevice(Request req, String hash) async {
    final a = await auth.authenticate(req, Perm.settings);
    if (!_hash.hasMatch(hash)) throw ApiError.badRequest('Appareil inconnu');
    final n = await db.exec('DELETE FROM blocked_installs WHERE install_hash = @h', {'h': hash});
    if (n == 0) throw ApiError.notFound;
    await ctx.audit(a, 'app.device_unblock', targetType: 'install', targetId: hash.substring(0, 12));
    return jsonOk({'blocked': false});
  }

  Future<void> _setSetting(String key, Object? value, String? adminId) => db.exec(
    'INSERT INTO settings (key, value, updated_at, updated_by) VALUES (@k, CAST(@v AS jsonb), now(), CAST(@a AS uuid)) '
    'ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = EXCLUDED.updated_by',
    {'k': key, 'v': jsonEncode(value), 'a': adminId},
  );

  // --- Applications de bureau ----------------------------------------------

  Directory get _dir => Directory(ctx.config.desktopDir);

  Map<String, dynamic>? _manifestCache;
  DateTime? _manifestMtime;

  /// Manifeste déposé par la CI (`manifest.json`), ou null.
  Map<String, dynamic>? desktopManifest() {
    final f = File('${_dir.path}/manifest.json');
    try {
      if (!f.existsSync()) return null;
      final m = f.lastModifiedSync();
      if (_manifestCache == null || m != _manifestMtime) {
        _manifestCache = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        _manifestMtime = m;
      }
      return _manifestCache;
    } on Object catch (e) {
      ctx.recordError('versions:manifeste bureau', e);
      return null;
    }
  }

  Map<String, Object?>? _desktopLatest() {
    final m = desktopManifest();
    if (m == null) return null;
    return {for (final app in desktopApps) app: (m[app] as Map<String, dynamic>?)?['version']};
  }

  /// Dépôt par la CI : `PUT /admin/releases/desktop/<fichier>` avec
  /// `x-release-token`. `manifest.json` est déposé en dernier.
  Future<Response> _upload(Request req, String name) async {
    final token = ctx.config.releaseToken;
    final given = req.headers['x-release-token'] ?? '';
    if (token == null) throw const ApiError(503, 'Dépôt désactivé : VR_RELEASE_TOKEN absent du serveur', code: 'release_disabled');
    if (!secureEquals(token, given)) throw const ApiError(401, 'Jeton de dépôt invalide', code: 'release_token');
    if (!_fileName.hasMatch(name)) throw ApiError.badRequest('Nom de fichier invalide');
    await _dir.create(recursive: true);
    final tmp = File('${_dir.path}/.$name.part');
    final sink = tmp.openWrite();
    var size = 0;
    final digest = _DigestSink();
    final hash = c.sha256.startChunkedConversion(digest);
    try {
      await for (final chunk in req.read()) {
        size += chunk.length;
        if (size > 400 * 1024 * 1024) throw ApiError.badRequest('Fichier trop volumineux');
        sink.add(chunk);
        hash.add(chunk);
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    hash.close();
    if (name == 'manifest.json') {
      final m = jsonDecode(await tmp.readAsString());
      if (m is! Map<String, dynamic> || !desktopApps.any(m.containsKey)) {
        await tmp.delete();
        throw ApiError.badRequest('Manifeste invalide');
      }
      // Chaque fichier annoncé doit déjà être là, avec la bonne empreinte.
      for (final app in desktopApps) {
        final files = ((m[app] as Map<String, dynamic>?)?['files'] as Map<String, dynamic>?) ?? const {};
        for (final f in files.values.cast<Map<String, dynamic>>()) {
          final file = File('${_dir.path}/${f['name']}');
          if (!await file.exists() || await _sha256(file) != f['sha256']) {
            await tmp.delete();
            throw ApiError.badRequest('Fichier ${f['name']} absent ou altéré : déposez-le avant le manifeste');
          }
        }
      }
    }
    await tmp.rename('${_dir.path}/$name');
    await _prune();
    await ctx.audit(null, 'release.desktop', email: 'ci', details: {'file': name, 'size': size, 'sha256': '${digest.value}'});
    return jsonOk({'name': name, 'size': size, 'sha256': '${digest.value}'}, status: 201);
  }

  /// Garde seulement les fichiers du manifeste en vigueur (et le dernier dépôt).
  Future<void> _prune() async {
    final m = desktopManifest();
    if (m == null) return;
    final keep = <String>{'manifest.json'};
    for (final app in desktopApps) {
      final files = ((m[app] as Map<String, dynamic>?)?['files'] as Map<String, dynamic>?) ?? const {};
      keep.addAll(files.values.map((f) => (f as Map<String, dynamic>)['name'] as String));
    }
    final ver = (m['admin-manager'] as Map<String, dynamic>?)?['version'] as String?;
    await for (final e in _dir.list()) {
      final n = e.uri.pathSegments.last;
      if (e is! File || keep.contains(n) || n.startsWith('.')) continue;
      // Fichiers d'une version plus récente en cours de dépôt : conservés.
      if (ver != null && n.contains('-$ver-')) continue;
      final match = RegExp(r'vigiroad-(\d+\.\d+\.\d+)-').firstMatch(n);
      if (match != null && ver != null && compareVersions(match.group(1)!, ver) > 0) continue;
      await e.delete();
    }
  }

  static Future<String> _sha256(File f) async => (await c.sha256.bind(f.openRead()).first).toString();

  /// Manifeste public (versions et empreintes, sans lien de téléchargement direct).
  Future<Response> _desktopManifest(Request req) async {
    final m = desktopManifest();
    if (m == null) throw const ApiError(404, 'Aucune application de bureau déposée sur ce serveur', code: 'no_desktop');
    return jsonOk(m);
  }

  /// Téléchargement : administrateur connecté, ou ticket remis avec un 426.
  Future<Response> _download(Request req, String name) async {
    if (!_fileName.hasMatch(name) || name == 'manifest.json') throw ApiError.notFound;
    final ticket = req.url.queryParameters['ticket'];
    if (ticket != null) {
      if (!_validTicket(ticket, name)) throw const ApiError(401, 'Lien de téléchargement expiré', code: 'ticket_expired');
    } else {
      await auth.authenticate(req, Perm.read, false);
    }
    final f = File('${_dir.path}/$name');
    if (!await f.exists()) throw ApiError.notFound;
    return Response.ok(
      f.openRead(),
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': '${await f.length()}',
        'content-disposition': 'attachment; filename="$name"',
        'cache-control': 'no-store',
      },
    );
  }

  String _sign(String payload) =>
      b64url(c.Hmac(c.sha256, ctx.config.masterKey).convert(utf8.encode('desktop:$payload')).bytes);

  String ticketFor(String name, {Duration valid = const Duration(minutes: 30)}) {
    final exp = DateTime.now().add(valid).millisecondsSinceEpoch ~/ 1000;
    return '$exp.${_sign('$name|$exp')}';
  }

  bool _validTicket(String ticket, String name) {
    final i = ticket.indexOf('.');
    if (i <= 0) return false;
    final exp = int.tryParse(ticket.substring(0, i));
    if (exp == null || exp * 1000 < DateTime.now().millisecondsSinceEpoch) return false;
    return secureEquals(_sign('$name|$exp'), ticket.substring(i + 1));
  }

  /// Contrôle de l'application de bureau (en-tête `x-vigiroad-app:
  /// admin-manager/1.7.0`). Version antérieure à la dernière déposée, ou
  /// en-tête absent (applications 1.6 et antérieures) : refus 426 avec la
  /// mise à jour à installer. Sans application déposée : aucun contrôle.
  Future<void> checkDesktop(Request req, {String? adminId, String? adminEmail}) async {
    final m = desktopManifest();
    if (m == null) return;
    final header = req.headers['x-vigiroad-app'] ?? '';
    final parts = header.split('/');
    final app = parts.length == 2 && desktopApps.contains(parts[0]) ? parts[0] : null;
    final version = parts.length == 2 ? parts[1] : null;
    final latestFor = app == null ? null : (m[app] as Map<String, dynamic>?)?['version'] as String?;
    if (app != null && version != null && (latestFor == null || compareVersions(version, latestFor) >= 0)) return;

    final target = app ?? (req.headers['user-agent']?.toLowerCase().contains('linux') == true ? 'server-control' : 'admin-manager');
    final entry = (m[target] as Map<String, dynamic>?) ?? const {};
    final files = (entry['files'] as Map<String, dynamic>?) ?? const {};
    await logEvent(
      app: target,
      platform: target == 'admin-manager' ? 'windows' : 'linux',
      version: version ?? '1.6 ou antérieure',
      status: 'outdated',
      required: entry['version'] as String?,
      source: 'admin',
      adminId: adminId,
      ip: clientIp(req),
    );
    throw ApiError(
      426,
      'Application d\'administration obsolète (${version ?? '1.6 ou antérieure'}) : la version ${entry['version']} est requise.',
      code: 'update_required',
      extra: {
        'update': {
          'app': target,
          'version': entry['version'],
          'notes': entry['notes'],
          'files': {
            for (final e in files.entries)
              e.key: {
                ...(e.value as Map<String, dynamic>),
                'url': '/admin/desktop/files/${(e.value as Map<String, dynamic>)['name']}'
                    '?ticket=${ticketFor((e.value as Map<String, dynamic>)['name'] as String)}',
              },
          },
        },
      },
    );
  }
}

/// Récupère le condensé d'une conversion par blocs.
class _DigestSink implements Sink<c.Digest> {
  c.Digest? value;
  @override
  void add(c.Digest data) => value = data;
  @override
  void close() {}
}

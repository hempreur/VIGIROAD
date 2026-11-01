import 'dart:convert';

import 'config.dart';
import 'db.dart';
import 'geoip.dart';
import 'http_kit.dart';
import 'security.dart';

/// Droits accordés par rôle. Toute action est vérifiée côté serveur.
enum Perm { read, serverControl, backups, usersManage, usersDelete, export, settings, adminsManage, deploy }

const rolePerms = <String, Set<Perm>>{
  'viewer': {Perm.read},
  'operator': {Perm.read, Perm.serverControl, Perm.backups},
  'admin': {
    Perm.read,
    Perm.serverControl,
    Perm.backups,
    Perm.usersManage,
    Perm.usersDelete,
    Perm.export,
    Perm.settings,
  },
  'owner': {...Perm.values},
};

const roleLabels = {
  'owner': 'Propriétaire',
  'admin': 'Administrateur',
  'operator': 'Opérateur serveur',
  'viewer': 'Lecture seule',
};

/// Administrateur authentifié (mot de passe + code TOTP).
class AdminPrincipal {
  const AdminPrincipal({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.sessionId,
    this.ipPrefix,
  });

  final String id;
  final String email;
  final String displayName;
  final String role;
  final String sessionId;
  final String? ipPrefix;

  Set<Perm> get perms => rolePerms[role] ?? const {};
  bool can(Perm p) => perms.contains(p);

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'role': role,
    'roleLabel': roleLabels[role],
    'permissions': [for (final p in perms) p.name],
  };
}

/// Dépendances partagées par les services.
class AppContext {
  AppContext({required this.config, required this.db, required this.geo, PasswordHasher? hasher, SecretBoxer? boxer})
    : hasher = hasher ?? PasswordHasher(memoryKb: config.argonMemoryKb, iterations: config.argonIterations),
      boxer = boxer ?? SecretBoxer(config.masterKey);

  final AdminConfig config;
  final Db db;
  GeoIp geo;
  final PasswordHasher hasher;
  final SecretBoxer boxer;

  /// Dernières erreurs internes (consultables dans « Maintenance »).
  final recentErrors = <Map<String, Object?>>[];

  final requestStats = RequestStats();

  void recordError(String where, Object error) {
    recentErrors.insert(0, {'at': DateTime.now().toUtc().toIso8601String(), 'where': where, 'error': '$error'});
    if (recentErrors.length > 100) recentErrors.removeLast();
  }

  Future<Map<String, dynamic>> settings() async => {
    for (final r in await db.query('SELECT key, value FROM settings')) r['key'] as String: r['value'],
  };

  Future<int> intSetting(String key, int fallback) async {
    final r = await db.one('SELECT value FROM settings WHERE key = @k', {'k': key});
    final v = r?['value'];
    return v is num ? v.toInt() : fallback;
  }

  /// Journal des actions sensibles (succès et refus).
  Future<void> audit(
    AdminPrincipal? a,
    String action, {
    String? targetType,
    String? targetId,
    Map<String, Object?> details = const {},
    bool success = true,
    String? email,
    String? ipPrefix,
  }) async {
    try {
      await db.exec(
        'INSERT INTO admin_audit_logs (admin_id, admin_email, action, target_type, target_id, success, details, ip_prefix) '
        'VALUES (CAST(@a AS uuid), @e, @act, @tt, @tid, @s, CAST(@d AS jsonb), @ip)',
        {
          'a': a?.id,
          'e': a?.email ?? email,
          'act': action,
          'tt': targetType,
          'tid': targetId,
          's': success,
          'd': jsonEncode(details),
          'ip': a?.ipPrefix ?? ipPrefix,
        },
      );
    } catch (e) {
      recordError('audit', e);
    }
  }
}

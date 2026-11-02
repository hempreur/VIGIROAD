import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/session.dart';
import '../format.dart';
import '../theme.dart';
import '../update/updater.dart';
import '../widgets/dialogs.dart';
import '../widgets/fetch.dart';
import '../widgets/panel.dart';
import '../widgets/table.dart';
import 'common.dart';

/// Journal des actions administratives (audit).
class AuditPage extends StatefulWidget {
  const AuditPage({super.key});

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  String _action = '';
  int _offset = 0;

  static const _labels = {
    'admin.login': 'connexion administrateur',
    'admin.logout': 'déconnexion administrateur',
    'admin.setup': 'création du propriétaire',
    'admin.mfa_enrolled': 'double authentification activée',
    'admin.create': 'administrateur créé',
    'admin.update': 'administrateur modifié',
    'admin.delete': 'administrateur supprimé',
    'admin.reset_mfa': 'double authentification réinitialisée',
    'admin.password_change': 'mot de passe changé',
    'user.update': 'utilisateur modifié',
    'user.disable': 'utilisateur désactivé',
    'user.enable': 'utilisateur réactivé',
    'user.revoke_sessions': 'sessions révoquées',
    'user.reset_access': 'accès réinitialisé',
    'user.export': 'données exportées',
    'users.export': 'liste exportée',
    'user.delete': 'utilisateur supprimé',
    'device.revoke': 'appareil révoqué',
    'session.revoke': 'session révoquée',
    'docker.start': 'conteneur démarré',
    'docker.stop': 'conteneur arrêté',
    'docker.restart': 'conteneur redémarré',
    'backup.manual': 'sauvegarde demandée',
    'backup.restore_test': 'test de restauration demandé',
    'deploy.request': 'mise à jour du serveur',
    'settings.update': 'réglages modifiés',
    'maintenance.retention': 'conservation appliquée',
    'denied': 'action refusée (droits)',
  };

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      Row(
        children: [
          PeriodPicker(
            value: _action,
            options: const {'': 'Tout', 'admin.': 'Administrateurs', 'user': 'Utilisateurs', 'docker.': 'Docker', 'backup.': 'Sauvegardes', 'denied': 'Refus'},
            onChanged: (v) => setState(() {
              _action = v;
              _offset = 0;
            }),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Panel(
        padding: const EdgeInsets.all(8),
        child: Fetch(
          key: ValueKey('$_action|$_offset'),
          refresh: const Duration(seconds: 30),
          load: (api) => api.get('/admin/audit', query: {if (_action.isNotEmpty) 'action': _action, 'limit': '100', 'offset': '$_offset'}),
          builder: (context, d, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VrTable(
                empty: 'Journal vide',
                columns: const [
                  VrColumn('Date', flex: 2),
                  VrColumn('Administrateur', flex: 2),
                  VrColumn('Action', flex: 3),
                  VrColumn('Cible', flex: 2),
                  VrColumn('Résultat'),
                  VrColumn('Détails', flex: 3),
                ],
                rows: [
                  for (final e in listOf(d['items']))
                    [
                      CellText(Fmt.dateTime(e['at'])),
                      CellText('${e['adminEmail'] ?? '—'}'),
                      CellText(_labels[e['action']] ?? '${e['action']}'),
                      CellText(e['targetType'] == null ? '—' : '${e['targetType']} ${('${e['targetId'] ?? ''}').split('-').first}', muted: true, mono: true),
                      StatusPill(e['success'] == true ? 'réussi' : 'refusé', e['success'] == true ? Health.ok : Health.critical),
                      CellText(
                        (e['details'] as Map<String, dynamic>? ?? const {}).isEmpty ? '' : jsonEncode(e['details']),
                        muted: true,
                        mono: true,
                      ),
                    ],
                ],
              ),
              Pager(offset: _offset, limit: 100, total: d['total'] as int, onChanged: (o) => setState(() => _offset = o)),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Comptes administrateurs et rôles (propriétaire uniquement).
class AdminsPage extends StatefulWidget {
  const AdminsPage({super.key});

  @override
  State<AdminsPage> createState() => _AdminsPageState();
}

class _AdminsPageState extends State<AdminsPage> {
  int _gen = 0;

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return PageBody(
      children: [
        Panel(
          title: 'Rôles',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Propriétaire : tous les droits, dont la gestion des administrateurs et la mise à jour du serveur.', style: VrText.caption),
              Text('Administrateur : utilisateurs, appareils, sessions, exports, réglages, Docker et sauvegardes.', style: VrText.caption),
              Text('Opérateur serveur : supervision, Docker et sauvegardes, sans accès aux actions sur les comptes.', style: VrText.caption),
              Text('Lecture seule : consultation uniquement.', style: VrText.caption),
              const SizedBox(height: 6),
              Text('La double authentification (TOTP) est obligatoire pour tous les rôles.', style: VrText.caption.copyWith(color: VrColors.cyan)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'Administrateurs',
          trailing: VrButton(label: 'Ajouter', icon: Icons.person_add_alt_1_rounded, onPressed: () => unawaited(_create(context))),
          child: Fetch(
            key: ValueKey(_gen),
            load: (api) => api.get('/admin/admins'),
            builder: (context, d, _) => VrTable(
              columns: const [
                VrColumn('Administrateur', flex: 3),
                VrColumn('Rôle', flex: 2),
                VrColumn('État', flex: 2),
                VrColumn('TOTP'),
                VrColumn('Dernière connexion', flex: 2),
                VrColumn('Actions', flex: 3),
              ],
              rows: [
                for (final a in listOf(d['admins']))
                  [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [CellText('${a['displayName']}'), CellText('${a['email']}', muted: true)],
                    ),
                    CellText('${(d['roles'] as Map<String, dynamic>)[a['role']]}'),
                    StatusPill(
                      a['locked'] == true ? 'verrouillé' : (a['status'] == 'active' ? 'actif' : 'désactivé'),
                      a['status'] == 'active' && a['locked'] != true ? Health.ok : Health.critical,
                    ),
                    Icon(
                      a['totpConfirmed'] == true ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded,
                      color: a['totpConfirmed'] == true ? VrColors.ok : VrColors.warning,
                      size: 18,
                    ),
                    CellText(Fmt.ago(a['lastLoginAt'])),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PopupMenuButton<String>(
                          tooltip: 'Changer le rôle',
                          icon: const Icon(Icons.manage_accounts_rounded, size: 20),
                          onSelected: (r) => unawaited(_patch(context, a, {'role': r}, 'Rôle modifié')),
                          itemBuilder: (_) => [
                            for (final e in (d['roles'] as Map<String, dynamic>).entries)
                              PopupMenuItem(value: e.key, child: Text('${e.value}')),
                          ],
                        ),
                        IconButton(
                          tooltip: a['status'] == 'active' ? 'Désactiver' : 'Activer',
                          onPressed: () => unawaited(_patch(
                            context,
                            a,
                            {'status': a['status'] == 'active' ? 'disabled' : 'active'},
                            a['status'] == 'active' ? 'Administrateur désactivé' : 'Administrateur activé',
                          )),
                          icon: Icon(a['status'] == 'active' ? Icons.block_rounded : Icons.check_circle_outline_rounded, size: 19),
                        ),
                        IconButton(
                          tooltip: 'Réinitialiser la double authentification',
                          onPressed: () async {
                            if (!await confirm(
                              context,
                              title: 'Réinitialiser la double authentification ?',
                              message: '${a['email']} devra enrôler une nouvelle application d\'authentification à sa prochaine connexion.',
                            )) {
                              return;
                            }
                            if (!context.mounted) return;
                            await runAction(context, () => s.api.post('/admin/admins/${a['id']}/reset-mfa'), success: 'Double authentification réinitialisée');
                            setState(() => _gen++);
                          },
                          icon: const Icon(Icons.phonelink_lock_rounded, size: 19),
                        ),
                        if (a['id'] != s.admin?['id'])
                          IconButton(
                            tooltip: 'Supprimer',
                            onPressed: () async {
                              if (!await confirm(
                                context,
                                title: 'Supprimer ${a['email']} ?',
                                message: 'Ce compte administrateur sera supprimé (le journal d\'audit est conservé).',
                                action: 'Supprimer',
                                danger: true,
                                typed: '${a['email']}',
                              )) {
                                return;
                              }
                              if (!context.mounted) return;
                              await runAction(context, () => s.api.delete('/admin/admins/${a['id']}'), success: 'Administrateur supprimé');
                              setState(() => _gen++);
                            },
                            icon: const Icon(Icons.delete_outline_rounded, size: 19, color: VrColors.criticalText),
                          ),
                      ],
                    ),
                  ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _patch(BuildContext context, Map<String, dynamic> a, Map<String, Object> body, String ok) async {
    await runAction(context, () => SessionScope.read(context).api.patch('/admin/admins/${a['id']}', body), success: ok);
    setState(() => _gen++);
  }

  Future<void> _create(BuildContext context) async {
    final r = await editFields(
      context,
      title: 'Nouvel administrateur',
      fields: const {
        'displayName': 'Nom',
        'email': 'Adresse e-mail',
        'role': 'Rôle (owner, admin, operator, viewer)',
        'password': 'Mot de passe provisoire (12 caractères minimum)',
      },
      initial: const {'role': 'viewer'},
      obscure: const {'password'},
      action: 'Créer',
    );
    if (r == null || !context.mounted) return;
    await runAction(
      context,
      () => SessionScope.read(context).api.post('/admin/admins', r),
      success: 'Administrateur créé : il activera la double authentification à sa première connexion',
    );
    setState(() => _gen++);
  }
}

/// Connexion, sécurité, conservation des données, version et mises à jour.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.appName, required this.updater});
  final String appName;
  final DesktopUpdater updater;

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return PageBody(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Panel(
                title: 'Connexion',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InfoRow('Serveur', '${s.server}'),
                    InfoRow('Administrateur', '${s.admin?['displayName']} <${s.admin?['email']}>'),
                    InfoRow('Rôle', s.role),
                    InfoRow('Sécurité', 'HTTPS · mot de passe Argon2id · double authentification TOTP'),
                    InfoRow('Inactivité', 'déconnexion automatique après ${s.inactivity.inMinutes} minutes'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      children: [
                        VrButton(label: 'Changer mon mot de passe', icon: Icons.password_rounded, primary: false, onPressed: () => unawaited(_password(context))),
                        VrButton(label: 'Se déconnecter', icon: Icons.logout_rounded, primary: false, onPressed: () => unawaited(s.logout())),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Panel(
                title: 'Application',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InfoRow('Logiciel', appName),
                    InfoRow('Version', updater.currentVersion),
                    const InfoRow('Éditeur', 'VIGIROAD INC (CODEX HEMPREUR)'),
                    const InfoRow('Polices', 'Rajdhani et Inter (SIL OFL 1.1)'),
                    const InfoRow('Carte', 'Natural Earth (domaine public)'),
                    const SizedBox(height: 10),
                    ValueListenableBuilder(
                      valueListenable: updater.available,
                      builder: (context, u, _) => Row(
                        children: [
                          VrButton(
                            label: 'Rechercher une mise à jour',
                            icon: Icons.update_rounded,
                            primary: false,
                            onPressed: () async {
                              await updater.check();
                              if (context.mounted && updater.available.value == null) notify(context, 'Votre version est à jour');
                            },
                          ),
                          const SizedBox(width: 10),
                          if (u != null) Text('Version ${u.version} disponible', style: VrText.caption.copyWith(color: VrColors.cyan)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Mises à jour automatiques : vérifiées toutes les 15 minutes sur votre serveur et installées sans intervention.',
                      style: VrText.caption,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'Conservation des données',
          child: Fetch(
            load: (api) => api.get('/admin/settings'),
            builder: (context, d, reload) => _Retention(d, editable: s.can('settings'), reload: reload),
          ),
        ),
      ],
    );
  }

  Future<void> _password(BuildContext context) async {
    final r = await editFields(
      context,
      title: 'Changer mon mot de passe',
      fields: const {'current': 'Mot de passe actuel', 'new': 'Nouveau mot de passe (12 caractères minimum)'},
      obscure: const {'current', 'new'},
    );
    if (r == null || !context.mounted) return;
    await runAction(
      context,
      () => SessionScope.read(context).api.post('/admin/me/password', r),
      success: 'Mot de passe changé (vos autres sessions sont fermées)',
    );
  }
}

class _Retention extends StatelessWidget {
  const _Retention(this.d, {required this.editable, required this.reload});
  final Map<String, dynamic> d;
  final bool editable;
  final Future<void> Function() reload;

  static const _labels = {
    'retention.login_events_days': 'Historique des connexions (jours)',
    'retention.sessions_days': 'Sessions terminées (jours)',
    'retention.location_days': 'Positions approximatives (jours)',
    'retention.metrics_days': 'Mesures du serveur (jours)',
    'retention.audit_days': 'Journal d\'audit (jours)',
    'sessions.idle_expiry_days': 'Expiration des sessions inactives (jours)',
    'backups.keep': 'Sauvegardes conservées (nombre)',
  };

  @override
  Widget build(BuildContext context) {
    final settings = d['settings'] as Map<String, dynamic>;
    final limits = d['limits'] as Map<String, dynamic>;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in _labels.entries)
          InfoRow(
            e.value,
            '${settings[e.key]}',
            trailing: editable
                ? IconButton(
                    tooltip: 'Modifier',
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    onPressed: () async {
                      final range = (limits[e.key] as List<dynamic>).cast<int>();
                      final r = await editFields(
                        context,
                        title: e.value,
                        fields: {'v': 'Valeur (${range[0]} à ${range[1]})'},
                        initial: {'v': '${settings[e.key]}'},
                      );
                      final v = int.tryParse(r?['v'] ?? '');
                      if (v == null || !context.mounted) return;
                      await runAction(context, () => SessionScope.read(context).api.put('/admin/settings', {e.key: v}), success: 'Réglage enregistré');
                      await reload();
                    },
                  )
                : null,
          ),
        if (editable) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: VrButton(
              label: 'Appliquer la conservation maintenant',
              icon: Icons.cleaning_services_rounded,
              primary: false,
              onPressed: () async {
                final r = await runAction(context, () => SessionScope.read(context).api.post('/admin/maintenance/retention'));
                if (r != null && context.mounted) {
                  final n = r.values.whereType<num>().fold<num>(0, (a, b) => a + b);
                  notify(context, '$n élément(s) supprimé(s) ou expiré(s)');
                }
              },
            ),
          ),
        ],
      ],
    );
  }
}

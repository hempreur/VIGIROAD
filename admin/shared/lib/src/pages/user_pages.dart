import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/session.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/dialogs.dart';
import '../widgets/fetch.dart';
import '../widgets/panel.dart';
import '../widgets/table.dart';
import '../widgets/world_map.dart';
import 'common.dart';
import 'server_pages.dart';

/// Tableau de bord : utilisateurs, appareils, sessions, activité, disponibilité.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _period = '7d';

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return PageBody(
      children: [
        Fetch(
          refresh: const Duration(seconds: 20),
          load: (api) => api.get('/admin/dashboard'),
          builder: (context, d, _) => ValueListenableBuilder(
            valueListenable: s.snapshot,
            builder: (context, snap, _) {
              final online = (snap?['counts'] as Map<String, dynamic>?)?['usersOnline'] ?? d['usersOnline'];
              final sessionsOnline = (snap?['counts'] as Map<String, dynamic>?)?['sessionsOnline'] ?? d['sessionsOnline'];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ResponsiveGrid(
                    minWidth: 250,
                    children: [
                      StatCard(
                        label: 'Utilisateurs enregistrés',
                        value: Fmt.number(d['usersTotal'] as num?),
                        icon: Icons.people_alt_rounded,
                        sub: '+${d['usersNew24h']} en 24 h · ${d['usersDisabled']} désactivé(s)',
                      ),
                      StatCard(
                        label: 'Utilisateurs connectés',
                        value: Fmt.number(online as num?),
                        icon: Icons.wifi_tethering_rounded,
                        color: VrColors.ok,
                        sub: 'activité dans les 2 dernières minutes',
                      ),
                      StatCard(
                        label: 'Appareils enregistrés',
                        value: Fmt.number(d['devicesTotal'] as num?),
                        icon: Icons.smartphone_rounded,
                        color: VrColors.electricBright,
                        sub: '${d['devicesOnline']} en ligne',
                      ),
                      StatCard(
                        label: 'Sessions actives',
                        value: Fmt.number(sessionsOnline as num?),
                        icon: Icons.timelapse_rounded,
                        sub: '${d['sessionsOpen']} ouvertes au total',
                      ),
                      StatCard(
                        label: 'Connexions aujourd\'hui',
                        value: Fmt.number(d['loginsToday'] as num?),
                        icon: Icons.login_rounded,
                        sub: '${d['failedLogins24h']} échec(s) en 24 h',
                        color: (d['failedLogins24h'] as num? ?? 0) > 20 ? VrColors.warning : VrColors.cyan,
                      ),
                      StatCard(
                        label: 'Durée moyenne d\'utilisation',
                        value: Fmt.duration(d['avgSessionSeconds'] as num?),
                        icon: Icons.av_timer_rounded,
                        sub: 'par session (30 jours)',
                      ),
                      StatCard(
                        label: 'Utilisation aujourd\'hui',
                        value: Fmt.duration(d['usageTodaySeconds'] as num?),
                        icon: Icons.insights_rounded,
                        sub: 'temps cumulé des utilisateurs',
                      ),
                      StatCard(
                        label: 'Disponibilité du serveur',
                        value: (d['samples24h'] as num? ?? 0) == 0 ? '—' : Fmt.percent(dbl(d['availability24h'])! * 100, digits: 2),
                        icon: Icons.verified_rounded,
                        color: VrColors.ok,
                        sub: '24 h · ${Fmt.percent(dbl(d['availability30d'])! * 100, digits: 2)} sur 30 jours',
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'Activité',
          trailing: PeriodPicker(
            value: _period,
            options: const {'24h': '24 h', '7d': '7 jours', '30d': '30 jours'},
            onChanged: (p) => setState(() => _period = p),
          ),
          child: Fetch(
            key: ValueKey(_period),
            refresh: const Duration(minutes: 1),
            load: (api) => api.get('/admin/stats/activity', query: {'period': _period}),
            builder: (context, d, _) {
              final pts = listOf(d['points']);
              final labels = [for (final p in pts) _period == '24h' ? Fmt.time(p['at']) : Fmt.date(p['at']).substring(0, 5)];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VrLineChart(
                    labels: labels,
                    height: 230,
                    series: [
                      ChartSeries('Utilisateurs actifs', [for (final p in pts) dbl(p['activeUsers'])], color: VrColors.cyan),
                      ChartSeries('Connexions', [for (final p in pts) dbl(p['logins'])], color: VrColors.electricBright),
                      ChartSeries('Nouveaux comptes', [for (final p in pts) dbl(p['newUsers'])], color: VrColors.ok, area: false),
                      ChartSeries('Échecs de connexion', [for (final p in pts) dbl(p['failedLogins'])], color: VrColors.critical, area: false),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Temps d\'utilisation cumulé (heures)', style: VrText.label),
                  const SizedBox(height: 8),
                  VrLineChart(
                    labels: labels,
                    height: 170,
                    bars: true,
                    yFormat: (v) => Fmt.number(v, digits: v < 10 ? 1 : 0),
                    series: [ChartSeries('Heures', [for (final p in pts) (dbl(p['usageSeconds']) ?? 0) / 3600], color: VrColors.electricBright)],
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Panel(
                title: 'Versions de l\'application',
                child: Fetch(
                  load: (api) => api.get('/admin/dashboard'),
                  builder: (context, d, _) {
                    final v = listOf(d['appVersions']);
                    final total = v.fold<num>(0, (a, b) => a + (b['users'] as num));
                    return Column(
                      children: [
                        if (v.isEmpty) const EmptyState('Aucun utilisateur'),
                        for (final x in v)
                          MeterBar(label: '${x['version']}', percent: total == 0 ? 0 : (x['users'] as num) / total * 100, trailing: '${x['users']}'),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Panel(
                title: 'Serveur en direct',
                child: ValueListenableBuilder(
                  valueListenable: s.snapshot,
                  builder: (context, snap, _) {
                    final m = snap?['metrics'] as Map<String, dynamic>?;
                    final mem = m?['memory'] as Map<String, dynamic>?;
                    final disk = listOf(m?['disks']).firstOrNull;
                    final traffic = snap?['traffic'] as Map<String, dynamic>?;
                    return Column(
                      children: [
                        MeterBar(label: 'CPU', percent: dbl(m?['cpuPercent']) ?? 0),
                        MeterBar(label: 'RAM', percent: mem == null ? 0 : (mem['used'] as num) / (mem['total'] as num) * 100),
                        MeterBar(label: 'Disque', percent: disk == null ? 0 : (disk['used'] as num) / (disk['total'] as num) * 100),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            StatusDot(traffic?['ok'] == true ? Health.ok : (traffic == null ? Health.unknown : Health.critical)),
                            const SizedBox(width: 8),
                            Text(
                              traffic == null
                                  ? 'État du trafic en attente'
                                  : (traffic['ok'] == true ? 'Backend GPS et trafic opérationnel (${traffic['latencyMs']} ms)' : 'Backend trafic indisponible'),
                              style: VrText.caption,
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Comptes VIGIROAD : recherche, filtres, fiche détaillée et actions.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  String _q = '';
  String _status = '';
  bool _online = false;
  String _sort = 'created';
  int _offset = 0;
  String? _selected;
  int _gen = 0;
  static const _limit = 50;

  @override
  Widget build(BuildContext context) {
    if (_selected != null) {
      return UserDetail(
        key: ValueKey(_selected),
        userId: _selected!,
        onBack: () => setState(() {
          _selected = null;
          _gen++;
        }),
      );
    }
    final s = SessionScope.of(context);
    return PageBody(
      children: [
        Row(
          children: [
            SearchField(
              hint: 'Pseudonyme, e-mail, nom ou identifiant…',
              onChanged: (q) => setState(() {
                _q = q;
                _offset = 0;
              }),
            ),
            const SizedBox(width: 12),
            PeriodPicker(
              value: _status,
              options: const {'': 'Tous', 'active': 'Actifs', 'disabled': 'Désactivés'},
              onChanged: (v) => setState(() {
                _status = v;
                _offset = 0;
              }),
            ),
            const SizedBox(width: 12),
            FilterChip(
              label: const Text('Connectés'),
              selected: _online,
              onSelected: (v) => setState(() {
                _online = v;
                _offset = 0;
              }),
            ),
            const Spacer(),
            if (s.can('export'))
              VrButton(
                label: 'Exporter (CSV)',
                icon: Icons.download_rounded,
                primary: false,
                onPressed: () async {
                  final csv = await runAction(context, () => s.api.getText('/admin/users/export'));
                  if (csv != null && context.mounted) {
                    await saveExport(context, name: 'vigiroad-utilisateurs.csv', content: csv, extension: 'csv');
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        Panel(
          padding: const EdgeInsets.all(8),
          child: Fetch(
            key: ValueKey('$_q|$_status|$_online|$_sort|$_offset|$_gen'),
            refresh: const Duration(seconds: 30),
            load: (api) => api.get('/admin/users', query: {
              if (_q.isNotEmpty) 'q': _q,
              if (_status.isNotEmpty) 'status': _status,
              if (_online) 'online': 'true',
              'sort': _sort,
              'limit': '$_limit',
              'offset': '$_offset',
            }),
            builder: (context, d, _) {
              final items = listOf(d['items']);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VrTable(
                    empty: 'Aucun utilisateur ne correspond',
                    sortKey: _sort,
                    onSort: (k) => setState(() => _sort = k),
                    onTap: (i) => setState(() => _selected = items[i]['id'] as String),
                    columns: const [
                      VrColumn('Utilisateur', flex: 3, sortKey: 'pseudonym'),
                      VrColumn('E-mail', flex: 3),
                      VrColumn('Statut', flex: 2),
                      VrColumn('Créé le', flex: 2, sortKey: 'created'),
                      VrColumn('Dernière activité', flex: 2, sortKey: 'lastSeen'),
                      VrColumn('Appareils', numeric: true),
                      VrColumn('Utilisation', numeric: true, sortKey: 'usage'),
                      VrColumn('Pays'),
                      VrColumn('Version'),
                    ],
                    rows: [
                      for (final u in items)
                        [
                          Row(
                            children: [
                              StatusDot(u['online'] == true ? Health.ok : Health.unknown, size: 8),
                              const SizedBox(width: 10),
                              Flexible(child: CellText('${u['pseudonym']}${u['displayName'] == null ? '' : ' · ${u['displayName']}'}')),
                            ],
                          ),
                          CellText('${u['email'] ?? '—'}', muted: u['email'] == null),
                          StatusPill(u['status'] == 'active' ? 'actif' : 'désactivé', u['status'] == 'active' ? Health.ok : Health.critical),
                          CellText(Fmt.date(u['createdAt'])),
                          CellText(Fmt.ago(u['lastSeenAt'])),
                          CellText('${u['devices']}'),
                          CellText(Fmt.duration(u['totalActiveSeconds'] as num?)),
                          CellText(u['country'] == null ? '—' : '${Fmt.flag(u['country'] as String)} ${u['country']}'),
                          CellText('${u['appVersion'] ?? '—'}', muted: true),
                        ],
                    ],
                  ),
                  Pager(offset: _offset, limit: _limit, total: d['total'] as int, onChanged: (o) => setState(() => _offset = o)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Fiche utilisateur : informations, appareils, sessions, utilisation,
/// connexions, positions consenties, actions administrateur.
class UserDetail extends StatefulWidget {
  const UserDetail({super.key, required this.userId, required this.onBack});
  final String userId;
  final VoidCallback onBack;

  @override
  State<UserDetail> createState() => _UserDetailState();
}

class _UserDetailState extends State<UserDetail> {
  int _gen = 0;

  void _reload() => setState(() => _gen++);

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final id = widget.userId;
    return PageBody(
      children: [
        Row(
          children: [
            TextButton.icon(
              key: const Key('user-back'),
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Tous les utilisateurs'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Fetch(
          key: ValueKey(_gen),
          refresh: const Duration(seconds: 30),
          load: (api) => api.get('/admin/users/$id'),
          builder: (context, d, _) {
            final u = d['user'] as Map<String, dynamic>;
            final active = u['status'] == 'active';
            final manage = s.can('usersManage');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Panel(
                  glow: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: VrColors.cyan.withValues(alpha: 0.15),
                            child: Text('${u['pseudonym']}'.substring(0, 1).toUpperCase(), style: VrText.title.copyWith(color: VrColors.cyan)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${u['pseudonym']}', style: VrText.display.copyWith(fontSize: 26)),
                                Text('${u['displayName'] ?? ''}', style: VrText.caption),
                              ],
                            ),
                          ),
                          StatusPill(u['online'] == true ? 'connecté' : 'hors ligne', u['online'] == true ? Health.ok : Health.unknown),
                          const SizedBox(width: 8),
                          StatusPill(active ? 'actif' : 'désactivé', active ? Health.ok : Health.critical),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (manage)
                            VrButton(label: 'Modifier', icon: Icons.edit_rounded, primary: false, onPressed: () => unawaited(_edit(context, u))),
                          if (manage)
                            VrButton(
                              key: Key(active ? 'user-disable' : 'user-enable'),
                              label: active ? 'Désactiver' : 'Activer',
                              icon: active ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                              primary: false,
                              danger: active,
                              onPressed: () => unawaited(_toggle(context, u)),
                            ),
                          if (manage)
                            VrButton(
                              label: 'Révoquer les sessions',
                              icon: Icons.logout_rounded,
                              primary: false,
                              onPressed: () => unawaited(_revokeAll(context, u)),
                            ),
                          if (manage)
                            VrButton(
                              key: const Key('user-reset'),
                              label: 'Réinitialiser l\'accès',
                              icon: Icons.lock_reset_rounded,
                              primary: false,
                              onPressed: () => unawaited(_reset(context, u)),
                            ),
                          if (s.can('export'))
                            VrButton(
                              label: 'Exporter',
                              icon: Icons.download_rounded,
                              primary: false,
                              onPressed: () async {
                                final data = await runAction(context, () => s.api.get('/admin/users/$id/export'));
                                if (data != null && context.mounted) {
                                  await saveExport(
                                    context,
                                    name: 'vigiroad-${u['pseudonym']}.json',
                                    content: const JsonEncoder.withIndent('  ').convert(data),
                                    extension: 'json',
                                  );
                                }
                              },
                            ),
                          if (s.can('usersDelete'))
                            VrButton(
                              key: const Key('user-delete'),
                              label: 'Supprimer le compte',
                              icon: Icons.delete_forever_rounded,
                              danger: true,
                              onPressed: () => unawaited(_delete(context, u)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Panel(
                        title: 'Informations',
                        child: Column(
                          children: [
                            InfoRow('Identifiant', '${u['id']}', mono: true),
                            InfoRow('Pseudonyme', '${u['pseudonym']}'),
                            InfoRow('Nom', '${u['displayName'] ?? '—'}'),
                            InfoRow('Adresse e-mail', '${u['email'] ?? 'non renseignée'}'),
                            InfoRow('Création du compte', Fmt.dateTime(u['createdAt'])),
                            InfoRow('Dernière connexion', '${Fmt.dateTime(u['lastLoginAt'])} (${Fmt.ago(u['lastLoginAt'])})'),
                            InfoRow('Dernière activité', Fmt.ago(u['lastSeenAt'])),
                            InfoRow('Durée totale d\'utilisation', Fmt.duration(u['totalActiveSeconds'] as num?)),
                            InfoRow('Appareils associés', '${u['devices']}'),
                            InfoRow(
                              'Pays (approximatif)',
                              u['regionConsent'] == true
                                  ? (u['country'] == null ? 'inconnu' : '${Fmt.flag(u['country'] as String)} ${Fmt.country(u['country'] as String)}')
                                  : 'non autorisé par l\'utilisateur',
                            ),
                            InfoRow('Position approximative', u['locationConsent'] == true ? 'autorisée (≈ 5 km)' : 'désactivée'),
                            InfoRow('Version de l\'application', '${u['appVersion'] ?? '—'}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Panel(
                        title: 'Utilisation sur 30 jours',
                        child: _Usage(listOf(d['usage'])),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Panel(
                  title: 'Appareils',
                  child: DevicesTable(listOf(d['devices']), withUser: false, onChanged: _reload),
                ),
                const SizedBox(height: 16),
                Panel(
                  title: 'Historique des sessions',
                  child: SessionsTable(listOf(d['sessions']), withUser: false, onChanged: _reload),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Panel(
                        title: 'Connexions récentes',
                        child: VrTable(
                          maxHeight: 320,
                          empty: 'Aucune connexion',
                          columns: const [VrColumn('Date', flex: 2), VrColumn('Résultat'), VrColumn('Méthode', flex: 2), VrColumn('Réseau', flex: 2)],
                          rows: [
                            for (final l in listOf(d['logins']))
                              [
                                CellText(Fmt.dateTime(l['at'])),
                                StatusPill(l['success'] == true ? 'réussie' : 'échec', l['success'] == true ? Health.ok : Health.critical),
                                CellText(Fmt.loginReason(l['reason'])),
                                CellText('${l['ipPrefix'] ?? '—'}${l['country'] == null ? '' : ' ${Fmt.flag(l['country'] as String)}'}', mono: true),
                              ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Panel(
                        title: 'Positions approximatives',
                        child: listOf(d['locations']).isEmpty
                            ? EmptyState(
                                u['locationConsent'] == true ? 'Aucune position enregistrée' : 'L\'utilisateur n\'a pas autorisé la localisation.',
                                icon: Icons.location_off_rounded,
                              )
                            : WorldMap(
                                height: 260,
                                values: const {},
                                unit: 'positions',
                                points: [
                                  for (final p in listOf(d['locations'])) (lat: dbl(p['lat'])!, lng: dbl(p['lng'])!, weight: 1),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, Map<String, dynamic> u) async {
    final r = await editFields(
      context,
      title: 'Modifier ${u['pseudonym']}',
      fields: const {'pseudonym': 'Pseudonyme', 'displayName': 'Nom', 'email': 'Adresse e-mail'},
      initial: {'pseudonym': '${u['pseudonym']}', 'displayName': '${u['displayName'] ?? ''}', 'email': '${u['email'] ?? ''}'},
    );
    if (r == null || !context.mounted) return;
    await runAction(
      context,
      () => SessionScope.read(context).api.patch('/admin/users/${u['id']}', {
        'pseudonym': r['pseudonym'],
        'displayName': r['displayName']!.isEmpty ? null : r['displayName'],
        'email': r['email']!.isEmpty ? null : r['email'],
      }),
      success: 'Informations mises à jour',
    );
    _reload();
  }

  Future<void> _toggle(BuildContext context, Map<String, dynamic> u) async {
    final active = u['status'] == 'active';
    if (active &&
        !await confirm(
          context,
          title: 'Désactiver ${u['pseudonym']} ?',
          message: 'Le compte ne pourra plus se connecter et toutes ses sessions seront fermées immédiatement.',
          action: 'Désactiver',
          danger: true,
        )) {
      return;
    }
    if (!context.mounted) return;
    await runAction(
      context,
      () => SessionScope.read(context).api.post('/admin/users/${u['id']}/${active ? 'disable' : 'enable'}'),
      success: active ? 'Compte désactivé' : 'Compte réactivé',
    );
    _reload();
  }

  Future<void> _revokeAll(BuildContext context, Map<String, dynamic> u) async {
    if (!await confirm(
      context,
      title: 'Révoquer toutes les sessions ?',
      message: '${u['pseudonym']} sera déconnecté de tous ses appareils.',
      action: 'Révoquer',
    )) {
      return;
    }
    if (!context.mounted) return;
    final r = await runAction(context, () => SessionScope.read(context).api.post('/admin/users/${u['id']}/revoke-sessions'));
    if (r != null && context.mounted) notify(context, '${r['revoked']} session(s) révoquée(s)');
    _reload();
  }

  Future<void> _reset(BuildContext context, Map<String, dynamic> u) async {
    if (!await confirm(
      context,
      title: 'Réinitialiser l\'accès de ${u['pseudonym']} ?',
      message: 'Un code à usage unique (valable 30 minutes) sera généré. Transmettez-le à l\'utilisateur par un canal sûr ; '
          'il pourra choisir un nouveau mot de passe dans l\'application. Ses sessions actuelles sont fermées.',
      action: 'Générer le code',
    )) {
      return;
    }
    if (!context.mounted) return;
    final r = await runAction(context, () => SessionScope.read(context).api.post('/admin/users/${u['id']}/reset-access'));
    if (r != null && context.mounted) {
      await showSecret(
        context,
        title: 'Code de réinitialisation',
        value: '${r['code']}',
        help: 'Valable jusqu\'à ${Fmt.time(r['expiresAt'])}. Ce code n\'est affiché qu\'une fois et n\'est jamais enregistré en clair.',
      );
    }
    _reload();
  }

  Future<void> _delete(BuildContext context, Map<String, dynamic> u) async {
    final ok = await confirm(
      context,
      title: 'Supprimer définitivement ${u['pseudonym']} ?',
      message: 'Le compte et toutes ses données (appareils, sessions, statistiques, positions, historique de connexion) '
          'seront effacés. Cette action est irréversible.',
      action: 'Supprimer',
      danger: true,
      typed: '${u['pseudonym']}',
    );
    if (!ok || !context.mounted) return;
    final r = await runAction(
      context,
      () => SessionScope.read(context).api.delete('/admin/users/${u['id']}', query: {'confirm': '${u['pseudonym']}'}),
      success: 'Compte supprimé',
    );
    if (r != null) widget.onBack();
  }
}

class _Usage extends StatelessWidget {
  const _Usage(this.days);
  final List<Map<String, dynamic>> days;

  @override
  Widget build(BuildContext context) {
    final byDay = {for (final d in days) Fmt.date(d['day']): d};
    final now = DateTime.now();
    final labels = [for (var i = 29; i >= 0; i--) Fmt.date(now.subtract(Duration(days: i)))];
    return VrLineChart(
      labels: [for (final l in labels) l.substring(0, 5)],
      bars: true,
      height: 250,
      yFormat: (v) => Fmt.duration(v * 60),
      series: [ChartSeries('Minutes', [for (final l in labels) (dbl(byDay[l]?['activeSeconds']) ?? 0) / 60], color: VrColors.cyan)],
    );
  }
}

/// Tableau d'appareils (liste générale ou fiche utilisateur).
class DevicesTable extends StatelessWidget {
  const DevicesTable(this.items, {super.key, this.withUser = true, required this.onChanged, this.onTap});
  final List<Map<String, dynamic>> items;
  final bool withUser;
  final VoidCallback onChanged;
  final void Function(Map<String, dynamic>)? onTap;

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return VrTable(
      empty: 'Aucun appareil enregistré',
      onTap: onTap == null ? null : (i) => onTap!(items[i]),
      columns: [
        const VrColumn('Appareil', flex: 3),
        const VrColumn('Système', flex: 2),
        if (withUser) const VrColumn('Utilisateur', flex: 2),
        const VrColumn('Version'),
        const VrColumn('Première activation', flex: 2),
        const VrColumn('Dernière activité', flex: 2),
        const VrColumn('État', flex: 2),
        const VrColumn(''),
      ],
      rows: [
        for (final d in items)
          [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CellText('${d['brand'] ?? ''} ${d['model'] ?? 'Modèle inconnu'}'.trim()),
                CellText('${d['installationId']}', muted: true, mono: true),
              ],
            ),
            CellText(Fmt.os(d['os'], d['osVersion'])),
            if (withUser) CellText('${d['pseudonym']}'),
            CellText('${d['appVersion'] ?? '—'}', muted: true),
            CellText(Fmt.dateTime(d['firstSeenAt'])),
            CellText(Fmt.ago(d['lastSeenAt'])),
            d['revokedAt'] != null
                ? const StatusPill('révoqué', Health.critical)
                : StatusPill(d['online'] == true ? 'en ligne' : 'hors ligne', d['online'] == true ? Health.ok : Health.unknown),
            if (s.can('usersManage') && d['revokedAt'] == null)
              IconButton(
                tooltip: 'Révoquer l\'appareil',
                icon: const Icon(Icons.phonelink_erase_rounded, size: 19, color: VrColors.criticalText),
                onPressed: () async {
                  if (!await confirm(
                    context,
                    title: 'Révoquer cet appareil ?',
                    message: 'Ses sessions sont fermées ; l\'application devra se reconnecter et générer un nouvel identifiant.',
                    action: 'Révoquer',
                    danger: true,
                  )) {
                    return;
                  }
                  if (!context.mounted) return;
                  await runAction(context, () => s.api.post('/admin/devices/${d['id']}/revoke'), success: 'Appareil révoqué');
                  onChanged();
                },
              )
            else
              const SizedBox(),
          ],
      ],
    );
  }
}

/// Tableau de sessions (liste générale, fiche utilisateur ou appareil).
class SessionsTable extends StatelessWidget {
  const SessionsTable(this.items, {super.key, this.withUser = true, required this.onChanged});
  final List<Map<String, dynamic>> items;
  final bool withUser;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return VrTable(
      maxHeight: 420,
      empty: 'Aucune session',
      columns: [
        if (withUser) const VrColumn('Utilisateur', flex: 2),
        const VrColumn('Appareil', flex: 2),
        const VrColumn('Début', flex: 2),
        const VrColumn('Dernière activité', flex: 2),
        const VrColumn('Fin', flex: 2),
        const VrColumn('Durée active', numeric: true),
        const VrColumn('Pays'),
        const VrColumn(''),
      ],
      rows: [
        for (final x in items)
          [
            if (withUser) CellText('${x['pseudonym']}'),
            CellText(x['deviceId'] == null && x['model'] == null && x['deviceModel'] == null
                ? 'non enregistré'
                : '${x['brand'] ?? ''} ${x['model'] ?? x['deviceModel'] ?? ''}'.trim(), muted: x['deviceId'] == null),
            CellText(Fmt.dateTime(x['startedAt'])),
            Row(
              children: [
                if (x['online'] == true) ...[const StatusDot(Health.ok, size: 7), const SizedBox(width: 6)],
                Flexible(child: CellText(Fmt.ago(x['lastSeenAt']))),
              ],
            ),
            CellText(x['endedAt'] == null ? 'ouverte' : '${Fmt.dateTime(x['endedAt'])} · ${Fmt.endReason(x['endReason'])}', muted: x['endedAt'] != null),
            CellText(Fmt.duration(x['activeSeconds'] as num?)),
            CellText(x['country'] == null ? '—' : '${Fmt.flag(x['country'] as String)} ${x['country']}'),
            if (s.can('usersManage') && x['endedAt'] == null)
              IconButton(
                tooltip: 'Révoquer la session',
                icon: const Icon(Icons.cancel_outlined, size: 19, color: VrColors.criticalText),
                onPressed: () async {
                  await runAction(context, () => s.api.post('/admin/sessions/${x['id']}/revoke'), success: 'Session révoquée');
                  onChanged();
                },
              )
            else
              const SizedBox(),
          ],
      ],
    );
  }
}

/// Appareils enregistrés.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  String _q = '';
  bool _online = false;
  bool _revoked = false;
  int _offset = 0;
  int _gen = 0;

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      Row(
        children: [
          SearchField(hint: 'Modèle, marque, utilisateur, identifiant…', onChanged: (q) => setState(() {
            _q = q;
            _offset = 0;
          })),
          const SizedBox(width: 12),
          FilterChip(label: const Text('En ligne'), selected: _online, onSelected: (v) => setState(() => _online = v)),
          const SizedBox(width: 8),
          FilterChip(label: const Text('Inclure les révoqués'), selected: _revoked, onSelected: (v) => setState(() => _revoked = v)),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        'Identifiant d\'installation aléatoire généré par l\'application (aucun identifiant matériel), révocable et renouvelable.',
        style: VrText.caption,
      ),
      const SizedBox(height: 12),
      Panel(
        padding: const EdgeInsets.all(8),
        child: Fetch(
          key: ValueKey('$_q|$_online|$_revoked|$_offset|$_gen'),
          refresh: const Duration(seconds: 30),
          load: (api) => api.get('/admin/devices', query: {
            if (_q.isNotEmpty) 'q': _q,
            if (_online) 'online': 'true',
            if (_revoked) 'revoked': 'true',
            'limit': '100',
            'offset': '$_offset',
          }),
          builder: (context, d, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DevicesTable(
                listOf(d['items']),
                onChanged: () => setState(() => _gen++),
                onTap: (dev) => unawaited(_showDevice(context, dev)),
              ),
              Pager(offset: _offset, limit: 100, total: d['total'] as int, onChanged: (o) => setState(() => _offset = o)),
            ],
          ),
        ),
      ),
    ],
  );

  Future<void> _showDevice(BuildContext context, Map<String, dynamic> dev) => showDialog<void>(
    context: context,
    builder: (d) => Dialog(
      child: SizedBox(
        width: 1000,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Fetch(
            load: (api) => api.get('/admin/devices/${dev['id']}'),
            builder: (context, data, _) {
              final x = data['device'] as Map<String, dynamic>;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.smartphone_rounded, color: VrColors.cyan),
                      const SizedBox(width: 10),
                      Text('${x['brand'] ?? ''} ${x['model'] ?? ''}', style: VrText.title),
                      const Spacer(),
                      IconButton(onPressed: () => Navigator.pop(d), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                  InfoRow('Identifiant d\'appareil', '${x['installationId']}', mono: true),
                  InfoRow('Utilisateur', '${x['pseudonym']}'),
                  InfoRow('Système', Fmt.os(x['os'], x['osVersion'])),
                  InfoRow('Version de VIGIROAD', '${x['appVersion'] ?? '—'}'),
                  InfoRow('Première activation', Fmt.dateTime(x['firstSeenAt'])),
                  InfoRow('Dernière activité', '${Fmt.dateTime(x['lastSeenAt'])} (${Fmt.ago(x['lastSeenAt'])})'),
                  InfoRow('État', x['revokedAt'] != null ? 'révoqué le ${Fmt.dateTime(x['revokedAt'])}' : (x['online'] == true ? 'en ligne' : 'hors ligne')),
                  InfoRow('Pays', x['country'] == null ? '—' : Fmt.country(x['country'] as String)),
                  const SizedBox(height: 12),
                  Text('SESSIONS DE L\'APPAREIL', style: VrText.section),
                  const SizedBox(height: 8),
                  SessionsTable(listOf(data['sessions']), withUser: false, onChanged: () {}),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// Sessions, connexions simultanées et échecs d'authentification.
class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  String _state = 'online';
  int _gen = 0;

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      Row(
        children: [
          PeriodPicker(
            value: _state,
            options: const {'online': 'En ligne', 'open': 'Ouvertes', 'ended': 'Terminées', 'all': 'Toutes'},
            onChanged: (v) => setState(() => _state = v),
          ),
          const Spacer(),
          Text(
            'Battement toutes les 60 s ; hors ligne après 2 min 30 sans signal ; fermeture automatique après inactivité prolongée.',
            style: VrText.caption,
          ),
        ],
      ),
      const SizedBox(height: 14),
      Panel(
        padding: const EdgeInsets.all(8),
        child: Fetch(
          key: ValueKey('$_state|$_gen'),
          refresh: const Duration(seconds: 15),
          load: (api) => api.get('/admin/sessions', query: {'state': _state, 'limit': '200'}),
          builder: (context, d, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SessionsTable(listOf(d['items']), onChanged: () => setState(() => _gen++)),
              Padding(padding: const EdgeInsets.all(8), child: Text('${d['total']} session(s)', style: VrText.caption)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Panel(
              title: 'Connexions simultanées',
              child: Fetch(
                refresh: const Duration(seconds: 30),
                load: (api) => api.get('/admin/sessions/concurrent'),
                builder: (context, d, _) => VrTable(
                  empty: 'Aucun compte connecté depuis plusieurs sessions',
                  columns: const [VrColumn('Utilisateur', flex: 2), VrColumn('Sessions', numeric: true), VrColumn('Appareils', numeric: true), VrColumn('Pays', flex: 2)],
                  rows: [
                    for (final c in listOf(d['items']))
                      [
                        CellText('${c['pseudonym']}', color: VrColors.warning),
                        CellText('${c['sessions']}'),
                        CellText('${c['devices']}'),
                        CellText('${c['countries']}'),
                      ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Panel(
              title: 'Échecs d\'authentification',
              child: Fetch(
                refresh: const Duration(seconds: 30),
                load: (api) => api.get('/admin/login-events', query: {'success': 'false', 'limit': '100'}),
                builder: (context, d, _) {
                  final sum = d['summary'] as Map<String, dynamic>;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${sum['failed24h']} sur 24 h · ${sum['failed7d']} sur 7 jours · ${sum['success24h']} connexions réussies en 24 h', style: VrText.caption),
                      const SizedBox(height: 10),
                      VrTable(
                        maxHeight: 360,
                        empty: 'Aucun échec',
                        columns: const [VrColumn('Date', flex: 2), VrColumn('Compte', flex: 2), VrColumn('Motif', flex: 2), VrColumn('Réseau', flex: 2)],
                        rows: [
                          for (final e in listOf(d['items']))
                            [
                              CellText(Fmt.dateTime(e['at'])),
                              CellText(e['kind'] == 'admin' ? 'admin ${e['adminEmail'] ?? '?'}' : '${e['pseudonym'] ?? 'inconnu'}'),
                              CellText(Fmt.loginReason(e['reason']), color: VrColors.criticalText),
                              CellText('${e['ipPrefix'] ?? '—'}${e['country'] == null ? '' : ' ${Fmt.flag(e['country'] as String)}'}', mono: true),
                            ],
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Statistiques géographiques (pays, positions consenties).
class GeoPage extends StatefulWidget {
  const GeoPage({super.key});

  @override
  State<GeoPage> createState() => _GeoPageState();
}

class _GeoPageState extends State<GeoPage> {
  String _days = '30';

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      Fetch(
        key: ValueKey(_days),
        refresh: const Duration(minutes: 1),
        load: (api) => api.get('/admin/geo', query: {'days': _days}),
        builder: (context, d, _) {
          final countries = listOf(d['countries']);
          final consents = d['consents'] as Map<String, dynamic>;
          final geo = d['geoIp'] as Map<String, dynamic>;
          final settings = d['settings'] as Map<String, dynamic>;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ResponsiveGrid(
                children: [
                  StatCard(label: 'Pays représentés', value: '${countries.length}', icon: Icons.public_rounded),
                  StatCard(
                    label: 'Région autorisée',
                    value: '${consents['region']} / ${consents['total']}',
                    icon: Icons.flag_rounded,
                    sub: 'pays déduit de l\'adresse IP',
                  ),
                  StatCard(
                    label: 'Position autorisée',
                    value: '${consents['location']} / ${consents['total']}',
                    icon: Icons.my_location_rounded,
                    sub: 'désactivée par défaut, arrondie à ~5 km',
                    color: VrColors.electricBright,
                  ),
                  StatCard(
                    label: 'Conservation des positions',
                    value: '${settings['retention.location_days']} j',
                    icon: Icons.auto_delete_rounded,
                    sub: 'réglable dans Paramètres',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Panel(
                title: 'Carte des utilisateurs',
                trailing: PeriodPicker(
                  value: _days,
                  options: const {'7': '7 j', '30': '30 j', '90': '90 j', '365': '1 an'},
                  onChanged: (v) => setState(() => _days = v),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    WorldMap(
                      values: {for (final c in countries) c['country'] as String: (c['users'] as num) > 0 ? c['users'] as num : c['sessions'] as num},
                      points: [
                        for (final p in listOf(d['points'])) (lat: dbl(p['lat'])!, lng: dbl(p['lng'])!, weight: p['samples'] as num),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${geo['available'] == true ? 'Pays : ${geo['attribution']}' : 'Base GeoIP absente sur le serveur : pays inconnus.'} '
                      'Carte : Natural Earth (domaine public). Aucune donnée sans consentement de l\'utilisateur.',
                      style: VrText.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Panel(
                title: 'Répartition par pays',
                child: VrTable(
                  empty: 'Aucune donnée géographique (consentement « région » requis)',
                  columns: const [VrColumn('Pays', flex: 3), VrColumn('Utilisateurs', numeric: true), VrColumn('Sessions', numeric: true), VrColumn('Connexions', numeric: true)],
                  rows: [
                    for (final c in countries)
                      [
                        CellText('${Fmt.flag(c['country'] as String)}  ${Fmt.country(c['country'] as String)}'),
                        CellText(Fmt.number(c['users'] as num?)),
                        CellText(Fmt.number(c['sessions'] as num?)),
                        CellText(Fmt.number(c['logins'] as num?)),
                      ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ],
  );
}

/// Résumé serveur pour l'application Windows (temps réel + backend).
class ServerSummaryPage extends StatelessWidget {
  const ServerSummaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return PageBody(
      children: [
        ValueListenableBuilder(
          valueListenable: s.snapshot,
          builder: (context, snap, _) => LiveGauges(metrics: snap?['metrics'] as Map<String, dynamic>?),
        ),
        const SizedBox(height: 16),
        Fetch(
          refresh: const Duration(seconds: 30),
          load: (api) => api.get('/admin/vigiroad/status'),
          builder: (context, d, _) => VigiroadStatus(d),
        ),
      ],
    );
  }
}

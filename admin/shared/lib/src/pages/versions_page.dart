import 'dart:async';

import 'package:flutter/material.dart';

import '../api/session.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/fetch.dart';
import '../widgets/panel.dart';
import '../widgets/table.dart';
import 'common.dart';

/// Versions de l'application GPS : tentatives d'utilisation d'une version
/// obsolète ou bloquée, versions en circulation, et blocage à distance.
class VersionsPage extends StatefulWidget {
  const VersionsPage({super.key});

  @override
  State<VersionsPage> createState() => _VersionsPageState();
}

class _VersionsPageState extends State<VersionsPage> {
  int _gen = 0;

  static String _app(Object? a) => switch (a) {
    'gps' => 'VIGIROAD (GPS)',
    'admin-manager' => 'ADMIN MANAGER',
    'server-control' => 'SERVER CONTROL',
    _ => '$a',
  };

  static String _platform(Object? p) => switch (p) {
    'android' => 'Android',
    'ios' => 'iPhone',
    'windows' => 'Windows',
    'linux' => 'Linux',
    _ => 'Android ou iPhone (≤ 1.6)',
  };

  Future<void> _blockDevice(BuildContext context, Map<String, dynamic> e) async {
    final values = await editFields(
      context,
      title: 'Bloquer cet appareil (${e['model'] ?? _platform(e['platform'])})',
      fields: const {'reason': 'Motif affiché sur l\'appareil (facultatif)'},
      action: 'Bloquer l\'appareil',
    );
    if (values == null || !context.mounted) return;
    final s = SessionScope.read(context);
    final r = await runAction(
      context,
      () => s.api.post('/admin/app/devices/${e['installHash']}/block', {if (values['reason']!.isNotEmpty) 'reason': values['reason']}),
      success: 'Appareil bloqué : il ne peut plus utiliser VIGIROAD',
    );
    if (r != null && mounted) setState(() => _gen++);
  }

  Future<void> _unblockDevice(BuildContext context, String hash) async {
    final s = SessionScope.read(context);
    final r = await runAction(context, () => s.api.delete('/admin/app/devices/$hash'), success: 'Appareil débloqué');
    if (r != null && mounted) setState(() => _gen++);
  }

  static String _source(Object? s) => switch (s) {
    'traffic' => 'données refusées',
    'admin' => 'connexion refusée',
    _ => 'au démarrage',
  };

  Future<void> _put(BuildContext context, Map<String, Object?> body, String done) async {
    final s = SessionScope.read(context);
    final r = await runAction(context, () => s.api.put('/admin/app/policy', body), success: done);
    if (r != null && mounted) setState(() => _gen++);
  }

  Future<void> _block(BuildContext context, Map<String, dynamic> policy) async {
    final values = await editFields(
      context,
      title: 'Bloquer l\'application à distance',
      fields: const {'message': 'Message affiché aux conducteurs'},
      initial: {'message': '${policy['message'] ?? ''}'},
      action: 'Bloquer maintenant',
    );
    if (values == null || !context.mounted) return;
    await _put(context, {'blocked': true, 'message': values['message']}, 'Application bloquée sur tous les téléphones');
  }

  Future<void> _minBuild(BuildContext context, Map<String, dynamic> policy) async {
    final values = await editFields(
      context,
      title: 'Version minimale (numéro de compilation)',
      fields: const {'minBuild': 'Numéro minimal (0 = aucun)'},
      initial: {'minBuild': '${policy['manualMinBuild'] ?? 0}'},
    );
    final n = int.tryParse(values?['minBuild'] ?? '');
    if (n == null || n < 0 || !context.mounted) return;
    await _put(context, {'minBuild': n}, 'Version minimale enregistrée');
  }

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final canEdit = s.can('settings');
    return PageBody(
      children: [
        Fetch(
          key: ValueKey(_gen),
          refresh: const Duration(seconds: 30),
          load: (api) => api.get('/admin/app/versions'),
          builder: (context, d, reload) {
            final policy = (d['policy'] as Map<String, dynamic>?) ?? const {};
            final latest = policy['latest'] as Map<String, dynamic>?;
            final blocked = policy['blocked'] == true;
            final counts = (d['counts'] as Map<String, dynamic>?) ?? const {};
            final desktop = d['desktop'] as Map<String, dynamic>?;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ResponsiveGrid(
                  children: [
                    StatCard(
                      label: 'État de l\'application',
                      value: blocked ? 'BLOQUÉE' : 'Active',
                      icon: blocked ? Icons.block_rounded : Icons.verified_rounded,
                      color: blocked ? VrColors.critical : VrColors.ok,
                      sub: blocked ? '${policy['message']}' : 'utilisable dans sa dernière version',
                    ),
                    StatCard(
                      label: 'Dernière version publiée',
                      value: latest == null ? 'inconnue' : '${latest['version']}',
                      icon: Icons.new_releases_rounded,
                      sub: latest == null ? 'manifeste GitHub non lu' : 'compilation ${latest['build']} · vérifiée ${Fmt.ago(latest['checkedAt'])}',
                    ),
                    StatCard(
                      label: 'Version minimale exigée',
                      value: '${policy['minBuild'] ?? 0}',
                      icon: Icons.rule_rounded,
                      sub: policy['forceLatest'] == true ? 'toute version plus ancienne est bloquée' : 'règle manuelle',
                    ),
                    StatCard(
                      label: 'Tentatives (24 h / 7 j)',
                      value: '${counts['last24h'] ?? 0} / ${counts['last7d'] ?? 0}',
                      icon: Icons.history_toggle_off_rounded,
                      color: VrColors.warning,
                      sub: 'anciennes versions refusées',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Panel(
                  title: 'Contrôle à distance',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Une version antérieure à la dernière publiée ne peut plus être utilisée : seul l\'écran de mise à jour '
                        's\'affiche, et le serveur lui refuse toute donnée. Le blocage à distance suspend toutes les versions.',
                        style: VrText.caption,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (blocked)
                            VrButton(
                              label: 'Débloquer l\'application',
                              icon: Icons.lock_open_rounded,
                              onPressed: canEdit ? () => unawaited(_put(context, {'blocked': false}, 'Application débloquée')) : null,
                            )
                          else
                            VrButton(
                              label: 'Bloquer l\'application',
                              icon: Icons.block_rounded,
                              danger: true,
                              onPressed: canEdit
                                  ? () async {
                                      final ok = await confirm(
                                        context,
                                        title: 'Bloquer VIGIROAD sur tous les téléphones ?',
                                        message: 'Tous les conducteurs verront votre message et ne pourront plus utiliser l\'application '
                                            'jusqu\'au déblocage (un guidage en cours n\'est pas interrompu).',
                                        action: 'Continuer',
                                        danger: true,
                                      );
                                      if (ok && context.mounted) await _block(context, policy);
                                    }
                                  : null,
                            ),
                          VrButton(
                            label: policy['forceLatest'] == true ? 'Tolérer les versions précédentes' : 'Exiger la dernière version',
                            icon: Icons.rule_rounded,
                            primary: false,
                            onPressed: canEdit
                                ? () => unawaited(_put(
                                    context,
                                    {'forceLatest': policy['forceLatest'] != true},
                                    policy['forceLatest'] == true ? 'Versions précédentes tolérées' : 'Dernière version exigée',
                                  ))
                                : null,
                          ),
                          VrButton(
                            label: 'Version minimale…',
                            icon: Icons.pin_rounded,
                            primary: false,
                            onPressed: canEdit ? () => unawaited(_minBuild(context, policy)) : null,
                          ),
                        ],
                      ),
                      if (!canEdit) ...[
                        const SizedBox(height: 8),
                        Text('Réservé aux rôles Administrateur et Propriétaire.', style: VrText.caption),
                      ],
                      if (desktop != null) ...[
                        const SizedBox(height: 12),
                        InfoRow('Administration déposée', 'ADMIN MANAGER ${desktop['admin-manager'] ?? '—'} · SERVER CONTROL ${desktop['server-control'] ?? '—'}'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Panel(
                  title: 'Tentatives avec une ancienne version',
                  padding: const EdgeInsets.all(8),
                  child: VrTable(
                    empty: 'Aucune tentative : tout le monde utilise la dernière version.',
                    maxHeight: 420,
                    columns: const [
                      VrColumn('Date', flex: 2),
                      VrColumn('Application', flex: 2),
                      VrColumn('Version', flex: 2),
                      VrColumn('État'),
                      VrColumn('Appareil', flex: 3),
                      VrColumn('Utilisateur', flex: 2),
                      VrColumn('Origine', flex: 2),
                      VrColumn('Lieu', flex: 2),
                      VrColumn('Action', flex: 2),
                    ],
                    rows: [
                      for (final e in listOf(d['events']))
                        [
                          CellText(Fmt.dateTime(e['at'])),
                          CellText(_app(e['app'])),
                          CellText('${e['version']}${e['build'] == null ? '' : ' (${e['build']})'} → ${e['required'] ?? '?'}', mono: true),
                          StatusPill(e['status'] == 'blocked' ? 'bloquée' : 'obsolète', e['status'] == 'blocked' ? Health.critical : Health.warning),
                          CellText(
                            [_platform(e['platform']), e['model'], e['os']].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
                          ),
                          CellText('${e['pseudonym'] ?? e['adminEmail'] ?? 'anonyme'}', muted: e['pseudonym'] == null && e['adminEmail'] == null),
                          CellText(_source(e['source']), muted: true),
                          CellText('${e['country'] ?? '?'} · ${e['ipPrefix'] ?? ''}', muted: true, mono: true),
                          if (e['deviceBlocked'] == true)
                            const Align(alignment: Alignment.centerLeft, child: StatusPill('appareil bloqué', Health.critical))
                          else if (e['installHash'] != null && e['app'] == 'gps')
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                key: Key('block-${e['id']}'),
                                onPressed: canEdit ? () => unawaited(_blockDevice(context, e)) : null,
                                icon: const Icon(Icons.phonelink_lock_rounded, size: 16),
                                label: const Text('Bloquer'),
                                style: TextButton.styleFrom(foregroundColor: VrColors.critical),
                              ),
                            )
                          else
                            const CellText('non identifiable', muted: true),
                        ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Panel(
                  title: 'Appareils bloqués',
                  padding: const EdgeInsets.all(8),
                  child: VrTable(
                    empty: 'Aucun appareil bloqué',
                    columns: const [
                      VrColumn('Appareil', flex: 3),
                      VrColumn('Version', flex: 2),
                      VrColumn('Motif', flex: 3),
                      VrColumn('Bloqué le', flex: 2),
                      VrColumn('Par', flex: 2),
                      VrColumn('Action', flex: 2),
                    ],
                    rows: [
                      for (final b in listOf(d['blockedDevices']))
                        [
                          CellText([_platform(b['platform']), b['model']].where((v) => v != null).join(' · ')),
                          CellText('${b['version'] ?? '?'}', mono: true),
                          CellText('${b['reason'] ?? '—'}', muted: b['reason'] == null),
                          CellText(Fmt.dateTime(b['blockedAt'])),
                          CellText('${b['blockedBy'] ?? '—'}', muted: true),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: canEdit ? () => unawaited(_unblockDevice(context, b['installHash'] as String)) : null,
                              icon: const Icon(Icons.lock_open_rounded, size: 16),
                              label: const Text('Débloquer'),
                            ),
                          ),
                        ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Panel(
                  title: 'Versions en circulation (7 jours)',
                  padding: const EdgeInsets.all(8),
                  child: VrTable(
                    empty: 'Aucune ouverture enregistrée',
                    columns: const [
                      VrColumn('Version', flex: 2),
                      VrColumn('Plateforme'),
                      VrColumn('Ouvertures', numeric: true),
                      VrColumn('Dernier jour', flex: 2),
                    ],
                    rows: [
                      for (final v in listOf(d['inUse']))
                        [
                          CellText('${v['version']} (${v['build']})', mono: true),
                          CellText(_platform(v['platform'])),
                          CellText(Fmt.number(v['checks'] as num?)),
                          CellText(Fmt.date(v['lastDay'])),
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
}

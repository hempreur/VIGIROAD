import 'dart:async';

import 'package:flutter/material.dart';

import '../api/session.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/dialogs.dart';
import '../widgets/fetch.dart';
import '../widgets/panel.dart';
import '../widgets/table.dart';
import 'common.dart';

/// Supervision du VPS en temps réel : jauges, historique, système.
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key, this.compact = false});

  /// Version réduite (application Windows) : jauges et état seulement.
  final bool compact;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  String _period = '24h';

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
          load: (api) => api.get('/admin/server/overview'),
          builder: (context, d, _) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _SystemPanel(d['system'] as Map<String, dynamic>?, d['agentError'] as String?)),
              const SizedBox(width: 16),
              Expanded(child: _CoresPanel()),
            ],
          ),
        ),
        if (!widget.compact) ...[
          const SizedBox(height: 16),
          Panel(
            title: 'Historique des performances',
            trailing: PeriodPicker(
              value: _period,
              options: const {'1h': '1 h', '24h': '24 h', '7d': '7 j', '30d': '30 j'},
              onChanged: (p) => setState(() => _period = p),
            ),
            child: Fetch(
              key: ValueKey(_period),
              refresh: const Duration(minutes: 1),
              load: (api) => api.get('/admin/server/history', query: {'period': _period}),
              builder: (context, d, _) => _History(listOf(d['points']), _period),
            ),
          ),
        ],
      ],
    );
  }
}

/// Jauges CPU, RAM, disque, charge, réseau, température.
class LiveGauges extends StatelessWidget {
  const LiveGauges({super.key, required this.metrics});
  final Map<String, dynamic>? metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final mem = m?['memory'] as Map<String, dynamic>?;
    final disk = listOf(m?['disks']).firstOrNull;
    final net = m?['network'] as Map<String, dynamic>?;
    final load = ((m?['load'] as List<dynamic>?) ?? const []).cast<num>();
    final temps = listOf(m?['temperatures']);
    final cores = ((m?['perCore'] as List<dynamic>?) ?? const []).length;
    double? pct(num? a, num? b) => a == null || b == null || b == 0 ? null : a / b * 100;
    final memPct = pct(mem?['used'] as num?, mem?['total'] as num?);
    final diskPct = pct(disk?['used'] as num?, disk?['total'] as num?);
    final loadPct = load.isEmpty || cores == 0 ? null : load.first / cores * 100;
    final temp = temps.isEmpty ? null : temps.map((t) => (t['celsius'] as num).toDouble()).reduce((a, b) => a > b ? a : b);
    return Panel(
      title: 'Ressources en temps réel',
      trailing: m == null
          ? Text('en attente des mesures…', style: VrText.caption)
          : Text('mis à jour ${Fmt.time(m['at'], seconds: true)}', style: VrText.caption),
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        spacing: 24,
        runSpacing: 18,
        children: [
          Gauge(label: 'Processeur', percent: dbl(m?['cpuPercent']), value: Fmt.percent(dbl(m?['cpuPercent'])), sub: cores > 0 ? '$cores cœurs' : null),
          Gauge(
            label: 'Mémoire',
            percent: memPct,
            value: Fmt.percent(memPct),
            sub: mem == null ? null : '${Fmt.bytes(mem['used'] as num?)} / ${Fmt.bytes(mem['total'] as num?)}',
          ),
          Gauge(
            label: 'Disque',
            percent: diskPct,
            value: Fmt.percent(diskPct),
            sub: disk == null ? null : '${Fmt.bytes(disk['available'] as num?)} libres',
          ),
          Gauge(
            label: 'Charge',
            percent: loadPct,
            value: load.isEmpty ? '—' : Fmt.number(load.first, digits: 2),
            sub: load.length < 3 ? null : '5 min ${Fmt.number(load[1], digits: 2)} · 15 min ${Fmt.number(load[2], digits: 2)}',
          ),
          Gauge(
            label: 'Réseau',
            percent: null,
            value: Fmt.rate(net?['rxBps'] as num?),
            sub: 'entrant · sortant ${Fmt.rate(net?['txBps'] as num?)}',
          ),
          Gauge(
            label: 'Température',
            percent: temp,
            value: temp == null ? 'n/d' : '${Fmt.number(temp)} °C',
            sub: temp == null ? 'capteurs non exposés par le VPS' : temps.first['sensor'] as String?,
          ),
          Gauge(label: 'Disponibilité', percent: null, value: Fmt.duration(m?['uptimeSeconds'] as num?), sub: 'depuis le démarrage'),
        ],
      ),
    );
  }
}

class _SystemPanel extends StatelessWidget {
  const _SystemPanel(this.system, this.error);
  final Map<String, dynamic>? system;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final s = system;
    final gui = s?['gui'] as Map<String, dynamic>?;
    return Panel(
      title: 'Système',
      child: s == null
          ? EmptyState(error ?? 'Agent de supervision injoignable', icon: Icons.sensors_off_rounded)
          : Column(
              children: [
                InfoRow('Nom d\'hôte', '${s['hostname']}'),
                InfoRow('Système', '${s['os']}'),
                InfoRow('Noyau', '${s['kernel']}'),
                InfoRow('Processeur', '${s['cpuModel'] ?? '—'} × ${s['cpus']}'),
                InfoRow('Mémoire totale', Fmt.bytes(s['memTotal'] as num?)),
                InfoRow('Démarré', Fmt.ago(DateTime.now().subtract(Duration(seconds: ((s['uptimeSeconds'] as num?) ?? 0).round())))),
                InfoRow('Docker', '${s['docker'] ?? 'inconnu'} (projet ${s['project'] ?? '?'})'),
                InfoRow(
                  'Environnement graphique',
                  gui == null
                      ? '—'
                      : [
                          gui['xfce'] == true ? 'XFCE installé' : 'aucun bureau',
                          if (gui['xrdp'] == true) 'bureau à distance (xrdp)',
                          if (gui['serverControl'] == true) 'Server Control installé',
                        ].join(' · '),
                ),
              ],
            ),
    );
  }
}

class _CoresPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return Panel(
      title: 'Cœurs du processeur',
      child: ValueListenableBuilder(
        valueListenable: s.snapshot,
        builder: (context, snap, _) {
          final cores = ((snap?['metrics']?['perCore'] as List<dynamic>?) ?? const []).cast<num>();
          if (cores.isEmpty) return const EmptyState('Mesure en cours…', icon: Icons.memory_rounded);
          return Column(children: [for (var i = 0; i < cores.length; i++) MeterBar(label: 'Cœur ${i + 1}', percent: cores[i].toDouble())]);
        },
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History(this.points, this.period);
  final List<Map<String, dynamic>> points;
  final String period;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const EmptyState('Historique en cours de constitution (une mesure par minute).', icon: Icons.timeline_rounded);
    final labels = [for (final p in points) period == '1h' || period == '24h' ? Fmt.time(p['at']) : Fmt.dayHour(p['at'])];
    double? memPct(Map<String, dynamic> p) =>
        dbl(p['memUsed']) == null || dbl(p['memTotal']) == null ? null : dbl(p['memUsed'])! / dbl(p['memTotal'])! * 100;
    double? diskPct(Map<String, dynamic> p) =>
        dbl(p['diskUsed']) == null || dbl(p['diskTotal']) == null ? null : dbl(p['diskUsed'])! / dbl(p['diskTotal'])! * 100;
    Widget chart(String title, List<ChartSeries> s, String Function(double) f, {double? maxY}) => Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: VrText.label),
          const SizedBox(height: 8),
          VrLineChart(labels: labels, series: s, yFormat: f, maxY: maxY, height: 180),
        ],
      ),
    );
    return Column(
      children: [
        chart('Processeur et mémoire (%)', [
          ChartSeries('CPU moyen', [for (final p in points) dbl(p['cpu'])], color: VrColors.cyan),
          ChartSeries('CPU pointe', [for (final p in points) dbl(p['cpuMax'])], color: VrColors.warning, area: false),
          ChartSeries('RAM', [for (final p in points) memPct(p)], color: VrColors.electricBright),
        ], (v) => '${Fmt.number(v)} %', maxY: 100),
        chart('Réseau', [
          ChartSeries('Entrant', [for (final p in points) dbl(p['rx'])], color: VrColors.ok),
          ChartSeries('Sortant', [for (final p in points) dbl(p['tx'])], color: VrColors.electricBright),
        ], Fmt.rate),
        chart('Disque (%) et disponibilité du trafic (%)', [
          ChartSeries('Disque', [for (final p in points) diskPct(p)], color: VrColors.warning),
          ChartSeries('Trafic disponible', [for (final p in points) dbl(p['availability']) == null ? null : dbl(p['availability'])! * 100], color: VrColors.ok, area: false),
        ], (v) => '${Fmt.number(v)} %', maxY: 100),
      ],
    );
  }
}

/// Processus actifs et services de l'hôte.
class ProcessesPage extends StatelessWidget {
  const ProcessesPage({super.key});

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      Fetch(
        refresh: const Duration(seconds: 5),
        load: (api) => api.get('/admin/server/processes'),
        builder: (context, d, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Panel(
              title: 'Services actifs',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final s in listOf(d['services']))
                    StatusPill('${s['label']}${(s['instances'] as int) > 1 ? ' ×${s['instances']}' : ''}', Health.ok),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Panel(
              title: 'Processus les plus actifs',
              child: VrTable(
                columns: const [
                  VrColumn('PID'),
                  VrColumn('Nom', flex: 3),
                  VrColumn('État'),
                  VrColumn('CPU', numeric: true),
                  VrColumn('Mémoire', numeric: true),
                ],
                rows: [
                  for (final p in listOf(d['processes']))
                    [
                      CellText('${p['pid']}', mono: true),
                      CellText('${p['name']}'),
                      CellText(switch (p['state']) {
                        'R' => 'en cours',
                        'S' => 'en attente',
                        'D' => 'E/S',
                        'Z' => 'zombie',
                        _ => '${p['state']}',
                      }, muted: true),
                      CellText(Fmt.percent(dbl(p['cpuPercent']), digits: 1)),
                      CellText(Fmt.bytes(p['rss'] as num?)),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Conteneurs, journaux, volumes, réseaux et images Docker.
class DockerPage extends StatefulWidget {
  const DockerPage({super.key});

  @override
  State<DockerPage> createState() => _DockerPageState();
}

class _DockerPageState extends State<DockerPage> {
  String _tab = 'containers';
  int _gen = 0;

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return PageBody(
      children: [
        Row(
          children: [
            PeriodPicker(
              value: _tab,
              options: const {'containers': 'Conteneurs', 'volumes': 'Volumes', 'networks': 'Réseaux', 'images': 'Images'},
              onChanged: (t) => setState(() => _tab = t),
            ),
            const Spacer(),
            IconButton(tooltip: 'Actualiser', onPressed: () => setState(() => _gen++), icon: const Icon(Icons.refresh_rounded)),
          ],
        ),
        const SizedBox(height: 14),
        Panel(
          child: switch (_tab) {
            'volumes' => Fetch(
              key: ValueKey('v$_gen'),
              load: (api) => api.get('/admin/docker/volumes'),
              builder: (context, d, _) => VrTable(
                columns: const [VrColumn('Volume', flex: 3), VrColumn('Projet'), VrColumn('Pilote'), VrColumn('Taille', numeric: true), VrColumn('Créé')],
                rows: [
                  for (final v in listOf(d['volumes']))
                    [
                      CellText('${v['name']}', mono: true),
                      CellText('${v['project'] ?? '—'}'),
                      CellText('${v['driver']}', muted: true),
                      CellText((v['size'] as num? ?? -1) < 0 ? '—' : Fmt.bytes(v['size'] as num)),
                      CellText(Fmt.date(v['createdAt'])),
                    ],
                ],
              ),
            ),
            'networks' => Fetch(
              key: ValueKey('n$_gen'),
              load: (api) => api.get('/admin/docker/networks'),
              builder: (context, d, _) => VrTable(
                columns: const [VrColumn('Réseau', flex: 3), VrColumn('Pilote'), VrColumn('Portée'), VrColumn('Interne'), VrColumn('Conteneurs', numeric: true)],
                rows: [
                  for (final n in listOf(d['networks']))
                    [
                      CellText('${n['name']}', mono: true),
                      CellText('${n['driver']}'),
                      CellText('${n['scope']}', muted: true),
                      CellText(n['internal'] == true ? 'oui (sans Internet)' : 'non'),
                      CellText('${n['containers']}'),
                    ],
                ],
              ),
            ),
            'images' => Fetch(
              key: ValueKey('i$_gen'),
              load: (api) => api.get('/admin/docker/images'),
              builder: (context, d, _) => VrTable(
                columns: const [VrColumn('Image', flex: 3), VrColumn('Identifiant'), VrColumn('Taille', numeric: true), VrColumn('Créée')],
                rows: [
                  for (final i in listOf(d['images']))
                    [
                      CellText(((i['tags'] as List<dynamic>?) ?? const []).join(', ').isEmpty ? '<sans étiquette>' : (i['tags'] as List<dynamic>).join(', ')),
                      CellText('${i['id']}', mono: true, muted: true),
                      CellText(Fmt.bytes(i['size'] as num?)),
                      CellText(Fmt.date(i['created'])),
                    ],
                ],
              ),
            ),
            _ => Fetch(
              key: ValueKey('c$_gen'),
              refresh: const Duration(seconds: 15),
              load: (api) => api.get('/admin/docker/containers'),
              builder: (context, d, reload) => _Containers(listOf(d['containers']), canControl: s.can('serverControl'), reload: reload),
            ),
          },
        ),
      ],
    );
  }
}

class _Containers extends StatelessWidget {
  const _Containers(this.items, {required this.canControl, required this.reload});
  final List<Map<String, dynamic>> items;
  final bool canControl;
  final Future<void> Function() reload;

  Future<void> _action(BuildContext context, Map<String, dynamic> c, String action) async {
    final labels = {'start': 'Démarrer', 'stop': 'Arrêter', 'restart': 'Redémarrer'};
    if (action != 'start') {
      final ok = await confirm(
        context,
        title: '${labels[action]} « ${c['service'] ?? c['name']} » ?',
        message: action == 'stop'
            ? 'Le service sera indisponible jusqu\'à son redémarrage.'
            : 'Le service sera indisponible quelques secondes (redémarrage contrôlé).',
        action: labels[action]!,
        danger: action == 'stop',
      );
      if (!ok || !context.mounted) return;
    }
    final api = SessionScope.read(context).api;
    await runAction(context, () => api.post('/admin/docker/containers/${c['id']}/$action'), success: '${labels[action]} : ${c['service'] ?? c['name']} ✓');
    await reload();
  }

  @override
  Widget build(BuildContext context) => VrTable(
    empty: 'Aucun conteneur',
    columns: const [
      VrColumn('Conteneur', flex: 3),
      VrColumn('État', flex: 2),
      VrColumn('CPU', numeric: true),
      VrColumn('Mémoire', numeric: true),
      VrColumn('Ports'),
      VrColumn('Actions', flex: 3),
    ],
    rows: [
      for (final c in items)
        [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CellText('${c['service'] ?? c['name']}', color: c['vigiroad'] == true ? VrColors.cyan : null),
              CellText('${c['image']}', muted: true),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusPill(
                c['state'] == 'running' ? (c['health'] == 'unhealthy' ? 'en mauvaise santé' : 'en fonctionnement') : '${c['state']}',
                c['state'] == 'running' ? (c['health'] == 'unhealthy' ? Health.warning : Health.ok) : Health.critical,
              ),
              CellText('${c['status']}', muted: true),
            ],
          ),
          CellText(Fmt.percent(dbl(c['stats']?['cpuPercent']), digits: 1)),
          CellText(c['stats'] == null ? '—' : Fmt.bytes(c['stats']['memUsage'] as num?)),
          CellText(((c['ports'] as List<dynamic>?) ?? const []).join(', ').isEmpty ? '—' : (c['ports'] as List<dynamic>).join(', '), muted: true),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Journaux',
                onPressed: () => unawaited(showLogs(context, c)),
                icon: const Icon(Icons.article_outlined, size: 19),
              ),
              if (canControl)
                for (final a in ((c['actions'] as List<dynamic>?) ?? const []).cast<String>())
                  if (!(a == 'start' && c['state'] == 'running') && !(a == 'stop' && c['state'] != 'running'))
                    IconButton(
                      key: Key('docker-$a-${c['service']}'),
                      tooltip: {'start': 'Démarrer', 'stop': 'Arrêter', 'restart': 'Redémarrer'}[a],
                      onPressed: () => unawaited(_action(context, c, a)),
                      icon: Icon(
                        {'start': Icons.play_arrow_rounded, 'stop': Icons.stop_rounded, 'restart': Icons.restart_alt_rounded}[a],
                        size: 20,
                        color: a == 'stop' ? VrColors.criticalText : VrColors.cyan,
                      ),
                    ),
            ],
          ),
        ],
    ],
  );
}

/// Journaux d'un conteneur (stdout en clair, stderr en rouge).
Future<void> showLogs(BuildContext context, Map<String, dynamic> c) => showDialog<void>(
  context: context,
  builder: (d) => Dialog(
    child: SizedBox(
      width: 1000,
      height: 640,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Journaux — ${c['service'] ?? c['name']}', style: VrText.title),
                const Spacer(),
                IconButton(onPressed: () => Navigator.pop(d), icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: VrColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: VrColors.line),
                ),
                child: Fetch(
                  refresh: const Duration(seconds: 5),
                  load: (api) => api.get('/admin/docker/containers/${c['id']}/logs', query: {'tail': '400'}),
                  builder: (context, data, _) {
                    final lines = ((data['lines'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>();
                    return SizedBox(
                      height: 560,
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(12),
                        itemCount: lines.length,
                        itemBuilder: (context, i) {
                          final l = lines[lines.length - 1 - i];
                          return SelectableText.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: '${Fmt.time(l['at'], seconds: true)}  ', style: VrText.mono.copyWith(color: VrColors.textMuted)),
                                TextSpan(
                                  text: '${l['line']}',
                                  style: VrText.mono.copyWith(color: l['stream'] == 'stderr' ? VrColors.criticalText : VrColors.textPrimary),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

/// Backend VIGIROAD : services, flux routiers, requêtes et latence.
class VigiroadPage extends StatefulWidget {
  const VigiroadPage({super.key});

  @override
  State<VigiroadPage> createState() => _VigiroadPageState();
}

class _VigiroadPageState extends State<VigiroadPage> {
  String _period = '24h';

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      Fetch(
        refresh: const Duration(seconds: 30),
        load: (api) => api.get('/admin/vigiroad/status'),
        builder: (context, d, _) => VigiroadStatus(d),
      ),
      const SizedBox(height: 16),
      Panel(
        title: 'Requêtes entrantes et latence',
        trailing: PeriodPicker(
          value: _period,
          options: const {'1h': '1 h', '24h': '24 h', '7d': '7 j'},
          onChanged: (p) => setState(() => _period = p),
        ),
        child: Fetch(
          key: ValueKey(_period),
          refresh: const Duration(minutes: 1),
          load: (api) => api.get('/admin/vigiroad/requests', query: {'period': _period}),
          builder: (context, d, _) => _Requests(d, _period),
        ),
      ),
    ],
  );
}

/// Cartes d'état des services et tableau des flux routiers.
class VigiroadStatus extends StatelessWidget {
  const VigiroadStatus(this.d, {super.key});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final t = d['traffic'] as Map<String, dynamic>;
    final db = d['database'] as Map<String, dynamic>;
    final agent = d['agent'] as Map<String, dynamic>;
    final cert = d['certificate'] as Map<String, dynamic>;
    final certExp = Fmt.parse(cert['expiresAt']);
    final certDays = certExp?.difference(DateTime.now()).inDays;
    final req = {for (final r in listOf(d['requests24h'])) r['service']: r};
    final sources = listOf(t['sources']);
    Widget card(String title, IconData icon, Health h, List<String> lines) => Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: healthColor(h)),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: VrText.section)),
              StatusDot(h),
            ],
          ),
          const SizedBox(height: 10),
          for (final l in lines) Text(l, style: VrText.caption),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
          minWidth: 250,
          children: [
            card('Backend GPS et trafic', Icons.traffic_rounded, t['ok'] == true ? Health.ok : Health.critical, [
              t['ok'] == true ? 'Répond en ${t['latencyMs']} ms' : 'Indisponible : ${t['error'] ?? '?'}',
              'Couverture : ${((t['coverage'] as List<dynamic>?) ?? const []).join(', ')}',
              '${req['traffic']?['requests'] ?? 0} requêtes / 24 h',
            ]),
            card('Flux routiers', Icons.alt_route_rounded, sources.isEmpty
                ? Health.unknown
                : (t['activeSources'] == t['totalSources'] ? Health.ok : (t['activeSources'] == 0 ? Health.critical : Health.warning)), [
              '${t['activeSources']} actif(s) sur ${t['totalSources']}',
              '${Fmt.number(t['events'] as num?)} événements collectés',
            ]),
            card('Base PostgreSQL', Icons.storage_rounded, db['ok'] == true ? Health.ok : Health.critical, [
              'Réponse en ${db['latencyMs']} ms · schéma v${db['schemaVersion']}',
              '${Fmt.bytes(db['sizeBytes'] as num?)} · ${db['connections']} connexion(s)',
            ]),
            card('API d\'administration', Icons.admin_panel_settings_rounded, Health.ok, [
              '${req['admin-api']?['requests'] ?? 0} requêtes / 24 h · p95 ${Fmt.number(dbl(req['admin-api']?['p95Ms']))} ms',
              '${d['adminApi']['recentErrors']} erreur(s) interne(s) récente(s)',
            ]),
            card('Agent de supervision', Icons.sensors_rounded, agent['ok'] == true ? Health.ok : Health.critical, [
              agent['ok'] == true ? 'Métriques reçues' : '${agent['error'] ?? 'injoignable'}',
            ]),
            card('Certificat HTTPS', Icons.https_rounded, certDays == null
                ? Health.unknown
                : (certDays < 14 ? Health.critical : Health.ok), [
              certExp == null ? (cert['error'] as String? ?? 'non vérifié') : 'Expire le ${Fmt.date(certExp)} ($certDays j)',
              'Renouvellement automatique (Let\'s Encrypt)',
            ]),
          ],
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'Flux routiers',
          child: VrTable(
            empty: 'Aucun flux configuré',
            columns: const [
              VrColumn('Source', flex: 4),
              VrColumn('État', flex: 2),
              VrColumn('Événements', numeric: true),
              VrColumn('Dernière synchronisation', flex: 2),
              VrColumn('Erreur', flex: 3),
            ],
            rows: [
              for (final s in sources)
                [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [CellText('${s['name']}'), CellText('${s['id']} · ${s['licence'] ?? ''}', muted: true)],
                  ),
                  StatusPill(
                    s['healthy'] == true ? (s['usingFallback'] == true ? 'secours' : 'à jour') : 'en échec',
                    s['healthy'] == true ? (s['usingFallback'] == true ? Health.warning : Health.ok) : Health.critical,
                  ),
                  CellText(Fmt.number(s['events'] as num?)),
                  CellText('${Fmt.ago(s['lastSuccess'])} (${Fmt.time(s['lastSuccess'])})'),
                  CellText('${s['lastError'] ?? '—'}', color: s['lastError'] == null ? VrColors.textMuted : VrColors.criticalText),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Requests extends StatelessWidget {
  const _Requests(this.d, this.period);
  final Map<String, dynamic> d;
  final String period;

  @override
  Widget build(BuildContext context) {
    final series = listOf(d['series']);
    final times = <String>{for (final p in series) '${p['at']}'}.toList()..sort();
    if (times.isEmpty) return const EmptyState('Statistiques en cours de collecte (une mesure par minute).', icon: Icons.query_stats_rounded);
    double? val(String service, String at, String k) {
      final m = series.where((p) => p['service'] == service && '${p['at']}' == at).firstOrNull;
      return dbl(m?[k]);
    }

    final labels = [for (final t in times) period == '7d' ? Fmt.dayHour(t) : Fmt.time(t)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VrLineChart(
          labels: labels,
          bars: true,
          height: 190,
          series: [
            ChartSeries('Trafic (application)', [for (final t in times) val('traffic', t, 'requests') ?? 0], color: VrColors.cyan),
            ChartSeries('Administration et comptes', [for (final t in times) val('admin-api', t, 'requests') ?? 0], color: VrColors.electricBright),
            ChartSeries('Erreurs', [for (final t in times) (val('traffic', t, 'errors') ?? 0) + (val('admin-api', t, 'errors') ?? 0)], color: VrColors.critical),
          ],
        ),
        const SizedBox(height: 20),
        Text('Latence p95 (ms)', style: VrText.label),
        const SizedBox(height: 8),
        VrLineChart(
          labels: labels,
          height: 160,
          yFormat: (v) => '${Fmt.number(v)} ms',
          series: [
            ChartSeries('Trafic', [for (final t in times) val('traffic', t, 'p95Ms')], color: VrColors.cyan),
            ChartSeries('Administration', [for (final t in times) val('admin-api', t, 'p95Ms')], color: VrColors.warning),
          ],
        ),
        const SizedBox(height: 20),
        VrTable(
          columns: const [
            VrColumn('Service'),
            VrColumn('Route', flex: 3),
            VrColumn('Requêtes', numeric: true),
            VrColumn('Erreurs', numeric: true),
            VrColumn('p50', numeric: true),
            VrColumn('p95', numeric: true),
          ],
          rows: [
            for (final r in listOf(d['routes']))
              [
                CellText('${r['service']}', muted: true),
                CellText('${r['route']}', mono: true),
                CellText(Fmt.number(r['requests'] as num?)),
                CellText(Fmt.number(r['errors'] as num?), color: (r['errors'] as num? ?? 0) > 0 ? VrColors.criticalText : null),
                CellText('${Fmt.number(dbl(r['p50Ms']), digits: 1)} ms'),
                CellText('${Fmt.number(dbl(r['p95Ms']), digits: 1)} ms'),
              ],
          ],
        ),
      ],
    );
  }
}

/// Diagnostic, alertes, erreurs, sauvegardes, mises à jour.
class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key});

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  int _diag = 0;

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return PageBody(
      children: [
        Panel(
          title: 'Diagnostic de fonctionnement',
          trailing: VrButton(
            key: const Key('run-diagnostics'),
            label: 'Relancer',
            icon: Icons.health_and_safety_rounded,
            primary: false,
            onPressed: () => setState(() => _diag++),
          ),
          child: Fetch(
            key: ValueKey(_diag),
            load: (api) => api.get('/admin/diagnostics'),
            builder: (context, d, _) => Column(
              children: [
                for (final c in listOf(d['checks']))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          c['ok'] == true
                              ? Icons.check_circle_rounded
                              : (c['level'] == 'critical' ? Icons.cancel_rounded : Icons.error_outline_rounded),
                          color: c['ok'] == true
                              ? VrColors.ok
                              : (c['level'] == 'critical' ? VrColors.critical : (c['level'] == 'info' ? VrColors.textMuted : VrColors.warning)),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        SizedBox(width: 300, child: Text('${c['label']}', style: VrText.body)),
                        Expanded(child: Text('${c['detail']}', style: VrText.caption)),
                      ],
                    ),
                  ),
                Align(alignment: Alignment.centerRight, child: Text('Diagnostic du ${Fmt.dateTime(d['at'])}', style: VrText.caption)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'Sauvegardes',
          trailing: s.can('backups')
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VrButton(
                      key: const Key('backup-now'),
                      label: 'Sauvegarder maintenant',
                      icon: Icons.backup_rounded,
                      onPressed: () => unawaited(_requestBackup(context, 'manual')),
                    ),
                    const SizedBox(width: 10),
                    VrButton(
                      label: 'Tester la restauration',
                      icon: Icons.settings_backup_restore_rounded,
                      primary: false,
                      onPressed: () => unawaited(_requestBackup(context, 'restore_test')),
                    ),
                  ],
                )
              : null,
          child: Fetch(
            key: ValueKey('b$_diag'),
            refresh: const Duration(seconds: 8),
            load: (api) => api.get('/admin/backups'),
            builder: (context, d, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sauvegarde automatique chaque nuit, test de restauration chaque semaine. Les ${d['keep']} dernières '
                  'sont conservées sur le VPS (/opt/vigiroad/backups). Restauration complète : '
                  'sudo bash /opt/vigiroad/server/database/backup/restore.sh',
                  style: VrText.caption,
                ),
                const SizedBox(height: 12),
                VrTable(
                  maxHeight: 360,
                  empty: 'Aucune sauvegarde pour le moment',
                  columns: const [
                    VrColumn('Type'),
                    VrColumn('État'),
                    VrColumn('Date', flex: 2),
                    VrColumn('Fichier', flex: 3),
                    VrColumn('Taille', numeric: true),
                    VrColumn('Détail', flex: 3),
                  ],
                  rows: [
                    for (final b in listOf(d['items']))
                      [
                        CellText(switch (b['kind']) {
                          'scheduled' => 'automatique',
                          'manual' => 'manuelle',
                          _ => 'test de restauration',
                        }),
                        StatusPill(
                          switch (b['status']) {
                            'success' => 'réussie',
                            'failed' => 'échec',
                            'running' => 'en cours',
                            _ => 'en attente',
                          },
                          switch (b['status']) {
                            'success' => Health.ok,
                            'failed' => Health.critical,
                            _ => Health.warning,
                          },
                        ),
                        CellText(Fmt.dateTime(b['finishedAt'] ?? b['createdAt'])),
                        CellText('${b['fileName'] ?? '—'}', mono: true),
                        CellText(Fmt.bytes(b['sizeBytes'] as num?)),
                        CellText('${b['message'] ?? ''}', muted: true),
                      ],
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _Updates(canDeploy: s.can('deploy'))),
            const SizedBox(width: 16),
            Expanded(child: _Errors(key: ValueKey('e$_diag'))),
          ],
        ),
      ],
    );
  }

  Future<void> _requestBackup(BuildContext context, String kind) async {
    final api = SessionScope.read(context).api;
    await runAction(
      context,
      () => api.post('/admin/backups', {'kind': kind}),
      success: kind == 'manual' ? 'Sauvegarde lancée' : 'Test de restauration lancé',
    );
    setState(() {});
  }
}

class _Updates extends StatelessWidget {
  const _Updates({required this.canDeploy});
  final bool canDeploy;

  @override
  Widget build(BuildContext context) => Panel(
    title: 'Mises à jour du serveur',
    child: Fetch(
      refresh: const Duration(seconds: 20),
      load: (api) => api.get('/admin/updates'),
      builder: (context, d, reload) {
        final deploy = d['deploy'] as Map<String, dynamic>?;
        final deployed = deploy?['deployed'] as Map<String, dynamic>?;
        final latest = d['latestCommit'] as Map<String, dynamic>?;
        final release = d['latestRelease'] as Map<String, dynamic>?;
        final state = deploy?['state'] as String? ?? 'idle';
        final log = ((deploy?['log'] as List<dynamic>?) ?? const []).cast<String>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoRow('Version déployée', deployed == null ? 'inconnue' : '${(deployed['commit'] as String).substring(0, 7)} du ${Fmt.dateTime(deployed['date'])}', mono: true),
            InfoRow('Dernière version (main)', latest == null ? (d['githubError'] as String? ?? '—') : '${(latest['sha'] as String).substring(0, 7)} — ${latest['message']}', mono: true),
            InfoRow('Dernière publication', release == null ? '—' : '${release['tag']} (${Fmt.date(release['publishedAt'])})'),
            InfoRow('État', switch (state) {
              'pending' => 'mise à jour demandée…',
              'running' => 'mise à jour en cours…',
              'success' => 'dernière mise à jour réussie',
              'failed' => 'dernière mise à jour en échec',
              _ => d['updateAvailable'] == true ? 'mise à jour disponible' : 'à jour',
            }),
            const SizedBox(height: 10),
            if (canDeploy)
              Align(
                alignment: Alignment.centerLeft,
                child: VrButton(
                  label: 'Mettre à jour le serveur',
                  icon: Icons.system_update_alt_rounded,
                  onPressed: state == 'pending' || state == 'running'
                      ? null
                      : () async {
                          final ok = await confirm(
                            context,
                            title: 'Mettre à jour le serveur ?',
                            message: 'Le VPS télécharge la dernière version, reconstruit les services et les redémarre '
                                '(coupure de quelques secondes). Les données et les clés sont conservées.',
                            action: 'Mettre à jour',
                          );
                          if (!ok || !context.mounted) return;
                          await runAction(context, () => SessionScope.read(context).api.post('/admin/updates/deploy'), success: 'Mise à jour demandée');
                          await reload();
                        },
                ),
              ),
            if (log.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                height: 160,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: VrColors.background, borderRadius: BorderRadius.circular(8)),
                child: SingleChildScrollView(reverse: true, child: SelectableText(log.join('\n'), style: VrText.mono.copyWith(fontSize: 11))),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class _Errors extends StatelessWidget {
  const _Errors({super.key});

  @override
  Widget build(BuildContext context) => Panel(
    title: 'Erreurs récentes',
    child: Fetch(
      refresh: const Duration(seconds: 30),
      load: (api) => api.get('/admin/errors'),
      builder: (context, d, _) {
        final items = <(String, String, String)>[
          for (final e in listOf(d['sources'])) ('Flux ${e['source']}', '${e['error']}', Fmt.ago(e['lastAttempt'])),
          for (final e in listOf(d['backups'])) ('Sauvegarde', '${e['message']}', Fmt.ago(e['finishedAt'])),
          for (final e in listOf(d['requestErrors'])) ('${e['service']} ${e['route']}', '${e['errors']} erreur(s) serveur', Fmt.ago(e['lastAt'])),
          for (final e in listOf(d['failedLogins'])) ('Connexions ${e['kind'] == 'admin' ? 'admin' : 'utilisateurs'}', '${e['count']} × ${Fmt.loginReason(e['reason'])}', Fmt.ago(e['lastAt'])),
          for (final e in listOf(d['internal'])) ('API ${e['where']}', '${e['error']}'.split('\n').first, Fmt.ago(e['at'])),
        ];
        if (items.isEmpty) return const EmptyState('Aucune erreur sur les dernières 24 h.', icon: Icons.verified_rounded);
        return Column(
          children: [
            for (final (title, detail, ago) in items.take(30))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: VrColors.criticalText),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: VrText.body.copyWith(fontWeight: FontWeight.w600)),
                          Text(detail, style: VrText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Text(ago, style: VrText.caption),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

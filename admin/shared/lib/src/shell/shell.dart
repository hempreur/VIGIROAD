import 'dart:async';

import 'package:flutter/material.dart';

import '../api/session.dart';
import '../theme.dart';
import '../update/updater.dart';
import '../widgets/dialogs.dart';
import '../widgets/panel.dart';

/// Page d'une application d'administration.
class AdminPage {
  const AdminPage({required this.id, required this.label, required this.icon, required this.builder, this.permission});
  final String id;
  final String label;
  final IconData icon;
  final WidgetBuilder builder;

  /// Droit requis pour afficher la page (null = lecture).
  final String? permission;
}

/// Structure commune : barre latérale, en-tête (état temps réel, alertes,
/// administrateur), contenu, notifications d'alertes et mises à jour.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.appName, required this.pages, required this.updater});
  final String appName;
  final List<AdminPage> pages;
  final DesktopUpdater updater;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  final _seenAlerts = <String>{};
  AdminSession? _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = SessionScope.read(context);
    if (!identical(s, _session)) {
      _session?.snapshot.removeListener(_onSnapshot);
      _session = s..snapshot.addListener(_onSnapshot);
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(widget.updater.check());
  }

  @override
  void dispose() {
    _session?.snapshot.removeListener(_onSnapshot);
    super.dispose();
  }

  /// Notification des nouvelles alertes (ressources critiques, services).
  void _onSnapshot() {
    final alerts = ((_session?.snapshot.value?['alerts'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>();
    final ids = {for (final a in alerts) '${a['id']}:${a['level']}'};
    for (final a in alerts) {
      final key = '${a['id']}:${a['level']}';
      if (_seenAlerts.contains(key)) continue;
      if (_seenAlerts.isNotEmpty || a['level'] == 'critical') {
        notify(context, '${a['title']} — ${a['detail']}', health: a['level'] == 'critical' ? Health.critical : Health.warning);
      }
    }
    _seenAlerts
      ..removeWhere((k) => !ids.contains(k))
      ..addAll(ids);
  }

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final pages = [for (final p in widget.pages) if (p.permission == null || s.can(p.permission!)) p];
    final index = _index.clamp(0, pages.length - 1);
    final page = pages[index];
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            appName: widget.appName,
            pages: pages,
            index: index,
            onSelect: (i) => setState(() => _index = i),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(title: page.label, icon: page.icon, onAlerts: () => _showAlerts(context, s)),
                ValueListenableBuilder(
                  valueListenable: widget.updater.available,
                  builder: (context, update, _) => update == null ? const SizedBox() : _UpdateBanner(widget.updater, update),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    // Pages ancrées en haut (pas centrées verticalement).
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topLeft,
                      fit: StackFit.expand,
                      children: [...previous, ?current],
                    ),
                    child: KeyedSubtree(key: ValueKey(page.id), child: page.builder(context)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAlerts(BuildContext context, AdminSession s) {
    final alerts = ((s.snapshot.value?['alerts'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>();
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Alertes actives'),
        content: SizedBox(
          width: 560,
          child: alerts.isEmpty
              ? const EmptyState('Aucune alerte : tout fonctionne normalement.', icon: Icons.verified_rounded)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final a in alerts) AlertTile(a)],
                ),
        ),
        actions: [VrButton(label: 'Fermer', onPressed: () => Navigator.pop(d))],
      ),
    );
  }
}

/// Ligne d'alerte (niveau, titre, détail).
class AlertTile extends StatelessWidget {
  const AlertTile(this.alert, {super.key});
  final Map<String, dynamic> alert;

  @override
  Widget build(BuildContext context) {
    final critical = alert['level'] == 'critical';
    final c = critical ? VrColors.critical : VrColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(critical ? Icons.error_rounded : Icons.warning_amber_rounded, color: c),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${alert['title']}', style: VrText.body.copyWith(fontWeight: FontWeight.w600)),
                Text('${alert['detail']}', style: VrText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.appName, required this.pages, required this.index, required this.onSelect});
  final String appName;
  final List<AdminPage> pages;
  final int index;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: VrColors.backgroundRaised,
        border: Border(right: BorderSide(color: VrColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset('packages/vigiroad_admin_core/assets/vigiroad_logo.png', width: 44, height: 44),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('VIGIROAD', style: VrText.title.copyWith(fontSize: 20, color: VrColors.cyan)),
                      Text(appName.replaceFirst('VIGIROAD ', ''), style: VrText.caption.copyWith(letterSpacing: 1.2, fontSize: 10.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (var i = 0; i < pages.length; i++)
                  _NavItem(
                    key: Key('nav-${pages[i].id}'),
                    page: pages[i],
                    selected: i == index,
                    onTap: () => onSelect(i),
                  ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder(
                  valueListenable: s.live,
                  builder: (context, live, _) => Row(
                    children: [
                      StatusDot(switch (live) {
                        LiveState.live => Health.ok,
                        LiveState.connecting => Health.warning,
                        LiveState.offline => Health.critical,
                        LiveState.off => Health.unknown,
                      }),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          switch (live) {
                            LiveState.live => 'Temps réel actif',
                            LiveState.connecting => 'Connexion…',
                            LiveState.offline => 'Reconnexion automatique…',
                            LiveState.off => 'Hors ligne',
                          },
                          style: VrText.caption,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(s.server?.host ?? '', style: VrText.caption.copyWith(fontSize: 11), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: VrColors.cyan.withValues(alpha: 0.15),
                      child: Text(
                        ((s.admin?['displayName'] as String?) ?? '?').substring(0, 1).toUpperCase(),
                        style: VrText.section.copyWith(color: VrColors.cyan),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${s.admin?['displayName'] ?? ''}', style: VrText.body, overflow: TextOverflow.ellipsis),
                          Text(s.role, style: VrText.caption),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const Key('logout'),
                      tooltip: 'Se déconnecter',
                      onPressed: () => unawaited(s.logout()),
                      icon: const Icon(Icons.logout_rounded, size: 20, color: VrColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({super.key, required this.page, required this.selected, required this.onTap});
  final AdminPage page;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected ? VrColors.cyan.withValues(alpha: 0.12) : null,
            border: Border.all(color: selected ? VrColors.border(0.5) : Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(page.icon, size: 20, color: selected ? VrColors.cyan : VrColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  page.label,
                  style: VrText.body.copyWith(
                    color: selected ? VrColors.textPrimary : VrColors.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.icon, required this.onAlerts});
  final String title;
  final IconData icon;
  final VoidCallback onAlerts;

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: VrColors.line))),
      child: Row(
        children: [
          Icon(icon, color: VrColors.cyan),
          const SizedBox(width: 12),
          Text(title.toUpperCase(), style: VrText.title),
          const Spacer(),
          ValueListenableBuilder(
            valueListenable: s.snapshot,
            builder: (context, snap, _) {
              final alerts = ((snap?['alerts'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>();
              final critical = alerts.where((a) => a['level'] == 'critical').length;
              final counts = snap?['counts'] as Map<String, dynamic>?;
              return Row(
                children: [
                  if (counts != null) ...[
                    const Icon(Icons.people_alt_rounded, size: 18, color: VrColors.textSecondary),
                    const SizedBox(width: 6),
                    Text('${counts['usersOnline']} connecté(s)', style: VrText.caption),
                    const SizedBox(width: 18),
                  ],
                  Tooltip(
                    message: alerts.isEmpty ? 'Aucune alerte' : '${alerts.length} alerte(s)',
                    child: IconButton(
                      key: const Key('alerts'),
                      onPressed: onAlerts,
                      icon: Badge(
                        isLabelVisible: alerts.isNotEmpty,
                        backgroundColor: critical > 0 ? VrColors.critical : VrColors.warning,
                        label: Text('${alerts.length}'),
                        child: Icon(
                          alerts.isEmpty ? Icons.notifications_none_rounded : Icons.notifications_active_rounded,
                          color: alerts.isEmpty ? VrColors.textSecondary : (critical > 0 ? VrColors.critical : VrColors.warning),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner(this.updater, this.update);
  final DesktopUpdater updater;
  final DesktopUpdate update;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(24, 14, 24, 0),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: VrColors.cyan.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: VrColors.border(0.5)),
    ),
    child: Row(
      children: [
        const Icon(Icons.rocket_launch_rounded, color: VrColors.cyan),
        const SizedBox(width: 12),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: updater.error,
            builder: (context, err, _) => Text(
              err == null
                  ? 'Version ${update.version} en cours d\'installation automatique (installée : ${updater.currentVersion}). '
                        'L\'application redémarrera toute seule.'
                  : 'Mise à jour ${update.version} : $err',
              style: VrText.body.copyWith(color: err == null ? null : VrColors.critical),
            ),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: updater.progress,
          builder: (context, p, _) => p == null
              ? VrButton(
                  label: 'Réessayer',
                  icon: Icons.system_update_alt_rounded,
                  onPressed: () => unawaited(updater.install(update).catchError((Object e) {
                    if (context.mounted) notify(context, '$e', health: Health.critical);
                  })),
                )
              : SizedBox(
                  width: 180,
                  child: LinearProgressIndicator(value: p <= 0 ? null : p, minHeight: 6),
                ),
        ),
      ],
    ),
  );
}

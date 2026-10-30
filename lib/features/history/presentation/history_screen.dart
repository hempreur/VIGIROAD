import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/glow_panel.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../core/widgets/vr_page.dart';
import '../../navigation/application/navigation_session.dart';
import '../../plates/application/alert_service.dart';
import '../../plates/application/watchlist_controller.dart';
import '../../plates/data/repositories.dart';
import '../../plates/domain/plate_models.dart';
import '../../plates/domain/watch_entry.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/presentation/settings_screen.dart' show fileSaverProvider;

String _two(int n) => n.toString().padLeft(2, '0');
String formatDateTime(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';

/// Période affichée.
enum HistoryPeriod {
  today('Aujourd\'hui', Duration(days: 1)),
  week('7 jours', Duration(days: 7)),
  month('30 jours', Duration(days: 30)),
  all('Tout', null);

  const HistoryPeriod(this.label, this.span);
  final String label;
  final Duration? span;
}

/// Filtrage pur (testé séparément).
List<DetectionRecord> filterDetections(
  List<DetectionRecord> all, {
  required String query,
  required HistoryPeriod period,
  WatchPriority? priority,
  required DateTime now,
}) {
  final q = query.toUpperCase().replaceAll(RegExp('[^A-Z0-9 ]'), '').trim();
  final from = period == HistoryPeriod.today
      ? DateTime(now.year, now.month, now.day)
      : (period.span == null ? null : now.subtract(period.span!));
  return [
    for (final d in all)
      if ((from == null || !d.at.isBefore(from)) &&
          (priority == null || d.priority == priority) &&
          (q.isEmpty || d.plate.contains(q.replaceAll(' ', '')) || d.category.toUpperCase().contains(q)))
        d,
  ];
}

/// Export CSV de l'historique.
String exportDetectionsCsv(Iterable<DetectionRecord> records) {
  String q(String s) => s.contains(RegExp('[,"\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  final b = StringBuffer('date,plate,country,category,priority,confidence,latitude,longitude\n');
  for (final r in records) {
    b.writeln([
      r.at.toIso8601String(),
      r.plate,
      r.country,
      q(r.category),
      r.priority.name,
      r.confidence.toStringAsFixed(2),
      r.latitude?.toStringAsFixed(6) ?? '',
      r.longitude?.toStringAsFixed(6) ?? '',
    ].join(','));
  }
  return b.toString();
}

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _query = '';
  HistoryPeriod _period = HistoryPeriod.all;
  WatchPriority? _priority;

  Future<void> _delete(DetectionRecord d) async {
    if (d.id == null) return;
    await (await ref.read(detectionLogProvider.future)).delete(d.id!);
    ref.invalidate(detectionsProvider);
  }

  Future<void> _purge() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Effacer l\'historique ?'),
        content: const Text('Toutes les correspondances enregistrées seront supprimées.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Effacer', style: TextStyle(color: VrColors.alert)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await (await ref.read(detectionLogProvider.future)).clear();
    ref.invalidate(detectionsProvider);
  }

  Future<void> _export(List<DetectionRecord> shown) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await ref.read(fileSaverProvider)('vigiroad_historique.csv', exportDetectionsCsv(shown));
    if (saved) messenger.showSnackBar(SnackBar(content: Text('${shown.length} correspondance(s) exportée(s)')));
  }

  @override
  Widget build(BuildContext context) {
    final detections = ref.watch(detectionsProvider);
    final settings = ref.watch(appSettingsProvider);
    final now = ref.watch(clockProvider)();

    return VrPage(
      title: 'Historique',
      actions: [
        if (detections.value?.isNotEmpty ?? false)
          IconButton(
            tooltip: 'Effacer l\'historique',
            onPressed: _purge,
            icon: const Icon(Icons.delete_sweep_rounded, color: VrColors.textSecondary),
          ),
      ],
      children: switch (detections) {
        AsyncData(:final value) when value.isEmpty => [
          EmptyStatePanel(
            icon: Icons.history_rounded,
            title: 'Aucune détection enregistrée',
            message: settings.logHistory
                ? 'Seules les plaques présentes dans votre liste de surveillance sont journalisées ; '
                      'les autres lectures sont oubliées immédiatement. Conservation : ${settings.retention.label}.'
                : 'L\'enregistrement des correspondances est désactivé dans les réglages.',
          ),
        ],
        AsyncData(:final value) => _content(value, now, settings.allowExport),
        AsyncError(:final error) => [
          GlowPanel(tone: PanelTone.alert, child: Text('Historique indisponible : $error', style: VrText.label)),
        ],
        _ => const [Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: VrColors.cyan)))],
      },
    );
  }

  List<Widget> _content(List<DetectionRecord> all, DateTime now, bool allowExport) {
    final shown = filterDetections(all, query: _query, period: _period, priority: _priority, now: now);
    Widget chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: VrColors.cyan.withValues(alpha: 0.25),
      side: BorderSide(color: VrColors.border(selected ? 0.9 : 0.3)),
      labelStyle: VrText.caption.copyWith(color: VrColors.textPrimary),
    );
    return [
      GlowPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        radius: 14,
        glow: false,
        child: TextField(
          onChanged: (v) => setState(() => _query = v),
          style: VrText.label,
          decoration: const InputDecoration(
            border: InputBorder.none,
            icon: Icon(Icons.search_rounded, color: VrColors.cyan),
            hintText: 'Plaque ou catégorie',
            hintStyle: TextStyle(color: VrColors.textMuted),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final p in HistoryPeriod.values) chip(p.label, _period == p, () => setState(() => _period = p)),
          chip('Toutes priorités', _priority == null, () => setState(() => _priority = null)),
          for (final p in WatchPriority.values.reversed)
            chip(priorityLabel(p), _priority == p, () => setState(() => _priority = p)),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: Text('${shown.length} / ${all.length} correspondance(s)', style: VrText.caption)),
          if (allowExport)
            TextButton.icon(
              onPressed: shown.isEmpty ? null : () => _export(shown),
              icon: const Icon(Icons.download_rounded, color: VrColors.cyan, size: 18),
              label: const Text('Exporter', style: TextStyle(color: VrColors.cyan)),
            ),
        ],
      ),
      const SizedBox(height: 6),
      for (final d in shown)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Dismissible(
            key: ValueKey(d.id ?? d.at),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete_rounded, color: VrColors.alert),
            ),
            onDismissed: (_) => _delete(d).ignore(),
            child: _DetectionTile(d),
          ),
        ),
    ];
  }
}

class _DetectionTile extends StatelessWidget {
  const _DetectionTile(this.d);
  final DetectionRecord d;

  @override
  Widget build(BuildContext context) {
    return GlowPanel(
      glow: false,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          PlateBadge(text: d.display, countryLetter: euBandLetter(d.country), height: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${d.category} · priorité ${priorityLabel(d.priority).toLowerCase()}',
                  style: VrText.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${formatDateTime(d.at)} · confiance ${(d.confidence * 100).round()} %'
                  '${d.latitude == null ? '' : ' · ${d.latitude!.toStringAsFixed(4)}, ${d.longitude!.toStringAsFixed(4)}'}',
                  style: VrText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

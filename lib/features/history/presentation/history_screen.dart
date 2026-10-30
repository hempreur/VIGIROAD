import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/glow_panel.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../core/widgets/vr_page.dart';
import '../../plates/application/alert_service.dart';
import '../../plates/data/repositories.dart';
import '../../plates/domain/plate_models.dart';
import '../../plates/domain/watch_entry.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String formatDateTime(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';

/// Historique des correspondances enregistrées (filtres et purge en phase 8).
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detections = ref.watch(detectionsProvider);
    return VrPage(
      title: 'Historique',
      children: switch (detections) {
        AsyncData(:final value) when value.isEmpty => const [
          EmptyStatePanel(
            icon: Icons.history_rounded,
            title: 'Aucune détection enregistrée',
            message: 'Seules les plaques présentes dans votre liste de surveillance '
                'sont journalisées ; les autres lectures sont oubliées immédiatement.',
          ),
        ],
        AsyncData(:final value) => [
          Text('${value.length} correspondance(s)', style: VrText.caption),
          const SizedBox(height: 8),
          for (final d in value) Padding(padding: const EdgeInsets.only(bottom: 8), child: _DetectionTile(d)),
        ],
        AsyncError(:final error) => [
          GlowPanel(tone: PanelTone.alert, child: Text('Historique indisponible : $error', style: VrText.label)),
        ],
        _ => const [Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: VrColors.cyan)))],
      },
    );
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
                Text('${d.category} · priorité ${priorityLabel(d.priority).toLowerCase()}',
                    style: VrText.label, maxLines: 1, overflow: TextOverflow.ellipsis),
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

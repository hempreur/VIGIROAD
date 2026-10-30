import 'package:flutter/material.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/glow_panel.dart';
import '../domain/traffic_labels.dart';
import '../domain/traffic_snapshot.dart';
import 'traffic_format.dart';

/// Détail d'une perturbation touchée sur la carte, avec sa source.
Future<void> showTrafficEvent(BuildContext context, TrafficEvent e, List<TrafficAttribution> attributions) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => TrafficEventSheet(event: e, attributions: attributions),
  );
}

class TrafficEventSheet extends StatelessWidget {
  const TrafficEventSheet({super.key, required this.event, required this.attributions});

  final TrafficEvent event;
  final List<TrafficAttribution> attributions;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final color = TrafficLabels.color(e.severity);
    final sources = [
      for (final a in attributions)
        if (e.sources.contains(a.source)) a.text,
    ];
    final when = [
      if (e.startTime case final t?) 'depuis ${hhmm(t)}',
      if (e.endTime case final t?) 'jusqu\'à ${hhmm(t)}',
    ].join(', ');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: GlowPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(TrafficLabels.headline(e), style: VrText.label)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Gravité ${TrafficLabels.severity(e.severity)}${when.isEmpty ? '' : ' · $when'}',
                style: VrText.caption.copyWith(color: VrColors.textSecondary),
              ),
              if (e.description case final d? when d.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(d.trim(), style: VrText.caption.copyWith(color: VrColors.textPrimary)),
              ],
              const SizedBox(height: 10),
              Text(
                [
                  if (sources.isNotEmpty) sources.join(' · ') else 'Source : ${e.sources.join(', ')}',
                  'mis à jour à ${hhmm(e.updatedAt)}',
                ].join(' — '),
                style: VrText.caption.copyWith(fontSize: 11, color: VrColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

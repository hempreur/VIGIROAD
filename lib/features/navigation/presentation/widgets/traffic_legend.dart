import 'package:flutter/widgets.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../../../../core/theme/vr_colors.dart';
import '../../../../core/theme/vr_typography.dart';
import '../../../../core/widgets/glow_panel.dart';
import '../../../traffic/application/traffic_controller.dart';
import '../../../traffic/domain/traffic_labels.dart';
import '../../../traffic/presentation/traffic_format.dart';

/// Légende « Trafic en temps réel ».
///
/// Elle ne montre que ce que disent les sources officielles : « état
/// inconnu » hors de leur couverture, « aucun incident signalé » (et non
/// « fluide ») quand une source à jour ne signale rien. Les mentions des
/// sources et l'heure de mise à jour sont toujours affichées avec les données.
class TrafficLegend extends StatelessWidget {
  const TrafficLegend({super.key, required this.state});

  final TrafficState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final hasData = s.status == TrafficStatus.known || s.status == TrafficStatus.unknown;
    final events = s.visible.length;
    final (String line, Color dot) = switch (s.status) {
      TrafficStatus.disabled => ('Source non configurée', VrColors.textMuted),
      TrafficStatus.waiting => ('Chargement…', VrColors.textMuted),
      TrafficStatus.error => ('Indisponible', VrColors.textMuted),
      TrafficStatus.unknown => ('État inconnu ici', VrColors.textMuted),
      TrafficStatus.known when events == 0 => ('Aucun incident signalé', VrColors.cyan),
      TrafficStatus.known => (events == 1 ? '1 perturbation' : '$events perturbations', VrColors.trafficSlow),
    };
    final mentions = [for (final a in s.attributions) a.text];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 168),
      child: GlowPanel(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        radius: 14,
        opacity: 0.88,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Trafic en temps réel', style: VrText.label.copyWith(fontSize: 12.5)),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    line,
                    style: VrText.caption.copyWith(
                      fontSize: 11.5,
                      color: s.status == TrafficStatus.known ? VrColors.textPrimary : VrColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            if (hasData && events > 0) ...[
              const SizedBox(height: 4),
              _row(Severity.high, 'Grave'),
              _row(Severity.medium, 'Modérée'),
              _row(Severity.low, 'Faible'),
            ],
            if (hasData && mentions.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                [
                  ...mentions,
                  if (s.updatedAt case final t?) 'Mise à jour ${hhmm(t)}',
                ].join(' · '),
                style: VrText.caption.copyWith(fontSize: 10, color: VrColors.textMuted, height: 1.25),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(Severity sev, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 8,
            decoration: BoxDecoration(color: TrafficLabels.color(sev), borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 8),
          Text(label, style: VrText.caption.copyWith(fontSize: 11, color: VrColors.textPrimary)),
        ],
      ),
    );
  }
}

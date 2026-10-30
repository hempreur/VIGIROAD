import 'package:flutter/widgets.dart';

import '../../../../core/theme/vr_colors.dart';
import '../../../../core/theme/vr_typography.dart';
import '../../../../core/widgets/glow_panel.dart';

/// Légende « Trafic en temps réel ».
///
/// Sans fournisseur de trafic configuré, la légende l'indique explicitement
/// au lieu de suggérer des données (règle 6 — transparence).
class TrafficLegend extends StatelessWidget {
  const TrafficLegend({super.key, required this.available});

  final bool available;

  @override
  Widget build(BuildContext context) {
    return GlowPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      radius: 14,
      opacity: 0.88,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Trafic en temps réel', style: VrText.label.copyWith(fontSize: 12.5)),
          const SizedBox(height: 6),
          _row(VrColors.trafficFluid, 'Fluide'),
          _row(VrColors.trafficSlow, 'Ralenti'),
          _row(VrColors.trafficJam, 'Embouteillage'),
          if (!available) ...[
            const SizedBox(height: 4),
            Text(
              'Source non configurée',
              style: VrText.caption.copyWith(fontSize: 11, color: VrColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(Color color, String label) {
    return Opacity(
      opacity: available ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 10,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Text(label, style: VrText.caption.copyWith(color: VrColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

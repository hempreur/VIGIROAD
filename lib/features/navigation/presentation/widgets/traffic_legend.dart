import 'package:flutter/widgets.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../../../../core/theme/vr_colors.dart';
import '../../../../core/theme/vr_typography.dart';
import '../../../../core/widgets/glow_panel.dart';
import '../../../traffic/application/traffic_controller.dart';
import '../../../traffic/domain/traffic_labels.dart';

/// Encadré compact « Trafic » : nombre de perturbations **sur le trajet
/// défini par l'utilisateur**, encore devant lui.
///
/// Rien n'est inventé : « état inconnu » hors de la couverture des sources,
/// « aucune perturbation » (jamais « fluide ») quand une source à jour ne
/// signale rien. Les mentions des sources sont dans le détail de chaque
/// perturbation (toucher son point sur la carte).
class TrafficLegend extends StatelessWidget {
  const TrafficLegend({super.key, required this.state, this.hasRoute = false, this.alongM});

  final TrafficState state;

  /// Un trajet est en cours.
  final bool hasRoute;

  /// Distance déjà parcourue sur le trajet (les perturbations dépassées ne
  /// sont plus comptées).
  final double? alongM;

  /// Perturbations du trajet encore devant le véhicule.
  List<TrafficEvent> get ahead => [
    for (final r in state.onRoute)
      if (alongM == null || r.alongM >= alongM! - 50) r.event,
  ];

  @override
  Widget build(BuildContext context) {
    final s = state;
    final ahead = this.ahead;
    final worst = ahead.isEmpty
        ? null
        : ahead.map((e) => e.severity).reduce((a, b) => a.index >= b.index ? a : b);
    final (String line, Color dot) = switch (s.status) {
      TrafficStatus.disabled => ('Non configuré', VrColors.textMuted),
      TrafficStatus.waiting => ('Chargement…', VrColors.textMuted),
      TrafficStatus.error => ('Indisponible', VrColors.textMuted),
      _ when !hasRoute => ('Aucun trajet', VrColors.textMuted),
      TrafficStatus.unknown when ahead.isEmpty => ('État inconnu', VrColors.textMuted),
      _ when ahead.isEmpty => ('0 perturbation', VrColors.cyan),
      _ => (ahead.length == 1 ? '1 perturbation' : '${ahead.length} perturbations', TrafficLabels.color(worst!)),
    };

    return Semantics(
      label: 'Trafic sur le trajet : $line',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 132),
        child: GlowPanel(
          padding: const EdgeInsets.fromLTRB(9, 6, 10, 6),
          radius: 11,
          opacity: 0.88,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Trafic trajet', style: VrText.caption.copyWith(fontSize: 10, color: VrColors.textMuted, height: 1.1)),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VrText.caption.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: ahead.isNotEmpty ? VrColors.textPrimary : VrColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

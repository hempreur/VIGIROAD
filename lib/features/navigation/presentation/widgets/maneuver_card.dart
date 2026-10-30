import 'package:flutter/material.dart';

import '../../../../core/theme/vr_colors.dart';
import '../../../../core/theme/vr_typography.dart';
import '../../../../core/widgets/glow_panel.dart';

/// Cartouche de guidage en haut de l'écran.
///
/// Même composition que la référence : grande icône à gauche, valeur en
/// gros chiffres, consigne et précision en dessous.
class ManeuverCard extends StatelessWidget {
  const ManeuverCard({
    super.key,
    required this.icon,
    required this.headline,
    required this.title,
    this.subtitle,
    this.onTap,
    this.onClose,
  });

  /// Carte d'invitation quand aucune destination n'est choisie.
  factory ManeuverCard.prompt({required VoidCallback onTap}) => ManeuverCard(
    icon: Icons.search_rounded,
    headline: 'Où allez-vous ?',
    title: 'Touchez pour chercher une adresse',
    onTap: onTap,
  );

  final IconData icon;
  final String headline;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: [headline, title, if (subtitle != null) subtitle!].join(', '),
      excludeSemantics: onClose == null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: GlowPanel(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              Icon(icon, size: 44, color: VrColors.textPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VrText.metric.copyWith(fontSize: 26),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VrText.label.copyWith(fontSize: 14.5),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VrText.caption,
                      ),
                  ],
                ),
              ),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  tooltip: 'Annuler la destination',
                  icon: const Icon(Icons.close_rounded, color: VrColors.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/vr_colors.dart';

/// Bouton carré flottant de la carte (couches, recentrage, alertes),
/// comme la colonne de droite de l'image de référence.
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.alert = false,
    this.active = false,
    this.size = 52,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Variante rouge (accès aux alertes).
  final bool alert;

  /// État activé (ex. suivi de position en cours).
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = alert ? VrColors.alert : VrColors.cyan;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    VrColors.panelLight.withValues(alpha: 0.95),
                    VrColors.panel.withValues(alpha: 0.95),
                  ],
                ),
                border: Border.all(
                  color: accent.withValues(alpha: active || alert ? 0.8 : 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: active || alert ? 0.35 : 0.12),
                    blurRadius: 12,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Icon(
                icon,
                size: size * 0.5,
                color: alert
                    ? VrColors.alert
                    : (active ? VrColors.cyanBright : VrColors.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

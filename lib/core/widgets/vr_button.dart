import 'package:flutter/material.dart';

import '../theme/vr_colors.dart';
import '../theme/vr_typography.dart';

enum VrButtonStyle { primary, outline, alert }

/// Bouton minimaliste VIGIROAD : icône + libellé, coins arrondis, lueur cyan.
///
/// Inspiré des pastilles « Commandes vocales » de l'image de référence.
/// Cible tactile ≥ 52 px pour une utilisation en véhicule.
class VrButton extends StatelessWidget {
  const VrButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = VrButtonStyle.outline,
    this.expanded = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final VrButtonStyle style;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final accent = switch (style) {
      VrButtonStyle.alert => VrColors.alert,
      _ => VrColors.cyan,
    };
    final filled = style == VrButtonStyle.primary;
    final fg = filled ? VrColors.background : VrColors.textPrimary;

    final content = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 22, color: filled ? fg : accent),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: VrText.label.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: filled ? accent : VrColors.panel.withValues(alpha: 0.9),
                border: Border.all(
                  color: accent.withValues(alpha: filled ? 1 : 0.55),
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: filled ? 0.45 : 0.18),
                    blurRadius: 16,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

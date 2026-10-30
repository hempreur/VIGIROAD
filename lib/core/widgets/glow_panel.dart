import 'package:flutter/widgets.dart';

import '../theme/vr_colors.dart';

/// Ton d'un panneau : neutre (cyan) ou alerte (rouge).
enum PanelTone { normal, alert }

/// Panneau sombre à coins arrondis et bordure lumineuse discrète.
///
/// Brique de base de toute l'interface : cartouche de guidage, fenêtre OCR,
/// légende trafic, encadré d'alerte… (cf. image de référence).
class GlowPanel extends StatelessWidget {
  const GlowPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 18,
    this.tone = PanelTone.normal,
    this.glow = true,
    this.opacity = 0.92,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final PanelTone tone;
  final bool glow;

  /// Opacité du fond — < 1 pour laisser deviner la carte en dessous.
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final isAlert = tone == PanelTone.alert;
    final accent = isAlert ? VrColors.alert : VrColors.cyan;
    final top = isAlert ? const Color(0xFF2A0D12) : VrColors.panelLight;
    final bottom = isAlert ? VrColors.alertBackground : VrColors.panel;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            top.withValues(alpha: opacity),
            bottom.withValues(alpha: opacity),
          ],
        ),
        border: Border.all(
          color: accent.withValues(alpha: isAlert ? 0.85 : 0.32),
          width: isAlert ? 1.6 : 1,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: isAlert ? 0.45 : 0.18),
                  blurRadius: isAlert ? 22 : 14,
                  spreadRadius: -2,
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

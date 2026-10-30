import 'package:flutter/widgets.dart';

import '../../../../core/theme/vr_colors.dart';
import '../../../../core/theme/vr_typography.dart';

/// Compteur de vitesse circulaire à anneau cyan (référence : « 82 km/h »).
class SpeedGauge extends StatelessWidget {
  const SpeedGauge({super.key, required this.speedKmh, this.size = 68, this.overLimit = false});

  /// `null` tant que le GPS ne fournit pas de vitesse.
  final int? speedKmh;
  final double size;

  /// Dépassement de la limitation : l'anneau passe au rouge.
  final bool overLimit;

  @override
  Widget build(BuildContext context) {
    final ring = overLimit ? VrColors.alert : VrColors.cyan;
    final label = speedKmh == null ? 'Vitesse indisponible' : '$speedKmh kilomètres heure';
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: VrColors.background.withValues(alpha: 0.92),
          border: Border.all(color: ring, width: size * 0.045),
          boxShadow: [BoxShadow(color: ring.withValues(alpha: 0.5), blurRadius: 14)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              speedKmh?.toString() ?? '--',
              style: VrText.metric.copyWith(fontSize: size * 0.4),
            ),
            Text(
              'km/h',
              style: VrText.caption.copyWith(fontSize: size * 0.15, height: 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// Panneau de limitation de vitesse (disque blanc cerclé de rouge).
class SpeedLimitSign extends StatelessWidget {
  const SpeedLimitSign({super.key, required this.limitKmh, this.size = 48});

  final int limitKmh;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Limitation $limitKmh kilomètres heure',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFFFFFF),
          border: Border.all(color: VrColors.trafficJam, width: size * 0.12),
        ),
        child: Text(
          '$limitKmh',
          style: VrText.metric.copyWith(
            fontSize: size * (limitKmh >= 100 ? 0.36 : 0.44),
            color: const Color(0xFF111418),
          ),
        ),
      ),
    );
  }
}

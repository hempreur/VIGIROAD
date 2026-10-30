import 'package:flutter/widgets.dart';

import '../theme/vr_colors.dart';

/// Fond d'écran VIGIROAD pour les écrans hors carte : noir profond avec un
/// halo cyan diffus en bas, évoquant la route nocturne de l'image de référence.
class VrBackdrop extends StatelessWidget {
  const VrBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            VrColors.background,
            VrColors.backgroundRaised,
            Color(0xFF031627),
          ],
          stops: [0, 0.6, 1],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, 1.25),
            radius: 0.9,
            colors: [
              VrColors.electric.withValues(alpha: 0.28),
              VrColors.electric.withValues(alpha: 0),
            ],
          ),
        ),
        child: child,
      ),
    );
  }
}

import 'package:flutter/widgets.dart';

import '../theme/vr_colors.dart';
import '../theme/vr_typography.dart';

/// Logotype « VIGIROAD » : VIGI en blanc, ROAD en cyan lumineux, comme le
/// titre bicolore de l'image de référence.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final base = VrText.brand.copyWith(fontSize: size, letterSpacing: size * 0.14);
    return Semantics(
      label: 'VIGIROAD',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'VIGI', style: base),
            TextSpan(
              text: 'ROAD',
              style: base.copyWith(
                color: VrColors.cyan,
                shadows: [
                  Shadow(color: VrColors.glow(0.7), blurRadius: size * 0.45),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

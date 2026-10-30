import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/vr_colors.dart';
import '../theme/vr_typography.dart';

/// Plaque d'immatriculation au format européen : fond blanc, bande bleue
/// à gauche avec cercle d'étoiles et lettre du pays.
///
/// Sans [text], affiche un emplacement vide (aucune lecture en cours).
class PlateBadge extends StatelessWidget {
  const PlateBadge({
    super.key,
    this.text,
    this.countryLetter = 'F',
    this.height = 52,
    this.glow = false,
  });

  final String? text;
  final String countryLetter;
  final double height;

  /// Cadre lumineux cyan, comme la plaque repérée dans la vue caméra.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final h = height;
    final empty = text == null;
    return Semantics(
      label: empty ? 'Aucune plaque lue' : 'Plaque $text',
      excludeSemantics: true,
      child: Container(
        height: h,
        constraints: BoxConstraints(minWidth: h * 3.6),
        decoration: BoxDecoration(
          color: empty ? VrColors.panelLight : VrColors.plateWhite,
          borderRadius: BorderRadius.circular(h * 0.12),
          border: Border.all(
            color: glow ? VrColors.cyanBright : const Color(0xFF15191E),
            width: glow ? 2 : h * 0.05,
          ),
          boxShadow: glow
              ? [BoxShadow(color: VrColors.glow(0.7), blurRadius: 16, spreadRadius: 1)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: h * 0.38,
              decoration: BoxDecoration(
                color: empty ? VrColors.textMuted : VrColors.plateEuBlue,
                borderRadius: BorderRadius.horizontal(left: Radius.circular(h * 0.08)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  CustomPaint(size: Size.square(h * 0.26), painter: _EuStarsPainter()),
                  Text(
                    countryLetter,
                    style: TextStyle(
                      fontFamily: VrText.display,
                      fontWeight: FontWeight.w700,
                      fontSize: h * 0.28,
                      height: 1,
                      color: const Color(0xFFFFFFFF),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: h * 0.22),
              child: Text(
                text ?? '— — —',
                maxLines: 1,
                style: VrText.plate.copyWith(
                  fontSize: h * 0.62,
                  height: 1,
                  color: empty ? VrColors.textMuted : const Color(0xFF111418),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EuStarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.4;
    final p = Paint()..color = const Color(0xFFFFD43B);
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r, size.width * 0.07, p);
    }
  }

  @override
  bool shouldRepaint(_EuStarsPainter oldDelegate) => false;
}

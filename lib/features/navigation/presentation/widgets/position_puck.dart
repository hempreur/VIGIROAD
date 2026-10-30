import 'package:flutter/widgets.dart';

import '../../../../core/theme/vr_colors.dart';

/// Marqueur de position : flèche blanche dans un disque bleu lumineux,
/// comme sur l'image de référence. Dessiné par-dessus la carte en mode suivi.
class PositionPuck extends StatelessWidget {
  const PositionPuck({super.key, this.size = 54});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Votre position',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _PuckPainter()),
      ),
    );
  }
}

class _PuckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = VrColors.electric.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      c,
      r * 0.78,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF2E8BFF), VrColors.electric],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.78)),
    );
    canvas.drawCircle(
      c,
      r * 0.78,
      Paint()
        ..color = VrColors.cyanBright
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07,
    );
    // Flèche de navigation (pointe vers le haut : la carte tourne avec le cap).
    final arrow = Path()
      ..moveTo(c.dx, c.dy - r * 0.48)
      ..lineTo(c.dx + r * 0.34, c.dy + r * 0.36)
      ..lineTo(c.dx, c.dy + r * 0.18)
      ..lineTo(c.dx - r * 0.34, c.dy + r * 0.36)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(_PuckPainter oldDelegate) => false;
}

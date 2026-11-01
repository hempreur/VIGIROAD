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

/// Voiture du suivi GPS (vue arrière, fournie par le propriétaire de
/// VIGIROAD), à la place du marqueur rond.
///
/// En vue conduite 3D, la carte tourne avec le cap : la voiture reste droite.
/// En vue à plat (nord en haut), elle est tournée selon le cap.
class CarPuck extends StatelessWidget {
  const CarPuck({super.key, this.width = 64, this.headingDeg});

  static const asset = 'assets/icons/car_puck.png';

  /// Proportions de l'image (256 × 227).
  static const aspect = 227 / 256;

  final double width;

  /// Rotation à appliquer (vue à plat), null = droite.
  final double? headingDeg;

  double get height => width * aspect;

  @override
  Widget build(BuildContext context) {
    Widget car = DecoratedBox(
      decoration: BoxDecoration(
        // Ombre portée : la voiture se détache de la carte sombre.
        boxShadow: [BoxShadow(color: VrColors.electric.withValues(alpha: 0.45), blurRadius: 18, spreadRadius: -6)],
      ),
      child: Image.asset(asset, width: width, height: height, filterQuality: FilterQuality.medium, excludeFromSemantics: true),
    );
    final h = headingDeg;
    if (h != null) car = Transform.rotate(angle: h * 3.141592653589793 / 180, child: car);
    return Semantics(label: 'Votre position', child: car);
  }
}

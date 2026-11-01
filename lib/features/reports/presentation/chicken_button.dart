import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/vr_colors.dart';

/// Tête de poulet coiffée d'un képi (dessin original VIGIROAD), sur un
/// disque sombre cerclé d'ambre.
class ChickenHeadPainter extends CustomPainter {
  const ChickenHeadPainter({this.pressed = false});

  final bool pressed;

  static const _amber = Color(0xFFFFB020);
  static const _cream = Color(0xFFFFF3DC);
  static const _red = Color(0xFFE53935);
  static const _beak = Color(0xFFFFA726);
  static const _navy = Color(0xFF1B2B6B);
  static const _navyTop = Color(0xFF2C3F8F);
  static const _visor = Color(0xFF0A0E18);
  static const _gold = Color(0xFFFFD54F);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 100;
    canvas.save();
    canvas.translate((size.width - 100 * s) / 2, (size.height - 100 * s) / 2);
    canvas.scale(s);

    // Disque et anneau lumineux.
    const center = Offset(50, 50);
    canvas.drawCircle(
      center,
      48,
      Paint()
        ..shader = const RadialGradient(colors: [VrColors.panelLight, VrColors.panel])
            .createShader(Rect.fromCircle(center: center, radius: 48)),
    );
    canvas.drawCircle(
      center,
      46.5,
      Paint()
        ..color = _amber.withValues(alpha: pressed ? 0.9 : 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      center,
      46.5,
      Paint()
        ..color = _amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6,
    );

    // Crête qui dépasse du képi, à l'arrière.
    final comb = Paint()..color = _red;
    canvas.drawCircle(const Offset(29, 45), 6.5, comb);
    canvas.drawCircle(const Offset(26, 53), 5.5, comb);

    // Barbillon sous le bec.
    canvas.drawOval(Rect.fromCenter(center: const Offset(67, 76), width: 8, height: 13), comb);

    // Tête.
    final head = Rect.fromCenter(center: const Offset(49, 61), width: 44, height: 46);
    canvas.drawOval(head, Paint()..color = _cream);
    canvas.drawOval(
      head,
      Paint()
        ..color = const Color(0xFFD9C7A3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Bec.
    final beak = Path()
      ..moveTo(68, 57)
      ..quadraticBezierTo(80, 60, 84, 64)
      ..quadraticBezierTo(78, 68, 68, 69)
      ..close();
    canvas.drawPath(beak, Paint()..color = _beak);
    canvas.drawLine(
      const Offset(69, 63.5),
      const Offset(81, 64),
      Paint()
        ..color = const Color(0xFFB86E12)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );

    // Œil et sourcil sévère.
    canvas.drawCircle(const Offset(59, 55), 4.2, Paint()..color = const Color(0xFF111111));
    canvas.drawCircle(const Offset(60.4, 53.6), 1.4, Paint()..color = Colors.white);
    canvas.drawLine(
      const Offset(53, 47.5),
      const Offset(65, 50),
      Paint()
        ..color = const Color(0xFF3B2A1A)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );

    // Képi : calot, bandeau, insigne doré, visière.
    final crown = Path()
      ..moveTo(28, 42)
      ..lineTo(32, 17)
      ..quadraticBezierTo(48, 13, 64, 17)
      ..lineTo(68, 42)
      ..close();
    canvas.drawPath(crown, Paint()..color = _navy);
    canvas.drawOval(Rect.fromCenter(center: const Offset(48, 17), width: 32, height: 7), Paint()..color = _navyTop);
    canvas.drawRect(const Rect.fromLTRB(29, 34, 67.5, 42), Paint()..color = _red);
    canvas.drawLine(
      const Offset(29.5, 34),
      const Offset(67, 34),
      Paint()
        ..color = _gold
        ..strokeWidth = 1.4,
    );
    final badge = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? 5.2 : 2.3;
      final a = -1.5708 + i * 0.6283;
      final p = Offset(48 + r * math.cos(a), 26 + r * math.sin(a));
      if (i == 0) {
        badge.moveTo(p.dx, p.dy);
      } else {
        badge.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(badge..close(), Paint()..color = _gold);
    final visor = Path()
      ..moveTo(52, 41)
      ..quadraticBezierTo(70, 40, 82, 46)
      ..quadraticBezierTo(70, 48.5, 52, 45.5)
      ..close();
    canvas.drawPath(visor, Paint()..color = _visor);

    canvas.restore();
  }

  @override
  bool shouldRepaint(ChickenHeadPainter old) => old.pressed != pressed;
}

/// Bouton rond « Chicken » : ouvre le choix du sens du signalement.
class ChickenButton extends StatefulWidget {
  const ChickenButton({super.key, required this.onPressed, this.size = 64});

  final VoidCallback? onPressed;
  final double size;

  @override
  State<ChickenButton> createState() => _ChickenButtonState();
}

class _ChickenButtonState extends State<ChickenButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Signaler un Chicken',
    excludeSemantics: true,
    child: GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: const Duration(milliseconds: 90),
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(painter: ChickenHeadPainter(pressed: _down)),
        ),
      ),
    ),
  );
}

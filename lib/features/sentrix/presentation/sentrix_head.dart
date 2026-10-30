import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme/vr_colors.dart';
import '../domain/sentrix_state.dart';

/// Tête robotique animée de SENTRIX, dessinée en vectoriel.
///
/// Reprend l'identité de l'image de référence : casque blanc nacré,
/// visière noire à trame de points, yeux en arc cyan lumineux, écouteurs à
/// anneau lumineux et micro-perche. Entièrement vectorielle : nette à toutes
/// les tailles, sans fichier image.
class SentrixHead extends StatefulWidget {
  const SentrixHead({
    super.key,
    this.state = SentrixState.idle,
    this.size = 120,
  });

  final SentrixState state;

  /// Largeur du widget ; la hauteur vaut 0,8 × la largeur (tête plus large
  /// que haute, comme sur la référence).
  final double size;

  @override
  State<SentrixHead> createState() => _SentrixHeadState();
}

class _SentrixHeadState extends State<SentrixHead>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: 'SENTRIX, ${_stateLabel(widget.state)}',
      image: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size * 0.8,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _clock,
            builder: (context, _) => CustomPaint(
              painter: SentrixPainter(
                state: widget.state,
                t: reduceMotion ? 0.3 : _clock.value,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _stateLabel(SentrixState s) => switch (s) {
    SentrixState.idle => 'au repos',
    SentrixState.listening => 'à l\'écoute',
    SentrixState.thinking => 'analyse en cours',
    SentrixState.speaking => 'répond',
    SentrixState.notification => 'notification',
    SentrixState.error => 'erreur',
  };
}

/// Peintre de la tête. Exposé pour les tests de rendu (golden).
class SentrixPainter extends CustomPainter {
  SentrixPainter({required this.state, required this.t});

  final SentrixState state;

  /// Horloge d'animation normalisée [0, 1[ sur 4 s.
  final double t;

  Color get _eyeColor => switch (state) {
    SentrixState.notification => VrColors.alert,
    SentrixState.error => VrColors.trafficSlow,
    _ => VrColors.cyanBright,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final glowPulse = switch (state) {
      SentrixState.listening => 0.55 + 0.45 * (0.5 + 0.5 * math.sin(t * math.pi * 8)),
      SentrixState.notification => 0.5 + 0.5 * (0.5 + 0.5 * math.sin(t * math.pi * 12)),
      _ => 0.75,
    };

    // --- Écouteurs (derrière le casque) -------------------------------------
    for (final left in [true, false]) {
      final cx = left ? w * 0.075 : w * 0.925;
      final ear = Rect.fromCenter(
        center: Offset(cx, h * 0.47),
        width: w * 0.16,
        height: h * 0.5,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(ear, Radius.circular(w * 0.07)),
        Paint()
          ..shader = LinearGradient(
            colors: const [Color(0xFF3A434D), Color(0xFF14191F)],
            begin: left ? Alignment.centerLeft : Alignment.centerRight,
            end: left ? Alignment.centerRight : Alignment.centerLeft,
          ).createShader(ear),
      );
      // Anneau lumineux vertical.
      final ring = Rect.fromCenter(
        center: Offset(cx + (left ? -w * 0.012 : w * 0.012), h * 0.47),
        width: w * 0.05,
        height: h * 0.38,
      );
      final ringPaint = Paint()
        ..color = _eyeColor.withValues(alpha: glowPulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.022
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        ring,
        left ? math.pi * 0.6 : -math.pi * 0.4,
        math.pi * 0.8,
        false,
        ringPaint..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.02),
      );
      canvas.drawArc(
        ring,
        left ? math.pi * 0.6 : -math.pi * 0.4,
        math.pi * 0.8,
        false,
        ringPaint
          ..maskFilter = null
          ..strokeWidth = w * 0.012,
      );
    }

    // --- Casque ----------------------------------------------------------------
    final shell = Rect.fromLTWH(w * 0.1, h * 0.04, w * 0.8, h * 0.86);
    final shellR = RRect.fromRectAndRadius(shell, Radius.circular(w * 0.36));
    canvas.drawRRect(
      shellR.shift(Offset(0, h * 0.02)),
      Paint()
        ..color = const Color(0xAA000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.03),
    );
    canvas.drawRRect(
      shellR,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF3F5F8), Color(0xFFC3CAD2), Color(0xFF7E8893)],
          stops: [0, 0.55, 1],
        ).createShader(shell),
    );
    // Reflet nacré.
    canvas.drawArc(
      Rect.fromLTWH(w * 0.2, h * 0.08, w * 0.6, h * 0.35),
      math.pi * 1.1,
      math.pi * 0.8,
      false,
      Paint()
        ..color = const Color(0x99FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.015
        ..strokeCap = StrokeCap.round,
    );
    // Ligne de jointure du casque.
    canvas.drawArc(
      Rect.fromLTWH(w * 0.16, h * 0.1, w * 0.68, h * 0.5),
      math.pi * 1.15,
      math.pi * 0.7,
      false,
      Paint()
        ..color = const Color(0x55606A75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.006,
    );

    // --- Visière -----------------------------------------------------------------
    final visor = Rect.fromLTWH(w * 0.165, h * 0.17, w * 0.67, h * 0.6);
    final visorR = RRect.fromRectAndRadius(visor, Radius.circular(w * 0.2));
    canvas.drawRRect(
      visorR,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.2, -0.4),
          radius: 1.1,
          colors: [Color(0xFF0C1622), Color(0xFF020407)],
        ).createShader(visor),
    );
    canvas.drawRRect(
      visorR,
      Paint()
        ..color = VrColors.cyan.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.006,
    );
    // Trame de points (écran LED).
    canvas.save();
    canvas.clipRRect(visorR);
    final dot = Paint()..color = VrColors.cyan.withValues(alpha: 0.07);
    final step = w * 0.022;
    for (var y = visor.top + step / 2; y < visor.bottom; y += step) {
      for (var x = visor.left + step / 2; x < visor.right; x += step) {
        canvas.drawCircle(Offset(x, y), step * 0.18, dot);
      }
    }
    canvas.restore();

    // --- Yeux -------------------------------------------------------------------
    final eyeY = h * 0.47;
    final eyeDx = w * 0.14;
    final eyeW = w * 0.15;
    final center = w / 2;
    _paintEyes(canvas, Offset(center - eyeDx, eyeY), eyeW, w, glowPulse);
    _paintEyes(canvas, Offset(center + eyeDx, eyeY), eyeW, w, glowPulse);

    if (state == SentrixState.speaking) {
      _paintVoiceWave(canvas, Offset(center, h * 0.66), w * 0.26, w);
    }

    // --- Micro-perche -------------------------------------------------------------
    final micPath = Path()
      ..moveTo(w * 0.86, h * 0.62)
      ..quadraticBezierTo(w * 0.8, h * 0.82, w * 0.62, h * 0.82);
    canvas.drawPath(
      micPath,
      Paint()
        ..color = const Color(0xFF20262D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.018
        ..strokeCap = StrokeCap.round,
    );
    final mic = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.58, h * 0.82), width: w * 0.11, height: h * 0.065),
      Radius.circular(w * 0.04),
    );
    canvas.drawRRect(mic, Paint()..color = const Color(0xFF0B0F14));
    canvas.drawRRect(
      mic,
      Paint()
        ..color = _eyeColor.withValues(alpha: state == SentrixState.listening ? glowPulse : 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.008,
    );
  }

  void _paintEyes(Canvas canvas, Offset c, double eyeW, double w, double pulse) {
    final color = _eyeColor;
    final stroke = w * 0.036;
    final glow = Paint()
      ..color = color.withValues(alpha: 0.55 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 2.2
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.025);
    final core = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    switch (state) {
      case SentrixState.idle:
      case SentrixState.listening:
      case SentrixState.speaking:
        // Clignement : les arcs s'aplatissent brièvement vers t ≈ 0.9.
        final blink = state == SentrixState.idle
            ? (1 - math.exp(-math.pow((t - 0.9) / 0.012, 2).toDouble()))
            : 1.0;
        final arc = Rect.fromCenter(
          center: c.translate(0, eyeW * 0.15),
          width: eyeW,
          height: eyeW * 0.85 * math.max(blink, 0.08),
        );
        for (final p in [glow, core]) {
          canvas.drawArc(arc, math.pi * 1.08, math.pi * 0.84, false, p);
        }
      case SentrixState.thinking:
        // Balayage gauche-droite.
        final dx = math.sin(t * math.pi * 6) * eyeW * 0.28;
        final r = eyeW * 0.16;
        final fill = Paint()..color = color;
        canvas.drawCircle(
          c.translate(dx, 0),
          r * 1.8,
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.02),
        );
        canvas.drawCircle(c.translate(dx, 0), r, fill);
      case SentrixState.notification:
        final r = eyeW * 0.36;
        for (final p in [glow, core]) {
          canvas.drawCircle(c, r, p);
        }
      case SentrixState.error:
        final d = eyeW * 0.3;
        for (final p in [glow, core]) {
          canvas.drawLine(c.translate(-d, -d), c.translate(d, d), p);
          canvas.drawLine(c.translate(d, -d), c.translate(-d, d), p);
        }
    }
  }

  void _paintVoiceWave(Canvas canvas, Offset c, double width, double w) {
    final paint = Paint()
      ..color = VrColors.cyanBright
      ..strokeWidth = w * 0.012
      ..strokeCap = StrokeCap.round;
    const bars = 9;
    for (var i = 0; i < bars; i++) {
      final x = c.dx - width / 2 + width * i / (bars - 1);
      final env = math.sin(math.pi * i / (bars - 1));
      final amp = (0.25 + 0.75 * (0.5 + 0.5 * math.sin(t * math.pi * 16 + i * 1.7))) * env;
      final half = w * 0.05 * amp + w * 0.004;
      canvas.drawLine(Offset(x, c.dy - half), Offset(x, c.dy + half), paint);
    }
  }

  @override
  bool shouldRepaint(SentrixPainter old) => old.t != t || old.state != state;
}

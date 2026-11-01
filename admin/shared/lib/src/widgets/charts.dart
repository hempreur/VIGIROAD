import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';

class ChartSeries {
  const ChartSeries(this.name, this.values, {required this.color, this.area = true});
  final String name;

  /// Une valeur par point de l'axe X (null = mesure absente).
  final List<double?> values;
  final Color color;
  final bool area;
}

/// Courbes interactives (survol : repère et valeurs du point).
class VrLineChart extends StatefulWidget {
  const VrLineChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 220,
    this.yFormat,
    this.minY,
    this.maxY,
    this.bars = false,
  });

  final List<String> labels;
  final List<ChartSeries> series;
  final double height;
  final String Function(double v)? yFormat;
  final double? minY;
  final double? maxY;

  /// Histogramme (barres groupées) au lieu de courbes.
  final bool bars;

  @override
  State<VrLineChart> createState() => _VrLineChartState();
}

class _VrLineChartState extends State<VrLineChart> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final n = widget.labels.length;
    if (n == 0 || widget.series.isEmpty) {
      return SizedBox(height: widget.height, child: Center(child: Text('Aucune donnée', style: VrText.caption)));
    }
    final fmt = widget.yFormat ?? (v) => Fmt.number(v, digits: v.abs() < 10 && v != v.roundToDouble() ? 1 : 0);
    final all = [for (final s in widget.series) ...s.values.whereType<double>()];
    var lo = widget.minY ?? (all.isEmpty ? 0 : math.min(0, all.reduce(math.min)));
    var hi = widget.maxY ?? (all.isEmpty ? 1 : all.reduce(math.max));
    if (hi <= lo) hi = lo + 1;
    if (widget.maxY == null) hi = _nice(hi);
    final scale = _Scale(lo, hi);
    lo = scale.lo;
    hi = scale.hi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          children: [
            for (final s in widget.series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 6),
                  Text(s.name, style: VrText.caption),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, c) {
              const left = 54.0, bottom = 22.0;
              final w = c.maxWidth - left;
              int indexAt(double x) => n == 1 ? 0 : (((x - left) / w) * (widget.bars ? n : n - 1) - (widget.bars ? 0.5 : 0)).round().clamp(0, n - 1);
              return MouseRegion(
                onHover: (e) => setState(() => _hover = e.localPosition.dx < left ? null : indexAt(e.localPosition.dx)),
                onExit: (_) => setState(() => _hover = null),
                child: Stack(
                  children: [
                    CustomPaint(
                      size: Size(c.maxWidth, widget.height),
                      painter: _ChartPainter(
                        labels: widget.labels,
                        series: widget.series,
                        lo: lo,
                        hi: hi,
                        hover: _hover,
                        fmt: fmt,
                        left: left,
                        bottom: bottom,
                        bars: widget.bars,
                      ),
                    ),
                    if (_hover != null) _tooltip(_hover!, c.maxWidth, left, fmt),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tooltip(int i, double width, double left, String Function(double) fmt) {
    final n = widget.labels.length;
    final w = width - left;
    final x = left + (widget.bars ? (i + 0.5) / n * w : (n == 1 ? w / 2 : i / (n - 1) * w));
    const tw = 190.0;
    final dx = (x + 14 + tw > width) ? x - tw - 14 : x + 14;
    return Positioned(
      left: dx,
      top: 4,
      child: IgnorePointer(
        child: Container(
          width: tw,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: VrColors.background.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: VrColors.border(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.labels[i], style: VrText.label.copyWith(color: VrColors.textPrimary)),
              const SizedBox(height: 4),
              for (final s in widget.series)
                Row(
                  children: [
                    Container(width: 8, height: 8, color: s.color),
                    const SizedBox(width: 6),
                    Expanded(child: Text(s.name, style: VrText.caption, overflow: TextOverflow.ellipsis)),
                    Text(
                      i < s.values.length && s.values[i] != null ? fmt(s.values[i]!) : '—',
                      style: VrText.caption.copyWith(color: VrColors.textPrimary),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static double _nice(double v) {
    if (v <= 0) return 1;
    final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]) {
      if (v <= m * p) return m * p;
    }
    return 10 * p;
  }
}

class _Scale {
  _Scale(this.lo, this.hi);
  final double lo;
  final double hi;
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.labels,
    required this.series,
    required this.lo,
    required this.hi,
    required this.hover,
    required this.fmt,
    required this.left,
    required this.bottom,
    required this.bars,
  });

  final List<String> labels;
  final List<ChartSeries> series;
  final double lo, hi, left, bottom;
  final int? hover;
  final String Function(double) fmt;
  final bool bars;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - left, h = size.height - bottom;
    final n = labels.length;
    double y(double v) => h - (v - lo) / (hi - lo) * h;
    double x(int i) => left + (bars ? (i + 0.5) / n * w : (n == 1 ? w / 2 : i / (n - 1) * w));

    final grid = Paint()
      ..color = VrColors.line
      ..strokeWidth = 1;
    for (var k = 0; k <= 4; k++) {
      final v = lo + (hi - lo) * k / 4;
      final yy = y(v);
      canvas.drawLine(Offset(left, yy), Offset(size.width, yy), grid);
      _text(canvas, fmt(v), Offset(left - 8, yy), align: TextAlign.right);
    }
    final step = math.max(1, (n / 8).ceil());
    for (var i = 0; i < n; i += step) {
      _text(canvas, labels[i], Offset(x(i), h + 12), align: TextAlign.center);
    }

    if (bars) {
      final group = w / n * 0.72;
      final bw = group / series.length;
      for (var s = 0; s < series.length; s++) {
        final paint = Paint()..color = series[s].color;
        for (var i = 0; i < n && i < series[s].values.length; i++) {
          final v = series[s].values[i];
          if (v == null) continue;
          final x0 = x(i) - group / 2 + s * bw;
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTRB(x0 + 1, y(v), x0 + bw - 1, y(math.max(lo, 0))),
              topLeft: const Radius.circular(3),
              topRight: const Radius.circular(3),
            ),
            paint..color = series[s].color.withValues(alpha: hover == null || hover == i ? 0.95 : 0.55),
          );
        }
      }
    } else {
      for (final s in series) {
        final path = Path();
        final area = Path();
        var started = false;
        int? first, last;
        for (var i = 0; i < n && i < s.values.length; i++) {
          final v = s.values[i];
          if (v == null) continue;
          final p = Offset(x(i), y(v));
          if (!started) {
            path.moveTo(p.dx, p.dy);
            area.moveTo(p.dx, h);
            area.lineTo(p.dx, p.dy);
            started = true;
            first = i;
          } else {
            path.lineTo(p.dx, p.dy);
            area.lineTo(p.dx, p.dy);
          }
          last = i;
        }
        if (!started) continue;
        if (s.area && first != null && last != null) {
          area
            ..lineTo(x(last), h)
            ..close();
          canvas.drawPath(
            area,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [s.color.withValues(alpha: 0.28), s.color.withValues(alpha: 0.0)],
              ).createShader(Rect.fromLTWH(left, 0, w, h)),
          );
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = s.color.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    final hv = hover;
    if (hv != null) {
      canvas.drawLine(Offset(x(hv), 0), Offset(x(hv), h), Paint()..color = VrColors.cyan.withValues(alpha: 0.5));
      if (!bars) {
        for (final s in series) {
          if (hv < s.values.length && s.values[hv] != null) {
            canvas.drawCircle(Offset(x(hv), y(s.values[hv]!)), 4.5, Paint()..color = s.color);
            canvas.drawCircle(Offset(x(hv), y(s.values[hv]!)), 2, Paint()..color = VrColors.background);
          }
        }
      }
    }
  }

  void _text(Canvas canvas, String t, Offset at, {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: VrText.caption.copyWith(fontSize: 10.5)),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: 120);
    final dx = switch (align) {
      TextAlign.right => at.dx - tp.width,
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}

/// Jauge circulaire (CPU, RAM, disque…).
class Gauge extends StatelessWidget {
  const Gauge({super.key, required this.label, required this.percent, required this.value, this.sub, this.size = 132});

  final String label;

  /// 0–100, ou null si la mesure est indisponible.
  final double? percent;
  final String value;
  final String? sub;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = percent;
    final color = p == null
        ? VrColors.textMuted
        : p >= 90
        ? VrColors.critical
        : p >= 75
        ? VrColors.warning
        : VrColors.cyan;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _GaugePainter((p ?? 0) / 100, color),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value, style: VrText.metric.copyWith(fontSize: size * 0.2, color: color == VrColors.textMuted ? VrColors.textMuted : VrColors.textPrimary)),
                  if (sub != null) Text(sub!, style: VrText.caption.copyWith(fontSize: 10.5), textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label.toUpperCase(), style: VrText.label.copyWith(letterSpacing: 1)),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.fraction, this.color);
  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 8;
    final c = size.center(Offset.zero);
    const start = math.pi * 0.75, sweep = math.pi * 1.5;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..color = VrColors.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );
    final f = fraction.clamp(0.0, 1.0);
    if (f > 0) {
      canvas.drawArc(
        rect,
        start,
        sweep * f,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawArc(
        rect,
        start,
        sweep * f,
        false,
        Paint()
          ..shader = SweepGradient(
            startAngle: start,
            endAngle: start + sweep,
            colors: [VrColors.electricBright, color],
            transform: const GradientRotation(0),
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.fraction != fraction || old.color != color;
}

/// Barre de progression horizontale (cœurs du processeur, quotas).
class MeterBar extends StatelessWidget {
  const MeterBar({super.key, required this.label, required this.percent, this.trailing});
  final String label;
  final double percent;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final color = percent >= 90 ? VrColors.critical : (percent >= 75 ? VrColors.warning : VrColors.cyan);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(label, style: VrText.caption)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (percent / 100).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: VrColors.line,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          SizedBox(width: 70, child: Text(trailing ?? Fmt.percent(percent), style: VrText.caption, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

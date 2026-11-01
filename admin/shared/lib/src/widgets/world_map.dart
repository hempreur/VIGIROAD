import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../theme.dart';

/// Pays (Natural Earth 1:110m, domaine public) : nom, centre, contours.
class WorldData {
  WorldData(this.countries);
  final Map<String, ({String name, Offset center, List<List<Offset>> rings})> countries;

  static WorldData? _cache;

  static Future<WorldData> load() async {
    if (_cache != null) return _cache!;
    final raw = jsonDecode(await rootBundle.loadString('packages/vigiroad_admin_core/assets/world_110m.json')) as Map<String, dynamic>;
    final out = <String, ({String name, Offset center, List<List<Offset>> rings})>{};
    for (final e in raw.entries) {
      final v = e.value as Map<String, dynamic>;
      final c = (v['c'] as List<dynamic>).cast<num>();
      out[e.key] = (
        name: v['n'] as String,
        center: Offset(c[0].toDouble(), c[1].toDouble()),
        rings: [
          for (final r in (v['r'] as List<dynamic>))
            [
              for (var i = 0; i + 1 < (r as List<dynamic>).length; i += 2)
                Offset((r[i] as num).toDouble(), (r[i + 1] as num).toDouble()),
            ],
        ],
      );
    }
    return _cache = WorldData(out);
  }
}

/// Carte mondiale statistique : pays colorés selon [values], points
/// approximatifs ([points] : lat, lng, poids), survol avec info-bulle.
class WorldMap extends StatefulWidget {
  const WorldMap({super.key, required this.values, this.points = const [], this.unit = 'utilisateurs', this.height = 380});

  final Map<String, num> values;
  final List<({double lat, double lng, num weight})> points;
  final String unit;
  final double height;

  @override
  State<WorldMap> createState() => _WorldMapState();
}

class _WorldMapState extends State<WorldMap> {
  WorldData? _world;
  String? _hover;
  Offset? _mouse;

  @override
  void initState() {
    super.initState();
    WorldData.load().then((w) {
      if (mounted) setState(() => _world = w);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = _world;
    if (w == null) return SizedBox(height: widget.height, child: const Center(child: CircularProgressIndicator()));
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, c) {
          final proj = _Projection(Size(c.maxWidth, widget.height));
          return MouseRegion(
            onHover: (e) => setState(() {
              _mouse = e.localPosition;
              _hover = _hit(w, proj.unproject(e.localPosition));
            }),
            onExit: (_) => setState(() => _hover = null),
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(c.maxWidth, widget.height),
                  painter: _MapPainter(w, widget.values, widget.points, proj, _hover),
                ),
                if (_hover != null && _mouse != null)
                  Positioned(
                    left: (_mouse!.dx + 14).clamp(0.0, c.maxWidth - 220),
                    top: (_mouse!.dy + 10).clamp(0.0, widget.height - 60),
                    child: IgnorePointer(
                      child: Container(
                        width: 210,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: VrColors.background.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: VrColors.border(0.5)),
                        ),
                        child: Text(
                          '${Fmt.flag(_hover)} ${w.countries[_hover]?.name ?? _hover}\n'
                          '${Fmt.number(widget.values[_hover] ?? 0)} ${widget.unit}',
                          style: VrText.caption.copyWith(color: VrColors.textPrimary),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Pays sous le pointeur (test point-dans-polygone).
  String? _hit(WorldData w, Offset lngLat) {
    for (final e in w.countries.entries) {
      for (final ring in e.value.rings) {
        if (_inside(ring, lngLat)) return e.key;
      }
    }
    return null;
  }

  static bool _inside(List<Offset> ring, Offset p) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) && p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }
}

/// Projection équirectangulaire (−180..180, −58..84) ajustée à la zone.
class _Projection {
  _Projection(Size size) {
    const lngSpan = 360.0, latSpan = 142.0;
    scale = math.min(size.width / lngSpan, size.height / latSpan);
    dx = (size.width - lngSpan * scale) / 2;
    dy = (size.height - latSpan * scale) / 2;
  }

  late final double scale, dx, dy;

  Offset project(Offset lngLat) => Offset(dx + (lngLat.dx + 180) * scale, dy + (84 - lngLat.dy) * scale);
  Offset unproject(Offset p) => Offset((p.dx - dx) / scale - 180, 84 - (p.dy - dy) / scale);
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.world, this.values, this.points, this.proj, this.hover);
  final WorldData world;
  final Map<String, num> values;
  final List<({double lat, double lng, num weight})> points;
  final _Projection proj;
  final String? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = values.values.isEmpty ? 1 : values.values.reduce(math.max).toDouble().clamp(1, double.infinity);
    final stroke = Paint()
      ..color = VrColors.cyan.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (final e in world.countries.entries) {
      final v = values[e.key]?.toDouble() ?? 0;
      final t = v <= 0 ? 0.0 : (0.25 + 0.75 * math.sqrt(v / maxV));
      final fill = Paint()
        ..color = v <= 0
            ? VrColors.panelLight
            : Color.lerp(VrColors.electric, VrColors.cyanBright, t)!.withValues(alpha: 0.35 + 0.6 * t);
      for (final ring in e.value.rings) {
        final path = Path()..addPolygon([for (final p in ring) proj.project(p)], true);
        canvas.drawPath(path, fill);
        canvas.drawPath(path, e.key == hover ? (Paint()
          ..color = VrColors.cyanBright
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6) : stroke);
      }
    }
    final maxW = points.isEmpty ? 1.0 : points.map((p) => p.weight.toDouble()).reduce(math.max);
    for (final p in points) {
      final c = proj.project(Offset(p.lng, p.lat));
      final r = 2.5 + 7 * math.sqrt(p.weight / maxW);
      canvas.drawCircle(c, r + 4, Paint()
        ..color = VrColors.cyan.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(c, r, Paint()..color = VrColors.cyanBright.withValues(alpha: 0.85));
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.hover != hover || old.values != values || old.points != points;
}

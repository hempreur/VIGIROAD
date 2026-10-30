import 'dart:ui' show Color;

import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../../../core/theme/vr_colors.dart';

/// Libellés français et couleurs des perturbations (carte, légende, voix).
abstract final class TrafficLabels {
  static String type(TrafficEventType t) => switch (t) {
    TrafficEventType.accident => 'Accident',
    TrafficEventType.congestion => 'Bouchon',
    TrafficEventType.roadworks => 'Travaux',
    TrafficEventType.closure => 'Route fermée',
    TrafficEventType.obstruction => 'Obstacle sur la chaussée',
    TrafficEventType.weather => 'Conditions météo difficiles',
    TrafficEventType.restriction => 'Circulation restreinte',
    TrafficEventType.event => 'Événement',
    TrafficEventType.other => 'Perturbation',
  };

  static String severity(Severity s) => switch (s) {
    Severity.critical => 'très grave',
    Severity.high => 'importante',
    Severity.medium => 'modérée',
    Severity.low => 'faible',
    Severity.unknown => 'non précisée',
  };

  /// Gravité → couleur (palette du trafic de la référence).
  static Color color(Severity s) => switch (s) {
    Severity.critical || Severity.high => VrColors.trafficJam,
    Severity.medium => VrColors.trafficSlow,
    Severity.low => const Color(0xFFF2D544),
    Severity.unknown => VrColors.textSecondary,
  };

  static String hex(Color c) {
    final v = c.toARGB32() & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  /// Distance parlée : « 400 mètres », « 2,5 kilomètres », « 12 kilomètres ».
  static String spokenDistance(double m) {
    if (m < 1000) return '${((m / 100).round() * 100).clamp(100, 900)} mètres';
    final km = m / 1000;
    if (km < 10) {
      final r = (km * 2).round() / 2;
      return r == r.roundToDouble() ? '${r.round()} kilomètres' : '${r.toStringAsFixed(1).replaceAll('.', ',')} kilomètres';
    }
    return '${km.round()} kilomètres';
  }

  /// « Accident sur la N20 » / « Travaux sur l'A6 » / « Bouchon ».
  static String headline(TrafficEvent e) {
    final road = e.road;
    if (road == null || road.isEmpty) return type(e.type);
    final article = RegExp(r'^[AEIOUH]', caseSensitive: false).hasMatch(road) ? "l'" : 'la ';
    return '${type(e.type)} sur $article$road';
  }

  /// Annonce de SENTRIX pour une perturbation à [distanceM] devant.
  static String announcement(TrafficEvent e, double distanceM) {
    final grave = e.severity == Severity.high || e.severity == Severity.critical;
    final h = headline(e);
    final text = grave ? 'Attention, ${h[0].toLowerCase()}${h.substring(1)}' : h;
    return '$text dans ${spokenDistance(distanceM)}.';
  }
}

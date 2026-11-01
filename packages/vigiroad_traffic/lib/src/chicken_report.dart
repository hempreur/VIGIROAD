import 'dart:math' as math;

import 'geo.dart';
import 'traffic_event.dart';

/// Sens signalé par le conducteur au moment du signalement.
enum ReportSide {
  /// Sur sa propre route, dans son sens de circulation.
  mine,

  /// Sur la route d'en face (sens opposé).
  opposite;

  static ReportSide? tryParse(Object? v) => switch (v) {
    'mine' => ReportSide.mine,
    'opposite' => ReportSide.opposite,
    _ => null,
  };
}

/// Différence d'angle (0–180°) entre deux caps.
double headingDelta(double a, double b) {
  final d = ((a - b) % 360 + 360) % 360;
  return d > 180 ? 360 - d : d;
}

/// Cap (0–360°) de [from] vers [to].
double bearing(LatLng from, LatLng to) {
  double rad(double d) => d * math.pi / 180;
  final y = math.sin(rad(to.lng - from.lng)) * math.cos(rad(to.lat));
  final x = math.cos(rad(from.lat)) * math.sin(rad(to.lat)) -
      math.sin(rad(from.lat)) * math.cos(rad(to.lat)) * math.cos(rad(to.lng - from.lng));
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Signalement « Chicken » partagé entre conducteurs, visible 2 h.
///
/// [heading] est le sens de circulation **concerné** (cap en degrés) : celui
/// du conducteur pour « ma route », l'opposé pour « route en face ». Aucun
/// identifiant de personne ou d'appareil n'est conservé.
class ChickenReport {
  const ChickenReport({
    required this.id,
    required this.position,
    required this.heading,
    required this.side,
    required this.createdAt,
    required this.expiresAt,
    this.confirmations = 1,
  });

  /// Durée de vie d'un signalement.
  static const lifetime = Duration(hours: 2);

  final String id;
  final LatLng position;

  /// Sens de circulation concerné (0–360°), null si inconnu (à l'arrêt).
  final double? heading;
  final ReportSide side;
  final DateTime createdAt;

  /// Fin d'affichage : 2 h après le dernier signalement au même endroit.
  final DateTime expiresAt;

  /// Nombre de conducteurs ayant signalé le même endroit.
  final int confirmations;

  bool activeAt(DateTime now) => now.isBefore(expiresAt);

  /// Le signalement concerne-t-il un conducteur qui roule au cap [myHeading] ?
  /// (même sens à ±60° ; sens inconnu : oui).
  bool concerns(double? myHeading) {
    final h = heading;
    if (h == null || myHeading == null) return true;
    return headingDelta(h, myHeading) <= 60;
  }

  ChickenReport copyWith({DateTime? expiresAt, int? confirmations}) => ChickenReport(
    id: id,
    position: position,
    heading: heading,
    side: side,
    createdAt: createdAt,
    expiresAt: expiresAt ?? this.expiresAt,
    confirmations: confirmations ?? this.confirmations,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'position': position.toJson(),
    'heading': heading == null ? null : (heading! * 10).round() / 10,
    'side': side.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'confirmations': confirmations,
  };

  static ChickenReport fromJson(Map<String, dynamic> j) => ChickenReport(
    id: j['id'] as String,
    position: LatLng.fromJson(j['position'] as List<dynamic>),
    heading: (j['heading'] as num?)?.toDouble(),
    side: ReportSide.tryParse(j['side']) ?? ReportSide.mine,
    createdAt: DateTime.parse(j['createdAt'] as String),
    expiresAt: DateTime.parse(j['expiresAt'] as String),
    confirmations: (j['confirmations'] as num?)?.toInt() ?? 1,
  );
}

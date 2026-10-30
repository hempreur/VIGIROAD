/// Point géographique (WGS84), indépendant de tout SDK cartographique.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}

/// Position mesurée par le GPS du téléphone.
class GeoFix {
  const GeoFix({
    required this.point,
    required this.timestamp,
    this.speedMps,
    this.headingDeg,
    this.accuracyM,
  });

  final GeoPoint point;
  final DateTime timestamp;

  /// Vitesse en m/s, `null` si le capteur ne la fournit pas.
  final double? speedMps;

  /// Cap en degrés depuis le nord, `null` si inconnu.
  final double? headingDeg;

  /// Précision horizontale estimée, en mètres.
  final double? accuracyM;

  /// Vitesse arrondie en km/h ; 0 sous 1 km/h pour éviter le bruit à l'arrêt.
  int? get speedKmh {
    final s = speedMps;
    if (s == null || s.isNaN || s < 0) return null;
    final kmh = s * 3.6;
    return kmh < 1 ? 0 : kmh.round();
  }

  /// Le cap n'est fiable qu'en mouvement (≥ 5 km/h environ).
  bool get headingReliable =>
      headingDeg != null && !headingDeg!.isNaN && (speedMps ?? 0) >= 1.4;
}

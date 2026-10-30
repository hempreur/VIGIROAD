import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import 'maxspeed.dart';

/// Voie routière OpenStreetMap et sa limitation de vitesse (si connue).
class OsmWay {
  const OsmWay({required this.id, required this.geometry, this.forward, this.backward});

  /// Lecture d'un élément `way` d'une réponse Overpass (`out tags geom`).
  static OsmWay? fromOverpass(Map<String, dynamic> j) {
    if (j['type'] != 'way') return null;
    final tags = (j['tags'] as Map<String, dynamic>? ?? const {}).cast<String, Object?>();
    final geom = [
      for (final p in j['geometry'] as List<dynamic>? ?? const [])
        if (p is Map<String, dynamic> && p['lat'] is num && p['lon'] is num)
          LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()),
    ];
    if (geom.length < 2) return null;
    final both = parseMaxspeed(tags['maxspeed'] as String?);
    var fwd = parseMaxspeed(tags['maxspeed:forward'] as String?) ?? both;
    var bwd = parseMaxspeed(tags['maxspeed:backward'] as String?) ?? both;
    // Sens unique : la limitation ne vaut que dans le sens de circulation.
    final oneway = tags['oneway'] as String?;
    final motorway = tags['highway'] == 'motorway' || tags['junction'] == 'roundabout';
    if (oneway == 'yes' || oneway == '1' || oneway == 'true' || (oneway == null && motorway)) bwd = null;
    if (oneway == '-1') {
      bwd = fwd;
      fwd = null;
    }
    // Voie sans limitation connue conservée : elle évite d'attribuer à la
    // route suivie la limitation d'une voie parallèle voisine.
    return OsmWay(id: (j['id'] as num).toInt(), geometry: geom, forward: fwd, backward: bwd);
  }

  final int id;
  final List<LatLng> geometry;

  /// Limitation dans le sens de numérisation de la voie, et dans l'autre sens.
  final int? forward;
  final int? backward;

  BBox get bbox => BBox.around(geometry);

  Map<String, Object?> toJson() => {
    'id': id,
    'geometry': [for (final p in geometry) p.toJson()],
    'forward': forward,
    'backward': backward,
  };
}

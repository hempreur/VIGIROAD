import 'route.dart';

/// Formulation française des manœuvres (OSRM ne fournit pas de texte localisé).
abstract final class Instructions {
  static String _dir(ManeuverDirection d) => switch (d) {
    ManeuverDirection.uturn => 'faites demi-tour',
    ManeuverDirection.sharpRight => 'tournez franchement à droite',
    ManeuverDirection.right => 'tournez à droite',
    ManeuverDirection.slightRight => 'serrez à droite',
    ManeuverDirection.straight => 'continuez tout droit',
    ManeuverDirection.slightLeft => 'serrez à gauche',
    ManeuverDirection.left => 'tournez à gauche',
    ManeuverDirection.sharpLeft => 'tournez franchement à gauche',
    ManeuverDirection.none => 'continuez',
  };

  static String _side(ManeuverDirection d) => switch (d) {
    ManeuverDirection.slightLeft || ManeuverDirection.left || ManeuverDirection.sharpLeft => 'à gauche',
    ManeuverDirection.slightRight || ManeuverDirection.right || ManeuverDirection.sharpRight => 'à droite',
    _ => '',
  };

  static String _ordinal(int n) => switch (n) {
    1 => 'première',
    2 => 'deuxième',
    3 => 'troisième',
    4 => 'quatrième',
    5 => 'cinquième',
    _ => '${n}e',
  };

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Désignation de la voie : « D120 », « Rue de Rivoli (D120) ».
  static String road(RouteStep s) {
    if (s.roadName.isNotEmpty && s.roadRef.isNotEmpty) return '${s.roadName} (${s.roadRef})';
    return s.roadName.isNotEmpty ? s.roadName : s.roadRef;
  }

  /// Consigne principale : « Prendre la sortie D120 », « Tournez à droite ».
  static String headline(RouteStep s) {
    final r = road(s);
    final onto = r.isEmpty ? '' : ' sur $r';
    final text = switch (s.kind) {
      ManeuverKind.depart => r.isEmpty ? 'Partez' : 'Partez sur $r',
      ManeuverKind.arrive => 'Vous êtes arrivé',
      ManeuverKind.offRamp => s.exitNumber != null
          ? 'Prenez la sortie ${s.exitNumber}'
          : (r.isEmpty ? 'Prenez la sortie ${_side(s.direction)}'.trim() : 'Prenez la sortie $r'),
      ManeuverKind.onRamp => 'Prenez la bretelle${r.isEmpty ? ' ${_side(s.direction)}'.trimRight() : ' $r'}',
      ManeuverKind.merge => 'Insérez-vous$onto',
      ManeuverKind.fork => 'Restez ${_side(s.direction).isEmpty ? 'sur la voie' : _side(s.direction)}$onto',
      ManeuverKind.roundabout => s.roundaboutExit != null
          ? 'Au rond-point, prenez la ${_ordinal(s.roundaboutExit!)} sortie'
          : 'Entrez dans le rond-point',
      ManeuverKind.exitRoundabout => 'Sortez du rond-point$onto',
      ManeuverKind.endOfRoad => '${_capitalize(_dir(s.direction))} au bout de la route',
      ManeuverKind.continueStraight || ManeuverKind.newName => 'Continuez$onto',
      ManeuverKind.turn || ManeuverKind.notification => '${_capitalize(_dir(s.direction))}$onto',
    };
    return text;
  }

  /// Précision affichée sous la consigne : « vers Centre-ville ».
  static String? towards(RouteStep s) => s.destinations.isEmpty ? null : 'vers ${s.destinations}';

  /// Phrase vocale : « Dans 300 mètres, tournez à droite sur Rue de Rivoli ».
  static String spoken(RouteStep s, {required double inMeters}) {
    final h = headline(s);
    final lower = h[0].toLowerCase() + h.substring(1);
    if (s.kind == ManeuverKind.arrive) {
      return inMeters < 40 ? 'Vous êtes arrivé à destination.' : 'Dans ${_spokenDistance(inMeters)}, vous serez arrivé.';
    }
    if (inMeters < 40) return '$h.';
    final dest = towards(s);
    return 'Dans ${_spokenDistance(inMeters)}, $lower${dest == null ? '' : ', $dest'}.';
  }

  static String _spokenDistance(double m) {
    if (m >= 950) {
      final km = (m / 100).round() / 10;
      final txt = km == km.roundToDouble() ? km.toStringAsFixed(0) : km.toStringAsFixed(1).replaceAll('.', ',');
      return '$txt kilomètre${km >= 2 ? 's' : ''}';
    }
    final step = m >= 200 ? 50 : 10;
    return '${(m / step).round() * step} mètres';
  }
}

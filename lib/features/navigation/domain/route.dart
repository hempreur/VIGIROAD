import 'geo_fix.dart';

/// Type de manœuvre (vocabulaire OSRM, indépendant du fournisseur).
enum ManeuverKind {
  depart,
  arrive,
  turn,
  continueStraight,
  merge,
  onRamp,
  offRamp,
  fork,
  endOfRoad,
  roundabout,
  exitRoundabout,
  newName,
  notification,
}

/// Direction de la manœuvre.
enum ManeuverDirection { uturn, sharpRight, right, slightRight, straight, slightLeft, left, sharpLeft, none }

/// Étape d'un itinéraire : une manœuvre puis un tronçon.
class RouteStep {
  const RouteStep({
    required this.kind,
    required this.direction,
    required this.location,
    required this.distanceM,
    required this.durationS,
    this.roadName = '',
    this.roadRef = '',
    this.destinations = '',
    this.exitNumber,
    this.roundaboutExit,
  });

  final ManeuverKind kind;
  final ManeuverDirection direction;

  /// Point où la manœuvre a lieu.
  final GeoPoint location;

  /// Longueur et durée du tronçon qui suit la manœuvre.
  final double distanceM;
  final double durationS;

  /// Nom de la voie empruntée après la manœuvre (ex. « Rue de Rivoli »).
  final String roadName;

  /// Numéro de route (ex. « D120 », « A6 »).
  final String roadRef;

  /// Panneau de direction (ex. « Centre-ville »).
  final String destinations;

  /// Numéro de sortie (bretelles).
  final String? exitNumber;

  /// Rang de sortie dans un rond-point.
  final int? roundaboutExit;
}

/// Itinéraire complet.
class NavRoute {
  const NavRoute({
    required this.geometry,
    required this.distanceM,
    required this.durationS,
    required this.steps,
    this.segmentSpeedLimits = const [],
  });

  /// Tracé, du départ à l'arrivée.
  final List<GeoPoint> geometry;
  final double distanceM;
  final double durationS;
  final List<RouteStep> steps;

  /// Limitation de vitesse par segment de [geometry] (km/h), `null` si
  /// inconnue. Longueur = geometry.length - 1, ou vide si non fournie.
  final List<int?> segmentSpeedLimits;
}

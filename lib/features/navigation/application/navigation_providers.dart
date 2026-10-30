import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/location_source.dart';
import '../domain/geo_fix.dart';
import '../presentation/widgets/map_view.dart';

final locationSourceProvider = Provider<LocationSource>(
  (ref) => const GeolocatorLocationSource(),
);

/// Localisation en arrière-plan demandée (guidage en cours et réglage actif).
final backgroundLocationProvider = NotifierProvider<BackgroundLocationController, bool>(
  BackgroundLocationController.new,
);

class BackgroundLocationController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}

/// Flux de positions GPS en direct ; redémarré en mode arrière-plan
/// pendant le guidage.
final positionProvider = StreamProvider<GeoFix>(
  (ref) => ref.watch(locationSourceProvider).watch(background: ref.watch(backgroundLocationProvider)),
);

/// Destination choisie par l'utilisateur (calcul d'itinéraire en phase 3).
class Destination {
  const Destination({required this.label, required this.detail, required this.point});
  final String label;
  final String detail;
  final GeoPoint point;
}

final destinationProvider = NotifierProvider<DestinationController, Destination?>(
  DestinationController.new,
);

class DestinationController extends Notifier<Destination?> {
  @override
  Destination? build() => null;

  void set(Destination d) => state = d;
  void clear() => state = null;
}

/// Fabrique de la vue carte. Surchargée dans les tests, où la vue native
/// MapLibre ne peut pas s'afficher.
typedef MapViewBuilder = Widget Function(MapViewArgs args);

final mapViewBuilderProvider = Provider<MapViewBuilder>(
  (ref) => (args) => VrMapView(args: args),
);

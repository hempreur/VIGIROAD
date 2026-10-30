import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/location_source.dart';
import '../domain/geo_fix.dart';
import '../presentation/widgets/map_view.dart';

final locationSourceProvider = Provider<LocationSource>(
  (ref) => const GeolocatorLocationSource(),
);

/// Flux de positions GPS en direct.
final positionProvider = StreamProvider<GeoFix>(
  (ref) => ref.watch(locationSourceProvider).watch(),
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

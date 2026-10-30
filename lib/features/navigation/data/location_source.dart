import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/geo_fix.dart';

/// Causes d'indisponibilité de la position.
enum LocationIssue { serviceDisabled, permissionDenied }

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.issue);
  final LocationIssue issue;

  @override
  String toString() => switch (issue) {
    LocationIssue.serviceDisabled => 'La localisation du téléphone est désactivée.',
    LocationIssue.permissionDenied => 'L\'accès à la position n\'est pas autorisé.',
  };
}

/// Source de positions GPS. Implémentation réelle : [GeolocatorLocationSource].
abstract interface class LocationSource {
  Stream<GeoFix> watch();
}

class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  @override
  Stream<GeoFix> watch() async* {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable(LocationIssue.serviceDisabled);
    }
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationUnavailable(LocationIssue.permissionDenied);
    }

    final LocationSettings settings = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
        intervalDuration: const Duration(seconds: 1),
      ),
      TargetPlatform.iOS => AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 2,
        pauseLocationUpdatesAutomatically: false,
      ),
      _ => const LocationSettings(accuracy: LocationAccuracy.best),
    };

    yield* Geolocator.getPositionStream(locationSettings: settings).map(
      (p) => GeoFix(
        point: GeoPoint(p.latitude, p.longitude),
        timestamp: p.timestamp,
        speedMps: p.speed >= 0 ? p.speed : null,
        headingDeg: p.heading >= 0 ? p.heading : null,
        accuracyM: p.accuracy,
      ),
    );
  }
}

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
  /// [background] : la localisation doit continuer application masquée ou
  /// écran éteint (guidage en cours).
  Stream<GeoFix> watch({bool background = false});
}

/// Réglages de localisation selon la plateforme et le mode.
///
/// En arrière-plan, Android utilise un service de premier plan (notification
/// « Guidage en cours », obligatoire depuis Android 8) et iOS le mode
/// « location » en arrière-plan (indicateur bleu dans la barre d'état).
LocationSettings buildLocationSettings(TargetPlatform platform, {required bool background}) =>
    switch (platform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: background
            ? const ForegroundNotificationConfig(
                notificationTitle: 'VIGIROAD',
                notificationText: 'Guidage en cours',
                notificationChannelName: 'Guidage',
                enableWakeLock: true,
                setOngoing: true,
              )
            : null,
      ),
      TargetPlatform.iOS => AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 2,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: background,
        showBackgroundLocationIndicator: background,
      ),
      _ => const LocationSettings(accuracy: LocationAccuracy.best),
    };

class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  @override
  Stream<GeoFix> watch({bool background = false}) async* {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable(LocationIssue.serviceDisabled);
    }
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationUnavailable(LocationIssue.permissionDenied);
    }

    final settings = buildLocationSettings(defaultTargetPlatform, background: background);
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

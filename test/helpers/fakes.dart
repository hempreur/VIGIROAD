import 'dart:async';

import 'package:camera/camera.dart' show CameraController;
import 'package:flutter/widgets.dart';
import 'package:vigiroad/core/permissions/permission_service.dart';
import 'package:vigiroad/core/theme/vr_colors.dart';
import 'package:vigiroad/features/navigation/data/location_source.dart';
import 'package:vigiroad/features/navigation/data/osrm_router.dart';
import 'package:vigiroad/features/navigation/data/speaker.dart';
import 'package:vigiroad/features/navigation/domain/route.dart';
import 'package:vigiroad/features/navigation/domain/geo_fix.dart';
import 'package:vigiroad/features/navigation/presentation/widgets/map_view.dart';
import 'package:vigiroad/features/plates/application/alert_service.dart';
import 'package:vigiroad/features/plates/data/plate_scanner.dart';
import 'package:vigiroad/features/plates/data/repositories.dart';
import 'package:vigiroad/features/plates/domain/watch_entry.dart';
import 'package:vigiroad/features/plates/domain/plate_format.dart';
import 'package:vigiroad/features/plates/domain/plate_voter.dart';
import 'package:vigiroad/features/search/data/photon_geocoder.dart';
import 'package:vigiroad/features/sentrix/data/speech_input.dart';
import 'package:vigiroad/features/settings/application/settings_controller.dart';
import 'package:vigiroad/features/settings/domain/app_settings.dart';

/// Service d'autorisations simulé, pour les tests uniquement.
class FakePermissionService implements PermissionService {
  FakePermissionService(this.statuses, {this.onRequest});

  final Map<AppCapability, CapabilityStatus> statuses;
  final CapabilityStatus Function(AppCapability)? onRequest;
  int settingsOpened = 0;

  static FakePermissionService allGranted() => FakePermissionService({
    for (final c in AppCapability.values) c: CapabilityStatus.granted,
  });

  static FakePermissionService allDenied() => FakePermissionService(
    {for (final c in AppCapability.values) c: CapabilityStatus.denied},
    onRequest: (_) => CapabilityStatus.granted,
  );

  @override
  Future<CapabilityStatus> status(AppCapability c) async => statuses[c] ?? CapabilityStatus.denied;

  @override
  Future<CapabilityStatus> request(AppCapability c) async {
    final s = onRequest?.call(c) ?? statuses[c] ?? CapabilityStatus.denied;
    statuses[c] = s;
    return s;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

/// Source GPS simulée : émet les positions qu'on lui pousse.
class FakeLocationSource implements LocationSource {
  FakeLocationSource([this.initial]);

  final GeoFix? initial;
  final _controller = StreamController<GeoFix>.broadcast();
  Object? error;

  void push(GeoFix fix) => _controller.add(fix);

  @override
  Stream<GeoFix> watch() async* {
    if (error != null) throw error!;
    if (initial != null) yield initial!;
    yield* _controller.stream;
  }
}

/// Position de test : Paris, 82 km/h vers le nord.
GeoFix testFix({double kmh = 82}) => GeoFix(
  point: const GeoPoint(48.8566, 2.3522),
  timestamp: DateTime(2026, 10, 30, 14, 27),
  speedMps: kmh / 3.6,
  headingDeg: 12,
  accuracyM: 4,
);

/// Géocodeur simulé.
class FakeGeocoder implements Geocoder {
  FakeGeocoder(this.results);
  final List<Place> results;
  final queries = <String>[];

  @override
  Future<List<Place>> search(String query, {GeoPoint? near}) async {
    queries.add(query);
    return results;
  }
}

/// Remplace la carte native (indisponible en test) par un fond sombre
/// quadrillé. Réservé aux tests et captures.
Widget fakeMapView(MapViewArgs args) => const _FakeMap();

class _FakeMap extends StatelessWidget {
  const _FakeMap();

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _GridPainter(), child: SizedBox.expand());
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0B141C));
    final road = Paint()
      ..color = VrColors.mapBase
      ..strokeWidth = 3;
    for (var x = 0.0; x < size.width; x += 46) {
      canvas.drawLine(Offset(x, 0), Offset(x + 60, size.height), road);
    }
    for (var y = 0.0; y < size.height; y += 58) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 30), road);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

/// Itinéraire synthétique : 1 km plein nord depuis Paris, virage à droite,
/// puis 500 m plein est jusqu'à l'arrivée. Limitation 50 puis 30 km/h.
NavRoute testRoute() {
  const start = GeoPoint(48.8566, 2.3522);
  const dLat1km = 1000 / 111195.0;
  const dLon500m = 500 / (111195.0 * 0.6578);
  final corner = GeoPoint(start.latitude + dLat1km, start.longitude);
  final end = GeoPoint(corner.latitude, corner.longitude + dLon500m);
  final geometry = <GeoPoint>[
    for (var i = 0; i <= 10; i++) GeoPoint(start.latitude + dLat1km * i / 10, start.longitude),
    for (var i = 1; i <= 5; i++) GeoPoint(corner.latitude, corner.longitude + dLon500m * i / 5),
  ];
  return NavRoute(
    geometry: geometry,
    distanceM: 1500,
    durationS: 180,
    segmentSpeedLimits: [for (var i = 0; i < 10; i++) 50, for (var i = 0; i < 5; i++) 30],
    steps: [
      const RouteStep(kind: ManeuverKind.depart, direction: ManeuverDirection.none, location: start, distanceM: 1000, durationS: 120, roadName: 'Rue de Rivoli'),
      RouteStep(kind: ManeuverKind.turn, direction: ManeuverDirection.right, location: corner, distanceM: 500, durationS: 60, roadName: 'Avenue Victoria', destinations: 'Centre-ville'),
      RouteStep(kind: ManeuverKind.arrive, direction: ManeuverDirection.none, location: end, distanceM: 0, durationS: 0),
    ],
  );
}

/// Calculateur d'itinéraire simulé.
class FakeRouteService implements RouteService {
  FakeRouteService({NavRoute Function()? build, this.error}) : _build = build ?? testRoute;
  final NavRoute Function() _build;
  RoutingException? error;
  final calls = <(GeoPoint, GeoPoint)>[];

  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? bearing}) async {
    calls.add((from, to));
    if (error != null) throw error!;
    return _build();
  }
}

/// Synthèse vocale simulée : enregistre les phrases.
class FakeSpeaker implements Speaker {
  final spoken = <String>[];
  int stops = 0;
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async => stops++;
}

GeoFix fixAt(GeoPoint p, {double kmh = 50, double heading = 0}) => GeoFix(
  point: p,
  timestamp: DateTime(2026, 10, 30, 14, 27),
  speedMps: kmh / 3.6,
  headingDeg: heading,
  accuracyM: 5,
);

/// Point situé à [meters] au nord (puis [eastMeters] à l'est) du départ de [testRoute].
GeoPoint north(double meters, [double eastMeters = 0]) => GeoPoint(
  48.8566 + meters / 111195.0,
  2.3522 + eastMeters / (111195.0 * 0.6578),
);

/// Lecteur de plaques simulé : les images analysées sont poussées par le test.
class FakePlateScanner implements PlateScanner {
  final _frames = StreamController<ScanFrame>.broadcast();
  ScannerException? startError;
  int starts = 0, stops = 0;

  @override
  CameraController? get controller => null;

  @override
  Stream<ScanFrame> get frames => _frames.stream;

  @override
  Future<void> start() async {
    starts++;
    if (startError != null) throw startError!;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async {}

  void push(List<String> plates, {DateTime? at, Size size = const Size(720, 1280), double brightness = 120}) {
    _frames.add(ScanFrame(
      observations: [
        for (final p in plates)
          PlateObservation(
            candidate: PlateFormats.extract(p).first,
            at: at ?? DateTime.now(),
            ocrConfidence: 0.92,
            box: const Rect.fromLTWH(200, 700, 300, 70),
          ),
      ],
      uprightSize: size,
      sharpness: 80,
      brightness: brightness,
      took: const Duration(milliseconds: 60),
      analyzed: true,
    ));
  }
}

/// Liste de surveillance en mémoire (tests).
class MemoryWatchlist implements WatchlistRepository {
  final map = <String, WatchEntry>{};

  @override
  Future<List<WatchEntry>> all() async => map.values.toList();
  @override
  Future<void> upsert(WatchEntry e) async => map[e.plate] = e;
  @override
  Future<void> delete(String plate) async => map.remove(plate);
  @override
  Future<void> clear() async => map.clear();
  @override
  Future<(int, int)> importAll(List<WatchEntry> entries, {ImportMode mode = ImportMode.merge}) async {
    if (mode == ImportMode.replaceSource && entries.isNotEmpty) {
      map.removeWhere((_, e) => e.source == entries.first.source);
    }
    var added = 0, updated = 0;
    for (final e in entries) {
      map.containsKey(e.plate) ? updated++ : added++;
      map[e.plate] = e;
    }
    return (added, updated);
  }
}

/// Historique en mémoire (tests).
class MemoryDetectionLog implements DetectionLog {
  final records = <DetectionRecord>[];
  var _nextId = 1;
  @override
  Future<void> add(DetectionRecord r) async => records.insert(
    0,
    DetectionRecord(
      id: r.id ?? _nextId++,
      plate: r.plate,
      display: r.display,
      country: r.country,
      category: r.category,
      priority: r.priority,
      confidence: r.confidence,
      at: r.at,
      latitude: r.latitude,
      longitude: r.longitude,
    ),
  );
  @override
  Future<List<DetectionRecord>> recent({int limit = 500}) async => records.take(limit).toList();
  @override
  Future<void> delete(int id) async => records.removeWhere((r) => r.id == id);
  @override
  Future<int> purgeOlderThan(DateTime limit) async {
    final before = records.length;
    records.removeWhere((r) => r.at.isBefore(limit));
    return before - records.length;
  }
  @override
  Future<void> clear() async => records.clear();
}

/// Son d'alerte simulé.
class FakeAlertSound implements AlertSound {
  int plays = 0;
  @override
  Future<void> play({double volume = 1}) async => plays++;
}

/// Reconnaissance vocale simulée : renvoie la phrase préparée.
class FakeSpeechInput implements SpeechInput {
  String? next;
  SpeechUnavailable? error;
  int cancels = 0;

  @override
  Future<String?> listenOnce({
    required void Function(String partial) onPartial,
    Duration listenFor = const Duration(seconds: 8),
    Duration pauseFor = const Duration(seconds: 2),
  }) async {
    if (error != null) throw error!;
    if (next != null) onPartial(next!);
    return next;
  }

  @override
  Future<void> cancel() async => cancels++;
}

/// Réglages en mémoire (tests).
class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([this.value = const AppSettings()]);
  AppSettings value;
  int saves = 0;
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings s) async {
    value = s;
    saves++;
  }
}

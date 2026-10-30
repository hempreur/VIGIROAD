import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:vigiroad/core/permissions/permission_service.dart';
import 'package:vigiroad/core/theme/vr_colors.dart';
import 'package:vigiroad/features/navigation/data/location_source.dart';
import 'package:vigiroad/features/navigation/domain/geo_fix.dart';
import 'package:vigiroad/features/navigation/presentation/widgets/map_view.dart';
import 'package:vigiroad/features/search/data/photon_geocoder.dart';

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

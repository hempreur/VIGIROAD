import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart' as tr;

import '../../../traffic/domain/traffic_labels.dart';
import '../../domain/geo_fix.dart';

/// Paramètres transmis à la vue carte par l'écran de navigation.
class MapViewArgs {
  const MapViewArgs({
    required this.styleUrl,
    required this.following,
    required this.tilted,
    required this.fix,
    required this.destination,
    this.route,
    required this.insets,
    required this.locationGranted,
    required this.onUserGesture,
    this.traffic = const [],
    this.onTrafficTap,
  });

  final String styleUrl;

  /// La caméra suit la position (mode conduite).
  final bool following;

  /// Vue inclinée 3D (mode conduite) ou vue à plat.
  final bool tilted;
  final GeoFix? fix;
  final GeoPoint? destination;

  /// Tracé de l'itinéraire en cours (ligne bleue lumineuse).
  final List<GeoPoint>? route;

  /// Zones de la carte masquées par les panneaux : le point focal de la
  /// caméra est recentré dans la partie visible.
  final EdgeInsets insets;
  final bool locationGranted;

  /// Appelé quand l'utilisateur manipule la carte (désactive le suivi).
  final VoidCallback onUserGesture;

  /// Perturbations signalées par les sources officielles.
  final List<tr.TrafficEvent> traffic;
  final void Function(tr.TrafficEvent event)? onTrafficTap;
}

/// Carte MapLibre sombre (données OpenStreetMap).
class VrMapView extends StatefulWidget {
  const VrMapView({super.key, required this.args});

  final MapViewArgs args;

  @override
  State<VrMapView> createState() => _VrMapViewState();
}

class _VrMapViewState extends State<VrMapView> {
  MapLibreMapController? _controller;
  bool _styleReady = false;
  Circle? _destinationMarker;
  List<Line> _routeLines = const [];
  List<Line> _trafficLines = const [];
  List<Circle> _trafficCircles = const [];
  final _circleEvents = <String, tr.TrafficEvent>{};

  /// Centre de la France métropolitaine, avant le premier point GPS.
  static const _initial = CameraPosition(target: LatLng(46.6, 2.4), zoom: 5);

  @override
  void didUpdateWidget(VrMapView old) {
    super.didUpdateWidget(old);
    final a = widget.args;
    if (a.insets != old.args.insets) {
      unawaited(_controller?.updateContentInsets(a.insets, true));
    }
    final fixChanged = a.fix?.point != old.args.fix?.point;
    final modeChanged = a.following != old.args.following || a.tilted != old.args.tilted;
    if (a.following && (fixChanged || modeChanged)) {
      unawaited(_follow());
    }
    if (a.destination != old.args.destination) {
      unawaited(_syncDestination());
    }
    if (!identical(a.route, old.args.route)) {
      unawaited(_syncRoute());
    }
    if (!identical(a.traffic, old.args.traffic)) {
      unawaited(_syncTraffic());
    }
  }

  /// Perturbations : tronçon concerné (trait coloré selon la gravité) et
  /// point touchable, cerclé de noir pour rester lisible sur la carte sombre.
  Future<void> _syncTraffic() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    if (_trafficLines.isNotEmpty) await c.removeLines(_trafficLines);
    if (_trafficCircles.isNotEmpty) await c.removeCircles(_trafficCircles);
    _trafficLines = const [];
    _trafficCircles = const [];
    _circleEvents.clear();
    final events = widget.args.traffic;
    if (events.isEmpty) return;
    LatLng ll(tr.LatLng p) => LatLng(p.lat, p.lng);
    final withLine = [for (final e in events) if (e.geometry.length >= 2) e];
    _trafficLines = await c.addLines([
      for (final e in withLine)
        LineOptions(
          geometry: [for (final p in e.geometry) ll(p)],
          lineColor: TrafficLabels.hex(TrafficLabels.color(e.severity)),
          lineWidth: 6,
          lineOpacity: 0.85,
          lineJoin: 'round',
        ),
    ]);
    _trafficCircles = await c.addCircles([
      for (final e in events)
        CircleOptions(
          geometry: ll(e.position),
          circleRadius: 7,
          circleColor: TrafficLabels.hex(TrafficLabels.color(e.severity)),
          circleStrokeWidth: 2.5,
          circleStrokeColor: '#02050A',
        ),
    ]);
    for (var i = 0; i < _trafficCircles.length && i < events.length; i++) {
      _circleEvents[_trafficCircles[i].id] = events[i];
    }
  }

  void _onCircleTapped(Circle circle) {
    final e = _circleEvents[circle.id];
    if (e != null) widget.args.onTrafficTap?.call(e);
  }

  @override
  void dispose() {
    _controller?.onCircleTapped.remove(_onCircleTapped);
    super.dispose();
  }

  /// Itinéraire en trois couches superposées : halo bleu électrique flou,
  /// trait cyan, cœur clair — l'effet « néon » de la référence.
  Future<void> _syncRoute() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    if (_routeLines.isNotEmpty) {
      await c.removeLines(_routeLines);
      _routeLines = const [];
    }
    final route = widget.args.route;
    if (route == null || route.length < 2) return;
    final geometry = [for (final p in route) LatLng(p.latitude, p.longitude)];
    _routeLines = await c.addLines([
      LineOptions(geometry: geometry, lineColor: '#066DD3', lineWidth: 18, lineBlur: 8, lineOpacity: 0.7, lineJoin: 'round'),
      LineOptions(geometry: geometry, lineColor: '#19CFF4', lineWidth: 8, lineOpacity: 0.95, lineJoin: 'round'),
      LineOptions(geometry: geometry, lineColor: '#C9FFFF', lineWidth: 2.5, lineOpacity: 0.9, lineJoin: 'round'),
    ]);
  }

  Future<void> _follow() async {
    final c = _controller;
    final fix = widget.args.fix;
    if (c == null || fix == null) return;
    final a = widget.args;
    await c.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(fix.point.latitude, fix.point.longitude),
          zoom: a.tilted ? 16.5 : 15,
          bearing: a.tilted && fix.headingReliable ? fix.headingDeg! : 0,
          tilt: a.tilted ? 55 : 0,
        ),
      ),
      duration: const Duration(milliseconds: 900),
    );
  }

  Future<void> _syncDestination() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    if (_destinationMarker != null) {
      await c.removeCircle(_destinationMarker!);
      _destinationMarker = null;
    }
    final d = widget.args.destination;
    if (d == null) return;
    _destinationMarker = await c.addCircle(
      CircleOptions(
        geometry: LatLng(d.latitude, d.longitude),
        circleRadius: 9,
        circleColor: '#19CFF4',
        circleStrokeWidth: 3,
        circleStrokeColor: '#02050A',
      ),
    );
    if (!widget.args.following) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(LatLng(d.latitude, d.longitude), 15));
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.args;
    return Listener(
      // Tout contact de l'utilisateur sur la carte suspend le suivi automatique.
      onPointerDown: (_) => a.onUserGesture(),
      child: MapLibreMap(
        styleString: a.styleUrl,
        initialCameraPosition: _initial,
        compassEnabled: false,
        // En mode suivi, l'écran dessine son propre marqueur de position.
        myLocationEnabled: a.locationGranted && !a.following,
        myLocationRenderMode: MyLocationRenderMode.normal,
        attributionButtonPosition: AttributionButtonPosition.bottomLeft,
        attributionButtonMargins: Point(8, a.insets.bottom + 8),
        onMapCreated: (c) {
          _controller = c;
          c.onCircleTapped.add(_onCircleTapped);
        },
        onStyleLoadedCallback: () {
          _styleReady = true;
          unawaited(_controller?.updateContentInsets(widget.args.insets));
          unawaited(_syncDestination());
          unawaited(_syncRoute());
          unawaited(_syncTraffic());
          if (widget.args.following) unawaited(_follow());
        },
      ),
    );
  }
}

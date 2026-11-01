import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart' as tr;

import '../../../traffic/domain/traffic_labels.dart';
import '../../../reports/presentation/report_sheets.dart';
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
    this.reports = const [],
    this.onReportTap,
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

  /// Signalements « Chicken » des conducteurs (marqueurs 🍗).
  final List<tr.ChickenReport> reports;
  final void Function(tr.ChickenReport report)? onReportTap;
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
  List<Symbol> _reportSymbols = const [];
  final _symbolReports = <String, tr.ChickenReport>{};
  bool _markerImage = false;
  static const _chickenImage = 'vr-chicken';

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
    if (!identical(a.reports, old.args.reports)) {
      unawaited(_syncReports());
    }
  }

  static const _buildingsLayer = 'vr-buildings-3d';

  /// Bâtiments en relief (hauteurs OpenStreetMap), sous les noms de rues.
  ///
  /// Le style sombre CARTO (source « protomaps », couche « buildings ») et
  /// les styles OpenMapTiles (couche « building ») sont reconnus ; un
  /// bâtiment sans hauteur connue reçoit 3 étages (≈ 9 m).
  Future<void> _add3dBuildings() async {
    final c = _controller;
    if (c == null) return;
    try {
      final sources = await c.getSourceIds();
      final (String source, String layer)? target = sources.contains('protomaps')
          ? ('protomaps', 'buildings')
          : sources.contains('carto')
          ? ('carto', 'building')
          : sources.contains('openmaptiles')
          ? ('openmaptiles', 'building')
          : null;
      if (target == null) return;
      final layers = [for (final l in await c.getLayerIds()) '$l'];
      if (layers.contains(_buildingsLayer)) return;
      final firstLabel = layers.where((l) => l.contains('label') || l.contains('place') || l.contains('poi')).firstOrNull;
      await c.addFillExtrusionLayer(
        target.$1,
        _buildingsLayer,
        const FillExtrusionLayerProperties(
          fillExtrusionColor: [
            'interpolate', ['linear'], ['coalesce', ['get', 'height'], ['get', 'render_height'], 9],
            0, '#16222D',
            40, '#1E3346',
            120, '#29506E',
          ],
          fillExtrusionHeight: [
            'interpolate', ['linear'], ['zoom'],
            14.5, 0,
            15.5, ['coalesce', ['get', 'height'], ['get', 'render_height'], 9],
          ],
          fillExtrusionBase: ['coalesce', ['get', 'min_height'], ['get', 'render_min_height'], 0],
          fillExtrusionOpacity: 0.88,
        ),
        sourceLayer: target.$2,
        minzoom: 14.5,
        belowLayerId: firstLabel,
        enableInteraction: false,
      );
    } on Object catch (e) {
      debugPrint('VIGIROAD carte : bâtiments 3D indisponibles ($e)');
    }
  }

  /// Marqueurs 🍗 des signalements, visibles 2 h.
  Future<void> _syncReports() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    if (!_markerImage) {
      try {
        await c.addImage(_chickenImage, await renderChickenMarker());
        _markerImage = true;
      } on Object {
        return;
      }
    }
    if (_reportSymbols.isNotEmpty) await c.removeSymbols(_reportSymbols);
    _reportSymbols = const [];
    _symbolReports.clear();
    final reports = widget.args.reports;
    if (reports.isEmpty) return;
    _reportSymbols = await c.addSymbols([
      for (final r in reports)
        SymbolOptions(
          geometry: LatLng(r.position.lat, r.position.lng),
          iconImage: _chickenImage,
          iconSize: 0.55,
          iconAnchor: 'center',
        ),
    ]);
    for (var i = 0; i < _reportSymbols.length && i < reports.length; i++) {
      _symbolReports[_reportSymbols[i].id] = reports[i];
    }
  }

  void _onSymbolTapped(Symbol symbol) {
    final r = _symbolReports[symbol.id];
    if (r != null) widget.args.onReportTap?.call(r);
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
    _controller?.onSymbolTapped.remove(_onSymbolTapped);
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
          zoom: a.tilted ? 17 : 15,
          bearing: a.tilted && fix.headingReliable ? fix.headingDeg! : 0,
          // Vue conduite : forte inclinaison pour voir les bâtiments en relief.
          tilt: a.tilted ? 60 : 0,
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
          c.onSymbolTapped.add(_onSymbolTapped);
        },
        onStyleLoadedCallback: () {
          _styleReady = true;
          unawaited(_controller?.updateContentInsets(widget.args.insets));
          unawaited(_syncDestination());
          unawaited(_syncRoute());
          unawaited(_syncTraffic());
          _markerImage = false;
          unawaited(_syncReports());
          unawaited(_add3dBuildings());
          if (widget.args.following) unawaited(_follow());
        },
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../domain/geo_fix.dart';

/// Paramètres transmis à la vue carte par l'écran de navigation.
class MapViewArgs {
  const MapViewArgs({
    required this.styleUrl,
    required this.following,
    required this.tilted,
    required this.fix,
    required this.destination,
    required this.insets,
    required this.locationGranted,
    required this.onUserGesture,
  });

  final String styleUrl;

  /// La caméra suit la position (mode conduite).
  final bool following;

  /// Vue inclinée 3D (mode conduite) ou vue à plat.
  final bool tilted;
  final GeoFix? fix;
  final GeoPoint? destination;

  /// Zones de la carte masquées par les panneaux : le point focal de la
  /// caméra est recentré dans la partie visible.
  final EdgeInsets insets;
  final bool locationGranted;

  /// Appelé quand l'utilisateur manipule la carte (désactive le suivi).
  final VoidCallback onUserGesture;
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
        onMapCreated: (c) => _controller = c,
        onStyleLoadedCallback: () {
          _styleReady = true;
          unawaited(_controller?.updateContentInsets(widget.args.insets));
          unawaited(_syncDestination());
          if (widget.args.following) unawaited(_follow());
        },
      ),
    );
  }
}

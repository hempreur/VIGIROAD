import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../../navigation/application/navigation_session.dart';
import '../../navigation/domain/route.dart';
import '../data/traffic_client.dart';
import 'traffic_controller.dart';

/// Limitations de vitesse connues pour l'itinéraire en cours, par segment.
class SpeedLimits {
  const SpeedLimits({this.route, this.limits = const []});

  final NavRoute? route;
  final List<int?> limits;

  /// Limitation du segment [i] (`null` = inconnue).
  int? at(int i) => i >= 0 && i < limits.length ? limits[i] : null;
}

final speedLimitProvider = NotifierProvider<SpeedLimitController, SpeedLimits>(SpeedLimitController.new);

/// Demande au serveur VIGIROAD les limitations OpenStreetMap par tronçons de
/// [windowM] devant le véhicule, et redemande avant d'en atteindre la fin.
/// Aucune valeur n'est déduite : un segment sans donnée reste inconnu et le
/// panneau n'est pas affiché.
class SpeedLimitController extends Notifier<SpeedLimits> {
  static const windowM = 20000.0;

  /// Première fenêtre plus courte : premier panneau affiché plus vite.
  static const firstWindowM = 5000.0;

  /// Distance restante dans la fenêtre chargée qui déclenche la suivante.
  static const refillM = 6000.0;
  static const retryAfter = Duration(seconds: 45);

  List<double> _cum = const [];
  int _coveredUntil = 0;
  bool _busy = false;
  DateTime? _retryAt;

  @override
  SpeedLimits build() {
    if (ref.watch(trafficClientProvider) == null) return const SpeedLimits();
    ref.listen(navigationSessionProvider, (_, nav) => _onNav(nav));
    return const SpeedLimits();
  }

  void _onNav(NavState nav) {
    final route = nav.hasRoute ? nav.route : null;
    if (route == null) {
      if (state.route != null) state = const SpeedLimits();
      return;
    }
    if (!identical(route, state.route)) {
      _reset(route);
    }
    final p = nav.progress;
    if (p != null) _maybeFetch(p.segmentIndex);
  }

  void _reset(NavRoute route) {
    final g = route.geometry;
    final cum = List<double>.filled(g.length, 0);
    for (var i = 1; i < g.length; i++) {
      cum[i] = cum[i - 1] +
          haversine(LatLng(g[i - 1].latitude, g[i - 1].longitude), LatLng(g[i].latitude, g[i].longitude));
    }
    _cum = cum;
    _coveredUntil = 0;
    _retryAt = null;
    state = SpeedLimits(route: route, limits: List<int?>.filled(g.length - 1, null));
  }

  void _maybeFetch(int segment) {
    final route = state.route;
    if (route == null || _busy) return;
    final last = route.geometry.length - 1;
    if (_coveredUntil >= last) return;
    if (_coveredUntil > segment && _cum[_coveredUntil] - _cum[segment] > refillM) return;
    final now = ref.read(clockProvider)();
    if (_retryAt != null && now.isBefore(_retryAt!)) return;
    unawaited(_fetch(route, segment < _coveredUntil ? _coveredUntil : segment));
  }

  Future<void> _fetch(NavRoute route, int start) async {
    final client = ref.read(trafficClientProvider);
    if (client == null) return;
    final last = route.geometry.length - 1;
    final window = _coveredUntil == 0 ? firstWindowM : windowM;
    var end = start + 1;
    while (end < last && _cum[end + 1] - _cum[start] <= window && end - start < 4000) {
      end++;
    }
    _busy = true;
    try {
      final pts = [
        for (var i = start; i <= end; i++) LatLng(route.geometry[i].latitude, route.geometry[i].longitude),
      ];
      final r = await client.speedLimits(pts);
      if (!ref.mounted || !identical(route, state.route)) return;
      final limits = [...state.limits];
      for (var i = 0; i < r.limits.length; i++) {
        limits[start + i] = r.limits[i] ?? limits[start + i];
      }
      state = SpeedLimits(route: route, limits: limits);
      if (r.complete) {
        _coveredUntil = end;
        _retryAt = null;
      } else {
        // Données partielles (serveur cartographique saturé) : on redemande plus tard.
        _retryAt = ref.read(clockProvider)().add(retryAfter);
      }
    } on TrafficException {
      _retryAt = ref.read(clockProvider)().add(retryAfter);
    } finally {
      _busy = false;
    }
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../../../app/providers.dart';
import '../../navigation/application/navigation_providers.dart';
import '../../navigation/application/navigation_session.dart';
import '../../navigation/domain/geo_fix.dart';
import '../../navigation/domain/route.dart';
import '../../update/application/app_policy_controller.dart';
import '../data/traffic_client.dart';
import '../domain/traffic_snapshot.dart';

enum TrafficStatus {
  /// Aucun serveur de trafic configuré.
  disabled,

  /// En attente de la position ou de la première réponse.
  waiting,

  /// Aucune donnée récente pour cette zone : état inconnu.
  unknown,

  /// Une source à jour couvre la zone (il peut n'y avoir aucun incident).
  known,

  /// Serveur injoignable depuis trop longtemps : rien n'est affiché.
  error,
}

/// Perturbation située sur l'itinéraire, à [alongM] mètres du départ.
class RouteTrafficEvent {
  const RouteTrafficEvent(this.event, this.alongM);
  final TrafficEvent event;
  final double alongM;
}

class TrafficState {
  const TrafficState({
    this.status = TrafficStatus.waiting,
    this.nearby = const [],
    this.onRoute = const [],
    this.attributions = const [],
    this.updatedAt,
    this.coverageNotes = const [],
    this.message,
    this.visible = const [],
  });

  final TrafficStatus status;

  /// Événements autour de la position (affichés sur la carte).
  final List<TrafficEvent> nearby;

  /// Événements sur l'itinéraire, dans l'ordre de rencontre.
  final List<RouteTrafficEvent> onRoute;
  final List<TrafficAttribution> attributions;
  final DateTime? updatedAt;
  final List<String> coverageNotes;
  final String? message;

  /// Événements à dessiner (zone + itinéraire, sans doublon), calculés une
  /// fois par réponse : la carte ne se redessine que s'ils changent.
  final List<TrafficEvent> visible;
}

final trafficClientProvider = Provider<TrafficClient?>((ref) {
  final c = ref.watch(appConfigProvider);
  if (!c.trafficEnabled) return null;
  return HttpTrafficClient(
    baseUrl: c.trafficApiUrl,
    apiKey: c.trafficApiKey,
    userAgent: c.userAgent,
    extraHeaders: appVersionHeaders(),
    onRejected: ({required bool blocked, String? message}) =>
        unawaited(ref.read(appPolicyProvider.notifier).rejected(blocked: blocked, message: message)),
  );
});

final trafficProvider = NotifierProvider<TrafficController, TrafficState>(TrafficController.new);

/// Perturbations routières venant du serveur VIGIROAD (sources officielles).
///
/// Règle : rien n'est simulé. Sans donnée récente pour la zone, l'état est
/// « inconnu » ; après [maxDataAge] sans réponse, plus rien n'est affiché.
class TrafficController extends Notifier<TrafficState> {
  /// Fréquence de rafraîchissement (le serveur collecte toutes les 2 min).
  static const refreshEvery = Duration(seconds: 60);

  /// Au-delà, des données non renouvelées ne sont plus montrées.
  static const maxDataAge = Duration(minutes: 5);

  /// Demi-côté de la zone interrogée autour de la position (≈ 30 km).
  static const halfBoxDeg = 0.27;

  /// Distance parcourue au-delà de laquelle la zone est réinterrogée.
  static const moveRefreshM = 8000.0;

  Timer? _timer;
  GeoPoint? _lastCenter;
  DateTime? _lastSuccess;
  bool _busy = false;

  @override
  TrafficState build() {
    final client = ref.watch(trafficClientProvider);
    if (client == null) return const TrafficState(status: TrafficStatus.disabled);

    ref.listen(positionProvider, (_, next) {
      final p = next.value?.point;
      if (p == null) return;
      final last = _lastCenter;
      if (last == null || distanceM(last, p) > moveRefreshM) unawaited(refresh());
    });
    ref.listen(navigationSessionProvider.select((s) => s.hasRoute ? s.route : null), (prev, next) {
      if (!identical(prev, next)) unawaited(refresh());
    });
    _timer = Timer.periodic(refreshEvery, (_) => unawaited(refresh()));
    ref.onDispose(() => _timer?.cancel());
    unawaited(Future.microtask(refresh));
    return const TrafficState();
  }

  DateTime _now() => ref.read(clockProvider)();

  Future<void> refresh() async {
    final client = ref.read(trafficClientProvider);
    final fix = ref.read(positionProvider).value;
    if (client == null || _busy) return;
    if (fix == null) {
      if (state.status != TrafficStatus.known) state = const TrafficState();
      return;
    }
    _busy = true;
    try {
      final here = fix.point;
      final box = BBox(
        here.longitude - halfBoxDeg * 1.5,
        here.latitude - halfBoxDeg,
        here.longitude + halfBoxDeg * 1.5,
        here.latitude + halfBoxDeg,
      );
      final nav = ref.read(navigationSessionProvider);
      final route = nav.hasRoute ? nav.route : null;
      final results = await Future.wait([
        client.inBox(box),
        if (route != null) client.alongRoute(_toLatLng(route.geometry)),
      ]);
      if (!ref.mounted) return;
      _lastCenter = here;
      _lastSuccess = _now();
      state = _merge(results.first, results.length > 1 ? results[1] : null, route);
    } on TrafficException catch (e) {
      if (!ref.mounted) return;
      final last = _lastSuccess;
      if (last == null || _now().difference(last) > maxDataAge) {
        // Pas de donnée récente : on n'affiche rien plutôt que du périmé.
        state = TrafficState(status: TrafficStatus.error, message: e.message);
      }
    } finally {
      _busy = false;
    }
  }

  TrafficState _merge(TrafficSnapshot area, TrafficSnapshot? routeSnap, NavRoute? route) {
    final onRoute = <RouteTrafficEvent>[];
    if (routeSnap != null && route != null) {
      final line = _toLatLng(route.geometry);
      for (final e in routeSnap.events) {
        onRoute.add(RouteTrafficEvent(e, distanceToPolyline(e.position, line).along));
      }
      onRoute.sort((a, b) => a.alongM.compareTo(b.alongM));
    }
    final seen = <String>{};
    final visible = [
      for (final e in [...area.events, ...onRoute.map((r) => r.event)])
        if (seen.add(e.id)) e,
    ];
    final attributions = <String, TrafficAttribution>{
      for (final a in [...area.attributions, ...?routeSnap?.attributions]) a.source: a,
    };
    return TrafficState(
      status: area.known ? TrafficStatus.known : TrafficStatus.unknown,
      // Hors zone couverte, aucun événement n'est présenté comme complet :
      // on montre ceux éventuellement reçus mais l'état reste « inconnu ».
      nearby: area.events,
      onRoute: onRoute,
      attributions: attributions.values.toList(),
      updatedAt: area.updatedAt,
      coverageNotes: area.coverageNotes,
      visible: visible,
    );
  }

  static List<LatLng> _toLatLng(List<GeoPoint> pts) => [for (final p in pts) LatLng(p.latitude, p.longitude)];

  static double distanceM(GeoPoint a, GeoPoint b) =>
      haversine(LatLng(a.latitude, a.longitude), LatLng(b.latitude, b.longitude));
}

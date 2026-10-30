import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/providers.dart';
import '../data/osrm_router.dart';
import '../data/speaker.dart';
import '../domain/geo_fix.dart';
import '../domain/guidance_policy.dart';
import '../domain/route.dart';
import '../domain/route_tracker.dart';
import 'navigation_providers.dart';

enum NavStatus { idle, waitingForGps, routing, guiding, rerouting, arrived, failed }

class NavState {
  const NavState({
    this.status = NavStatus.idle,
    this.route,
    this.progress,
    this.message,
    this.arrival,
  });

  final NavStatus status;
  final NavRoute? route;
  final RouteProgress? progress;

  /// Message d'erreur lisible (statut `failed`).
  final String? message;

  /// Heure d'arrivée estimée.
  final DateTime? arrival;

  RouteStep? get nextStep {
    final r = route, p = progress;
    if (r == null || p == null) return null;
    return r.steps[p.nextStepIndex];
  }

  bool get hasRoute => route != null && (status == NavStatus.guiding || status == NavStatus.rerouting);

  NavState copyWith({
    NavStatus? status,
    NavRoute? route,
    RouteProgress? progress,
    String? message,
    DateTime? arrival,
  }) => NavState(
    status: status ?? this.status,
    route: route ?? this.route,
    progress: progress ?? this.progress,
    message: message,
    arrival: arrival ?? this.arrival,
  );
}

final routeServiceProvider = Provider<RouteService>((ref) {
  final c = ref.watch(appConfigProvider);
  return OsrmRouter(baseUrl: c.routingBaseUrl, userAgent: c.userAgent);
});

final speakerProvider = Provider<Speaker>((ref) => TtsSpeaker());

/// Horloge injectable (tests).
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Maintien de l'écran allumé pendant le guidage (désactivable en test).
final wakelockProvider = Provider<void Function(bool on)>(
  (ref) => (on) => unawaited(WakelockPlus.toggle(enable: on).catchError((Object _) {})),
);

/// Guidage vocal activé (bouton haut-parleur).
final voiceGuidanceProvider = NotifierProvider<VoiceGuidanceController, bool>(VoiceGuidanceController.new);

class VoiceGuidanceController extends Notifier<bool> {
  @override
  bool build() => true;
  void toggle() {
    state = !state;
    if (!state) unawaited(ref.read(speakerProvider).stop());
  }
}

final navigationSessionProvider = NotifierProvider<NavigationSession, NavState>(NavigationSession.new);

/// Session de guidage : calcule l'itinéraire vers la destination choisie,
/// suit la position, annonce les manœuvres et recalcule hors trajet.
class NavigationSession extends Notifier<NavState> {
  RouteTracker? _tracker;
  final _offRoute = OffRouteDetector();
  final _policy = GuidancePolicy();
  GeoFix? _lastFix;
  DateTime? _lastRouteAttempt;
  int _requestId = 0;

  /// Délai minimal entre deux calculs (recalcul ou nouvel essai après erreur).
  static const retryDelay = Duration(seconds: 12);

  @override
  NavState build() {
    ref.listen(positionProvider, (_, next) {
      final fix = next.value;
      if (fix != null) _onFix(fix);
    });
    ref.listen(destinationProvider, (prev, next) {
      if (next == null) {
        _stop();
      } else if (next != prev) {
        unawaited(_start());
      }
    });
    _lastFix = ref.read(positionProvider).value;
    ref.onDispose(() => ref.read(wakelockProvider)(false));
    return const NavState();
  }

  Future<void> _start() async {
    _tracker = null;
    _policy.reset();
    _offRoute.reset();
    if (_lastFix == null) {
      state = const NavState(status: NavStatus.waitingForGps);
      return;
    }
    await _compute(initial: true);
  }

  /// Nouvel essai manuel après une erreur.
  Future<void> retry() => _compute(initial: _tracker == null);

  void _stop() {
    _requestId++;
    _tracker = null;
    state = const NavState();
    ref.read(wakelockProvider)(false);
    unawaited(ref.read(speakerProvider).stop());
  }

  Future<void> _compute({required bool initial}) async {
    final dest = ref.read(destinationProvider);
    final fix = _lastFix;
    if (dest == null || fix == null) return;
    final id = ++_requestId;
    _lastRouteAttempt = ref.read(clockProvider)();
    state = state.copyWith(status: initial ? NavStatus.routing : NavStatus.rerouting);
    try {
      final route = await ref
          .read(routeServiceProvider)
          .route(fix.point, dest.point, bearing: fix.headingReliable ? fix.headingDeg : null);
      if (id != _requestId) return;
      if (route.geometry.length < 2 || route.steps.isEmpty) {
        throw const RoutingException('Itinéraire vide.');
      }
      _tracker = RouteTracker(route);
      _offRoute.reset();
      _policy.reset();
      final progress = _tracker!.update(fix.point);
      state = NavState(
        status: NavStatus.guiding,
        route: route,
        progress: progress,
        arrival: _eta(progress),
      );
      ref.read(wakelockProvider)(true);
      if (ref.read(voiceGuidanceProvider)) {
        unawaited(ref.read(speakerProvider).speak(initial ? _policy.start(route) : 'Itinéraire recalculé.'));
      }
    } on RoutingException catch (e) {
      if (id != _requestId) return;
      // En recalcul, on garde l'ancien tracé affiché.
      state = NavState(status: NavStatus.failed, route: state.route, progress: state.progress, message: e.message);
    }
  }

  DateTime _eta(RouteProgress p) =>
      ref.read(clockProvider)().add(Duration(seconds: p.remainingS.round()));

  void _onFix(GeoFix fix) {
    _lastFix = fix;
    final now = ref.read(clockProvider)();
    final canRetry = _lastRouteAttempt == null || now.difference(_lastRouteAttempt!) >= retryDelay;

    switch (state.status) {
      case NavStatus.waitingForGps:
        unawaited(_compute(initial: true));
        return;
      case NavStatus.failed:
        if (canRetry) unawaited(_compute(initial: _tracker == null));
        return;
      case NavStatus.guiding:
        break;
      case NavStatus.idle || NavStatus.routing || NavStatus.rerouting || NavStatus.arrived:
        return;
    }

    final tracker = _tracker!;
    final progress = tracker.update(fix.point);

    if (progress.arrived) {
      state = state.copyWith(status: NavStatus.arrived, progress: progress);
      ref.read(wakelockProvider)(false);
      if (ref.read(voiceGuidanceProvider)) {
        unawaited(ref.read(speakerProvider).speak('Vous êtes arrivé à destination.'));
      }
      return;
    }

    if (_offRoute.feed(progress, accuracyM: fix.accuracyM) && canRetry) {
      unawaited(_compute(initial: false));
      return;
    }

    state = state.copyWith(progress: progress, arrival: _eta(progress));

    if (ref.read(voiceGuidanceProvider)) {
      final phrase = _policy.next(progress, tracker.route, speedKmh: (fix.speedKmh ?? 0).toDouble());
      if (phrase != null) unawaited(ref.read(speakerProvider).speak(phrase));
    }
  }
}

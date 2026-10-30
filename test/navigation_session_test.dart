import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/navigation/application/navigation_providers.dart';
import 'package:vigiroad/features/navigation/application/navigation_session.dart';
import 'package:vigiroad/features/navigation/data/osrm_router.dart';
import 'package:vigiroad/features/navigation/domain/geo_fix.dart';
import 'package:vigiroad/features/navigation/data/location_source.dart';
import 'package:vigiroad/features/settings/application/settings_controller.dart';
import 'package:vigiroad/features/settings/domain/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'helpers/fakes.dart';

class _Env {
  _Env() {
    container = ProviderContainer(
      overrides: [
        locationSourceProvider.overrideWithValue(location),
        routeServiceProvider.overrideWithValue(router),
        speakerProvider.overrideWithValue(speaker),
        wakelockProvider.overrideWithValue((on) => wakelock.add(on)),
        clockProvider.overrideWithValue(() => now),
        notificationPermissionProvider.overrideWithValue(() async => notificationRequests++),
        settingsStoreProvider.overrideWithValue(settingsStore),
      ],
    );
    // Garde les providers actifs comme le ferait l'écran.
    container.listen(navigationSessionProvider, (_, _) {});
    container.listen(positionProvider, (_, _) {});
  }

  final location = FakeLocationSource();
  final router = FakeRouteService();
  final speaker = FakeSpeaker();
  final wakelock = <bool>[];
  var notificationRequests = 0;
  final settingsStore = MemorySettingsStore();
  DateTime now = DateTime(2026, 10, 30, 15, 0);
  late final ProviderContainer container;

  NavState get state => container.read(navigationSessionProvider);

  Future<void> fix(GeoPoint p, {double kmh = 50}) async {
    await pumpEventQueue();
    location.push(fixAt(p, kmh: kmh));
    await pumpEventQueue();
  }

  Future<void> go() async {
    container.read(destinationProvider.notifier).set(
      Destination(label: 'Arrivée', detail: '', point: testRoute().geometry.last),
    );
    await pumpEventQueue();
  }
}

void main() {
  test('attend le GPS, calcule, guide et annonce le départ', () async {
    final env = _Env();
    addTearDown(env.container.dispose);

    await env.go();
    expect(env.state.status, NavStatus.waitingForGps);

    await env.fix(north(0));
    expect(env.router.calls, hasLength(1));
    expect(env.state.status, NavStatus.guiding);
    expect(env.state.progress!.nextStepIndex, 1);
    expect(env.state.arrival, DateTime(2026, 10, 30, 15, 3), reason: '180 s restantes');
    expect(env.speaker.spoken.single, startsWith('Guidage démarré'));
    expect(env.wakelock.last, isTrue);
  });

  test('annonces vocales pendant le trajet puis arrivée', () async {
    final env = _Env();
    addTearDown(env.container.dispose);
    await env.fix(north(0));
    await env.go();

    await env.fix(north(520));
    expect(env.speaker.spoken.last, startsWith('Dans 500 mètres, tournez à droite'));
    await env.fix(north(1000, 495));
    expect(env.state.status, NavStatus.arrived);
    expect(env.speaker.spoken.last, 'Vous êtes arrivé à destination.');
    expect(env.wakelock.last, isFalse);
  });

  test('recalcule après plusieurs positions hors trajet', () async {
    final env = _Env();
    addTearDown(env.container.dispose);
    await env.fix(north(0));
    await env.go();
    expect(env.router.calls, hasLength(1));

    env.now = env.now.add(const Duration(seconds: 30));
    await env.fix(north(300, 150));
    await env.fix(north(310, 150));
    expect(env.router.calls, hasLength(1));
    await env.fix(north(320, 150));
    expect(env.router.calls, hasLength(2));
    expect(env.speaker.spoken.last, 'Itinéraire recalculé.');
  });

  test('erreur de calcul : statut explicite puis nouvel essai différé', () async {
    final env = _Env();
    addTearDown(env.container.dispose);
    env.router.error = const RoutingException('Aucun itinéraire routier trouvé vers cette destination.');
    await env.fix(north(0));
    await env.go();
    expect(env.state.status, NavStatus.failed);
    expect(env.state.message, contains('Aucun itinéraire'));

    env.router.error = null;
    await env.fix(north(5));
    expect(env.router.calls, hasLength(1), reason: 'trop tôt pour réessayer');
    env.now = env.now.add(NavigationSession.retryDelay);
    await env.fix(north(10));
    expect(env.router.calls, hasLength(2));
    expect(env.state.status, NavStatus.guiding);
  });

  test('guidage vocal coupé : aucune annonce', () async {
    final env = _Env();
    addTearDown(env.container.dispose);
    env.container.read(voiceGuidanceProvider.notifier).toggle();
    await env.fix(north(0));
    await env.go();
    await env.fix(north(520));
    expect(env.speaker.spoken, isEmpty);
  });

  test('annuler la destination arrête le guidage', () async {
    final env = _Env();
    addTearDown(env.container.dispose);
    await env.fix(north(0));
    await env.go();
    env.container.read(destinationProvider.notifier).clear();
    await pumpEventQueue();
    expect(env.state.status, NavStatus.idle);
    expect(env.wakelock.last, isFalse);
  });

  test('guidage en arrière-plan : localisation relancée en mode service, puis rétablie', () async {
    final env = _Env();
    addTearDown(env.container.dispose);
    await env.container.read(settingsControllerProvider.future);
    await env.fix(north(0));
    await env.go();
    await pumpEventQueue();
    expect(env.container.read(backgroundLocationProvider), isTrue);
    expect(env.location.modes.last, isTrue);
    expect(env.notificationRequests, 1);

    env.container.read(destinationProvider.notifier).clear();
    await pumpEventQueue();
    expect(env.container.read(backgroundLocationProvider), isFalse);
    expect(env.location.modes.last, isFalse);
  });

  test('réglage désactivé : pas de mode arrière-plan', () async {
    final env = _Env();
    addTearDown(env.container.dispose);
    env.settingsStore.value = const AppSettings(backgroundGuidance: false);
    await env.container.read(settingsControllerProvider.future);
    await env.fix(north(0));
    await env.go();
    expect(env.state.status, NavStatus.guiding);
    expect(env.container.read(backgroundLocationProvider), isFalse);
  });

  test('réglages de localisation selon la plateforme', () {
    final android = buildLocationSettings(TargetPlatform.android, background: true) as AndroidSettings;
    expect(android.foregroundNotificationConfig?.notificationText, 'Guidage en cours');
    final androidFg = buildLocationSettings(TargetPlatform.android, background: false) as AndroidSettings;
    expect(androidFg.foregroundNotificationConfig, isNull);
    final ios = buildLocationSettings(TargetPlatform.iOS, background: true) as AppleSettings;
    expect(ios.allowBackgroundLocationUpdates, isTrue);
    expect(ios.showBackgroundLocationIndicator, isTrue);
    final iosFg = buildLocationSettings(TargetPlatform.iOS, background: false) as AppleSettings;
    expect(iosFg.allowBackgroundLocationUpdates, isFalse);
  });
}

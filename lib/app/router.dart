import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/history/presentation/history_screen.dart';
import '../features/navigation/presentation/navigation_screen.dart';
import '../features/onboarding/presentation/permissions_screen.dart';
import '../features/plates/presentation/plates_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/sentrix/presentation/voice_training_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/splash/presentation/splash_screen.dart';

abstract final class Routes {
  static const splash = '/';
  static const permissions = '/permissions';
  static const home = '/home';
  static const search = '/search';
  static const plates = '/plates';
  static const history = '/history';
  static const settings = '/settings';
  static const voiceTraining = '/settings/sentrix-voice';
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: Routes.splash,
    routes: [
      GoRoute(path: Routes.splash, builder: (context, state) => const SplashScreen()),
      GoRoute(path: Routes.permissions, builder: (context, state) => const PermissionsScreen()),
      GoRoute(path: Routes.home, builder: (context, state) => const NavigationScreen()),
      GoRoute(path: Routes.search, builder: (context, state) => const SearchScreen()),
      GoRoute(path: Routes.plates, builder: (context, state) => const PlatesScreen()),
      GoRoute(path: Routes.history, builder: (context, state) => const HistoryScreen()),
      GoRoute(path: Routes.settings, builder: (context, state) => const SettingsScreen()),
      GoRoute(path: Routes.voiceTraining, builder: (context, state) => const VoiceTrainingScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

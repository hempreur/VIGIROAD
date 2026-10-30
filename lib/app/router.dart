import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/presentation/home_screen.dart';
import '../features/onboarding/presentation/permissions_screen.dart';
import '../features/splash/presentation/splash_screen.dart';

abstract final class Routes {
  static const splash = '/';
  static const permissions = '/permissions';
  static const home = '/home';
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: Routes.splash,
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.permissions,
        builder: (context, state) => const PermissionsScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

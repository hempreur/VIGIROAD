import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/vr_theme.dart';
import '../features/navigation/application/navigation_providers.dart';
import 'providers.dart';
import 'router.dart';

class VigiroadApp extends ConsumerStatefulWidget {
  const VigiroadApp({super.key});

  @override
  ConsumerState<VigiroadApp> createState() => _VigiroadAppState();
}

class _VigiroadAppState extends ConsumerState<VigiroadApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  /// Retour au premier plan (après un appel, les réglages système…) :
  /// les autorisations ont pu changer ; le GPS redémarre s'il était bloqué.
  void _onResume() {
    final before = ref.read(permissionsProvider).value;
    ref.invalidate(permissionsProvider);
    ref.read(permissionsProvider.future).then((after) {
      final positionFailed = ref.read(positionProvider).hasError;
      if (positionFailed || before?.toString() != after.toString()) {
        ref.invalidate(positionProvider);
      }
    }).ignore();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: VrTheme.overlay,
      child: MaterialApp.router(
        title: 'VIGIROAD',
        debugShowCheckedModeBanner: false,
        theme: VrTheme.build(),
        darkTheme: VrTheme.build(),
        themeMode: ThemeMode.dark,
        routerConfig: ref.watch(routerProvider),
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
      ),
    );
  }
}

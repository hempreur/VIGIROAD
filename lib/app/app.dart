import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/vr_theme.dart';
import 'router.dart';

class VigiroadApp extends ConsumerWidget {
  const VigiroadApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

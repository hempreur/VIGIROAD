import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/app/app.dart';
import 'package:vigiroad/app/providers.dart';
import 'package:vigiroad/core/permissions/permission_service.dart';

/// Monte l'application complète avec un service d'autorisations simulé.
Future<void> pumpVigiroad(WidgetTester tester, PermissionService permissions) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [permissionServiceProvider.overrideWithValue(permissions)],
      child: const VigiroadApp(),
    ),
  );
}

/// Taille d'un smartphone de référence (≈ iPhone 15, 393×852 pt @3x).
void usePhoneSurface(WidgetTester tester, {Size size = const Size(393, 852)}) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget wrapDark(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData.dark(),
  home: Scaffold(body: Center(child: child)),
);

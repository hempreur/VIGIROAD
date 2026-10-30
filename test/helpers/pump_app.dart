import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/app/app.dart';
import 'package:vigiroad/app/providers.dart';
import 'package:vigiroad/core/permissions/permission_service.dart';
import 'package:vigiroad/features/navigation/application/navigation_providers.dart';
import 'package:vigiroad/features/navigation/application/navigation_session.dart';
import 'package:vigiroad/features/navigation/data/location_source.dart';
import 'package:vigiroad/features/navigation/data/osrm_router.dart';
import 'package:vigiroad/features/navigation/data/speaker.dart';
import 'package:vigiroad/features/plates/application/plate_scanning_controller.dart';
import 'package:vigiroad/features/plates/data/plate_scanner.dart';

import 'fakes.dart';

/// Monte l'application complète avec des services simulés.
Future<void> pumpVigiroad(
  WidgetTester tester,
  PermissionService permissions, {
  LocationSource? location,
  RouteService? routeService,
  Speaker? speaker,
  PlateScanner? scanner,
  List<Override> extraOverrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        permissionServiceProvider.overrideWithValue(permissions),
        locationSourceProvider.overrideWithValue(location ?? FakeLocationSource()),
        mapViewBuilderProvider.overrideWithValue(fakeMapView),
        routeServiceProvider.overrideWithValue(routeService ?? FakeRouteService()),
        speakerProvider.overrideWithValue(speaker ?? FakeSpeaker()),
        wakelockProvider.overrideWithValue((_) {}),
        plateScannerProvider.overrideWithValue(scanner ?? FakePlateScanner()),
        ...extraOverrides,
      ],
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

/// Laisse passer le splash (1,8 s) et la transition.
Future<void> passSplash(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

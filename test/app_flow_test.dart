import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/navigation/presentation/navigation_screen.dart';
import 'package:vigiroad/features/onboarding/presentation/permissions_screen.dart';
import 'package:vigiroad/features/splash/presentation/splash_screen.dart';

import 'helpers/fakes.dart';
import 'helpers/pump_app.dart';

void main() {
  testWidgets('splash puis accueil quand toutes les autorisations sont accordées', (tester) async {
    usePhoneSurface(tester);
    await pumpVigiroad(tester, FakePermissionService.allGranted());

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('NAVIGATION  •  LECTURE DE PLAQUES  •  ASSISTANT VOCAL'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(NavigationScreen), findsOneWidget);
  });

  testWidgets('splash puis écran d\'autorisations quand elles manquent', (tester) async {
    usePhoneSurface(tester);
    final service = FakePermissionService.allDenied();
    await pumpVigiroad(tester, service);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(PermissionsScreen), findsOneWidget);
    expect(find.text('Autoriser'), findsNWidgets(3));

    await tester.tap(find.text('Autoriser').first);
    await tester.pump();
    await tester.pump();

    expect(find.text('Autoriser'), findsNWidgets(2));
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    await tester.ensureVisible(find.text('Continuer'));
    await tester.pump();
    await tester.tap(find.text('Continuer'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(NavigationScreen), findsOneWidget);
  });
}

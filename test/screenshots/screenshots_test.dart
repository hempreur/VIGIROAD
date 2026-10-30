@Tags(['screenshots'])
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vigiroad/core/permissions/permission_service.dart';
import 'package:vigiroad/core/theme/vr_colors.dart';
import 'package:vigiroad/core/theme/vr_typography.dart';
import 'package:vigiroad/features/navigation/application/navigation_providers.dart';
import 'package:vigiroad/features/navigation/domain/geo_fix.dart';
import 'package:vigiroad/features/navigation/presentation/navigation_screen.dart';
import 'package:vigiroad/features/plates/application/plates_providers.dart';
import 'package:vigiroad/features/plates/domain/plate_models.dart';
import 'package:vigiroad/features/search/data/photon_geocoder.dart';
import 'package:vigiroad/features/search/presentation/search_screen.dart';
import 'package:vigiroad/features/sentrix/domain/sentrix_state.dart';
import 'package:vigiroad/features/sentrix/presentation/sentrix_head.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

/// Captures de l'interface, générées en CI avec `--update-goldens` et publiées
/// comme artefact pour la comparaison avec l'image de référence (§6).
///
/// Les polices réelles (Rajdhani, Inter, Material Icons) sont chargées pour
/// que les captures correspondent au rendu sur téléphone.
Future<void> _loadFonts() async {
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('01 splash', (tester) async {
    usePhoneSurface(tester);
    await pumpVigiroad(tester, FakePermissionService.allDenied());
    await tester.pump(const Duration(milliseconds: 1300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/01_splash.png'));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('02 autorisations', (tester) async {
    usePhoneSurface(tester);
    final service = FakePermissionService({
      AppCapability.location: CapabilityStatus.granted,
      AppCapability.camera: CapabilityStatus.denied,
      AppCapability.microphone: CapabilityStatus.permanentlyDenied,
    });
    await pumpVigiroad(tester, service);
    await passSplash(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/02_permissions.png'));
  });

  testWidgets('03 navigation', (tester) async {
    usePhoneSurface(tester);
    await pumpVigiroad(tester, FakePermissionService.allGranted(), location: FakeLocationSource(testFix()));
    await passSplash(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/03_navigation.png'));
  });

  testWidgets('05 navigation avec alerte (données de test)', (tester) async {
    usePhoneSurface(tester);
    await pumpVigiroad(tester, FakePermissionService.allGranted(), location: FakeLocationSource(testFix()));
    await passSplash(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(NavigationScreen)));
    const reading = PlateReading(
      normalized: 'AA123BB',
      display: 'AA-123-BB',
      confidence: 0.98,
      vehicleType: 'VP',
    );
    c.read(destinationProvider.notifier).set(
      const Destination(label: 'Centre-ville', detail: '69002 Lyon', point: GeoPoint(45.764, 4.8357)),
    );
    c.read(lastReadingProvider.notifier).update(reading);
    c.read(activeAlertProvider.notifier).raise(
      PlateAlert(reading: reading, category: 'Véhicule à surveiller', priority: WatchPriority.high, at: DateTime(2026)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/05_navigation_alert.png'));
  });

  testWidgets('06 recherche', (tester) async {
    usePhoneSurface(tester);
    final geocoder = FakeGeocoder(const [
      Place(label: 'Gare de Lyon', detail: '75012 Paris', point: GeoPoint(48.8443, 2.3744)),
      Place(label: '12 Rue de la République', detail: '69002 Lyon', point: GeoPoint(45.764, 4.8357)),
      Place(label: 'Lyon', detail: 'Rhône', point: GeoPoint(45.75, 4.85)),
    ]);
    await pumpVigiroad(
      tester,
      FakePermissionService.allGranted(),
      location: FakeLocationSource(testFix()),
      extraOverrides: [geocoderProvider.overrideWithValue(geocoder)],
    );
    await passSplash(tester);
    await tester.tap(find.text('Où allez-vous ?'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField), 'lyon');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/06_search.png'));
  });

  for (final (name, route) in [('07_settings', '/settings'), ('08_plates', '/plates')]) {
    testWidgets(name, (tester) async {
      usePhoneSurface(tester);
      await pumpVigiroad(tester, FakePermissionService.allGranted());
      await passSplash(tester);
      GoRouter.of(tester.element(find.byType(NavigationScreen))).push(route);
      await tester.pump(const Duration(milliseconds: 700));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
    });
  }

  testWidgets('04 états SENTRIX', (tester) async {
    usePhoneSurface(tester, size: const Size(600, 420));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: VrColors.background,
          body: Center(
            child: Wrap(
              spacing: 24,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                for (final s in SentrixState.values)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SentrixHead(size: 150, state: s),
                      const SizedBox(height: 6),
                      Text(s.name.toUpperCase(), style: VrText.caption),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/04_sentrix_states.png'));
  });
}

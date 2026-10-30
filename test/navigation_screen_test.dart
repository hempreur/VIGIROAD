import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/history/presentation/history_screen.dart';
import 'package:vigiroad/features/navigation/application/navigation_providers.dart';
import 'package:vigiroad/features/navigation/data/location_source.dart';
import 'package:vigiroad/features/navigation/domain/geo_fix.dart';
import 'package:vigiroad/features/navigation/presentation/navigation_screen.dart';
import 'package:vigiroad/features/plates/application/plates_providers.dart';
import 'package:vigiroad/features/plates/domain/plate_models.dart';
import 'package:vigiroad/features/search/presentation/search_screen.dart';
import 'package:vigiroad/features/search/data/photon_geocoder.dart';

import 'helpers/fakes.dart';
import 'helpers/pump_app.dart';

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(NavigationScreen)));

void main() {
  testWidgets('affiche la vitesse GPS réelle et l\'invitation à chercher', (tester) async {
    usePhoneSurface(tester);
    await pumpVigiroad(tester, FakePermissionService.allGranted(), location: FakeLocationSource(testFix()));
    await passSplash(tester);

    expect(find.byType(NavigationScreen), findsOneWidget);
    expect(find.text('82'), findsOneWidget);
    expect(find.text('Où allez-vous ?'), findsOneWidget);
    expect(find.text('Source non configurée'), findsOneWidget, reason: 'pas de faux trafic');
    expect(find.text('Lecture des plaques arrêtée'), findsOneWidget);
  });

  testWidgets('vitesse inconnue sans GPS', (tester) async {
    usePhoneSurface(tester);
    await pumpVigiroad(tester, FakePermissionService.allGranted());
    await passSplash(tester);
    expect(find.text('--'), findsOneWidget);
  });

  testWidgets('erreur de localisation affichée', (tester) async {
    usePhoneSurface(tester);
    final loc = FakeLocationSource()..error = const LocationUnavailable(LocationIssue.serviceDisabled);
    await pumpVigiroad(tester, FakePermissionService.allGranted(), location: loc);
    await passSplash(tester);
    expect(find.textContaining('localisation du téléphone est désactivée'), findsOneWidget);
  });

  testWidgets('destination : distance à vol d\'oiseau et annulation', (tester) async {
    usePhoneSurface(tester);
    await pumpVigiroad(tester, FakePermissionService.allGranted(), location: FakeLocationSource(testFix()));
    await passSplash(tester);

    _container(tester).read(destinationProvider.notifier).set(
      const Destination(label: 'Lyon', detail: '69002 Lyon', point: GeoPoint(45.7640, 4.8357)),
    );
    await tester.pump();

    expect(find.text('Lyon'), findsOneWidget);
    expect(find.textContaining('km'), findsWidgets);
    await tester.tap(find.byTooltip('Annuler la destination'));
    await tester.pump();
    expect(find.text('Où allez-vous ?'), findsOneWidget);
  });

  testWidgets('alerte : encadré rouge puis fermeture', (tester) async {
    usePhoneSurface(tester);
    await pumpVigiroad(tester, FakePermissionService.allGranted());
    await passSplash(tester);

    _container(tester).read(activeAlertProvider.notifier).raise(
      PlateAlert(
        reading: const PlateReading(normalized: 'AA123BB', display: 'AA-123-BB', confidence: 0.98),
        category: 'Surveillance',
        priority: WatchPriority.high,
        at: DateTime(2026, 10, 30),
      ),
    );
    await tester.pump();
    expect(find.text('Plaque détectée dans la liste de surveillance'), findsOneWidget);

    await tester.tap(find.text('Plaque détectée dans la liste de surveillance'));
    await tester.pump();
    expect(find.text('Plaque détectée dans la liste de surveillance'), findsNothing);
  });

  testWidgets('boutons : vue 3D, historique, menu SENTRIX', (tester) async {
    usePhoneSurface(tester);
    await pumpVigiroad(tester, FakePermissionService.allGranted(), location: FakeLocationSource(testFix()));
    await passSplash(tester);

    expect(find.byTooltip('Vue à plat'), findsOneWidget);
    await tester.tap(find.byTooltip('Vue à plat'));
    await tester.pump();
    expect(find.byTooltip('Vue conduite 3D'), findsOneWidget);

    await tester.tap(find.byTooltip('Historique des alertes'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(HistoryScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Retour'));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.bySemanticsLabel('Ouvrir le menu SENTRIX'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Que voulez-vous faire ?'), findsOneWidget);
    expect(find.text('Réglages'), findsOneWidget);
  });

  testWidgets('recherche : choisir un résultat définit la destination', (tester) async {
    usePhoneSurface(tester);
    final geocoder = FakeGeocoder([
      const Place(label: 'Tour Eiffel', detail: '75007 Paris', point: GeoPoint(48.8584, 2.2945)),
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
    expect(find.byType(SearchScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'tour eif');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(geocoder.queries, ['tour eif']);

    await tester.tap(find.text('Tour Eiffel'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(NavigationScreen), findsOneWidget);
    expect(find.text('Tour Eiffel'), findsOneWidget);
  });
}

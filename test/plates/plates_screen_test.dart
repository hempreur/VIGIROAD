import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vigiroad/features/navigation/presentation/navigation_screen.dart';
import 'package:vigiroad/features/plates/presentation/plates_screen.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

Future<void> openPlates(WidgetTester tester) async {
  await passSplash(tester);
  unawaitedPush(tester);
  await tester.pump(const Duration(milliseconds: 700));
}

void unawaitedPush(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(NavigationScreen))).push('/plates').ignore();

void main() {
  testWidgets('ajout manuel avec validation du format', (tester) async {
    usePhoneSurface(tester);
    final repo = MemoryWatchlist();
    await pumpVigiroad(tester, FakePermissionService.allGranted(), watchlist: repo);
    await openPlates(tester);
    expect(find.text('Aucune plaque enregistrée'), findsOneWidget);

    await tester.tap(find.text('Ajouter'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).at(1), 'AA-000-BB');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();
    expect(find.textContaining('Format français invalide'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'aa 123 bb');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(repo.map.keys, ['AA123BB']);
    expect(find.text('AA-123-BB'), findsOneWidget);
  });

  testWidgets('import CSV avec aperçu et compte rendu', (tester) async {
    usePhoneSurface(tester);
    final repo = MemoryWatchlist();
    await pumpVigiroad(
      tester,
      FakePermissionService.allGranted(),
      watchlist: repo,
      extraOverrides: [
        watchlistFilePickerProvider.overrideWithValue(
          () async => (name: 'liste.csv', content: 'plate,priority\nAA123BB,high\nCC456DD,low\nBAD,high\n'),
        ),
      ],
    );
    await openPlates(tester);

    await tester.tap(find.text('Importer'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2 plaque(s) valide(s)'), findsOneWidget);
    expect(find.text('1 ligne(s) invalide(s) :'), findsOneWidget);

    await tester.tap(find.text('Ajouter').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(repo.map.keys.toSet(), {'AA123BB', 'CC456DD'});
    expect(find.text('2 plaque(s)'), findsOneWidget);
  });

  testWidgets('suppression confirmée', (tester) async {
    usePhoneSurface(tester);
    final repo = MemoryWatchlist();
    await pumpVigiroad(tester, FakePermissionService.allGranted(), watchlist: repo);
    await openPlates(tester);
    await tester.tap(find.text('Ajouter'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).at(1), 'CC-456-DD');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byTooltip('Supprimer CC-456-DD'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Supprimer'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.map, isEmpty);
    expect(find.byType(PlatesScreen), findsOneWidget);
  });
}

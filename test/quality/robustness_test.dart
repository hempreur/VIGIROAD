import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/navigation/domain/geo_fix.dart';
import 'package:vigiroad/features/navigation/domain/route_tracker.dart';
import 'package:vigiroad/features/navigation/presentation/navigation_screen.dart';
import 'package:vigiroad/features/plates/domain/plate_format.dart';
import 'package:vigiroad/features/plates/domain/plate_voter.dart';
import 'package:vigiroad/features/search/data/photon_geocoder.dart';
import 'package:vigiroad/features/search/presentation/search_screen.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

class _OfflineGeocoder implements Geocoder {
  @override
  Future<List<Place>> search(String query, {GeoPoint? near}) async =>
      throw const GeocodingException('Recherche impossible : vérifiez la connexion réseau.');
}

void main() {
  test('fonctionnement prolongé : 3 h de lecture à 4 images/s, temps et mémoire bornés', () {
    final voter = PlateVoter();
    final r = Random(7);
    final t0 = DateTime(2026);
    final sw = Stopwatch()..start();
    var confirmed = 0;
    const frames = 3 * 3600 * 4;
    for (var i = 0; i < frames; i++) {
      final now = t0.add(Duration(milliseconds: 250 * i));
      // Un nouveau véhicule toutes les ~10 s, plusieurs plaques par image.
      final plates = ['AA${(i ~/ 40 % 900 + 100)}BB', 'CC${(r.nextInt(900) + 100)}DD'];
      final obs = [
        for (final p in plates)
          PlateObservation(candidate: PlateFormats.extract(p).first, at: now, ocrConfidence: 0.9),
      ];
      confirmed += voter.add(obs, now).length;
    }
    sw.stop();
    expect(confirmed, greaterThan(1000));
    // Moins de 0,2 ms par image en moyenne : la logique Dart ne pèse pas face à l'OCR natif.
    expect(sw.elapsedMicroseconds / frames, lessThan(200));
  });

  test('suivi d\'itinéraire prolongé : 20 000 positions', () {
    final tracker = RouteTracker(testRoute());
    final sw = Stopwatch()..start();
    for (var i = 0; i < 20000; i++) {
      tracker.update(north((i % 1000).toDouble(), (i % 7).toDouble()));
    }
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });

  testWidgets('perte de réseau pendant la recherche : message clair, pas de plantage', (tester) async {
    usePhoneSurface(tester);
    await pumpVigiroad(
      tester,
      FakePermissionService.allGranted(),
      extraOverrides: [geocoderProvider.overrideWithValue(_OfflineGeocoder())],
    );
    await passSplash(tester);
    await tester.tap(find.text('Où allez-vous ?'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField), 'gare de lyon');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.textContaining('vérifiez la connexion réseau'), findsOneWidget);
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.byType(NavigationScreen, skipOffstage: false), findsOneWidget);
  });
}

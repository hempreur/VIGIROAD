import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/features/navigation/application/navigation_providers.dart';
import 'package:vigiroad/features/navigation/application/navigation_session.dart';
import 'package:vigiroad/features/navigation/domain/geo_fix.dart';
import 'package:vigiroad/features/navigation/presentation/navigation_screen.dart';
import 'package:vigiroad/features/plates/application/plate_scanning_controller.dart';
import 'package:vigiroad/features/plates/application/plates_providers.dart';
import 'package:vigiroad/features/plates/application/watchlist_controller.dart';
import 'package:vigiroad/features/plates/domain/watch_entry.dart';
import 'package:vigiroad/features/sentrix/application/sentrix_controller.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

/// Phase 7 : guidage, lecture des plaques, alerte et SENTRIX en même temps
/// sur un seul écran.
void main() {
  testWidgets('navigation + caméra + alerte + SENTRIX simultanés', (tester) async {
    usePhoneSurface(tester);
    final location = FakeLocationSource(fixAt(north(0)));
    final scanner = FakePlateScanner();
    final speaker = FakeSpeaker();
    final watchlist = MemoryWatchlist()..map['AA123BB'] = const WatchEntry(plate: 'AA123BB', category: 'Surveillance');
    await pumpVigiroad(
      tester,
      FakePermissionService.allGranted(),
      location: location,
      scanner: scanner,
      speaker: speaker,
      watchlist: watchlist,
    );
    await passSplash(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(NavigationScreen)));
    await c.read(watchlistProvider.future);

    // 1. Guidage vers une destination.
    c.read(destinationProvider.notifier).set(
      Destination(label: 'Arrivée', detail: '', point: testRoute().geometry.last),
    );
    await tester.pump();
    await tester.pump();
    expect(c.read(navigationSessionProvider).status, NavStatus.guiding);

    // 2. Lecture des plaques activée pendant le guidage.
    await c.read(plateScanningProvider.notifier).start();
    await tester.pump();
    expect(c.read(plateScanningProvider).status, ScanStatus.running);

    // 3. Le véhicule avance, une plaque surveillée apparaît.
    location.push(fixAt(north(300)));
    for (var i = 0; i < 3; i++) {
      scanner.push(['AA-123-BB']);
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pump();

    // L'alerte s'affiche SANS masquer la consigne de guidage.
    expect(c.read(activeAlertProvider)?.reading.normalized, 'AA123BB');
    expect(find.text('Plaque détectée dans la liste de surveillance'), findsOneWidget);
    expect(find.text('Tournez à droite sur Avenue Victoria'), findsOneWidget);
    expect(c.read(navigationSessionProvider).status, NavStatus.guiding);
    expect(c.read(plateScanningProvider).status, ScanStatus.running);

    // 4. SENTRIX reste disponible.
    final r = await c.read(sentrixProvider.notifier).execute('lire la dernière alerte');
    expect(r.reply, contains('A A , 1 2 3 , B B'));

    // 5. Le guidage continue de suivre la position.
    location.push(fixAt(north(600)));
    await tester.pump();
    expect(c.read(navigationSessionProvider).progress!.alongM, closeTo(600, 5));

    // Toutes les annonces sont passées par une seule voix, guidage compris.
    expect(speaker.spoken.first, startsWith('Guidage démarré'));
    expect(speaker.spoken.any((s) => s.startsWith('Alerte. Plaque')), isTrue);
    expect(speaker.spoken.last, startsWith('Dernière alerte'));
    expect(c.read(positionProvider).value?.point, isA<GeoPoint>());
  });
}

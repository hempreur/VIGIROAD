import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/app/providers.dart';
import 'package:vigiroad/core/permissions/permission_service.dart';
import 'package:vigiroad/features/plates/application/plate_scanning_controller.dart';
import 'package:vigiroad/features/plates/application/plates_providers.dart';
import 'package:vigiroad/features/plates/application/watchlist_controller.dart';
import 'package:vigiroad/features/plates/domain/watch_entry.dart';
import 'package:vigiroad/features/plates/data/plate_scanner.dart';
import 'package:vigiroad/features/plates/domain/plate_models.dart';

import '../helpers/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePlateScanner scanner;
  late FakePermissionService perms;
  late ProviderContainer c;
  var now = DateTime(2026, 10, 30, 15);

  setUp(() async {
    scanner = FakePlateScanner();
    final watchlist = MemoryWatchlist()..map['CC456DD'] = const WatchEntry(plate: 'CC456DD');
    perms = FakePermissionService.allGranted();
    now = DateTime(2026, 10, 30, 15);
    c = ProviderContainer(
      overrides: [
        plateScannerProvider.overrideWithValue(scanner),
        permissionServiceProvider.overrideWithValue(perms),
        scanClockProvider.overrideWithValue(() => now),
        watchlistRepositoryProvider.overrideWith((ref) async => watchlist),
      ],
    );
    c.listen(plateScanningProvider, (_, _) {});
    c.listen(watchlistIndexProvider, (_, _) {});
    await c.read(watchlistProvider.future);
  });
  tearDown(() => c.dispose());

  PlateScanningController ctrl() => c.read(plateScanningProvider.notifier);

  test('démarre la caméra et confirme une plaque après plusieurs images', () async {
    final confirmed = <PlateReading>[];
    ctrl().confirmed.listen(confirmed.add);
    await ctrl().start();
    expect(c.read(plateScanningProvider).status, ScanStatus.running);
    expect(scanner.starts, 1);

    for (var i = 0; i < 3; i++) {
      now = now.add(const Duration(milliseconds: 250));
      scanner.push(['F AA-123-BB'], at: now);
      await pumpEventQueue();
    }
    expect(confirmed.single.normalized, 'AA123BB');
    // Plaque ordinaire : lue et transmise, mais jamais affichée ni encadrée.
    expect(c.read(lastReadingProvider), isNull);
    expect(c.read(plateScanningProvider).boxes, isEmpty);
    expect(c.read(plateScanningProvider).tracked, 1);
  });

  test('plusieurs plaques sur la même image : toutes lues, seule la dangereuse encadrée', () async {
    final confirmed = <PlateReading>[];
    ctrl().confirmed.listen(confirmed.add);
    await ctrl().start();
    for (var i = 0; i < 3; i++) {
      now = now.add(const Duration(milliseconds: 250));
      scanner.push(['AA-123-BB', 'CC-456-DD', 'EE-789-FF'], at: now);
      await pumpEventQueue();
    }
    expect(confirmed.map((r) => r.normalized), unorderedEquals(['AA123BB', 'CC456DD', 'EE789FF']));
    final state = c.read(plateScanningProvider);
    expect(state.tracked, 3);
    expect(state.boxes, hasLength(1), reason: 'seule CC-456-DD est dans la liste');
    expect(state.boxes.single.left, closeTo(200 / 720, 1e-9));
  });

  test('deux lectures ne suffisent pas', () async {
    await ctrl().start();
    for (var i = 0; i < 2; i++) {
      scanner.push(['AA-123-BB'], at: now);
      await pumpEventQueue();
    }
    expect(c.read(lastReadingProvider), isNull);
  });

  test('caméra refusée : message, caméra non démarrée', () async {
    perms.statuses[AppCapability.camera] = CapabilityStatus.permanentlyDenied;
    await ctrl().start();
    expect(c.read(plateScanningProvider).status, ScanStatus.error);
    expect(c.read(plateScanningProvider).message, contains('Autorisez la caméra'));
    expect(scanner.starts, 0);
  });

  test('erreur caméra : message explicite', () async {
    scanner.startError = const ScannerException(ScannerIssue.noCamera);
    await ctrl().start();
    expect(c.read(plateScanningProvider).message, 'Aucune caméra arrière disponible.');
  });

  test('échecs OCR répétés : cause affichée, effacée à la lecture suivante', () async {
    await ctrl().start();
    scanner.pushError('PlatformException(MlKitException)');
    scanner.pushError('PlatformException(MlKitException)');
    await pumpEventQueue();
    expect(c.read(plateScanningProvider).ocrError, isNull, reason: 'deux échecs isolés sont tolérés');
    scanner.pushError('PlatformException(MlKitException)');
    await pumpEventQueue();
    expect(c.read(plateScanningProvider).ocrError, contains('MlKitException'));
    expect(c.read(plateScanningProvider).status, ScanStatus.running);

    scanner.push(['AA-123-BB'], at: now);
    await pumpEventQueue();
    expect(c.read(plateScanningProvider).ocrError, isNull);
  });

  test('arrêt : caméra libérée', () async {
    await ctrl().start();
    await ctrl().toggle();
    expect(c.read(plateScanningProvider).status, ScanStatus.off);
    expect(scanner.stops, greaterThanOrEqualTo(1));
  });

  test('faible luminosité signalée', () async {
    await ctrl().start();
    scanner.push([], brightness: 12);
    await pumpEventQueue();
    expect(c.read(plateScanningProvider).lowLight, isTrue);
  });
}

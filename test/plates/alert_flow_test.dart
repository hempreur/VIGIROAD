import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/app/providers.dart';
import 'package:vigiroad/features/navigation/application/navigation_providers.dart';
import 'package:vigiroad/features/navigation/application/navigation_session.dart';
import 'package:vigiroad/features/plates/application/alert_service.dart';
import 'package:vigiroad/features/plates/application/plate_scanning_controller.dart';
import 'package:vigiroad/features/plates/application/plates_providers.dart';
import 'package:vigiroad/features/plates/application/watchlist_controller.dart';
import 'package:vigiroad/features/plates/domain/alert_decider.dart';
import 'package:vigiroad/features/plates/domain/plate_models.dart';
import 'package:vigiroad/features/plates/domain/watch_entry.dart';
import 'package:vigiroad/features/plates/domain/watchlist_import.dart';

import '../helpers/fakes.dart';

/// Critère de validation de la phase 5 : une plaque fictive du fichier de
/// test provoque une alerte ; une plaque non répertoriée n'en provoque pas.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePlateScanner scanner;
  late MemoryDetectionLog log;
  late FakeSpeaker speaker;
  late FakeAlertSound sound;
  late ProviderContainer c;
  var now = DateTime(2026, 10, 30, 15);

  setUp(() async {
    scanner = FakePlateScanner();
    log = MemoryDetectionLog();
    speaker = FakeSpeaker();
    sound = FakeAlertSound();
    now = DateTime(2026, 10, 30, 15);
    c = ProviderContainer(
      overrides: [
        plateScannerProvider.overrideWithValue(scanner),
        permissionServiceProvider.overrideWithValue(FakePermissionService.allGranted()),
        scanClockProvider.overrideWithValue(() => now),
        clockProvider.overrideWithValue(() => now),
        watchlistRepositoryProvider.overrideWith((ref) async => MemoryWatchlist()),
        detectionLogProvider.overrideWith((ref) async => log),
        speakerProvider.overrideWithValue(speaker),
        alertSoundProvider.overrideWithValue(sound),
        locationSourceProvider.overrideWithValue(FakeLocationSource(testFix())),
      ],
    );
    c.listen(alertServiceProvider, (_, _) {});
    c.listen(positionProvider, (_, _) {});
    await c.read(watchlistProvider.future);
    await c.read(watchlistProvider.notifier).importReport(parseWatchlist(
      'plate,country,category,priority\nAA123BB,FR,Surveillance,high\nCC456DD,FR,Surveillance,medium\n',
    ));
    await c.read(plateScanningProvider.notifier).start();
    await pumpEventQueue();
  });
  tearDown(() => c.dispose());

  Future<void> see(String plateText, {int frames = 3}) async {
    for (var i = 0; i < frames; i++) {
      now = now.add(const Duration(milliseconds: 250));
      scanner.push([plateText], at: now);
      await pumpEventQueue();
    }
  }

  test('plaque du fichier : encadré, son, annonce SENTRIX, historique', () async {
    await see('F AA-123-BB');
    final alert = c.read(activeAlertProvider);
    expect(alert?.reading.display, 'AA-123-BB');
    expect(alert?.category, 'Surveillance');
    expect(alert?.priority, WatchPriority.high);
    expect(sound.plays, 1);
    expect(speaker.spoken.single, startsWith('Alerte. Plaque A A , 1 2 3 , B B.'));
    expect(log.records.single.plate, 'AA123BB');
    expect(log.records.single.latitude, closeTo(48.8566, 1e-6));
  });

  test('plaque non répertoriée : aucune alerte, aucune trace', () async {
    await see('EE-789-FF');
    expect(c.read(lastReadingProvider)?.normalized, 'EE789FF', reason: 'bien lue…');
    expect(c.read(activeAlertProvider), isNull, reason: '…mais absente de la liste');
    expect(sound.plays, 0);
    expect(log.records, isEmpty);
    expect(c.read(alertServiceProvider).single, isA<NotListed>());
  });

  test('lecture insuffisante (2 images) : aucune alerte', () async {
    await see('AA-123-BB', frames: 2);
    expect(c.read(activeAlertProvider), isNull);
  });

  test('pas d\'alerte répétée pour la même plaque', () async {
    await see('AA-123-BB');
    now = now.add(const Duration(seconds: 30));
    await see('AA-123-BB', frames: 4);
    expect(sound.plays, 1);
    expect(log.records, hasLength(1));
  });

  test('décideur : seuil de confiance et délai', () {
    final d = AlertDecider(const AlertPolicy(minConfidence: 0.9, cooldown: Duration(minutes: 5)));
    const entry = WatchEntry(plate: 'AA123BB');
    WatchEntry? lookup(String p) => p == 'AA123BB' ? entry : null;
    const weak = PlateReading(normalized: 'AA123BB', display: 'AA-123-BB', confidence: 0.85);
    const strong = PlateReading(normalized: 'AA123BB', display: 'AA-123-BB', confidence: 0.95);
    const other = PlateReading(normalized: 'EE789FF', display: 'EE-789-FF', confidence: 0.99);
    expect(d.examine(weak, lookup, now), isA<LowConfidence>());
    expect(d.examine(other, lookup, now), isA<NotListed>());
    expect(d.examine(strong, lookup, now), isA<Raise>());
    expect(d.examine(strong, lookup, now.add(const Duration(minutes: 4))), isA<Suppressed>());
    expect(d.examine(strong, lookup, now.add(const Duration(minutes: 6))), isA<Raise>());
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vigiroad/features/history/presentation/history_screen.dart';
import 'package:vigiroad/features/navigation/presentation/navigation_screen.dart';
import 'package:vigiroad/features/plates/data/repositories.dart';
import 'package:vigiroad/features/plates/domain/plate_models.dart';
import 'package:vigiroad/features/settings/domain/app_settings.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

DetectionRecord rec(String plate, DateTime at, {WatchPriority p = WatchPriority.high, String cat = 'Surveillance'}) =>
    DetectionRecord(plate: plate, display: plate, country: 'FR', category: cat, priority: p, confidence: 0.92, at: at, latitude: 48.85, longitude: 2.35);

void main() {
  final now = DateTime.now();
  final data = [
    rec('AA123BB', now.subtract(const Duration(hours: 1))),
    rec('CC456DD', now.subtract(const Duration(days: 3)), p: WatchPriority.low, cat: 'Flotte'),
    rec('EE789FF', now.subtract(const Duration(days: 20))),
    rec('GH321JK', now.subtract(const Duration(days: 60)), p: WatchPriority.medium),
  ];

  group('filtres', () {
    List<String> f({String q = '', HistoryPeriod p = HistoryPeriod.all, WatchPriority? prio}) =>
        filterDetections(data, query: q, period: p, priority: prio, now: now).map((d) => d.plate).toList();

    test('période', () {
      expect(f(p: HistoryPeriod.week), ['AA123BB', 'CC456DD']);
      expect(f(p: HistoryPeriod.month), ['AA123BB', 'CC456DD', 'EE789FF']);
      expect(f(), hasLength(4));
    });
    test('priorité', () => expect(f(prio: WatchPriority.low), ['CC456DD']));
    test('recherche plaque (tirets ignorés) et catégorie', () {
      expect(f(q: 'aa-123'), ['AA123BB']);
      expect(f(q: 'flotte'), ['CC456DD']);
    });
  });

  test('export CSV', () {
    final csv = exportDetectionsCsv([data.first]);
    expect(csv.split('\n').first, 'date,plate,country,category,priority,confidence,latitude,longitude');
    expect(csv, contains('AA123BB,FR,Surveillance,high,0.92,48.850000,2.350000'));
  });

  Future<MemoryDetectionLog> openHistory(WidgetTester tester, {AppSettings settings = const AppSettings()}) async {
    usePhoneSurface(tester);
    final log = MemoryDetectionLog();
    for (final d in data.reversed) {
      await log.add(d);
    }
    await pumpVigiroad(tester, FakePermissionService.allGranted(), detections: log, settings: MemorySettingsStore(settings));
    await passSplash(tester);
    GoRouter.of(tester.element(find.byType(NavigationScreen))).push('/history').ignore();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    await tester.pump();
    return log;
  }

  testWidgets('conservation appliquée à l\'ouverture', (tester) async {
    final log = await openHistory(tester, settings: const AppSettings(retention: Retention.days30));
    expect(log.records.map((r) => r.plate), isNot(contains('GH321JK')));
    expect(find.text('3 / 3 correspondance(s)'), findsOneWidget);
  });

  testWidgets('filtre par période et export autorisé', (tester) async {
    await openHistory(tester, settings: const AppSettings(retention: Retention.unlimited, allowExport: true));
    await tester.tap(find.text('7 jours'));
    await tester.pump();
    expect(find.text('2 / 4 correspondance(s)'), findsOneWidget);
    await tester.tap(find.text('Exporter'));
    await tester.pump();
    expect(savedFiles['vigiroad_historique.csv'], contains('CC456DD'));
  });

  testWidgets('export masqué par défaut', (tester) async {
    await openHistory(tester);
    expect(find.text('Exporter'), findsNothing);
  });

  testWidgets('purge confirmée', (tester) async {
    final log = await openHistory(tester);
    await tester.tap(find.byTooltip('Effacer l\'historique'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Effacer'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(log.records, isEmpty);
    expect(find.text('Aucune détection enregistrée'), findsOneWidget);
    expect(ProviderScope.containerOf(tester.element(find.byType(HistoryScreen))), isNotNull);
  });
}

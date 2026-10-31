import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vigiroad/features/navigation/presentation/navigation_screen.dart';
import 'package:vigiroad/features/plates/domain/watch_entry.dart';
import 'package:vigiroad/features/settings/domain/app_settings.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

Future<MemorySettingsStore> openSettings(WidgetTester tester, {MemoryWatchlist? watchlist, MemoryDetectionLog? log}) async {
  usePhoneSurface(tester);
  final store = MemorySettingsStore();
  await pumpVigiroad(tester, FakePermissionService.allGranted(), settings: store, watchlist: watchlist, detections: log);
  await passSplash(tester);
  GoRouter.of(tester.element(find.byType(NavigationScreen))).push('/settings').ignore();
  await tester.pump(const Duration(milliseconds: 700));
  return store;
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  final list = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(f, 200, scrollable: list);
  // Amène l'élément au milieu de la liste : tout juste visible, il peut être
  // masqué par l'en-tête ou le bas d'écran et ne pas recevoir le tap.
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await tester.pump();
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('interrupteurs et choix persistés', (tester) async {
    final store = await openSettings(tester);
    await tapText(tester, 'Démarrer la lecture automatiquement');
    expect(store.value.autoStartDetection, isTrue);
    await tapText(tester, 'Économie');
    expect(store.value.performance, PerformanceMode.economy);
    await tapText(tester, 'Son d\'alerte');
    expect(store.value.alertSound, isFalse);
    expect(find.text('Volume'), findsNothing, reason: 'volume masqué sans son');
    await tapText(tester, '7 jours');
    expect(store.value.retention, Retention.days7);
  });

  testWidgets('export de la liste et effacements confirmés', (tester) async {
    final watchlist = MemoryWatchlist()..map['AA123BB'] = const WatchEntry(plate: 'AA123BB');
    final log = MemoryDetectionLog();
    await openSettings(tester, watchlist: watchlist, log: log);

    await tapText(tester, 'Exporter la liste de plaques (CSV)');
    await tester.pump();
    expect(savedFiles['vigiroad_plaques.csv'], contains('AA123BB'));

    await tapText(tester, 'Supprimer toutes les plaques');
    await tester.tap(find.text('Supprimer').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(watchlist.map, isEmpty);
  });

  testWidgets('réinitialisation', (tester) async {
    final store = await openSettings(tester);
    await tapText(tester, 'Vue conduite 3D par défaut');
    expect(store.value.drive3d, isFalse);
    await tapText(tester, 'Réinitialiser les réglages');
    await tester.tap(find.text('Réinitialiser').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(store.value.drive3d, isTrue);
  });
}

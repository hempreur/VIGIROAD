import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/app/providers.dart';
import 'package:vigiroad/features/navigation/application/navigation_providers.dart';
import 'package:vigiroad/features/navigation/application/navigation_session.dart';
import 'package:vigiroad/features/reports/application/reports_controller.dart';
import 'package:vigiroad/features/reports/data/reports_client.dart';
import 'package:vigiroad/features/reports/presentation/chicken_button.dart';
import 'package:vigiroad/features/sentrix/application/sentrix_controller.dart';
import 'package:vigiroad/features/settings/application/settings_controller.dart';
import 'package:vigiroad/features/settings/domain/app_settings.dart';
import 'package:vigiroad_traffic/vigiroad_traffic.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

class FakeReportsClient implements ReportsClient {
  final reports = <ChickenReport>[];
  final submitted = <({LatLng position, double? heading, ReportSide side})>[];
  final boxes = <BBox>[];
  ReportsException? error;
  DateTime now = DateTime(2026, 10, 30, 14, 27);

  @override
  Future<List<ChickenReport>> inBox(BBox box) async {
    boxes.add(box);
    if (error != null) throw error!;
    return [for (final r in reports) if (box.contains(r.position)) r];
  }

  @override
  Future<ChickenReport> submit({required LatLng position, double? heading, required ReportSide side}) async {
    if (error != null) throw error!;
    submitted.add((position: position, heading: heading, side: side));
    final r = ChickenReport(
      id: 'r${submitted.length}',
      position: position,
      heading: heading == null ? null : (side == ReportSide.mine ? heading : (heading + 180) % 360),
      side: side,
      createdAt: now,
      expiresAt: now.add(ChickenReport.lifetime),
    );
    reports.add(r);
    return r;
  }
}

ChickenReport report(String id, LatLng at, {double? heading = 12, DateTime? created}) {
  final t = created ?? DateTime(2026, 10, 30, 14);
  return ChickenReport(id: id, position: at, heading: heading, side: ReportSide.mine, createdAt: t, expiresAt: t.add(ChickenReport.lifetime));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('modèle', () {
    test('écart de cap et cap entre deux points', () {
      expect(headingDelta(350, 10), 20);
      expect(headingDelta(90, 270), 180);
      expect(bearing(const LatLng(48, 2), const LatLng(49, 2)), closeTo(0, 0.01));
      expect(bearing(const LatLng(48, 2), const LatLng(48, 3)), closeTo(90, 0.5));
    });

    test('JSON aller-retour', () {
      final r = report('a', const LatLng(48.85, 2.35));
      final back = ChickenReport.fromJson(r.toJson());
      expect(back.position, r.position);
      expect(back.heading, 12);
      expect(back.expiresAt, r.expiresAt.toUtc());
    });
  });

  group('contrôleur', () {
    late FakeReportsClient client;
    late FakeSpeaker speaker;
    late ProviderContainer c;
    final now = DateTime(2026, 10, 30, 14, 27);

    setUp(() async {
      client = FakeReportsClient();
      speaker = FakeSpeaker();
      c = ProviderContainer(
        overrides: [
          reportsClientProvider.overrideWithValue(client),
          locationSourceProvider.overrideWithValue(FakeLocationSource(testFix())),
          permissionServiceProvider.overrideWithValue(FakePermissionService.allGranted()),
          clockProvider.overrideWithValue(() => now),
          speakerProvider.overrideWithValue(speaker),
          settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
          sentrixBubbleDurationProvider.overrideWithValue(Duration.zero),
        ],
      );
      await c.read(settingsControllerProvider.future);
      c.listen(positionProvider, (_, _) {});
      c.listen(reportsProvider, (_, _) {});
    });
    tearDown(() => c.dispose());

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await pumpEventQueue();
      }
    }

    test('marqueurs de la zone, expirés retirés', () async {
      client.reports
        ..add(report('proche', const LatLng(48.80, 2.30)))
        ..add(report('vieux', const LatLng(48.80, 2.31), created: DateTime(2026, 10, 30, 12)))
        ..add(report('lyon', const LatLng(45.76, 4.83)));
      await settle();
      await c.read(reportsProvider.notifier).refresh();
      expect(c.read(reportsProvider).reports.map((r) => r.id), ['proche']);
    });

    test('signalement « ma route » : position et cap envoyés, marqueur immédiat', () async {
      await settle();
      final res = await c.read(reportsProvider.notifier).submit(ReportSide.mine);
      expect(res, isA<Submitted>());
      final sent = client.submitted.single;
      expect(sent.side, ReportSide.mine);
      expect(sent.heading, 12);
      expect(sent.position.lat, closeTo(48.8566, 1e-9));
      expect(c.read(reportsProvider).reports, hasLength(1));
      expect(speaker.spoken, isEmpty, reason: 'son propre signalement n\'est pas annoncé');
    });

    test('à l\'arrêt : cap inconnu', () async {
      c.dispose();
      c = ProviderContainer(
        overrides: [
          reportsClientProvider.overrideWithValue(client),
          locationSourceProvider.overrideWithValue(FakeLocationSource(testFix(kmh: 0))),
          permissionServiceProvider.overrideWithValue(FakePermissionService.allGranted()),
          settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
        ],
      );
      c.listen(positionProvider, (_, _) {});
      c.listen(reportsProvider, (_, _) {});
      await settle();
      await c.read(reportsProvider.notifier).submit(ReportSide.opposite);
      expect(client.submitted.single.heading, isNull);
    });

    test('Chicken devant sur ma route : annoncé une seule fois', () async {
      // ≈ 800 m au nord (cap 12°).
      client.reports.add(report('devant', const LatLng(48.8637, 2.3542)));
      // Derrière : jamais annoncé.
      client.reports.add(report('derriere', const LatLng(48.8500, 2.3510)));
      await settle();
      await c.read(reportsProvider.notifier).refresh();
      await settle();
      expect(speaker.spoken.single, 'Attention, Chicken signalé sur votre route dans 800 mètres.');
      await c.read(reportsProvider.notifier).refresh();
      await settle();
      expect(speaker.spoken, hasLength(1));
    });

    test('route d\'en face annoncée comme telle', () {
      final r = report('x', const LatLng(48.86, 2.35), heading: 192);
      expect(ReportsController.announcement(r, 1230, 12), 'Attention, Chicken signalé sur la voie d\'en face dans 1,2 kilomètre.');
    });

    test('serveur injoignable : message, pas de plantage', () async {
      client.error = const ReportsException('Serveur injoignable');
      await settle();
      final res = await c.read(reportsProvider.notifier).submit(ReportSide.mine);
      expect((res as SubmitFailed).message, 'Serveur injoignable');
    });

    test('option désactivée : aucune requête', () async {
      await c.read(settingsControllerProvider.notifier).change((s) => s.copyWith(chickenReports: false));
      client.boxes.clear();
      await settle();
      await c.read(reportsProvider.notifier).refresh();
      expect(client.boxes, isEmpty);
      expect(c.read(reportsProvider).available, isFalse);
    });
  });

  group('écran', () {
    testWidgets('bouton Chicken → Ma route / Route en face → signalement envoyé', (tester) async {
      usePhoneSurface(tester);
      final client = FakeReportsClient();
      await pumpVigiroad(
        tester,
        FakePermissionService.allGranted(),
        location: FakeLocationSource(testFix()),
        settings: MemorySettingsStore(const AppSettings()),
        extraOverrides: [reportsClientProvider.overrideWithValue(client)],
      );
      await passSplash(tester);

      await tester.tap(find.byType(ChickenButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Signaler un Chicken'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
      expect(find.text('Ma route'), findsOneWidget);
      expect(find.text('Route en face'), findsOneWidget);

      await tester.tap(find.text('Route en face'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(client.submitted.single.side, ReportSide.opposite);
      expect(find.textContaining('Chicken signalé en face'), findsOneWidget);
    });

    testWidgets('dessin du bouton', (tester) async {
      await tester.pumpWidget(wrapDark(Center(child: ChickenButton(onPressed: () {}))));
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

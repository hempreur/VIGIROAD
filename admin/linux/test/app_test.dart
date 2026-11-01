import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigiroad_admin_core/testing.dart';
import 'package:vigiroad_admin_core/vigiroad_admin_core.dart';
import 'package:vigiroad_server_control/main.dart';

/// Polices réelles (Rajdhani, Inter, icônes) pour des captures fidèles.
Future<void> loadFonts() async {
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

Future<void> frames(WidgetTester t, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> precacheImages(WidgetTester tester) => tester.runAsync(() async {
  for (final e in find.byType(Image).evaluate()) {
    await precacheImage((e.widget as Image).image, e);
  }
});

class Harness {
  Harness(this.session, this.backend);
  final AdminSession session;
  final FakeAdminBackend backend;

  Future<void> close(WidgetTester tester) async {
    await session.logout();
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    backend.close();
  }
}

Future<Harness> start(
  WidgetTester tester, {
  bool setup = false,
  String role = 'owner',
  bool savedServer = true,
  DateTime Function()? clock,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    if (savedServer) 'admin.server': 'https://vps.vigiroad.test',
    'admin.email': 'proprietaire@vigiroad.fr',
  });
  final backend = FakeAdminBackend(needsSetup: setup, role: role);
  final session = AdminSession(clientName: 'linux', httpFactory: backend.client, clock: clock);
  // Carte du monde chargée hors de l'horloge simulée.
  await tester.runAsync(WorldData.load);
  final updater = DesktopUpdater(
    appId: 'server-control',
    currentVersion: appVersion,
    client: MockClient((_) async => http.Response('introuvable', 404)),
  );
  await tester.pumpWidget(buildApp(session: session, updater: updater));
  await frames(tester);
  await precacheImages(tester);
  await frames(tester, 3);
  return Harness(session, backend);
}

Future<void> login(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login-password')), 'MotDePasseAdmin2026');
  await tester.tap(find.byKey(const Key('login-submit')));
  await frames(tester);
  await tester.enterText(find.byKey(const Key('mfa-code')), '123456');
  await tester.tap(find.byKey(const Key('mfa-submit')));
  await frames(tester, 20);
  await precacheImages(tester);
  await frames(tester, 2);
}

Future<void> open(WidgetTester tester, String page) async {
  await tester.tap(find.byKey(Key('nav-$page')));
  await frames(tester, 20);
}

void main() {
  setUpAll(loadFonts);

  testWidgets('connexion puis supervision temps réel', (tester) async {
    final h = await start(tester);
    expect(find.text('VIGIROAD SERVER CONTROL'), findsOneWidget);
    await login(tester);
    h.backend.pushSnapshot();
    await frames(tester, 5);
    expect(find.text('SUPERVISION'), findsOneWidget);
    expect(find.text('PROCESSEUR'), findsOneWidget);
    expect(find.text('23 %'), findsOneWidget);
    expect(find.textContaining('Ubuntu 24.04.1 LTS'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/01_supervision.png'));
    await h.close(tester);
  });

  testWidgets('toutes les pages : processus, Docker, services, maintenance…', (tester) async {
    final h = await start(tester);
    await login(tester);
    h.backend.pushSnapshot();
    await frames(tester, 5);
    for (final (page, golden, text) in [
      ('processes', '02_processus', 'admin_api'),
      ('docker', '03_docker', 'admin-api'),
      ('vigiroad', '04_services_vigiroad', 'Bison Futé'),
      ('maintenance', '05_maintenance', 'Base PostgreSQL'),
      ('audit', '06_journal', 'connexion administrateur'),
      ('admins', '07_administrateurs', 'Propriétaire'),
      ('settings', '08_parametres', 'VIGIROAD INC (CODEX HEMPREUR)'),
    ]) {
      await open(tester, page);
      expect(find.textContaining(text), findsWidgets, reason: page);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$golden.png'));
    }
    await h.close(tester);
  });

  testWidgets('Docker : redémarrage contrôlé avec confirmation, journaux', (tester) async {
    final h = await start(tester);
    await login(tester);
    await open(tester, 'docker');
    await tester.tap(find.byKey(const Key('docker-restart-traffic')));
    await frames(tester);
    expect(find.textContaining('Redémarrer « traffic »'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Redémarrer'));
    await frames(tester);
    expect(h.backend.requests, contains('POST /admin/docker/containers/a1b2c3d4e5f6/restart'));
    expect(find.byKey(const Key('docker-stop-postgres')), findsNothing, reason: 'arrêt de PostgreSQL non proposé');
    await h.close(tester);
  });

  testWidgets('maintenance : sauvegarde à la demande', (tester) async {
    final h = await start(tester);
    await login(tester);
    await open(tester, 'maintenance');
    await tester.tap(find.byKey(const Key('backup-now')));
    await frames(tester);
    expect(h.backend.requests, contains('POST /admin/backups'));
    expect(find.text('Sauvegarde lancée'), findsOneWidget);
    await h.close(tester);
  });
}

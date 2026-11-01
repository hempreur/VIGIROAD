import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigiroad_admin_core/testing.dart';
import 'package:vigiroad_admin_core/vigiroad_admin_core.dart';
import 'package:vigiroad_admin_manager/main.dart';

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
  final session = AdminSession(clientName: 'windows', httpFactory: backend.client, clock: clock);
  // Carte du monde chargée hors de l'horloge simulée.
  await tester.runAsync(WorldData.load);
  final updater = DesktopUpdater(
    appId: 'admin-manager',
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

  testWidgets('connexion : mot de passe puis code TOTP', (tester) async {
    final h = await start(tester);
    expect(find.text('VIGIROAD ADMIN MANAGER'), findsOneWidget);
    expect(find.text('Connexion administrateur'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/00_connexion.png'));

    await tester.enterText(find.byKey(const Key('login-password')), 'mauvais');
    await tester.tap(find.byKey(const Key('login-submit')));
    await frames(tester);
    expect(find.text('Identifiant ou mot de passe incorrect'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-password')), 'MotDePasseAdmin2026');
    await tester.tap(find.byKey(const Key('login-submit')));
    await frames(tester);
    expect(find.text('Double authentification'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('mfa-code')), '000000');
    await tester.tap(find.byKey(const Key('mfa-submit')));
    await frames(tester);
    expect(find.text('Code de vérification incorrect'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('mfa-code')), '123456');
    await tester.tap(find.byKey(const Key('mfa-submit')));
    await frames(tester, 20);
    expect(find.text('TABLEAU DE BORD'), findsOneWidget);
    expect(h.backend.requests, contains('GET /admin/events'));
    await h.close(tester);
  });

  testWidgets('premier administrateur : jeton, compte, QR code TOTP', (tester) async {
    final h = await start(tester, setup: true, savedServer: false);
    await tester.enterText(find.byKey(const Key('server-url')), 'vps.vigiroad.test');
    await tester.tap(find.byKey(const Key('server-connect')));
    await frames(tester);
    expect(find.text('Créer le premier administrateur'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('setup-token')), 'jeton');
    await tester.enterText(find.byKey(const Key('setup-name')), 'Codex');
    await tester.enterText(find.byKey(const Key('setup-email')), 'proprietaire@vigiroad.fr');
    await tester.enterText(find.byKey(const Key('setup-password')), 'MotDePasseAdmin2026');
    await tester.enterText(find.byKey(const Key('setup-password2')), 'MotDePasseAdmin2026');
    await tester.ensureVisible(find.byKey(const Key('setup-submit')));
    await tester.tap(find.byKey(const Key('setup-submit')));
    await frames(tester);
    expect(find.text('Activer la double authentification'), findsOneWidget);
    expect(find.byKey(const Key('totp-secret')), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/00b_enrolement_totp.png'));
    await h.close(tester);
  });

  testWidgets('toutes les pages : tableau de bord, utilisateurs, appareils, sessions, géographie, serveur…', (tester) async {
    final h = await start(tester);
    await login(tester);
    h.backend.pushSnapshot();
    await frames(tester, 5);
    expect(find.text('37 connecté(s)'), findsOneWidget);
    expect(find.text('UTILISATEURS ENREGISTRÉS'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/01_tableau_de_bord.png'));

    await open(tester, 'users');
    expect(find.text('RouteurPro'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/02_utilisateurs.png'));

    await tester.tap(find.text('Camille_75 · Camille D.'));
    await frames(tester, 20);
    expect(find.text('Réinitialiser l\'accès'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/03_fiche_utilisateur.png'));

    await tester.tap(find.byKey(const Key('user-reset')));
    await frames(tester);
    await tester.tap(find.text('Générer le code'));
    await frames(tester);
    expect(find.text('K7QM-2XPA-W4ZT'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await frames(tester);
    expect(h.backend.requests.where((r) => r.endsWith('/reset-access')), hasLength(1));

    await tester.tap(find.byKey(const Key('user-back')));
    await frames(tester, 15);

    for (final (page, golden, text) in [
      ('devices', '04_appareils', 'Galaxy S24'),
      ('sessions', '05_sessions', 'CONNEXIONS SIMULTANÉES'),
      ('geo', '06_geographie', 'RÉPARTITION PAR PAYS'),
      ('server', '07_serveur', 'FLUX ROUTIERS'),
      ('audit', '08_journal', 'utilisateur désactivé'),
      ('admins', '09_administrateurs', 'support@vigiroad.fr'),
      ('settings', '10_parametres', 'VIGIROAD INC (CODEX HEMPREUR)'),
    ]) {
      await open(tester, page);
      expect(find.textContaining(text), findsWidgets, reason: page);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$golden.png'));
    }
    await h.close(tester);
  });

  testWidgets('alertes critiques notifiées en temps réel', (tester) async {
    final h = await start(tester);
    await login(tester);
    h.backend.pushSnapshot(alerts: [
      {'level': 'critical', 'id': 'disk', 'title': 'Disque presque plein', 'detail': 'Disque / utilisé à 94 %'},
    ]);
    await frames(tester, 5);
    expect(find.textContaining('Disque presque plein'), findsOneWidget);
    await tester.tap(find.byKey(const Key('alerts')));
    await frames(tester);
    expect(find.text('Alertes actives'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/11_alertes.png'));
    await tester.tap(find.text('Fermer'));
    await frames(tester);
    await h.close(tester);
  });

  testWidgets('rôle lecture seule : pas d\'actions ni de page Administrateurs', (tester) async {
    final h = await start(tester, role: 'viewer');
    await login(tester);
    expect(find.byKey(const Key('nav-admins')), findsNothing);
    await open(tester, 'users');
    expect(find.text('Exporter (CSV)'), findsNothing);
    await tester.tap(find.text('RouteurPro'));
    await frames(tester, 20);
    expect(find.byKey(const Key('user-disable')), findsNothing);
    expect(find.byKey(const Key('user-delete')), findsNothing);
    await h.close(tester);
  });

  testWidgets('verrouillage après inactivité', (tester) async {
    var now = DateTime(2026, 11, 1, 12);
    final h = await start(tester, clock: () => now);
    await login(tester);
    expect(find.text('TABLEAU DE BORD'), findsOneWidget);
    now = now.add(const Duration(minutes: 31));
    await tester.pump(const Duration(seconds: 31));
    await frames(tester, 10);
    expect(find.text('Connexion administrateur'), findsOneWidget);
    expect(find.textContaining('inactivité'), findsOneWidget);
    await h.close(tester);
  });
}

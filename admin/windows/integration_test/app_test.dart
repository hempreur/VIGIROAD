import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigiroad_admin_manager/main.dart';

/// Test de bout en bout de l'application native (Windows ou Linux) contre la
/// vraie API d'administration et une vraie base PostgreSQL :
///   flutter test integration_test -d windows --dart-define=VR_ADMIN_URL=http://127.0.0.1:8081 \
///     --dart-define=VR_SETUP_TOKEN=…
const adminUrl = String.fromEnvironment('VR_ADMIN_URL', defaultValue: 'http://127.0.0.1:8081');
const setupToken = String.fromEnvironment('VR_SETUP_TOKEN');

String totp(String secret, DateTime now) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final bytes = <int>[];
  var buffer = 0, bits = 0;
  for (final ch in secret.replaceAll(' ', '').toUpperCase().split('')) {
    buffer = ((buffer << 5) | alphabet.indexOf(ch)) & 0xffff;
    bits += 5;
    if (bits >= 8) {
      bytes.add((buffer >> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  final msg = ByteData(8)..setUint64(0, now.millisecondsSinceEpoch ~/ 30000);
  final h = Hmac(sha1, bytes).convert(msg.buffer.asUint8List()).bytes;
  final o = h.last & 0xf;
  final bin = ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  return (bin % 1000000).toString().padLeft(6, '0');
}

Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 40)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Introuvable après ${timeout.inSeconds} s : $f');
}

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ADMIN MANAGER : premier administrateur, TOTP, utilisateurs réels, actions', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildApp());
    await waitFor(tester, find.byKey(const Key('server-url')));

    await tester.enterText(find.byKey(const Key('server-url')), adminUrl);
    await tester.tap(find.byKey(const Key('server-connect')));
    await waitFor(tester, find.byKey(const Key('setup-token')));

    await tester.enterText(find.byKey(const Key('setup-token')), setupToken);
    await tester.enterText(find.byKey(const Key('setup-name')), 'Codex');
    await tester.enterText(find.byKey(const Key('setup-email')), 'proprietaire@vigiroad.test');
    await tester.enterText(find.byKey(const Key('setup-password')), 'MotDePasseAdmin2026');
    await tester.enterText(find.byKey(const Key('setup-password2')), 'MotDePasseAdmin2026');
    await tester.ensureVisible(find.byKey(const Key('setup-submit')));
    await tester.tap(find.byKey(const Key('setup-submit')));
    await waitFor(tester, find.byKey(const Key('totp-secret')));

    final secret = (tester.widget(find.byKey(const Key('totp-secret'))) as SelectableText).data!;
    await tester.enterText(find.byKey(const Key('mfa-code')), totp(secret, DateTime.now()));
    await tester.ensureVisible(find.byKey(const Key('mfa-submit')));
    await tester.tap(find.byKey(const Key('mfa-submit')));
    await waitFor(tester, find.text('TABLEAU DE BORD'));
    await waitFor(tester, find.text('UTILISATEURS ENREGISTRÉS'));
    // Comptes créés par la CI avant le test (inscription par l'API mobile).
    await waitFor(tester, find.textContaining('connecté(s)'));

    await tester.tap(find.byKey(const Key('nav-users')));
    await waitFor(tester, find.textContaining('ci_mobile_1'));
    await tester.tap(find.textContaining('ci_mobile_1').first);
    await waitFor(tester, find.byKey(const Key('user-disable')));
    expect(find.textContaining('Galaxy S24'), findsWidgets);

    await tester.tap(find.byKey(const Key('user-disable')));
    await settle(tester, 600);
    await tester.tap(find.widgetWithText(FilledButton, 'Désactiver'));
    await waitFor(tester, find.byKey(const Key('user-enable')));
    await tester.tap(find.byKey(const Key('user-enable')));
    await waitFor(tester, find.byKey(const Key('user-disable')));

    await tester.tap(find.byKey(const Key('user-back')));
    await settle(tester);
    for (final (page, text) in [
      ('devices', 'Galaxy S24'),
      ('sessions', 'ÉCHECS D\'AUTHENTIFICATION'),
      ('geo', 'CARTE DES UTILISATEURS'),
      ('server', 'Base PostgreSQL'),
      ('audit', 'utilisateur réactivé'),
      ('admins', 'proprietaire@vigiroad.test'),
      ('settings', 'Conservation des données'.toUpperCase()),
    ]) {
      await tester.tap(find.byKey(Key('nav-$page')));
      await waitFor(tester, find.textContaining(text));
    }

    await tester.tap(find.byKey(const Key('logout')));
    await waitFor(tester, find.text('Connexion administrateur'));
  });
}

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigiroad_server_control/main.dart';

/// Test de bout en bout de l'application native (Windows ou Linux) contre la
/// vraie API d'administration et une vraie base PostgreSQL :
///   flutter test integration_test -d linux --dart-define=VR_ADMIN_URL=http://127.0.0.1:8081 \
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

  testWidgets('SERVER CONTROL : TOTP, métriques réelles, Docker réel, services, sauvegarde', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildApp());
    await waitFor(tester, find.byKey(const Key('server-url')));

    await tester.enterText(find.byKey(const Key('server-url')), adminUrl);
    await tester.tap(find.byKey(const Key('server-connect')));
    await waitFor(tester, find.byKey(const Key('setup-token')));
    await tester.enterText(find.byKey(const Key('setup-token')), setupToken);
    await tester.enterText(find.byKey(const Key('setup-name')), 'Opérateur CI');
    await tester.enterText(find.byKey(const Key('setup-email')), 'serveur@vigiroad.test');
    await tester.enterText(find.byKey(const Key('setup-password')), 'MotDePasseAdmin2026');
    await tester.enterText(find.byKey(const Key('setup-password2')), 'MotDePasseAdmin2026');
    await tester.ensureVisible(find.byKey(const Key('setup-submit')));
    await tester.tap(find.byKey(const Key('setup-submit')));
    await waitFor(tester, find.byKey(const Key('totp-secret')));
    final secret = (tester.widget(find.byKey(const Key('totp-secret'))) as SelectableText).data!;
    await tester.enterText(find.byKey(const Key('mfa-code')), totp(secret, DateTime.now()));
    await tester.ensureVisible(find.byKey(const Key('mfa-submit')));
    await tester.tap(find.byKey(const Key('mfa-submit')));

    // Supervision : mesures réelles de la machine (agent local).
    await waitFor(tester, find.text('SUPERVISION'));
    await waitFor(tester, find.textContaining('mis à jour'));
    await waitFor(tester, find.text('Nom d\'hôte'));

    await tester.tap(find.byKey(const Key('nav-processes')));
    await waitFor(tester, find.text('SERVICES ACTIFS'));

    // Docker : conteneur de démonstration du projet, redémarrage contrôlé.
    await tester.tap(find.byKey(const Key('nav-docker')));
    await waitFor(tester, find.byKey(const Key('docker-restart-traffic')));
    await tester.tap(find.byKey(const Key('docker-restart-traffic')));
    await settle(tester, 600);
    await tester.tap(find.widgetWithText(FilledButton, 'Redémarrer'));
    await waitFor(tester, find.textContaining('Redémarrer : traffic'), timeout: const Duration(seconds: 90));

    await tester.tap(find.byKey(const Key('nav-vigiroad')));
    await waitFor(tester, find.textContaining('Bison Futé'));
    await waitFor(tester, find.text('Base PostgreSQL'));

    await tester.tap(find.byKey(const Key('nav-maintenance')));
    await waitFor(tester, find.textContaining('Agent de supervision'));
    await tester.tap(find.byKey(const Key('backup-now')));
    await waitFor(tester, find.text('Sauvegarde lancée'));

    await tester.tap(find.byKey(const Key('nav-audit')));
    await waitFor(tester, find.text('conteneur redémarré'));

    await tester.tap(find.byKey(const Key('logout')));
    await waitFor(tester, find.text('Connexion administrateur'));
  });
}

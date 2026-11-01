import 'dart:convert';

import 'package:test/test.dart';
import 'package:vigiroad_admin_api/admin_api.dart';

void main() {
  group('TOTP (RFC 6238)', () {
    // Secret de test de la RFC : « 12345678901234567890 » en ASCII.
    final secret = base32Encode(utf8.encode('12345678901234567890'));

    test('vecteurs officiels (6 derniers chiffres)', () {
      expect(secret, 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
      final cases = {59: '287082', 1111111109: '081804', 1111111111: '050471', 1234567890: '005924', 2000000000: '279037'};
      cases.forEach((t, code) {
        expect(Totp.code(secret, Totp.step(DateTime.fromMillisecondsSinceEpoch(t * 1000))), code, reason: 't=$t');
      });
    });

    test('tolérance d\'un pas, code à usage unique', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1111111109 * 1000);
      final s = Totp.step(now);
      expect(Totp.verify(secret, '081804', now), s);
      expect(Totp.verify(secret, Totp.code(secret, s - 1), now), s - 1);
      expect(Totp.verify(secret, Totp.code(secret, s + 1), now), s + 1);
      expect(Totp.verify(secret, Totp.code(secret, s + 2), now), isNull);
      expect(Totp.verify(secret, '081804', now, lastStep: s), isNull, reason: 'déjà utilisé');
      expect(Totp.verify(secret, '08 18 04', now), s);
      expect(Totp.verify(secret, 'abcdef', now), isNull);
    });

    test('URI otpauth pour les applications d\'authentification', () {
      final uri = Uri.parse(Totp.uri('ABC', 'admin@vigiroad.fr'));
      expect(uri.scheme, 'otpauth');
      expect(uri.queryParameters['secret'], 'ABC');
      expect(uri.queryParameters['issuer'], 'VIGIROAD');
    });

    test('base32 aller-retour', () {
      for (final n in [1, 5, 10, 20, 33]) {
        final bytes = randomBytes(n);
        expect(base32Decode(base32Encode(bytes)), bytes);
      }
    });
  });

  group('mots de passe', () {
    const hasher = PasswordHasher(memoryKb: 1024, iterations: 1);

    test('Argon2id : vérification, sel aléatoire, format PHC', () async {
      final h1 = await hasher.hash('Motdepasse1');
      final h2 = await hasher.hash('Motdepasse1');
      expect(h1, startsWith(r'$argon2id$v=19$m=1024,t=1,p=1$'));
      expect(h1, isNot(h2), reason: 'sel différent');
      expect(h1, isNot(contains('Motdepasse1')));
      expect(await hasher.verify('Motdepasse1', h1), isTrue);
      expect(await hasher.verify('motdepasse1', h1), isFalse);
      expect(await hasher.verify('Motdepasse1', 'pas-un-hash'), isFalse);
    });

    test('paramètres lus depuis l\'empreinte (changement de coût sans casse)', () async {
      final old = await const PasswordHasher(memoryKb: 512, iterations: 2).hash('Ancien123');
      expect(await hasher.verify('Ancien123', old), isTrue);
    });

    test('règles minimales', () {
      expect(PasswordHasher.validate('court1'), isNotNull);
      expect(PasswordHasher.validate('sanschiffre'), isNotNull);
      expect(PasswordHasher.validate('12345678'), isNotNull);
      expect(PasswordHasher.validate('Valide123'), isNull);
    });
  });

  test('chiffrement des secrets (AES-256-GCM)', () async {
    final boxer = SecretBoxer(List.generate(32, (i) => i));
    final sealed = await boxer.seal('JBSWY3DPEHPK3PXP');
    expect(sealed, isNot(contains('JBSWY3DPEHPK3PXP')));
    expect(await boxer.open(sealed), 'JBSWY3DPEHPK3PXP');
    expect(await boxer.seal('x'), isNot(await boxer.seal('x')), reason: 'nonce aléatoire');
    final other = SecretBoxer(List.generate(32, (i) => 31 - i));
    await expectLater(other.open(sealed), throwsA(anything), reason: 'mauvaise clé refusée');
  });

  test('adresses IP réduites au réseau', () {
    expect(ipPrefix('203.0.113.42'), '203.0.113.0/24');
    expect(ipPrefix('2001:db8:abcd:12::1'), '2001:db8:abcd::/48');
    expect(ipPrefix('::1'), '0:0:0::/48');
    expect(ipPrefix(null), isNull);
    expect(ipPrefix('pas une ip'), isNull);
  });

  test('jetons : longs, aléatoires, empreinte stable', () {
    final t = newToken('vrs');
    expect(t, startsWith('vrs_'));
    expect(t.length, greaterThan(40));
    expect(newToken('vrs'), isNot(t));
    expect(sha256Hex(t), hasLength(64));
    expect(sha256Hex(t), sha256Hex(t));
  });

  group('GeoIP', () {
    final geo = GeoIp.parse([
      '2.0.0.0,2.15.255.255,FR',
      '1.0.0.0,1.0.0.255,AU',
      '"5.0.0.0","5.0.255.255","DE"',
      '2001:db8::,2001:db8:ffff:ffff:ffff:ffff:ffff:ffff,FR',
      '2a00::,2a00:ffff:ffff:ffff:ffff:ffff:ffff:ffff,GB',
      '10.0.0.0,10.255.255.255,ZZ',
    ]);

    test('pays des adresses IPv4 et IPv6', () {
      expect(geo.available, isTrue);
      expect(geo.country('2.3.4.5'), 'FR');
      expect(geo.country('1.0.0.7'), 'AU');
      expect(geo.country('5.0.12.1'), 'DE');
      expect(geo.country('2001:db8:1::5'), 'FR');
      expect(geo.country('2a00:1450::1'), 'GB');
    });

    test('inconnu hors plages, pour ZZ et sans base', () {
      expect(geo.country('3.3.3.3'), isNull);
      expect(geo.country('10.1.1.1'), isNull);
      expect(geo.country('n/a'), isNull);
      expect(GeoIp.empty().country('2.3.4.5'), isNull);
    });
  });

  group('routeur', () {
    final r = Router()
      ..get('/admin/users', (req, p) => throw UnimplementedError())
      ..post('/admin/users/:id/disable', (req, p) => throw UnimplementedError());

    test('paramètres et modèle de route', () {
      final m = r.match('POST', '/admin/users/abc/disable');
      expect(m!.$2, {'id': 'abc'});
      expect(m.$3, '/admin/users/:id/disable');
      expect(r.match('GET', '/admin/nope'), isNull);
    });

    test('405 si la méthode ne correspond pas', () {
      expect(() => r.match('DELETE', '/admin/users'), throwsA(isA<ApiError>().having((e) => e.status, 'status', 405)));
    });
  });

  test('statistiques de requêtes par minute', () {
    var now = DateTime.utc(2026, 11, 1, 10, 0, 5);
    final s = RequestStats(clock: () => now);
    for (var i = 1; i <= 10; i++) {
      s.record('/v1/x', Duration(milliseconds: i * 10), error: i == 10);
    }
    now = DateTime.utc(2026, 11, 1, 10, 1, 0);
    final snap = s.snapshot(includeCurrent: false);
    expect(snap, hasLength(1));
    expect(snap.single['count'], 10);
    expect(snap.single['errors'], 1);
    expect(snap.single['p95Ms'], 100.0);
  });
}

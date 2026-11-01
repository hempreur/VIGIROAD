import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:cryptography/cryptography.dart';

final _rng = Random.secure();

List<int> randomBytes(int n) => List<int>.generate(n, (_) => _rng.nextInt(256));

String b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// Jeton opaque (256 bits). Seule son empreinte SHA-256 est enregistrée.
String newToken(String prefix) => '${prefix}_${b64url(randomBytes(32))}';

String sha256Hex(String s) => c.sha256.convert(utf8.encode(s)).toString();

/// Comparaison en temps constant.
bool secureEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Hachage des mots de passe : Argon2id (recommandation OWASP : 19 Mio,
/// 2 itérations), sel aléatoire de 16 octets, format PHC. Calcul dans un
/// isolat séparé pour ne pas bloquer les autres requêtes.
class PasswordHasher {
  const PasswordHasher({this.memoryKb = 19456, this.iterations = 2});

  final int memoryKb;
  final int iterations;

  static const minLength = 8;
  static const maxLength = 128;

  /// Message d'erreur, ou null si le mot de passe est acceptable.
  static String? validate(String password) {
    if (password.length < minLength) return 'Mot de passe trop court ($minLength caractères minimum)';
    if (password.length > maxLength) return 'Mot de passe trop long';
    if (!RegExp(r'[A-Za-z]').hasMatch(password) || !RegExp(r'[0-9]').hasMatch(password)) {
      return 'Le mot de passe doit contenir au moins une lettre et un chiffre';
    }
    return null;
  }

  Future<String> hash(String password) async {
    final salt = randomBytes(16);
    final m = memoryKb, t = iterations;
    final out = await Isolate.run(() => _derive(password, salt, m, t));
    return '\$argon2id\$v=19\$m=$m,t=$t,p=1\$${b64url(salt)}\$${b64url(out)}';
  }

  Future<bool> verify(String password, String encoded) async {
    final parts = encoded.split('\$');
    // ['', 'argon2id', 'v=19', 'm=..,t=..,p=1', sel, empreinte]
    if (parts.length != 6 || parts[1] != 'argon2id') return false;
    final params = {
      for (final kv in parts[3].split(','))
        if (kv.contains('=')) kv.split('=')[0]: int.tryParse(kv.split('=')[1]) ?? 0,
    };
    final m = params['m'] ?? 0, t = params['t'] ?? 0;
    if (m < 8 || t < 1) return false;
    final salt = _unb64(parts[4]);
    final expected = parts[5];
    final out = await Isolate.run(() => _derive(password, salt, m, t));
    return secureEquals(b64url(out), expected);
  }

  /// Empreinte factice pour les identifiants inconnus (temps de réponse
  /// identique, pas d'énumération des comptes).
  Future<void> dummyVerify(String password) => hash(password);

  static Future<List<int>> _derive(String password, List<int> salt, int m, int t) async {
    final algo = Argon2id(parallelism: 1, memory: m, iterations: t, hashLength: 32);
    final key = await algo.deriveKeyFromPassword(password: password, nonce: salt);
    return key.extractBytes();
  }
}

List<int> _unb64(String s) => base64Url.decode(s.padRight((s.length + 3) ~/ 4 * 4, '='));

/// Chiffrement AES-256-GCM des secrets stockés en base (secrets TOTP).
class SecretBoxer {
  SecretBoxer(List<int> key) : _key = SecretKey(key);

  final SecretKey _key;
  final _algo = AesGcm.with256bits();

  Future<String> seal(String clear) async {
    final box = await _algo.encrypt(utf8.encode(clear), secretKey: _key, nonce: _algo.newNonce());
    return b64url(box.concatenation());
  }

  Future<String> open(String sealed) async {
    final box = SecretBox.fromConcatenation(_unb64(sealed), nonceLength: 12, macLength: 16);
    return utf8.decode(await _algo.decrypt(box, secretKey: _key));
  }
}

/// Codes à usage unique (RFC 6238 : HMAC-SHA1, 6 chiffres, 30 s), compatibles
/// avec Google Authenticator, Microsoft Authenticator, Aegis, 1Password…
class Totp {
  static const period = 30;
  static const digits = 6;

  static String newSecret() => base32Encode(randomBytes(20));

  static int step(DateTime now) => now.millisecondsSinceEpoch ~/ 1000 ~/ period;

  static String code(String secret, int step) {
    final msg = ByteData(8)..setUint64(0, step);
    final h = c.Hmac(c.sha1, base32Decode(secret)).convert(msg.buffer.asUint8List()).bytes;
    final o = h[h.length - 1] & 0xf;
    final bin = ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
    return (bin % pow(10, digits)).toString().padLeft(digits, '0');
  }

  /// Pas de temps validé (tolérance ±1 pas), ou null. Un pas déjà utilisé
  /// ([lastStep]) est refusé : un code ne sert qu'une fois.
  static int? verify(String secret, String input, DateTime now, {int lastStep = 0}) {
    final code = input.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6}$').hasMatch(code)) return null;
    final s = step(now);
    for (final candidate in [s, s - 1, s + 1]) {
      if (candidate <= lastStep) continue;
      if (secureEquals(Totp.code(secret, candidate), code)) return candidate;
    }
    return null;
  }

  static String uri(String secret, String account, {String issuer = 'VIGIROAD'}) =>
      'otpauth://totp/${Uri.encodeComponent('$issuer:$account')}?secret=$secret'
      '&issuer=${Uri.encodeComponent(issuer)}&algorithm=SHA1&digits=$digits&period=$period';
}

const _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

String base32Encode(List<int> bytes) {
  final out = StringBuffer();
  var buffer = 0, bits = 0;
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out.write(_b32[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  if (bits > 0) out.write(_b32[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

Uint8List base32Decode(String s) {
  final out = <int>[];
  var buffer = 0, bits = 0;
  for (final ch in s.toUpperCase().replaceAll(RegExp(r'[\s=]'), '').split('')) {
    final v = _b32.indexOf(ch);
    if (v < 0) throw const FormatException('base32 invalide');
    buffer = ((buffer << 5) | v) & 0xffff;
    bits += 5;
    if (bits >= 8) {
      out.add((buffer >> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Uint8List.fromList(out);
}

/// Adresse réduite à son réseau (/24 en IPv4, /48 en IPv6) : suffisant pour
/// la sécurité, sans conserver l'adresse complète.
String? ipPrefix(String? ip) {
  if (ip == null || ip.isEmpty) return null;
  if (ip.contains('.') && !ip.contains(':')) {
    final p = ip.split('.');
    return p.length == 4 ? '${p[0]}.${p[1]}.${p[2]}.0/24' : null;
  }
  final full = expandIpv6(ip);
  if (full == null) return null;
  return '${full.take(3).map((h) => h.toRadixString(16)).join(':')}::/48';
}

/// Les 8 groupes d'une adresse IPv6, ou null.
List<int>? expandIpv6(String ip) {
  var s = ip.split('%').first;
  if (s.startsWith('::ffff:') && s.contains('.')) return null;
  final halves = s.split('::');
  if (halves.length > 2) return null;
  List<int>? parse(String part) {
    if (part.isEmpty) return [];
    final out = <int>[];
    for (final g in part.split(':')) {
      final v = int.tryParse(g, radix: 16);
      if (v == null || v < 0 || v > 0xffff) return null;
      out.add(v);
    }
    return out;
  }

  final a = parse(halves[0]);
  final b = halves.length == 2 ? parse(halves[1]) : <int>[];
  if (a == null || b == null) return null;
  if (halves.length == 1 && a.length != 8) return null;
  final zeros = 8 - a.length - b.length;
  if (zeros < 0) return null;
  return [...a, ...List.filled(zeros, 0), ...b];
}

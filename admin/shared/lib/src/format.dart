/// Mise en forme française (sans dépendance de localisation).
abstract final class Fmt {
  static String _two(int v) => v.toString().padLeft(2, '0');

  static DateTime? parse(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : (v is DateTime ? v.toLocal() : null);

  /// 01/11/2026 14:35
  static String dateTime(Object? v) {
    final d = parse(v);
    if (d == null) return '—';
    return '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';
  }

  static String date(Object? v) {
    final d = parse(v);
    if (d == null) return '—';
    return '${_two(d.day)}/${_two(d.month)}/${d.year}';
  }

  /// 01/11 14:00
  static String dayHour(Object? v) {
    final d = parse(v);
    if (d == null) return '—';
    return '${_two(d.day)}/${_two(d.month)} ${_two(d.hour)}:${_two(d.minute)}';
  }

  static String time(Object? v, {bool seconds = false}) {
    final d = parse(v);
    if (d == null) return '—';
    return '${_two(d.hour)}:${_two(d.minute)}${seconds ? ':${_two(d.second)}' : ''}';
  }

  /// « il y a 3 min », « dans 12 j »
  static String ago(Object? v, {DateTime? now}) {
    final d = parse(v);
    if (d == null) return 'jamais';
    final diff = (now ?? DateTime.now()).difference(d);
    final future = diff.isNegative;
    final s = diff.abs().inSeconds;
    final String t;
    if (s < 45) {
      t = '${s <= 1 ? 1 : s} s';
    } else if (s < 3600) {
      t = '${(s / 60).round()} min';
    } else if (s < 86400) {
      t = '${(s / 3600).round()} h';
    } else {
      t = '${(s / 86400).round()} j';
    }
    return future ? 'dans $t' : 'il y a $t';
  }

  /// 1 h 05 min, 3 min 20 s, 2 j 4 h
  static String duration(num? seconds) {
    if (seconds == null) return '—';
    final s = seconds.round();
    if (s < 60) return '$s s';
    if (s < 3600) return '${s ~/ 60} min${s % 60 == 0 ? '' : ' ${_two(s % 60)} s'}';
    if (s < 86400) return '${s ~/ 3600} h ${_two((s % 3600) ~/ 60)} min';
    return '${s ~/ 86400} j ${(s % 86400) ~/ 3600} h';
  }

  static String bytes(num? v, {int digits = 1}) {
    if (v == null) return '—';
    const units = ['o', 'Ko', 'Mo', 'Go', 'To'];
    var x = v.toDouble();
    var i = 0;
    while (x >= 1024 && i < units.length - 1) {
      x /= 1024;
      i++;
    }
    return '${number(x, digits: i == 0 ? 0 : digits)} ${units[i]}';
  }

  /// Débit en bits par seconde à partir d'octets par seconde.
  static String rate(num? bytesPerSecond) {
    if (bytesPerSecond == null) return '—';
    var x = bytesPerSecond * 8.0;
    const units = ['bit/s', 'kbit/s', 'Mbit/s', 'Gbit/s'];
    var i = 0;
    while (x >= 1000 && i < units.length - 1) {
      x /= 1000;
      i++;
    }
    return '${number(x, digits: x < 10 && i > 0 ? 1 : 0)} ${units[i]}';
  }

  /// 12 345,6 (espace fine insécable, virgule décimale).
  static String number(num? v, {int digits = 0}) {
    if (v == null) return '—';
    final fixed = v.toStringAsFixed(digits);
    final neg = fixed.startsWith('-');
    final parts = (neg ? fixed.substring(1) : fixed).split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(' ');
      buf.write(intPart[i]);
    }
    return '${neg ? '-' : ''}$buf${parts.length > 1 ? ',${parts[1]}' : ''}';
  }

  static String percent(num? v, {int digits = 0}) => v == null ? '—' : '${number(v, digits: digits)} %';

  /// Drapeau emoji d'un code pays ISO (FR → 🇫🇷).
  static String flag(String? cc) {
    if (cc == null || cc.length != 2) return '🏳';
    final u = cc.toUpperCase();
    return String.fromCharCodes([0x1F1E6 + u.codeUnitAt(0) - 65, 0x1F1E6 + u.codeUnitAt(1) - 65]);
  }

  static String country(String? cc) => cc == null ? 'Inconnu' : (countryNames[cc.toUpperCase()] ?? cc.toUpperCase());

  static String os(Object? os, Object? version) {
    final name = switch (os) {
      'android' => 'Android',
      'ios' => 'iOS',
      null => 'Inconnu',
      _ => 'Autre',
    };
    return version == null ? name : '$name $version';
  }

  static String endReason(Object? r) => switch (r) {
    'logout' => 'déconnexion',
    'revoked' => 'révoquée',
    'expired' => 'expirée (inactivité)',
    'disabled' => 'compte désactivé',
    'password_reset' => 'accès réinitialisé',
    'device_revoked' => 'appareil révoqué',
    null => '',
    _ => '$r',
  };

  static String loginReason(Object? r) => switch (r) {
    'password' => 'mot de passe',
    'register' => 'inscription',
    'bad_password' => 'mot de passe incorrect',
    'unknown_account' => 'compte inconnu',
    'disabled' => 'compte désactivé',
    'rate_limited' => 'trop de tentatives',
    'bad_reset_code' => 'code de réinitialisation invalide',
    'password_reset' => 'réinitialisation',
    'locked' => 'compte verrouillé',
    'bad_totp' => 'code TOTP incorrect',
    'password+totp' => 'mot de passe + TOTP',
    'mfa_enrolled' => 'enrôlement TOTP',
    _ => '$r',
  };

  static const countryNames = {
    'FR': 'France', 'BE': 'Belgique', 'CH': 'Suisse', 'LU': 'Luxembourg', 'MC': 'Monaco', 'DE': 'Allemagne',
    'ES': 'Espagne', 'IT': 'Italie', 'PT': 'Portugal', 'GB': 'Royaume-Uni', 'IE': 'Irlande', 'NL': 'Pays-Bas',
    'AT': 'Autriche', 'PL': 'Pologne', 'CZ': 'Tchéquie', 'SE': 'Suède', 'NO': 'Norvège', 'DK': 'Danemark',
    'FI': 'Finlande', 'GR': 'Grèce', 'RO': 'Roumanie', 'HU': 'Hongrie', 'US': 'États-Unis', 'CA': 'Canada',
    'MA': 'Maroc', 'DZ': 'Algérie', 'TN': 'Tunisie', 'SN': 'Sénégal', 'CI': 'Côte d\'Ivoire', 'CM': 'Cameroun',
    'GP': 'Guadeloupe', 'MQ': 'Martinique', 'RE': 'La Réunion', 'GF': 'Guyane', 'YT': 'Mayotte', 'NC': 'Nouvelle-Calédonie',
    'PF': 'Polynésie française', 'BR': 'Brésil', 'MX': 'Mexique', 'JP': 'Japon', 'CN': 'Chine', 'IN': 'Inde',
    'AU': 'Australie', 'TR': 'Turquie', 'UA': 'Ukraine', 'RU': 'Russie', 'AE': 'Émirats arabes unis',
  };
}

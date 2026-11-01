import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'security.dart';

/// Pays approximatif d'une adresse IP, d'après la base libre DB-IP « IP to
/// Country Lite » (CC BY 4.0, https://db-ip.com). Précision : le pays
/// seulement. Sans fichier, la fonction est simplement indisponible.
class GeoIp {
  GeoIp._(this._v4Start, this._v4End, this._v4Cc, this._v6Start, this._v6End, this._v6Cc);

  /// Base vide (fichier absent).
  GeoIp.empty() : this._(Uint32List(0), Uint32List(0), const [], Int64List(0), Int64List(0), const []);

  final Uint32List _v4Start, _v4End;
  final List<String> _v4Cc;
  // IPv6 : 64 premiers bits (préfixe /64), décalés pour une comparaison signée.
  final Int64List _v6Start, _v6End;
  final List<String> _v6Cc;

  static const attribution = 'IP Geolocation by DB-IP (https://db-ip.com), CC BY 4.0';

  bool get available => _v4Cc.isNotEmpty || _v6Cc.isNotEmpty;
  int get ranges => _v4Cc.length + _v6Cc.length;

  /// Lignes `debut,fin,PAYS` (CSV DB-IP).
  static GeoIp parse(Iterable<String> lines) {
    final b = _Builder();
    lines.forEach(b.add);
    return b.build();
  }

  /// Lecture en flux (fichier éventuellement compressé gzip).
  static Future<GeoIp> load(String path) async {
    final f = File(path);
    if (!await f.exists()) return GeoIp.empty();
    Stream<List<int>> bytes = f.openRead();
    if (path.endsWith('.gz')) bytes = bytes.transform(gzip.decoder);
    final b = _Builder();
    await for (final line in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      b.add(line);
    }
    return b.build();
  }

  /// Code pays ISO 3166-1 alpha-2, ou null.
  String? country(String? ip) {
    if (ip == null || ip.isEmpty) return null;
    if (ip.contains(':')) {
      final v = _v6(ip);
      return v == null ? null : _find(_v6Start, _v6End, _v6Cc, v);
    }
    final v = _v4(ip);
    return v == null ? null : _find(_v4Start, _v4End, _v4Cc, v);
  }

  static String? _find(List<int> starts, List<int> ends, List<String> cc, int v) {
    var lo = 0, hi = starts.length - 1, at = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (starts[mid] <= v) {
        at = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return at >= 0 && v <= ends[at] ? cc[at] : null;
  }

  static int? _v4(String ip) {
    final p = ip.split('.');
    if (p.length != 4) return null;
    var v = 0;
    for (final s in p) {
      final n = int.tryParse(s);
      if (n == null || n < 0 || n > 255) return null;
      v = (v << 8) | n;
    }
    return v;
  }

  static int? _v6(String ip) {
    final g = expandIpv6(ip);
    if (g == null) return null;
    final hi = (g[0] << 48) | (g[1] << 32) | (g[2] << 16) | g[3];
    // Bit de signe inversé : l'ordre signé suit l'ordre non signé.
    return hi ^ (1 << 63);
  }
}

class _Builder {
  final v4s = <int>[], v4e = <int>[], v4c = <String>[];
  final v6s = <int>[], v6e = <int>[], v6c = <String>[];
  final _intern = <String, String>{};

  void add(String line) {
    final f = line.split(',');
    if (f.length < 3) return;
    final a = f[0].replaceAll('"', ''), b = f[1].replaceAll('"', '');
    final raw = f[2].replaceAll('"', '').trim();
    if (raw.length != 2 || raw == 'ZZ') return;
    final cc = _intern.putIfAbsent(raw, () => raw);
    if (a.contains(':')) {
      final s = GeoIp._v6(a), e = GeoIp._v6(b);
      if (s == null || e == null) return;
      v6s.add(s);
      v6e.add(e);
      v6c.add(cc);
    } else {
      final s = GeoIp._v4(a), e = GeoIp._v4(b);
      if (s == null || e == null) return;
      v4s.add(s);
      v4e.add(e);
      v4c.add(cc);
    }
  }

  /// Plages triées par début (recherche dichotomique), quel que soit
  /// l'ordre du fichier.
  GeoIp build() {
    final i4 = List<int>.generate(v4s.length, (i) => i)..sort((a, b) => v4s[a].compareTo(v4s[b]));
    final i6 = List<int>.generate(v6s.length, (i) => i)..sort((a, b) => v6s[a].compareTo(v6s[b]));
    return GeoIp._(
      Uint32List.fromList([for (final i in i4) v4s[i]]),
      Uint32List.fromList([for (final i in i4) v4e[i]]),
      [for (final i in i4) v4c[i]],
      Int64List.fromList([for (final i in i6) v6s[i]]),
      Int64List.fromList([for (final i in i6) v6e[i]]),
      [for (final i in i6) v6c[i]],
    );
  }
}

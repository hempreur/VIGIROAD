import 'package:vigiroad_traffic/vigiroad_traffic.dart';

/// Décodage d'une polyligne encodée (algorithme Google, précision 1e-5).
List<LatLng> decodePolyline(String encoded, {int precision = 5}) {
  final factor = precision == 6 ? 1e6 : 1e5;
  final out = <LatLng>[];
  var index = 0, lat = 0, lng = 0;
  int next() {
    var result = 0, shift = 0, b = 0;
    do {
      if (index >= encoded.length) throw const FormatException('Polyligne tronquée');
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  while (index < encoded.length) {
    lat += next();
    lng += next();
    out.add(LatLng(lat / factor, lng / factor));
  }
  return out;
}

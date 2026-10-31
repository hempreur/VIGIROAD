// Contrôle réel (CI, informatif) : itinéraire OSRM réel puis limitations
// Overpass réelles. Affiche la répartition des valeurs et la part connue.
// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vigiroad_traffic/vigiroad_traffic.dart';
import 'package:vigiroad_traffic_aggregator/traffic_aggregator.dart';

const trips = {
  'Paris, Concorde → Bastille': ((48.8656, 2.3212), (48.8532, 2.3691)),
  'Essonne, N20 Arpajon → Étampes': ((48.5880, 2.2470), (48.4350, 2.1610)),
};

Future<void> main() async {
  final client = http.Client();
  final service = SpeedLimitService(client: client);
  for (final MapEntry(key: name, value: (from, to)) in trips.entries) {
    final osrm = Uri.parse('https://router.project-osrm.org/route/v1/driving/'
        '${from.$2},${from.$1};${to.$2},${to.$1}?overview=full&geometries=geojson');
    final r = jsonDecode((await client.get(osrm, headers: {'User-Agent': 'VIGIROAD-CI'})).body) as Map<String, dynamic>;
    final coords = ((r['routes'] as List).first as Map<String, dynamic>)['geometry']['coordinates'] as List<dynamic>;
    final route = [for (final c in coords) LatLng.fromJson(c as List<dynamic>)];
    final sw = Stopwatch()..start();
    final res = await service.along(route);
    var total = 0.0, known = 0.0;
    final byValue = <int?, double>{};
    for (var i = 0; i + 1 < route.length; i++) {
      final d = haversine(route[i], route[i + 1]);
      total += d;
      if (res.limits[i] != null) known += d;
      byValue[res.limits[i]] = (byValue[res.limits[i]] ?? 0) + d;
    }
    print('== $name : ${(total / 1000).toStringAsFixed(1)} km, ${route.length} points, '
        '${sw.elapsedMilliseconds} ms, complet=${res.complete}');
    print('   limitation connue sur ${(100 * known / total).toStringAsFixed(1)} % de la distance');
    final sorted = byValue.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sorted) {
      print('   ${e.key == null ? 'inconnue' : '${e.key} km/h'} : ${(e.value / 1000).toStringAsFixed(2)} km');
    }
  }
  final again = Stopwatch()..start();
  final (_, (lat, lng)) = trips.values.first;
  await service.along([LatLng(lat, lng), LatLng(lat + 0.001, lng)]);
  print('Nouvelle demande servie depuis le cache : ${again.elapsedMilliseconds} ms');
  print('Requêtes Overpass : ${service.overpassQueries}');
  client.close();
}

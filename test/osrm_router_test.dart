import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vigiroad/features/navigation/data/osrm_router.dart';
import 'package:vigiroad/features/navigation/domain/geo_fix.dart';
import 'package:vigiroad/features/navigation/domain/route.dart';

const _ok = '''
{"code":"Ok","routes":[{"distance":1520.4,"duration":190.2,
 "geometry":{"type":"LineString","coordinates":[[2.3522,48.8566],[2.3522,48.8656],[2.3590,48.8656]]},
 "legs":[{"annotation":{"maxspeed":[{"speed":50,"unit":"km/h"},{"unknown":true}]},
  "steps":[
   {"distance":1000,"duration":120,"name":"Rue de Rivoli","ref":"","maneuver":{"type":"depart","location":[2.3522,48.8566]}},
   {"distance":500,"duration":60,"name":"","ref":"D120;D7","destinations":"D 120: Centre-ville, Gare","exits":"12",
    "maneuver":{"type":"off ramp","modifier":"slight right","location":[2.3522,48.8656]}},
   {"distance":0,"duration":0,"name":"Place","maneuver":{"type":"roundabout","modifier":"right","exit":3,"location":[2.3590,48.8656]}},
   {"distance":0,"duration":0,"name":"","maneuver":{"type":"arrive","location":[2.3590,48.8656]}}
  ]}]}]}''';

void main() {
  test('analyse une réponse OSRM complète', () {
    final r = parseOsrmResponse(_ok);
    expect(r.distanceM, 1520.4);
    expect(r.durationS, 190.2);
    expect(r.geometry, hasLength(3));
    expect(r.geometry.first, const GeoPoint(48.8566, 2.3522));
    expect(r.segmentSpeedLimits, [50, null]);

    expect(r.steps, hasLength(4));
    expect(r.steps[0].kind, ManeuverKind.depart);
    expect(r.steps[0].roadName, 'Rue de Rivoli');
    final ramp = r.steps[1];
    expect(ramp.kind, ManeuverKind.offRamp);
    expect(ramp.direction, ManeuverDirection.slightRight);
    expect(ramp.roadRef, 'D120');
    expect(ramp.destinations, 'Centre-ville');
    expect(ramp.exitNumber, '12');
    expect(r.steps[2].kind, ManeuverKind.roundabout);
    expect(r.steps[2].roundaboutExit, 3);
    expect(r.steps[3].kind, ManeuverKind.arrive);
  });

  test('erreurs OSRM traduites', () {
    expect(() => parseOsrmResponse('{"code":"NoRoute"}'), throwsA(isA<RoutingException>()));
    expect(() => parseOsrmResponse('{"code":"NoSegment"}'), throwsA(isA<RoutingException>()));
    expect(() => parseOsrmResponse('{"code":"InvalidQuery"}'), throwsA(isA<RoutingException>()));
  });

  test('requête : coordonnées lon,lat, étapes, limitations, cap', () async {
    late Uri sent;
    final client = MockClient((req) async {
      sent = req.url;
      return http.Response.bytes(utf8.encode(_ok), 200);
    });
    final router = OsrmRouter(baseUrl: 'https://osrm.test', userAgent: 'VIGIROAD/test', client: client);
    await router.route(const GeoPoint(48.8566, 2.3522), const GeoPoint(45.764, 4.8357), bearing: 372);
    expect(sent.path, '/route/v1/driving/2.352200,48.856600;4.835700,45.764000');
    expect(sent.queryParameters['steps'], 'true');
    expect(sent.queryParameters['annotations'], 'maxspeed');
    expect(sent.queryParameters['bearings'], '12,45;');
  });

  test('erreur réseau : message explicite', () async {
    final client = MockClient((_) async => throw const SocketLikeException());
    final router = OsrmRouter(baseUrl: 'https://osrm.test', userAgent: 'x', client: client);
    expect(
      router.route(const GeoPoint(0, 0), const GeoPoint(1, 1)),
      throwsA(isA<RoutingException>().having((e) => e.message, 'message', contains('réseau'))),
    );
  });
}

class SocketLikeException implements Exception {
  const SocketLikeException();
}

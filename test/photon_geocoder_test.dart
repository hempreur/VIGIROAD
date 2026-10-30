import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vigiroad/features/navigation/domain/geo_fix.dart';
import 'package:vigiroad/features/search/data/photon_geocoder.dart';

const _sample = '''
{"type":"FeatureCollection","features":[
 {"type":"Feature","geometry":{"type":"Point","coordinates":[2.2945,48.8584]},
  "properties":{"name":"Tour Eiffel","street":"Avenue Gustave Eiffel","housenumber":"5","postcode":"75007","city":"Paris","country":"France"}},
 {"type":"Feature","geometry":{"type":"Point","coordinates":[4.8357,45.764]},
  "properties":{"street":"Rue de la République","housenumber":"12","postcode":"69002","city":"Lyon","country":"France"}},
 {"type":"Feature","geometry":{"type":"Point","coordinates":[4.8357,45.764]},
  "properties":{"street":"Rue de la République","housenumber":"12","postcode":"69002","city":"Lyon","country":"France"}},
 {"type":"Feature","geometry":{"type":"Point","coordinates":[4.35,50.85]},
  "properties":{"name":"Grand-Place","city":"Bruxelles","country":"Belgique"}},
 {"type":"Feature","geometry":{"type":"Point"},"properties":{"name":"Sans coordonnées"}}
]}''';

void main() {
  test('analyse une réponse Photon', () {
    final places = parsePhotonResponse(_sample);
    expect(places, hasLength(3), reason: 'doublon et entrée invalide ignorés');

    expect(places[0].label, 'Tour Eiffel');
    expect(places[0].detail, '5 Avenue Gustave Eiffel, 75007 Paris');
    expect(places[0].point, const GeoPoint(48.8584, 2.2945));

    expect(places[1].label, '12 Rue de la République');
    expect(places[1].detail, '69002 Lyon');

    expect(places[2].detail, 'Bruxelles, Belgique', reason: 'pays affiché hors France');
  });

  test('réponse non conforme : liste vide', () {
    expect(parsePhotonResponse('[]'), isEmpty);
    expect(parsePhotonResponse('{"features": 3}'), isEmpty);
  });

  test('envoie la requête attendue avec User-Agent', () async {
    late http.Request sent;
    final client = MockClient((req) async {
      sent = req;
      return http.Response.bytes(utf8.encode(_sample), 200);
    });
    final geocoder = PhotonGeocoder(baseUrl: 'https://photon.test', userAgent: 'VIGIROAD/test', client: client);

    final places = await geocoder.search('  tour eiffel ', near: const GeoPoint(48.85, 2.35));

    expect(places, isNotEmpty);
    expect(sent.url.host, 'photon.test');
    expect(sent.url.path, '/api');
    expect(sent.url.queryParameters['q'], 'tour eiffel');
    expect(sent.url.queryParameters['lang'], 'fr');
    expect(sent.url.queryParameters['lat'], '48.85000');
    expect(sent.headers['User-Agent'], 'VIGIROAD/test');
  });

  test('moins de 3 caractères : aucune requête', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    });
    final g = PhotonGeocoder(baseUrl: 'https://photon.test', userAgent: 'x', client: client);
    expect(await g.search('ab'), isEmpty);
    expect(calls, 0);
  });

  test('erreur HTTP : exception explicite', () async {
    final client = MockClient((_) async => http.Response('busy', 503));
    final g = PhotonGeocoder(baseUrl: 'https://photon.test', userAgent: 'x', client: client);
    expect(g.search('paris'), throwsA(isA<GeocodingException>()));
  });
}

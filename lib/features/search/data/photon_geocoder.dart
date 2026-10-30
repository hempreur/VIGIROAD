import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../navigation/domain/geo_fix.dart';

/// Résultat de recherche d'adresse.
class Place {
  const Place({required this.label, required this.detail, required this.point});

  /// Nom principal (lieu, ou numéro + rue).
  final String label;

  /// Complément : code postal, ville, pays.
  final String detail;
  final GeoPoint point;
}

class GeocodingException implements Exception {
  const GeocodingException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class Geocoder {
  Future<List<Place>> search(String query, {GeoPoint? near});
}

/// Recherche d'adresses via une API compatible Photon (données OSM).
class PhotonGeocoder implements Geocoder {
  PhotonGeocoder({required this.baseUrl, required this.userAgent, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final String userAgent;
  final http.Client _client;

  @override
  Future<List<Place>> search(String query, {GeoPoint? near}) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    final uri = Uri.parse('$baseUrl/api').replace(
      queryParameters: {
        'q': q,
        'limit': '8',
        'lang': 'fr',
        if (near != null) 'lat': near.latitude.toStringAsFixed(5),
        if (near != null) 'lon': near.longitude.toStringAsFixed(5),
      },
    );
    final http.Response res;
    try {
      res = await _client
          .get(uri, headers: {'User-Agent': userAgent, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
    } on Exception {
      throw const GeocodingException('Recherche impossible : vérifiez la connexion réseau.');
    }
    if (res.statusCode != 200) {
      throw GeocodingException('Le service de recherche a répondu ${res.statusCode}.');
    }
    return parsePhotonResponse(utf8.decode(res.bodyBytes));
  }
}

/// Convertit une réponse GeoJSON Photon en résultats affichables.
List<Place> parsePhotonResponse(String body) {
  final json = jsonDecode(body);
  if (json is! Map<String, dynamic>) return const [];
  final features = json['features'];
  if (features is! List) return const [];

  final places = <Place>[];
  final seen = <String>{};
  for (final f in features.whereType<Map<String, dynamic>>()) {
    final coords = (f['geometry'] as Map<String, dynamic>?)?['coordinates'];
    final props = f['properties'];
    if (coords is! List || coords.length < 2 || props is! Map<String, dynamic>) continue;
    final lon = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();

    String? s(String k) {
      final v = props[k];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final street = [s('housenumber'), s('street')].whereType<String>().join(' ');
    final name = s('name');
    final label = name ?? (street.isNotEmpty ? street : (s('city') ?? 'Lieu sans nom'));
    final locality = [s('postcode'), s('city') ?? s('county')].whereType<String>().join(' ');
    final detail = [
      if (name != null && street.isNotEmpty) street,
      if (locality.isNotEmpty) locality,
      if (s('country') case final c? when c != 'France') c,
    ].join(', ');

    final key = '$label|$detail';
    if (!seen.add(key)) continue;
    places.add(Place(label: label, detail: detail, point: GeoPoint(lat, lon)));
  }
  return places;
}

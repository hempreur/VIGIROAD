/// Lecture de la balise OpenStreetMap `maxspeed` en km/h.
///
/// Seules les valeurs sans ambiguïté sont retenues : nombre explicite
/// (« 50 », « 30 mph »), ou valeur implicite fixée par la loi pour toute la
/// zone (« FR:urban » = 50). Les valeurs qui dépendent d'un choix local —
/// « FR:rural » vaut 80 ou 90 km/h selon les départements —, « none »,
/// « signals », « variable » ou une liste donnent `null` : limitation inconnue.
int? parseMaxspeed(String? raw) {
  if (raw == null) return null;
  final v = raw.trim().toLowerCase();
  if (v.isEmpty || v.contains(';')) return null;
  final kmh = RegExp(r'^(\d{1,3}(?:\.\d+)?)\s*(?:km/h|kmh|kph)?$').firstMatch(v);
  if (kmh != null) return _sane(double.parse(kmh.group(1)!).round());
  final mph = RegExp(r'^(\d{1,3})\s*mph$').firstMatch(v);
  if (mph != null) return _sane((int.parse(mph.group(1)!) * 1.609344).round());
  return _implicit[v];
}

int? _sane(int v) => v >= 5 && v <= 150 ? v : null;

/// Valeurs implicites fixées nationalement (https://wiki.openstreetmap.org/wiki/Speed_limits).
const _implicit = <String, int>{
  'fr:urban': 50,
  'fr:zone30': 30,
  'fr:zone20': 20,
  'fr:motorway': 130,
  'be:urban': 50,
  'be-vlg:urban': 50,
  'be-wal:urban': 50,
  'be-bru:urban': 50,
  'ch:urban': 50,
  'ch:rural': 80,
  'ch:trunk': 100,
  'ch:motorway': 120,
  'de:urban': 50,
  'de:rural': 100,
  'de:zone30': 30,
  'es:urban': 50,
  'it:urban': 50,
  'it:motorway': 130,
  'lu:urban': 50,
  'nl:urban': 50,
  'gb:nsl_single': 97,
  'gb:nsl_dual': 113,
  'gb:motorway': 113,
};

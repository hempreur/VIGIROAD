import 'plate_format.dart';
import 'plate_models.dart';

/// Origine d'une entrée de la liste de surveillance.
enum EntrySource { manual, import, sync }

/// Plaque de la liste de surveillance.
class WatchEntry {
  const WatchEntry({
    required this.plate,
    this.country = 'FR',
    this.category = 'Surveillance',
    this.priority = WatchPriority.medium,
    this.note = '',
    this.source = EntrySource.manual,
    this.updatedAt,
  });

  /// Plaque normalisée (majuscules, sans séparateur) — clé unique.
  final String plate;
  final String country;
  final String category;
  final WatchPriority priority;
  final String note;
  final EntrySource source;
  final DateTime? updatedAt;

  /// Forme d'affichage selon le format reconnu (`AA-123-BB`).
  String get display => PlateFormats.match(plate)?.display(plate) ?? plate;

  WatchEntry copyWith({
    String? plate,
    String? country,
    String? category,
    WatchPriority? priority,
    String? note,
    EntrySource? source,
    DateTime? updatedAt,
  }) => WatchEntry(
    plate: plate ?? this.plate,
    country: country ?? this.country,
    category: category ?? this.category,
    priority: priority ?? this.priority,
    note: note ?? this.note,
    source: source ?? this.source,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is WatchEntry &&
      other.plate == plate &&
      other.country == country &&
      other.category == category &&
      other.priority == priority &&
      other.note == note &&
      other.source == source;

  @override
  int get hashCode => Object.hash(plate, country, category, priority, note, source);
}

/// Libellé français d'une priorité.
String priorityLabel(WatchPriority p) => switch (p) {
  WatchPriority.high => 'Haute',
  WatchPriority.medium => 'Moyenne',
  WatchPriority.low => 'Basse',
};

/// Lecture tolérante d'une priorité (anglais, français, chiffre).
WatchPriority? parsePriority(String raw) => switch (raw.trim().toLowerCase()) {
  '' => WatchPriority.medium,
  'high' || 'haute' || 'h' || '3' || 'élevée' || 'elevee' => WatchPriority.high,
  'medium' || 'moyenne' || 'm' || '2' || 'normal' || 'normale' => WatchPriority.medium,
  'low' || 'basse' || 'l' || 'b' || '1' || 'faible' => WatchPriority.low,
  _ => null,
};

/// Valide et normalise une plaque saisie ; retourne un message d'erreur ou
/// la plaque normalisée.
({String? plate, String? error}) validatePlate(String raw, {String country = 'FR'}) {
  final n = normalizePlateText(raw);
  if (n.isEmpty) return (plate: null, error: 'Plaque vide');
  if (country.toUpperCase() == 'FR') {
    if (PlateFormats.match(n) == null) {
      return (plate: null, error: 'Format français invalide (attendu AA-123-AA ou 1234 AB 75)');
    }
    return (plate: n, error: null);
  }
  if (n.length < 2 || n.length > 12) return (plate: null, error: 'Longueur de plaque invalide');
  return (plate: n, error: null);
}

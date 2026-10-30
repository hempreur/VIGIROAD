/// Lecture d'une plaque produite par le module OCR (phase 4).
class PlateReading {
  const PlateReading({
    required this.normalized,
    required this.display,
    required this.confidence,
    this.country = 'FR',
    this.vehicleType,
  });

  /// Forme canonique, sans séparateurs : `AA123BB`.
  final String normalized;

  /// Forme affichée, avec tirets : `AA-123-BB`.
  final String display;

  /// Confiance agrégée sur plusieurs images, entre 0 et 1.
  final double confidence;

  /// Code pays ISO 3166-1 alpha-2.
  final String country;

  /// Type de véhicule si connu (VP, VU, moto…).
  final String? vehicleType;

  int get confidencePercent => (confidence * 100).round().clamp(0, 100);
}

enum WatchPriority { low, medium, high }

/// Correspondance confirmée entre une lecture et la liste de surveillance.
class PlateAlert {
  const PlateAlert({
    required this.reading,
    required this.category,
    required this.priority,
    required this.at,
  });

  final PlateReading reading;
  final String category;
  final WatchPriority priority;
  final DateTime at;
}

/// Lettre du code pays sur la bande bleue européenne (F, D, E, I…).
String euBandLetter(String isoCountry) => switch (isoCountry.toUpperCase()) {
  'FR' => 'F',
  'DE' => 'D',
  'ES' => 'E',
  'IT' => 'I',
  'BE' => 'B',
  'NL' => 'NL',
  'LU' => 'L',
  'PT' => 'P',
  'AT' => 'A',
  'CH' => 'CH',
  final other => other,
};

/// Nom du pays affiché dans la fenêtre OCR.
String countryName(String isoCountry) => switch (isoCountry.toUpperCase()) {
  'FR' => 'France',
  'DE' => 'Allemagne',
  'ES' => 'Espagne',
  'IT' => 'Italie',
  'BE' => 'Belgique',
  'NL' => 'Pays-Bas',
  'LU' => 'Luxembourg',
  'PT' => 'Portugal',
  'AT' => 'Autriche',
  'CH' => 'Suisse',
  final other => other,
};

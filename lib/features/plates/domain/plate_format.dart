/// Formats d'immatriculation et extraction depuis le texte OCR.
///
/// Architecture ouverte : chaque pays/format implémente [PlateFormat] ;
/// [PlateFormats.all] liste ceux qui sont actifs.
library;

/// Plaque candidate extraite d'une ligne de texte OCR.
class PlateCandidate {
  const PlateCandidate({
    required this.normalized,
    required this.display,
    required this.formatId,
    required this.country,
    required this.corrections,
  });

  /// Forme canonique (majuscules, sans séparateur) : `AA123BB`.
  final String normalized;

  /// Forme d'affichage : `AA-123-BB`.
  final String display;
  final String formatId;
  final String country;

  /// Nombre de caractères corrigés (confusions OCR du type 0/D, 8/B).
  final int corrections;

  @override
  String toString() => 'PlateCandidate($display, $formatId, corr=$corrections)';
}

/// Classe de caractère attendue à une position du format.
enum CharClass { letter, digit }

/// Corrections des confusions OCR courantes, selon le type attendu.
abstract final class OcrConfusions {
  /// Chiffre lu là où une lettre est attendue.
  static const toLetter = <String, String>{
    '0': 'D',
    '8': 'B',
    '5': 'S',
    '2': 'Z',
    '6': 'G',
    '4': 'A',
    '7': 'T',
  };

  /// Lettre lue là où un chiffre est attendu.
  static const toDigit = <String, String>{
    'O': '0',
    'D': '0',
    'Q': '0',
    'U': '0',
    'I': '1',
    'L': '1',
    'J': '1',
    'Z': '2',
    'S': '5',
    'B': '8',
    'G': '6',
    'T': '7',
    'A': '4',
  };
}

/// Ne garde que les lettres et chiffres, en majuscules.
String normalizePlateText(String raw) =>
    raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

bool _isLetter(String c) => c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90;
bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

/// Applique un gabarit de classes à [s] en corrigeant les confusions.
/// Retourne `null` si incompatible, sinon (texte corrigé, nb corrections).
(String, int)? conformTo(String s, List<CharClass> pattern, {int maxCorrections = 2}) {
  if (s.length != pattern.length) return null;
  final out = StringBuffer();
  var corrections = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    switch (pattern[i]) {
      case CharClass.letter:
        if (_isLetter(c)) {
          out.write(c);
        } else if (OcrConfusions.toLetter[c] case final l?) {
          out.write(l);
          corrections++;
        } else {
          return null;
        }
      case CharClass.digit:
        if (_isDigit(c)) {
          out.write(c);
        } else if (OcrConfusions.toDigit[c] case final d?) {
          out.write(d);
          corrections++;
        } else {
          return null;
        }
    }
    if (corrections > maxCorrections) return null;
  }
  return (out.toString(), corrections);
}

abstract interface class PlateFormat {
  String get id;
  String get country;

  /// Candidats trouvés dans une ligne de texte OCR (déjà en majuscules ou non).
  List<PlateCandidate> extract(String line);

  /// La plaque normalisée respecte-t-elle ce format (sans correction) ?
  bool isValid(String normalized);

  String display(String normalized);
}

/// Système d'immatriculation des véhicules (France, depuis 2009) : AA-123-AA.
///
/// Lettres I, O et U exclues ; « SS » interdit ; bloc numérique 001 à 999.
class FrenchSivFormat implements PlateFormat {
  const FrenchSivFormat();

  static const _pattern = [
    CharClass.letter, CharClass.letter,
    CharClass.digit, CharClass.digit, CharClass.digit,
    CharClass.letter, CharClass.letter,
  ];

  @override
  String get id => 'FR-SIV';
  @override
  String get country => 'FR';

  @override
  bool isValid(String n) {
    if (n.length != 7) return false;
    if (conformTo(n, _pattern, maxCorrections: 0) == null) return false;
    final left = n.substring(0, 2), right = n.substring(5);
    if (RegExp('[IOU]').hasMatch(left + right)) return false;
    if (left == 'SS' || right == 'SS') return false;
    return n.substring(2, 5) != '000';
  }

  @override
  String display(String n) => '${n.substring(0, 2)}-${n.substring(2, 5)}-${n.substring(5)}';

  @override
  List<PlateCandidate> extract(String line) {
    final s = normalizePlateText(line);
    final found = <PlateCandidate>[];
    for (var i = 0; i + 7 <= s.length; i++) {
      final r = conformTo(s.substring(i, i + 7), _pattern);
      if (r == null || !isValid(r.$1)) continue;
      found.add(PlateCandidate(
        normalized: r.$1,
        display: display(r.$1),
        formatId: id,
        country: country,
        corrections: r.$2,
      ));
    }
    return found;
  }
}

/// Ancien format FNI (France, avant 2009) : 1234 AB 75, 123 ABC 2A, 12 AB 974.
class FrenchFniFormat implements PlateFormat {
  const FrenchFniFormat();

  static final _re = RegExp(r'^([0-9]{1,4})([A-Z]{1,3})(0[1-9]|[1-8][0-9]|9[0-5]|2A|2B|97[1-6])$');

  @override
  String get id => 'FR-FNI';
  @override
  String get country => 'FR';

  @override
  bool isValid(String n) {
    final m = _re.firstMatch(n);
    if (m == null) return false;
    // 4 chiffres + 3 lettres n'existe pas (8 à 9 caractères max avec le département).
    final digits = m.group(1)!, letters = m.group(2)!;
    if (digits.length + letters.length > 6) return false;
    return int.parse(digits) > 0 && !RegExp('[IOU]').hasMatch(letters);
  }

  @override
  String display(String n) {
    final m = _re.firstMatch(n)!;
    return '${m.group(1)} ${m.group(2)} ${m.group(3)}';
  }

  /// Le FNI est ambigu sans séparateurs : on n'accepte que des lignes dont
  /// les espaces délimitent les trois blocs, sans correction de confusion
  /// (sinon trop de faux positifs dans les textes de panneaux).
  @override
  List<PlateCandidate> extract(String line) {
    final tokens = line
        .toUpperCase()
        .split(RegExp(r'[\s\-.·]+'))
        .map(normalizePlateText)
        .where((t) => t.isNotEmpty)
        .toList();
    final found = <PlateCandidate>[];
    for (var i = 0; i + 3 <= tokens.length; i++) {
      final n = tokens[i] + tokens[i + 1] + tokens[i + 2];
      if (RegExp(r'^[0-9]+$').hasMatch(tokens[i]) &&
          RegExp(r'^[A-Z]+$').hasMatch(tokens[i + 1]) &&
          isValid(n)) {
        found.add(PlateCandidate(normalized: n, display: display(n), formatId: id, country: country, corrections: 0));
      }
    }
    return found;
  }
}

abstract final class PlateFormats {
  static const List<PlateFormat> all = [FrenchSivFormat(), FrenchFniFormat()];

  /// Tous les candidats d'une ligne, meilleurs (moins corrigés) d'abord.
  static List<PlateCandidate> extract(String line, {List<PlateFormat> formats = all}) {
    final out = <PlateCandidate>[];
    final seen = <String>{};
    for (final f in formats) {
      for (final c in f.extract(line)) {
        if (seen.add(c.normalized)) out.add(c);
      }
    }
    out.sort((a, b) => a.corrections.compareTo(b.corrections));
    return out;
  }

  /// Format reconnu pour une plaque saisie ou importée (`null` si aucun).
  static PlateFormat? match(String normalized, {List<PlateFormat> formats = all}) {
    for (final f in formats) {
      if (f.isValid(normalized)) return f;
    }
    return null;
  }
}

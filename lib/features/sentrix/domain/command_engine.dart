/// Moteur d'interprétation des commandes vocales de SENTRIX.
///
/// Une commande = un identifiant, un libellé, des phrases d'exemple et une
/// action. Ajouter une commande ne demande que de la déclarer dans
/// `sentrix_commands.dart` : la reconnaissance, l'aide et les tests
/// s'appuient sur ce registre.
library;

/// Réponse d'une commande exécutée.
class CommandResult {
  const CommandResult(this.reply, {this.success = true});
  const CommandResult.failure(this.reply) : success = false;

  /// Phrase prononcée et affichée par SENTRIX.
  final String reply;
  final bool success;
}

typedef CommandAction<C> = Future<CommandResult> Function(C context);

class VoiceCommand<C> {
  const VoiceCommand({
    required this.id,
    required this.label,
    required this.phrases,
    required this.action,
    this.keywords = const [],
  });

  final String id;

  /// Libellé affiché dans l'aide (« Lancer la navigation »).
  final String label;

  /// Façons de le dire. La première sert d'exemple dans l'aide.
  final List<String> phrases;

  /// Mots dont la présence est indispensable (après normalisation), pour
  /// distinguer « active la détection » de « désactive la détection ».
  final List<String> keywords;
  final CommandAction<C> action;
}

/// Commande reconnue et score de correspondance (0–1).
class CommandMatch<C> {
  const CommandMatch(this.command, this.score);
  final VoiceCommand<C> command;
  final double score;
}

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i',
  'ô': 'o', 'ö': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'œ': 'oe', 'æ': 'ae',
};

/// Mots sans valeur pour distinguer les commandes.
const _stopWords = {
  'le', 'la', 'les', 'l', 'un', 'une', 'des', 'du', 'de', 'd', 'au', 'aux', 'a', 'et',
  'moi', 'me', 'm', 'je', 'j', 'tu', 'vous', 'stp', 'svp', 'sil', 'plait', 'te', 'please',
  'sentrix', 'centrix', 'peux', 'pourrais', 'veux', 'voudrais', 'est', 'ce', 'que', 'qu', 'mon', 'ma', 'mes',
};

/// Variantes ramenées à une forme commune (conjugaisons, synonymes).
const _synonyms = {
  'lance': 'lancer', 'lances': 'lancer', 'demarre': 'lancer', 'demarrer': 'lancer', 'commence': 'lancer',
  'active': 'activer', 'actives': 'activer', 'allume': 'activer', 'allumer': 'activer', 'mets': 'activer', 'met': 'activer',
  'desactive': 'desactiver', 'eteins': 'desactiver', 'eteindre': 'desactiver', 'coupe': 'desactiver', 'couper': 'desactiver',
  'arrete': 'arreter', 'stoppe': 'arreter', 'stop': 'arreter', 'termine': 'arreter', 'annule': 'arreter', 'annuler': 'arreter',
  'ouvre': 'ouvrir', 'affiche': 'afficher', 'montre': 'afficher', 'montrer': 'afficher',
  'lis': 'lire', 'relis': 'lire', 'repete': 'lire', 'dis': 'lire', 'donne': 'lire',
  'detections': 'detection', 'lecture': 'detection', 'reconnaissance': 'detection', 'camera': 'detection', 'scan': 'detection',
  'alertes': 'alerte', 'historiques': 'historique', 'journal': 'historique',
  'guidage': 'navigation', 'itineraire': 'navigation', 'gps': 'navigation', 'trajet': 'navigation',
  'circulation': 'trafic', 'bouchons': 'trafic', 'embouteillages': 'trafic',
  'parametres': 'reglages', 'reglage': 'reglages', 'options': 'reglages',
  'plaques': 'plaque', 'liste': 'plaque',
};

/// Normalise une phrase : minuscules, sans accents ni ponctuation, mots
/// vides retirés, synonymes ramenés à une forme commune.
List<String> tokenize(String text) {
  final lower = text.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b
      .toString()
      .split(RegExp("[^a-z0-9]+"))
      .where((w) => w.isNotEmpty && !_stopWords.contains(w))
      .map((w) => _synonyms[w] ?? w)
      .toList();
}

class CommandEngine<C> {
  CommandEngine(this.commands) {
    final ids = <String>{};
    for (final c in commands) {
      if (!ids.add(c.id)) throw ArgumentError('Commande en double : ${c.id}');
    }
  }

  final List<VoiceCommand<C>> commands;

  /// Seuil sous lequel la phrase est considérée comme non comprise.
  static const threshold = 0.6;

  /// Meilleure commande pour [utterance], ou `null` si rien d'assez proche.
  CommandMatch<C>? match(String utterance) {
    final said = tokenize(utterance).toSet();
    if (said.isEmpty) return null;
    CommandMatch<C>? best;
    for (final c in commands) {
      final required = c.keywords.expand(tokenize).toSet();
      if (!said.containsAll(required)) continue;
      for (final phrase in c.phrases) {
        final p = tokenize(phrase).toSet();
        if (p.isEmpty) continue;
        // Part des mots de la phrase-type présents (rappel), légèrement
        // pénalisée par les mots en trop (précision).
        final common = p.intersection(said).length;
        final recall = common / p.length;
        final precision = common / said.length;
        final score = 0.8 * recall + 0.2 * precision;
        if (best == null || score > best.score) best = CommandMatch(c, score);
      }
    }
    return best != null && best.score >= threshold ? best : null;
  }
}

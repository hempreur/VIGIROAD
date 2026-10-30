/// États visuels de l'assistant SENTRIX (cahier des charges §10).
enum SentrixState {
  /// Au repos : yeux en arc, clignement lent.
  idle,

  /// Écoute active du microphone : lueur pulsée.
  listening,

  /// Analyse d'une commande : balayage des yeux.
  thinking,

  /// Réponse vocale en cours : onde sous les yeux.
  speaking,

  /// Notification / alerte : yeux rouges ouverts.
  notification,

  /// Erreur : yeux en croix orange.
  error,
}

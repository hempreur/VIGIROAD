# VIGIROAD 1.2 — mot d'activation « Sentrix »

## 1.2.1

- **Trafic et limitations de vitesse activés** : l'application est reliée au serveur
  VigiRoadTrafficAggregator du propriétaire (VPS, HTTPS). Perturbations Bison Futé sur la carte,
  état « inconnu » hors couverture, annonces de SENTRIX sur l'itinéraire, panneau de limitation
  pendant le guidage quand OpenStreetMap la connaît.

## Nouveautés

- **Dites « Sentrix »** pour activer SENTRIX sans toucher l'écran, sur l'écran de navigation.
  Option à activer : Réglages → SENTRIX → « Mot d'activation « Sentrix » ».
  - Analyse **sur le téléphone** (openWakeWord), rien n'est envoyé ; micro actif seulement sur
    l'écran de navigation, au premier plan.
  - Pause automatique pendant que SENTRIX écoute ou parle ; la voix de l'application (guidage,
    alertes, annonces) ne le déclenche pas.
  - Modèle entraîné avec la voix du propriétaire. Mesures sur des données jamais vues :
    **90 %** de détection de ses « Sentrix », **0,12** fausse activation par heure de parole
    française, **0,19** par heure de musique, bruit et autres voix. Détails :
    [`WAKE_WORD.md`](WAKE_WORD.md).
- **Enregistrement de la voix plus fiable** : « Parlez maintenant » n'apparaît que lorsque le micro
  enregistre réellement (le début du mot n'est plus coupé), extraits de 2,5 s.

## Limites

- Reconnaît surtout la voix du propriétaire ; une autre personne sera moins bien détectée.
- Taux mesuré sur un petit échantillon (13 enregistrements de test) : à confirmer à l'usage ; de
  nouveaux enregistrements permettront de réentraîner le modèle.
- Le micro n'écoute pas application masquée ou écran éteint.

## Installation

Par-dessus la 1.1.x (même signature VIGIROAD INC). Depuis une 1.0.x : exporter la liste de plaques,
désinstaller, installer, réimporter.

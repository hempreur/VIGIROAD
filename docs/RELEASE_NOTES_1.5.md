# VIGIROAD 1.5 — signalements Chicken, caméra stabilisée, « Sentrix » fiable

## 1.5.0

- Bouton Chicken (tête de poulet au képi) : signalez un Chicken sur votre route (flèche vers le haut) ou sur la route d'en face (flèche vers le bas) ; le marqueur 🍗 reste 2 h sur la carte de tous les conducteurs proches
- Annonce vocale quand un Chicken signalé est devant vous, à moins de 1,5 km, en précisant votre route ou la voie d'en face
- Caméra stabilisée : stabilisation du téléphone activée, images prises entre deux vibrations (gyroscope) et images floues de bougé écartées
- Zoom et mise au point automatiques sur la plaque repérée, retour au grand angle quand elle a disparu
- Lecture multi-plaques : toutes les plaques visibles sont lues, seules les plaques dangereuses (votre liste, par exemple ChickenPlate.csv) sont affichées et encadrées en rouge
- « Sentrix » ne se déclenche plus tout seul : micro coupé pendant les annonces de l'application, voix lointaine ou radio ignorée, fausse activation refermée sans bruit

## Détails

- **Signalements** : un signalement envoie uniquement sa position, son sens de circulation et l'heure, sans compte ni identifiant. Deux signalements au même endroit dans le même sens n'en font qu'un (confirmé, prolongé de 2 h). Un signalement par minute au plus par connexion. Option : Réglages → Signalements Chicken.
- **Cause des activations intempestives de « Sentrix » (1.2 – 1.4)** : le micro restait ouvert pendant que l'application parlait (guidage, alertes de plaques, perturbations) ; une phrase de l'application pouvait encore être dans la fenêtre d'analyse de 1,3 s à la fin de l'annonce et déclencher SENTRIX. Le micro est maintenant coupé pendant toute annonce et 1,5 s après ; une détection doit en plus correspondre à une voix proche du téléphone, nettement au-dessus du bruit de fond.
- **Caméra** : zoom limité à ×3 (au-delà le zoom numérique dégrade la plaque) et toujours assez large pour garder toutes les plaques visibles dans le champ. Option : Réglages → Lecture des plaques → Zoom et mise au point automatiques.
- Serveur : nouvelle route `/v1/reports` (VigiRoadTrafficAggregator) ; mettre à jour le VPS avec `sudo bash install.sh` ou depuis VIGIROAD SERVER CONTROL.

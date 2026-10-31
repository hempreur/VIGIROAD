# VIGIROAD 1.1 — nouveautés, limites et mise à jour

## ⚠️ Avant d'installer

Les versions 1.0.x étaient signées avec une clé de test. À partir de la 1.1.0, VIGIROAD est signé
par **VIGIROAD INC (CODEX HEMPREUR)** (empreinte SHA-256 `C5:A9:67:94:…:3D:B0:99`, voir
[`SIGNING.md`](SIGNING.md)). Android refuse d'installer par-dessus une signature différente :
**exporter la liste de plaques** (écran Plaques), **désinstaller l'ancienne version**, installer la
1.1.0 puis réimporter la liste. Les mises à jour suivantes s'installeront normalement.

## 1.1.2

- « Entraîner « Sentrix » avec ma voix » plus facile à trouver : en tête des Réglages et dans le
  menu de SENTRIX (appui long sur sa tête).
- Bouton **« Envoyer les enregistrements »** : ouvre le menu de partage du téléphone pour envoyer
  l'archive directement dans l'application Claude (ou par e-mail, Drive…), avec la marche à suivre
  affichée ensuite. « Enregistrer dans un fichier » reste disponible.

## 1.1.1

- **Entraîner « Sentrix » avec sa voix** (Réglages → Commandes vocales) : enregistrer une
  cinquantaine de « Sentrix », un peu de parole normale et le bruit de la voiture. Les
  enregistrements restent sur le téléphone ; l'utilisateur les exporte lui-même (.zip) pour
  l'entraînement du mot d'activation prévu en 1.2, et peut tout effacer.

## Nouveautés

### Trafic en temps réel (sources officielles)
- Serveur **VigiRoadTrafficAggregator** (image Docker) : Bison Futé (DATEX II), points d'accès
  nationaux européens configurables, Transport for London, 511 (WZDx et API v2), Waze for Cities
  si un accès partenaire est obtenu. Doublons fusionnés, données périmées écartées, basculement
  vers une source de secours. Droits et fréquences : [`server/SOURCES.md`](../server/SOURCES.md).
- **Carte** : perturbations (accident, bouchon, travaux, fermeture…), couleur selon la gravité,
  détail au toucher avec la source et l'heure de mise à jour.
- **Légende honnête** : « État inconnu ici » hors des zones couvertes, « Aucun incident signalé »
  quand une source à jour ne signale rien — jamais « fluide », les sources décrivant des incidents
  et non la vitesse de circulation. Mentions des sources toujours affichées.
- **SENTRIX** annonce une fois chaque perturbation située à moins de 5 km devant sur l'itinéraire
  ; la commande « État du trafic » résume la situation.
- Aucune circulation n'est simulée : après 5 minutes sans réponse du serveur, plus rien n'est
  affiché.

### Limitations de vitesse
- Pendant le guidage, limitation OpenStreetMap de la voie suivie, dans le sens de circulation.
- Valeurs explicites et valeurs légales sans ambiguïté seulement : « FR:rural » (80 ou 90 km/h
  selon le département) reste inconnue. Sans donnée, le panneau n'est pas affiché.
- Contrôle sur trajets réels : Paris Concorde → Bastille, limitation connue sur 100 % de la
  distance ; N20 Arpajon → Étampes, 95,8 %.

### Guidage en arrière-plan
- Les consignes vocales continuent écran éteint ou dans une autre application (notification
  « Guidage en cours »), désactivable dans les réglages.

### Identité
- Logo officiel VIGIROAD (icône Android adaptative et iOS, écran de démarrage).
- Application signée VIGIROAD INC (CODEX HEMPREUR) ; éditeur affiché dans les réglages.

### Corrections
- 1.0.1 : lecture des plaques réparée dans les APK release (R8 retirait des classes ML Kit).
  Un test sur émulateur lit désormais une plaque dans chaque APK release avant publication.

## Prérequis côté propriétaire

- **Trafic et limitations** : héberger le serveur (`server/README.md`) et renseigner les secrets
  `VR_TRAFFIC_API_URL` et `VR_TRAFFIC_API_KEY`. Sans eux, l'application affiche « Source non
  configurée » et aucun panneau de limitation.

## Reporté

- **Mot d'activation « Sentrix »** : un modèle entraîné uniquement sur des voix de synthèse
  (≈ 130 voix françaises) a été mesuré sur des voix et des heures de parole jamais vues. Au réglage
  respectant ≤ 0,5 fausse activation par heure de parole, il ne détecte qu'environ 40 % des
  « Sentrix », et se déclenche encore plusieurs fois par heure sur de la musique ou du bruit : pas
  assez fiable, il n'est pas intégré. Prochaine étape (1.2) : enregistrer des « Sentrix » prononcés
  par l'utilisateur, réentraîner, mesurer. SENTRIX s'active au toucher en attendant.

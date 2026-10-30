# VIGIROAD 1.0 — fonctionnalités livrées et limitations

## Fonctionnalités livrées

### Navigation GPS
- Carte sombre MapLibre (OpenStreetMap), suivi de la position, vue conduite 3D ou à plat, recentrage.
- Recherche d'adresses et de lieux (Photon), distance depuis la position.
- Calcul d'itinéraire (OSRM), tracé lumineux, cartouche de manœuvre (flèche, distance, consigne en
  français, direction), heure d'arrivée, durée et distance restantes.
- Guidage vocal en français, paliers d'annonce adaptés à la vitesse, bouton de coupure.
- Détection de sortie d'itinéraire et recalcul automatique ; nouvel essai après erreur réseau.
- Vitesse GPS réelle ; compteur rouge au-dessus de la limitation quand elle est connue.
- Écran maintenu allumé pendant le guidage.

### Lecture des plaques
- Caméra arrière, OCR Google ML Kit **sur le téléphone** (aucune image envoyée).
- Formats français SIV et FNI, correction des confusions OCR, architecture extensible à d'autres pays.
- Confirmation sur plusieurs images (vote), niveau de confiance, filtre de netteté, alerte faible
  luminosité, cadence adaptative, plusieurs véhicules à la fois.
- Aperçu en direct avec cadres lumineux, fenêtre « Lecture OCR » (plaque, confiance, pays).

### Base de plaques et alertes
- Base SQLite chiffrée (SQLCipher, clé dans le Keystore/Keychain).
- Import CSV/JSON avec rapport ligne par ligne, saisie, modification, suppression, recherche,
  doublons, pays, catégories, priorités, export CSV, synchronisation HTTPS optionnelle.
- Alerte sur correspondance confirmée : encadré rouge, son, annonce SENTRIX, historique avec
  position ; anti-répétition ; les plaques non listées ne laissent aucune trace.

### SENTRIX
- Tête robotique animée, 6 états (repos, écoute, analyse, réponse, notification, erreur).
- Commandes vocales à activation manuelle, moteur extensible, 14 commandes provisoires.
- File vocale à priorités : guidage > alerte > SENTRIX, jamais deux voix à la fois.

### Historique et réglages
- Historique filtrable (recherche, période, priorité), suppression, purge, export (sur autorisation),
  conservation automatique.
- Réglages persistants : lecture automatique, performance, seuils, sons, voix, vue, données.

### Qualité
- 156 tests automatiques, couverture 81 % du code Dart, banc de mesure post-OCR, contrôles
  d'accessibilité (contrastes WCAG AA, petits écrans, texte agrandi, cibles tactiles).
- CI : analyse, tests, captures d'écran, APK Android (debug et release), build iOS.

## Limitations

| Domaine | Limitation | Piste |
|---|---|---|
| Trafic | Pas de trafic en temps réel (choix OpenStreetMap) ; affiché « Source non configurée » | Brancher TomTom/HERE/Mapbox (payant) via l'interface prévue |
| Limitations de vitesse | Non fournies par OSRM : panneau masqué | Serveur compatible Mapbox ou données OSM `maxspeed` |
| Serveurs | OSRM et Photon publics = démonstration, sans garantie | Héberger ses instances |
| Arrière-plan | Guidage et caméra uniquement application au premier plan | Service de premier plan Android / mode location iOS |
| OCR | Taux de lecture réel non mesuré sur route (seul le banc synthétique l'est) | Protocole `DEVICE_TEST_PROTOCOL.md` |
| OCR iOS | ML Kit ne fournit pas la confiance par ligne sur iOS (valeur par défaut) | — |
| Formats | Plaques françaises uniquement pour la lecture | Ajouter des `PlateFormat` |
| Langues | Interface et SENTRIX en français uniquement | Internationalisation |
| SENTRIX | Commandes provisoires ; pas de mot d'activation ; reconnaissance vocale du système (peut être en ligne) | Validation des commandes, mot d'activation |
| Température | Pas d'API thermique ; cadence OCR adaptée à la durée d'analyse | Mesures sur appareil |
| iOS | Build non signé ; distribution = compte Apple Developer | Voir `INSTALL.md` |
| Signature Android | Clé de débogage tant que les secrets de distribution ne sont pas configurés | Voir `INSTALL.md` |
| Tests sur appareil | Caméra, batterie, chaleur, durée : à réaliser sur téléphone | `DEVICE_TEST_PROTOCOL.md` |
| Cadre légal | Lecture automatisée de plaques = données personnelles (RGPD/CNIL) | `PRIVACY.md` |

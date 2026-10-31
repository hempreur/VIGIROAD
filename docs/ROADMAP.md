# Feuille de route et limitations

## Plan d'implémentation

| # | Phase | Branche | Contenu | Validation |
|---|---|---|---|---|
| 1 | Socle | `feature/phase1-foundation` | Projet Flutter, natif Android/iOS, permissions, design tokens, SENTRIX, splash, CI | CI verte, APK installable |
| 2 | Interface DARK | `feature/phase2-ui` | Écran GPS principal, panneaux caméra/OCR/alerte, recherche, gestion des plaques, historique, réglages, app icon | Captures comparées à la référence |
| 3 | GPS | `feature/phase3-navigation` | Carte MapLibre sombre, suivi de position, recherche Photon, itinéraire OSRM, guidage vocal, ETA, vitesse, recalcul hors trajet, gestion hors-ligne | Trajet réel de bout en bout |
| 4 | Plaques | `feature/phase4-alpr` | Flux caméra, filtre de netteté, OCR ML Kit, extraction SIV/FNI, normalisation, vote multi-images, confiance | Mesures sur jeu d'images annoté (précision, rappel, latence) |
| 5 | Base & alertes | `feature/phase5-watchlist` | SQLite chiffré, import CSV/JSON, CRUD, doublons, priorités, synchronisation, moteur de correspondance, alertes | Plaque test → alerte ; plaque absente → aucune alerte |
| 6 | SENTRIX | `feature/phase6-sentrix` | Reconnaissance et synthèse vocale, registre extensible de commandes, états animés | Commandes exemples exécutées |
| 7 | Intégration | `feature/phase7-integration` | GPS + caméra + SENTRIX simultanés, file vocale à priorité, cycle de vie, interruptions | Session de conduite prolongée |
| 8 | Historique & réglages | `feature/phase8-settings` | Journal filtrable, purge, export, tous les réglages | Tests widgets |
| 9 | Qualité | `feature/phase9-hardening` | Couverture de tests, profilage CPU/batterie/température, accessibilité | Rapport de tests |
| 10 | Livraison | `release/1.0.0` | APK signé, archive iOS, documentation complète, captures finales | — |

## Version 1.1 (livrée)

Trafic officiel, limitations de vitesse, guidage en arrière-plan, logo et signature VIGIROAD INC :
voir [`RELEASE_NOTES_1.1.md`](RELEASE_NOTES_1.1.md).

## Version 1.2 (livrée)

- **Mot d'activation « Sentrix »** entraîné avec la voix du propriétaire : 90 % de détection,
  0,12 fausse activation/h de parole, 0,19/h de musique ou bruit. Voir
  [`WAKE_WORD.md`](WAKE_WORD.md) et [`RELEASE_NOTES_1.2.md`](RELEASE_NOTES_1.2.md).

## Limitations connues

Voir aussi [`RELEASE_NOTES_1.0.md`](RELEASE_NOTES_1.0.md) et [`RELEASE_NOTES_1.1.md`](RELEASE_NOTES_1.1.md).

- **Trafic temps réel** : perturbations officielles via le serveur VigiRoadTrafficAggregator
  (incidents, travaux, fermetures), pas de mesure de vitesse de circulation. Hors des zones
  couvertes, l'état est « inconnu ». Le serveur doit être hébergé (image Docker) et configuré
  (voir `API_CONFIG.md`).
- **Services publics OSM** : le serveur OSRM de démonstration et Photon public suffisent pour le
  développement mais pas pour une exploitation ; prévoir un hébergement.
- **Limitations de vitesse** (1.1) : pendant le guidage, balise OpenStreetMap `maxspeed` de la voie
  suivie (serveur VIGIROAD + Overpass), dans le sens de circulation. Valeurs explicites et valeurs
  légales sans ambiguïté seulement (« FR:rural » — 80 ou 90 selon le département — reste inconnue) ;
  la couverture OSM est incomplète : sans donnée, le panneau n'est pas affiché. Pas de données
  officielles nationales ouvertes en France à ce jour ; panneaux temporaires et limitations
  variables non connus. Hors guidage, aucune limitation n'est affichée.
- **Guidage en arrière-plan** (1.1) : pendant un guidage, la localisation passe en service de
  premier plan Android (notification « Guidage en cours ») et en mode « location » iOS ; les consignes
  vocales continuent écran éteint. Désactivable dans les réglages. La caméra, elle, s'arrête toujours
  en arrière-plan (contrainte des systèmes).
- **Température / batterie** : aucune API thermique n'est interrogée ; la cadence de l'OCR s'adapte
  automatiquement à sa durée (téléphone chargé ou chaud = analyses plus espacées). Mesures réelles
  en phase 9 sur appareil.
- **Caméra en arrière-plan** : impossible sur iOS et fortement restreinte sur Android ; la lecture
  des plaques ne fonctionne qu'application au premier plan.
- **Détection de plaques** : la première version localise les plaques via l'OCR et le format
  attendu ; un détecteur dédié (modèle embarqué) sera évalué en phase 4 selon les mesures.
- **iOS** : la CI produit un build non signé ; la distribution (TestFlight/App Store) nécessite
  un compte Apple Developer et les certificats du propriétaire.
- **Tests sur appareil** : la CI ne dispose pas de téléphone ; les tests caméra, GPS, batterie et
  température se font sur l'appareil de test du propriétaire, avec un protocole fourni en phase 9.
- **Cadre légal** : voir `PRIVACY.md`.
